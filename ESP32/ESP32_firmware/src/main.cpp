#include <Arduino.h>
#include <string.h>
#include "config.h"
#include "wifi_manager.h"
#include "http_client.h"
#include "lcd_display.h"
#include "fpga_uart.h"

static constexpr uint8_t GATE_ENTRY = 0;
static constexpr uint8_t GATE_EXIT = 1;

static uint8_t currentSlotMask = 0;
static int lastReportedSlotMask = -1;

QueueHandle_t httpRequestQueue;
QueueHandle_t httpResponseQueue;

enum HttpJobType
{
  HTTP_JOB_TRIGGER,
  HTTP_JOB_UPDATE_SLOTS
};

struct HttpJob
{
  HttpJobType type;
  uint8_t gate;
  uint8_t slotMask;
};

struct HttpResult
{
  HttpJobType type;
  uint8_t gate;
  uint8_t slotMask;
  bool slotUpdateOk;
  ServerResponse response;
};

static uint8_t validSlotMask()
{
  return (TOTAL_SLOTS >= 8) ? 0xFF : ((1U << TOTAL_SLOTS) - 1);
}

static uint8_t normalizeSlotMask(uint8_t rawSlotMask)
{
  uint8_t mask = validSlotMask();
  uint8_t normalized = rawSlotMask & mask;
  if (rawSlotMask != normalized)
  {
    Serial.printf("[FPGA] Slot mask ignored unused bits: raw=0x%02X normalized=0x%02X\n",
                  rawSlotMask,
                  normalized);
  }
  return normalized;
}

static int countOccupied(uint8_t slotMask)
{
  int occupied = 0;
  slotMask = normalizeSlotMask(slotMask);
  for (int bit = 0; bit < TOTAL_SLOTS; ++bit)
  {
    if ((slotMask >> bit) & 1)
    {
      ++occupied;
    }
  }
  return occupied;
}

static const char *gateName(uint8_t gate)
{
  return gate == GATE_EXIT ? "exit" : "entry";
}

static void updateDisplay(uint8_t slotMask)
{
  lcd_show_idle(slotMask);
}

static void enqueueHttpJob(const HttpJob &job)
{
  if (!httpRequestQueue || xQueueSend(httpRequestQueue, &job, 0) != pdTRUE)
  {
    Serial.println("[HTTP] Request queue full");
    lcd_show_error("HTTP queue full");
  }
}

static void reportSlotUpdateIfChanged()
{
  if (lastReportedSlotMask == currentSlotMask)
  {
    return;
  }

  HttpJob job = {};
  job.type = HTTP_JOB_UPDATE_SLOTS;
  job.slotMask = currentSlotMask;
  enqueueHttpJob(job);
}

static void handleTriggerResponse(uint8_t gate, const ServerResponse &resp)
{
  lcd_show_result(resp);

  if (!resp.valid)
  {
    Serial.printf("[HTTP] Invalid trigger response for %s: %s\n", gateName(gate), resp.reason);
    return;
  }

  if (strcmp(resp.status, "ok") != 0)
  {
    Serial.printf("[HTTP] Server error for %s: %s\n", gateName(gate), resp.reason);
    return;
  }

  if (strcmp(resp.action, "open_entry") == 0)
  {
    if (gate == GATE_ENTRY)
    {
      fpga_uart_send_open_gate(GATE_ENTRY);
    }
    else
    {
      Serial.printf("[HTTP] Action mismatch: gate=%s action=%s\n", gateName(gate), resp.action);
    }
    return;
  }

  if (strcmp(resp.action, "open_exit") == 0)
  {
    if (gate == GATE_EXIT)
    {
      fpga_uart_send_open_gate(GATE_EXIT);
    }
    else
    {
      Serial.printf("[HTTP] Action mismatch: gate=%s action=%s\n", gateName(gate), resp.action);
    }
    return;
  }

  Serial.printf("[HTTP] Gate %s rejected\n", gateName(gate));
}

static void handleFpgaFrame(uint8_t cmd, const uint8_t *payload, uint8_t len)
{
  switch (cmd)
  {
  case FPGA_RSP_PARKING_STATUS:
    if (len < 1)
    {
      Serial.println("[UART] Bad status frame length");
      lcd_show_error("UART status err");
      return;
    }
    {
      currentSlotMask = normalizeSlotMask(payload[0]);
      int occupied = countOccupied(currentSlotMask);
      Serial.printf("[FPGA] Slots mask=0x%02X occupied=%d free=%d\n",
                    currentSlotMask,
                    occupied,
                    TOTAL_SLOTS - occupied);
      updateDisplay(currentSlotMask);
      reportSlotUpdateIfChanged();
    }
    break;

  case FPGA_RSP_GATE_EVENT:
    if (len < 1)
    {
      Serial.println("[UART] Bad gate event length");
      lcd_show_error("UART gate err");
      return;
    }
    if (payload[0] > GATE_EXIT)
    {
      Serial.printf("[UART] Unknown gate event: %u\n", payload[0]);
      return;
    }
    Serial.printf("[FPGA] %s gate event\n", gateName(payload[0]));
    lcd_show_checking(payload[0] == GATE_ENTRY ? "ENTRY" : "EXIT");
    {
      HttpJob job = {};
      job.type = HTTP_JOB_TRIGGER;
      job.gate = payload[0];
      job.slotMask = currentSlotMask;
      enqueueHttpJob(job);
    }
    break;

  case FPGA_RSP_FAILSAFE_EVENT:
    if (len < 1)
    {
      Serial.println("[UART] Bad failsafe event length");
      return;
    }
    if (payload[0] > GATE_EXIT)
    {
      Serial.printf("[UART] Unknown failsafe gate: %u\n", payload[0]);
      return;
    }
    Serial.printf("[FPGA] Failsafe opened %s gate\n", gateName(payload[0]));
    lcd_show_manual_open(payload[0] == GATE_EXIT ? "EXIT" : "ENTRY");
    break;

  case FPGA_RSP_ACK:
    Serial.printf("[FPGA] ACK len=%u code=0x%02X\n", len, len ? payload[0] : 0);
    break;

  case FPGA_RSP_NACK:
    Serial.printf("[FPGA] NACK len=%u error=0x%02X\n", len, len ? payload[0] : 0);
    lcd_show_error("FPGA NACK");
    break;

  case FPGA_RSP_PONG:
    Serial.println("[FPGA] PONG");
    break;

  default:
    Serial.printf("[UART] Unknown frame cmd=0x%02X len=%u\n", cmd, len);
    break;
  }
}

static void httpWorkerTask(void *parameters)
{
  (void)parameters;
  HttpJob job;

  for (;;)
  {
    if (xQueueReceive(httpRequestQueue, &job, portMAX_DELAY) != pdTRUE)
    {
      continue;
    }

    HttpResult result = {};
    result.type = job.type;
    result.gate = job.gate;
    result.slotMask = job.slotMask;

    if (job.type == HTTP_JOB_TRIGGER)
    {
      result.response = http_send_trigger(gateName(job.gate), job.slotMask);
    }
    else if (job.type == HTTP_JOB_UPDATE_SLOTS)
    {
      result.slotUpdateOk = http_send_slot_update(job.slotMask);
    }

    if (httpResponseQueue)
    {
      xQueueSend(httpResponseQueue, &result, portMAX_DELAY);
    }
  }
}

static void handleHttpResults()
{
  if (!httpResponseQueue)
  {
    return;
  }

  HttpResult result;
  while (xQueueReceive(httpResponseQueue, &result, 0) == pdTRUE)
  {
    if (result.type == HTTP_JOB_TRIGGER)
    {
      handleTriggerResponse(result.gate, result.response);
    }
    else if (result.type == HTTP_JOB_UPDATE_SLOTS)
    {
      if (result.slotUpdateOk)
      {
        lastReportedSlotMask = result.slotMask;
      }
      else
      {
        lcd_show_error("HTTP slot err");
      }
    }
  }
}

void setup()
{
  Serial.begin(115200);
  delay(SERIAL_SETUP_MS);

  Serial.println();
  Serial.println("=== ESP32 FPGA Parking Gateway ===");
  Serial.printf("Server base URL -> %s\n", SERVER_BASE_URL);
  Serial.printf("FPGA UART2 RX=%d TX=%d baud=%d\n", FPGA_RX_PIN, FPGA_TX_PIN, FPGA_UART_BAUD);

  lcd_display_init();
  lcd_show_error("WiFi connecting");
  updateDisplay(currentSlotMask);

  httpRequestQueue = xQueueCreate(8, sizeof(HttpJob));
  httpResponseQueue = xQueueCreate(4, sizeof(HttpResult));
  if (!httpRequestQueue || !httpResponseQueue)
  {
    Serial.println("[HTTP] Failed to create queues");
    lcd_show_error("HTTP queue err");
  }

  BaseType_t taskCreated = xTaskCreatePinnedToCore(httpWorkerTask, "HTTP Worker", 8192, nullptr, 5, nullptr, 0);
  if (taskCreated != pdPASS)
  {
    Serial.println("[HTTP] Failed to create worker task");
    lcd_show_error("HTTP task err");
  }

  wifi_init();
  lcd_show_error("FPGA waiting");

  fpga_uart_set_frame_handler(handleFpgaFrame);
  fpga_uart_init();
  fpga_uart_send_frame(FPGA_CMD_PING, nullptr, 0);
  fpga_uart_send_frame(FPGA_CMD_REQUEST_STATUS, nullptr, 0);
}

void loop()
{
  wifi_handle();
  fpga_uart_poll();
  handleHttpResults();
  lcd_display_update();
  delay(5);
  if (Serial.available() > 0)
  {
    char c = Serial.read();
    if (c == '1')
    {
      fpga_uart_send_open_gate(GATE_ENTRY);
      Serial.println("[TEST] Manual open ENTRY");
    }
    else if (c == '2')
    {
      fpga_uart_send_open_gate(GATE_EXIT);
      Serial.println("[TEST] Manual open EXIT");
    }
  }
}
