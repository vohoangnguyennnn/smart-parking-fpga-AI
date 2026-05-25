#ifndef CONFIG_H
#define CONFIG_H

#include <IPAddress.h>

// ── WiFi credentials ──────────────────────────────────────────────
#define WIFI_SSID     "YOUR_WIFI_SSID"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"

// ── Static IP config (set USE_STATIC_IP to 0 to use DHCP) ─────────
#define USE_STATIC_IP 1
#define STATIC_IP     IPAddress(192, 168, 1, 50)
#define GATEWAY_IP    IPAddress(192, 168, 1, 1)
#define SUBNET_MASK   IPAddress(255, 255, 255, 0)

// ── Camera / HTTP timing ──────────────────────────────────────────
#define MIN_CAPTURE_INTERVAL_MS 200
#define WIFI_RECONNECT_DELAY_MS 5000
#define CAMERA_REINIT_DELAY_MS  30000
#define WIFI_CONNECT_TIMEOUT_MS 30000

#endif
