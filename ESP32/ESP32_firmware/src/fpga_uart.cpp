#include <Arduino.h>
#include <HardwareSerial.h>
#include "config.h"
#include "fpga_uart.h"

static constexpr uint8_t FPGA_START_BYTE = 0xAA;
static constexpr uint8_t FPGA_MAX_PAYLOAD = 16;
static constexpr unsigned long UART_FRAME_TIMEOUT_MS = 100;

struct FpgaFrame
{
  uint8_t cmd;
  uint8_t len;
  uint8_t payload[FPGA_MAX_PAYLOAD];
};

enum ParserState
{
  PARSER_WAIT_START,
  PARSER_CMD,
  PARSER_LEN,
  PARSER_PAYLOAD,
  PARSER_CHECKSUM
};

static HardwareSerial fpgaSerial(2);
static FpgaFrameHandler frameHandler = nullptr;
static ParserState parserState = PARSER_WAIT_START;
static FpgaFrame parserFrame = {};
static uint8_t parserIndex = 0;
static uint8_t parserChecksum = 0;
static unsigned long parserLastByteMs = 0;

static void resetParser()
{
  parserState = PARSER_WAIT_START;
  parserIndex = 0;
  parserChecksum = 0;
}

static void handleFrame(const FpgaFrame &frame)
{
  if (frameHandler)
  {
    frameHandler(frame.cmd, frame.payload, frame.len);
  }
}

static void checkParserTimeout()
{
  if (parserState != PARSER_WAIT_START && millis() - parserLastByteMs >= UART_FRAME_TIMEOUT_MS)
  {
    Serial.println("[UART] Frame timeout");
    resetParser();
  }
}

static void parseFpgaByte(uint8_t byte)
{
  parserLastByteMs = millis();

  switch (parserState)
  {
  case PARSER_WAIT_START:
    if (byte == FPGA_START_BYTE)
    {
      parserState = PARSER_CMD;
    }
    break;

  case PARSER_CMD:
    parserFrame = {};
    parserFrame.cmd = byte;
    parserChecksum = byte;
    parserState = PARSER_LEN;
    break;

  case PARSER_LEN:
    parserFrame.len = byte;
    parserChecksum ^= byte;
    parserIndex = 0;
    if (byte > FPGA_MAX_PAYLOAD)
    {
      Serial.printf("[UART] Invalid frame length: %u\n", byte);
      resetParser();
    }
    else if (byte == 0)
    {
      parserState = PARSER_CHECKSUM;
    }
    else
    {
      parserState = PARSER_PAYLOAD;
    }
    break;

  case PARSER_PAYLOAD:
    parserFrame.payload[parserIndex++] = byte;
    parserChecksum ^= byte;
    if (parserIndex >= parserFrame.len)
    {
      parserState = PARSER_CHECKSUM;
    }
    break;

  case PARSER_CHECKSUM:
    if (byte == parserChecksum)
    {
      handleFrame(parserFrame);
    }
    else
    {
      Serial.printf("[UART] Bad checksum got=0x%02X expected=0x%02X\n", byte, parserChecksum);
    }
    resetParser();
    break;
  }
}

void fpga_uart_init()
{
  fpgaSerial.begin(FPGA_UART_BAUD, SERIAL_8N1, FPGA_RX_PIN, FPGA_TX_PIN);
}

void fpga_uart_set_frame_handler(FpgaFrameHandler handler)
{
  frameHandler = handler;
}

void fpga_uart_poll()
{
  checkParserTimeout();
  while (fpgaSerial.available() > 0)
  {
    parseFpgaByte(static_cast<uint8_t>(fpgaSerial.read()));
  }
}

void fpga_uart_send_frame(uint8_t cmd, const uint8_t *payload, uint8_t len)
{
  if (len > FPGA_MAX_PAYLOAD)
  {
    Serial.printf("[UART] TX rejected: len=%u\n", len);
    return;
  }

  uint8_t checksum = cmd ^ len;

  fpgaSerial.write(FPGA_START_BYTE);
  fpgaSerial.write(cmd);
  fpgaSerial.write(len);

  for (uint8_t i = 0; i < len; ++i)
  {
    uint8_t value = payload ? payload[i] : 0;
    fpgaSerial.write(value);
    checksum ^= value;
  }

  fpgaSerial.write(checksum);
  Serial.printf("[UART] TX cmd=0x%02X len=%u checksum=0x%02X\n", cmd, len, checksum);
}

void fpga_uart_send_open_gate(uint8_t gate)
{
  uint8_t payload[1] = {gate};
  fpga_uart_send_frame(FPGA_CMD_OPEN_GATE, payload, 1);
}
