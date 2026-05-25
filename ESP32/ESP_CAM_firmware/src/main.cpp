/**
 * ESP32-CAM image capture firmware.
 * GET /capture -> JPEG image.
 */

#include "config.h"

#define PWDN_GPIO_NUM 32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 0
#define SIOD_GPIO_NUM 26
#define SIOC_GPIO_NUM 27

#define Y9_GPIO_NUM 35
#define Y8_GPIO_NUM 34
#define Y7_GPIO_NUM 39
#define Y6_GPIO_NUM 36
#define Y5_GPIO_NUM 21
#define Y4_GPIO_NUM 19
#define Y3_GPIO_NUM 18
#define Y2_GPIO_NUM 5

#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM 23
#define PCLK_GPIO_NUM 22

#include "esp_camera.h"
#include <WebServer.h>
#include <WiFi.h>
#include <freertos/FreeRTOS.h>

WebServer server(80);

static portMUX_TYPE captureBusymux = portMUX_INITIALIZER_UNLOCKED;
static volatile bool captureBusy = false;

static bool cameraReady = false;

static unsigned long lastCaptureMs = 0;
static const unsigned long minCaptureIntervalMs = MIN_CAPTURE_INTERVAL_MS;

static unsigned long lastWifiReconnectAttempt = 0;
static const unsigned long delayReconnect = WIFI_RECONNECT_DELAY_MS;

static unsigned long lastCameraReinitAttempt = 0;
static const unsigned long delayCameraReinit = CAMERA_REINIT_DELAY_MS;

bool initCamera()
{
  camera_config_t config = {0};

  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;

  config.xclk_freq_hz = 10000000;

  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAMESIZE_VGA;
  config.jpeg_quality = 10;

  config.fb_count = 2;

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK)
  {
    Serial.printf("[CAM] Init failed: 0x%x — will retry later\n", err);
    return false;
  }

  Serial.println("[CAM] Initialized");
  return true;
}

bool connectWiFi()
{
  if (WiFi.status() == WL_CONNECTED)
    return true;

  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
#if USE_STATIC_IP
  WiFi.config(STATIC_IP, GATEWAY_IP, SUBNET_MASK);
#endif
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  const unsigned long TIMEOUT_MS = WIFI_CONNECT_TIMEOUT_MS;
  const unsigned long POLL_INTERVAL = 500;
  unsigned long start = millis();

  Serial.print("[WIFI] Connecting");

  while (WiFi.status() != WL_CONNECTED)
  {
    if (millis() - start >= TIMEOUT_MS)
    {
      Serial.println("\n[WIFI] Connect timeout — will keep retrying in loop()");
      return false;
    }

    delay(POLL_INTERVAL);
    Serial.write('.');
  }

  Serial.println();
  Serial.print("[WIFI] Connected — IP: ");
  Serial.println(WiFi.localIP());
  return true;
}

static void handleCapture()
{
  Serial.println("[HTTP] /capture requested");

  if (WiFi.status() != WL_CONNECTED)
  {
    server.send(503, "text/plain", "WiFi not connected");
    return;
  }

  if (!cameraReady)
  {
    server.send(503, "text/plain", "Camera unavailable");
    return;
  }

  unsigned long now = millis();
  if (now - lastCaptureMs < minCaptureIntervalMs)
  {
    Serial.println("[HTTP] /capture rejected — rate limited");
    server.send(429, "text/plain", "Rate limited, try again shortly");
    return;
  }

  // Keep captureBusy read/write atomic across cores.
  portENTER_CRITICAL(&captureBusymux);
  bool wasBusy = captureBusy;
  if (!wasBusy)
    captureBusy = true;
  portEXIT_CRITICAL(&captureBusymux);

  lastCaptureMs = millis();

  if (wasBusy)
  {
    Serial.println("[HTTP] /capture rejected — busy");
    server.send(429, "text/plain", "Busy, try again shortly");
    return;
  }

  camera_fb_t *fb = esp_camera_fb_get();

  if (!fb)
  {
    Serial.println("[CAM] Capture failed — camera may need reinit");
    portENTER_CRITICAL(&captureBusymux);
    captureBusy = false;
    portEXIT_CRITICAL(&captureBusymux);
    cameraReady = false;
    server.send(500, "text/plain", "Camera capture error");
    return;
  }

  if (fb->len == 0 || fb->buf == nullptr)
  {
    Serial.println("[CAM] Zero-length frame received — discarding");
    esp_camera_fb_return(fb);
    portENTER_CRITICAL(&captureBusymux);
    captureBusy = false;
    portEXIT_CRITICAL(&captureBusymux);
    cameraReady = false;
    server.send(500, "text/plain", "Frame error");
    return;
  }

  Serial.printf("[CAM] Capture OK — %u bytes %ux%u\n",
                fb->len, fb->width, fb->height);

  server.send_P(200, "image/jpeg", (const char *)fb->buf, fb->len);

  esp_camera_fb_return(fb);
  portENTER_CRITICAL(&captureBusymux);
  captureBusy = false;
  portEXIT_CRITICAL(&captureBusymux);
}

static void handleNotFound()
{
  server.send(404, "text/plain", "Not found");
}

void setup()
{
  Serial.begin(115200);
  delay(1500);

  Serial.println("=== ESP32-CAM ===");

  if (!connectWiFi())
  {
    Serial.println("[SETUP] WiFi not ready — will reconnect in loop()");
  }

  cameraReady = initCamera();
  if (!cameraReady)
  {
    Serial.println("[SETUP] Camera not ready — will retry in loop()");
    lastCameraReinitAttempt = millis();
  }

  server.on("/capture", HTTP_GET, handleCapture);
  server.onNotFound(handleNotFound);

  server.begin();
  Serial.println("Ready — GET http://<IP>/capture");
}

void loop()
{
  server.handleClient();

  if (WiFi.status() != WL_CONNECTED)
  {
    if (millis() - lastWifiReconnectAttempt >= delayReconnect)
    {
      Serial.println("[LOOP] WiFi down — reconnecting...");
      lastWifiReconnectAttempt = millis();
      WiFi.reconnect();
    }
  }
  else
  {
    lastWifiReconnectAttempt = millis();
  }

  if (!cameraReady && (millis() - lastCameraReinitAttempt >= delayCameraReinit))
  {
    Serial.println("[LOOP] Attempting camera reinit...");
    lastCameraReinitAttempt = millis();

    esp_camera_deinit();
    delay(100);

    cameraReady = initCamera();
    if (cameraReady)
    {
      Serial.println("[LOOP] Camera recovered");
    }
  }

  // Keep loop non-blocking so HTTP remains responsive.
}
