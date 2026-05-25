#ifndef LCD_DISPLAY_H
#define LCD_DISPLAY_H

#include <Arduino.h>
#include "http_client.h"

void lcd_display_init();
void lcd_display_update();

void lcd_show_idle(int slot_mask);
void lcd_show_checking(const char *gate);
void lcd_show_result(const ServerResponse &resp);
void lcd_show_manual_open(const char *gate);
void lcd_show_error(const char *message);

#endif
