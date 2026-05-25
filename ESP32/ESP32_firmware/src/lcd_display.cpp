#include "lcd_display.h"
#include "config.h"
#include "fpga_uart.h"
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static constexpr uint8_t CMD_LCD_LINE0 = 0x06;
static constexpr uint8_t CMD_LCD_LINE1 = 0x07;

static void set_line(char line[LCD_COLS + 1], const char *text)
{
  int i = 0;
  for (; i < LCD_COLS && text && text[i] != '\0'; ++i)
  {
    line[i] = text[i];
  }
  for (; i < LCD_COLS; ++i)
  {
    line[i] = ' ';
  }
  line[LCD_COLS] = '\0';
}

static void set_formatted_line(char line[LCD_COLS + 1], const char *fmt, ...)
{
  char buffer[64];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buffer, sizeof(buffer), fmt, args);
  va_end(args);
  set_line(line, buffer);
}

static void send_lines(const char *line0Text, const char *line1Text)
{
  char line0[LCD_COLS + 1];
  char line1[LCD_COLS + 1];

  set_line(line0, line0Text);
  set_line(line1, line1Text);

  fpga_uart_send_frame(CMD_LCD_LINE0, reinterpret_cast<const uint8_t *>(line0), LCD_COLS);
  fpga_uart_send_frame(CMD_LCD_LINE1, reinterpret_cast<const uint8_t *>(line1), LCD_COLS);
}

void lcd_display_init()
{
  Serial.println("[LCD] FPGA LCD output enabled");
}

void lcd_display_update()
{
}

void lcd_show_idle(int slot_mask)
{
  (void)slot_mask;
}

void lcd_show_checking(const char *gate)
{
  char line0[LCD_COLS + 1];
  set_formatted_line(line0, "DANG KIEM TRA %s", gate);
  send_lines(line0, "XIN DOI...");
}

void lcd_show_result(const ServerResponse &resp)
{
  char line1[LCD_COLS + 1];

  if (!resp.valid)
  {
    send_lines("MAT KET NOI", "KHONG PHAN HOI");
    return;
  }

  bool statusOk = strcmp(resp.status, "ok") == 0;
  bool openEntry = statusOk && strcmp(resp.action, "open_entry") == 0;
  bool openExit = statusOk && strcmp(resp.action, "open_exit") == 0;

  set_formatted_line(line1, "Plate:%s", resp.plate[0] ? resp.plate : "KHONG CO");

  if (openEntry)
  {
    send_lines("XIN MOI VAO", line1);
  }
  else if (openExit)
  {
    send_lines("XIN MOI RA", line1);
  }
  else
  {
    send_lines("TU CHOI", line1);
  }
}

void lcd_show_manual_open(const char *gate)
{
  char line0[LCD_COLS + 1];
  set_formatted_line(line0, "MO/DONG CUA %s", gate);
  send_lines(line0, "MANUAL");
}

void lcd_show_error(const char *message)
{
  send_lines("LOI KET NOI", message ? message : "KHONG PHAN HOI");
}
