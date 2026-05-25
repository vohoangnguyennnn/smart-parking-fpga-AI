#ifndef FPGA_UART_H
#define FPGA_UART_H

#include <Arduino.h>

typedef void (*FpgaFrameHandler)(uint8_t cmd, const uint8_t *payload, uint8_t len);

static constexpr uint8_t FPGA_CMD_OPEN_GATE = 0x01;
static constexpr uint8_t FPGA_CMD_REQUEST_STATUS = 0x05;
static constexpr uint8_t FPGA_CMD_PING = 0x7F;

static constexpr uint8_t FPGA_RSP_PARKING_STATUS = 0x10;
static constexpr uint8_t FPGA_RSP_GATE_EVENT = 0x11;
static constexpr uint8_t FPGA_RSP_FAILSAFE_EVENT = 0x12;
static constexpr uint8_t FPGA_RSP_ACK = 0x80;
static constexpr uint8_t FPGA_RSP_NACK = 0x81;
static constexpr uint8_t FPGA_RSP_PONG = 0x82;

void fpga_uart_init();
void fpga_uart_set_frame_handler(FpgaFrameHandler handler);
void fpga_uart_poll();
void fpga_uart_send_frame(uint8_t cmd, const uint8_t *payload, uint8_t len);
void fpga_uart_send_open_gate(uint8_t gate);

#endif
