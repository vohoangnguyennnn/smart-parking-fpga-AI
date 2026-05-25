#include "config.h"
#include "wifi_manager.h"
#include <WiFi.h>

#define WIFI_INIT_TIMEOUT_MS 15000
#define WIFI_BEGIN_INTERVAL_MS 2000
#define WIFI_CONNECT_TIMEOUT_MS 10000

typedef enum
{
  WFS_IDLE,
  WFS_CONNECTING,
  WFS_CONNECTED
} WifiState;

static WifiState wifiState = WFS_IDLE;
static unsigned long lastBeginMs = 0;
static unsigned long lastPrintMs = 0;

void wifi_init()
{
  Serial.printf("[WiFi] Connecting to SSID \"%s\" ...\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED)
  {
    if (millis() - start >= WIFI_INIT_TIMEOUT_MS)
    {
      Serial.println();
      Serial.println("[WiFi] INIT TIMEOUT – will retry in background.");
      wifiState = WFS_IDLE;
      lastBeginMs = millis();
      return;
    }
    delay(250);
    Serial.print('.');
  }

  wifiState = WFS_CONNECTED;
  Serial.println();
  Serial.printf("[WiFi] Connected!  IP = %s\n", WiFi.localIP().toString().c_str());
}

void wifi_handle()
{
  unsigned long now = millis();
  wl_status_t st = WiFi.status();

  if (st == WL_CONNECTED)
  {
    if (wifiState != WFS_CONNECTED)
    {
      wifiState = WFS_CONNECTED;
      Serial.printf("[WiFi] Connected.  IP = %s\n", WiFi.localIP().toString().c_str());
    }
  }

  else
  {
    if (wifiState == WFS_CONNECTED)
    {
      wifiState = WFS_IDLE;
      Serial.println("[WiFi] Connection lost.");
      lastBeginMs = 0;
    }

    if (wifiState == WFS_CONNECTING && now - lastBeginMs >= WIFI_CONNECT_TIMEOUT_MS)
    {
      wifiState = WFS_IDLE;
      Serial.println("[WiFi] Reconnect timeout.");
    }

    if (wifiState == WFS_IDLE && now - lastBeginMs >= WIFI_BEGIN_INTERVAL_MS)
    {
      lastBeginMs = now;
      wifiState = WFS_CONNECTING;

      Serial.printf("[WiFi] Attempting to reconnect (status=%d)...\n", st);

      WiFi.disconnect();
      delay(50);
      WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    }
  }

  if (now - lastPrintMs >= WIFI_STATUS_PRINT_MS)
  {
    lastPrintMs = now;
    Serial.printf("[Status] WiFi=%s  RSSI=%d dBm\n",
                  (wifiState == WFS_CONNECTED) ? "connected" : "DISCONNECTED",
                  WiFi.RSSI());
  }
}
