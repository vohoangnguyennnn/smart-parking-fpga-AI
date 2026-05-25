#ifndef HTTP_CLIENT_H
#define HTTP_CLIENT_H

#include <Arduino.h>

struct ServerResponse
{
  bool valid;
  char status[16];
  char plate[32];
  char action[32];
  char reason[32];
};

ServerResponse http_send_trigger(const char *gate, int slot_mask);
bool http_send_slot_update(int slot_mask);

#endif