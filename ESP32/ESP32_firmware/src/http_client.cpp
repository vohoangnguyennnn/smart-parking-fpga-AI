#include "config.h"
#include "http_client.h"
#include <HTTPClient.h>
#include <WiFi.h>
#include <ArduinoJson.h>
#include <string.h>

static ServerResponse make_invalid_response(const char *reason)
{
  ServerResponse resp = {};
  resp.valid = false;
  strncpy(resp.status, "error", sizeof(resp.status) - 1);
  strncpy(resp.action, "reject", sizeof(resp.action) - 1);
  if (reason)
  {
    strncpy(resp.reason, reason, sizeof(resp.reason) - 1);
  }
  return resp;
}

static String endpoint_url(const char *path)
{
  String url = SERVER_BASE_URL;
  url += path;
  return url;
}

static ServerResponse parse_trigger_response(const String &json)
{
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, json);

  if (err)
  {
    Serial.printf("[JSON] Parse error: %s\n", err.c_str());
    return make_invalid_response("invalid_json");
  }

  ServerResponse resp = {};
  resp.valid = true;
  strncpy(resp.status, doc["status"] | "", sizeof(resp.status) - 1);
  strncpy(resp.plate, doc["plate"] | "", sizeof(resp.plate) - 1);
  strncpy(resp.action, doc["action"] | "", sizeof(resp.action) - 1);
  strncpy(resp.reason, doc["reason"] | "", sizeof(resp.reason) - 1);

  Serial.printf("[HTTP] status=%s action=%s plate=%s reason=%s\n",
                resp.status,
                resp.action,
                resp.plate,
                resp.reason);
  return resp;
}

ServerResponse http_send_trigger(const char *gate, int slot_mask)
{
  if (WiFi.status() != WL_CONNECTED)
  {
    Serial.println("[HTTP] WiFi not connected; trigger skipped");
    return make_invalid_response("wifi_disconnected");
  }

  JsonDocument doc;
  doc["gate"] = gate;
  doc["slot_mask"] = slot_mask;

  String body;
  serializeJson(doc, body);

  HTTPClient http;
  http.setTimeout(HTTP_TIMEOUT_MS);

  String url = endpoint_url("/trigger");
  if (!http.begin(url))
  {
    Serial.println("[HTTP] Failed to begin trigger request");
    return make_invalid_response("http_begin_failed");
  }

  http.addHeader("Content-Type", "application/json");
  Serial.printf("[HTTP] POST %s %s\n", url.c_str(), body.c_str());

  int httpCode = http.POST(body);
  if (httpCode != HTTP_CODE_OK && httpCode != HTTP_CODE_CREATED)
  {
    Serial.printf("[HTTP] Trigger failed code=%d %s\n", httpCode, http.errorToString(httpCode).c_str());
    http.end();
    return make_invalid_response("http_error");
  }

  String payload = http.getString();
  http.end();
  return parse_trigger_response(payload);
}

bool http_send_slot_update(int slot_mask)
{
  if (WiFi.status() != WL_CONNECTED)
  {
    Serial.println("[HTTP] WiFi not connected; slot update skipped");
    return false;
  }

  JsonDocument doc;
  doc["slot_mask"] = slot_mask;

  String body;
  serializeJson(doc, body);

  HTTPClient http;
  http.setTimeout(HTTP_TIMEOUT_MS);

  String url = endpoint_url("/update_slots");
  if (!http.begin(url))
  {
    Serial.println("[HTTP] Failed to begin slot update request");
    return false;
  }

  http.addHeader("Content-Type", "application/json");
  Serial.printf("[HTTP] POST %s %s\n", url.c_str(), body.c_str());

  int httpCode = http.POST(body);
  if (httpCode != HTTP_CODE_OK && httpCode != HTTP_CODE_CREATED)
  {
    Serial.printf("[HTTP] Slot update failed code=%d %s\n", httpCode, http.errorToString(httpCode).c_str());
    http.end();
    return false;
  }

  http.end();
  return true;
}
