##=============================================================================
## Constraints for parking_uart_top
## Board: MicroPhase Artyx A7 Lite 35T (Artix-7 XC7A35T)
## Notes:
##   - Pins are assigned only from the provided board pinout reference.
##   - The system clock uses the documented 50 MHz oscillator on CLK_50M/J19.
##   - All external project I/O is mapped to documented JP1 GPIO pins.
##=============================================================================

##=============================================================================
## System clock and reset
##=============================================================================
set_property PACKAGE_PIN J19 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 20.000 -name sys_clk [get_ports clk]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## KEY1 (K1) on board, active level handled by RTL as rst_n
set_property PACKAGE_PIN AA1 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]
set_property PULLUP true [get_ports rst_n]

##=============================================================================
## UART interface on JP1 GPIO
##=============================================================================
set_property PACKAGE_PIN W22 [get_ports uart_rx_i]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_i]

set_property PACKAGE_PIN P17 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_o]

##=============================================================================
## Failsafe buttons on JP1 GPIO
## Active-low buttons with external pull-up
##=============================================================================
set_property PACKAGE_PIN W20 [get_ports entry_failsafe_btn_raw]
set_property IOSTANDARD LVCMOS33 [get_ports entry_failsafe_btn_raw]
set_property PULLUP true [get_ports entry_failsafe_btn_raw]
set_property PACKAGE_PIN AB18 [get_ports exit_failsafe_btn_raw]
set_property IOSTANDARD LVCMOS33 [get_ports exit_failsafe_btn_raw]
set_property PULLUP true [get_ports exit_failsafe_btn_raw]

##=============================================================================
## Parking slot IR sensors on JP1 GPIO
##=============================================================================
set_property PACKAGE_PIN R19 [get_ports {ir_sensors_raw[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ir_sensors_raw[0]}]

set_property PACKAGE_PIN T18 [get_ports {ir_sensors_raw[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ir_sensors_raw[1]}]

set_property PACKAGE_PIN U21 [get_ports {ir_sensors_raw[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ir_sensors_raw[2]}]

set_property PACKAGE_PIN V22 [get_ports {ir_sensors_raw[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ir_sensors_raw[3]}]

##=============================================================================
## Entry/exit barrier IR sensors on JP1 GPIO
##=============================================================================
set_property PACKAGE_PIN Y22 [get_ports entry_ir1_raw]
set_property IOSTANDARD LVCMOS33 [get_ports entry_ir1_raw]

set_property PACKAGE_PIN AA21 [get_ports entry_ir2_raw]
set_property IOSTANDARD LVCMOS33 [get_ports entry_ir2_raw]

set_property PACKAGE_PIN AB22 [get_ports exit_ir1_raw]
set_property IOSTANDARD LVCMOS33 [get_ports exit_ir1_raw]

set_property PACKAGE_PIN AB20 [get_ports exit_ir2_raw]
set_property IOSTANDARD LVCMOS33 [get_ports exit_ir2_raw]

##=============================================================================
## Servo PWM outputs on JP1 GPIO
##=============================================================================
set_property PACKAGE_PIN V20 [get_ports entry_servo_pwm]
set_property IOSTANDARD LVCMOS33 [get_ports entry_servo_pwm]

set_property PACKAGE_PIN Y19 [get_ports exit_servo_pwm]
set_property IOSTANDARD LVCMOS33 [get_ports exit_servo_pwm]

##=============================================================================
## Slot occupancy debug/status outputs on JP1 GPIO
##=============================================================================
set_property PACKAGE_PIN AA20 [get_ports {slot_occupied[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {slot_occupied[0]}]

set_property PACKAGE_PIN AB21 [get_ports {slot_occupied[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {slot_occupied[1]}]

set_property PACKAGE_PIN AA19 [get_ports {slot_occupied[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {slot_occupied[2]}]

set_property PACKAGE_PIN U20 [get_ports {slot_occupied[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {slot_occupied[3]}]

##=============================================================================
## Error and busy status outputs on JP1 GPIO
##=============================================================================
set_property PACKAGE_PIN Y18 [get_ports tx_busy]
set_property IOSTANDARD LVCMOS33 [get_ports tx_busy]

set_property PACKAGE_PIN W19 [get_ports system_alive_led]
set_property IOSTANDARD LVCMOS33 [get_ports system_alive_led]

set_property PACKAGE_PIN AA18 [get_ports system_error_led]
set_property IOSTANDARD LVCMOS33 [get_ports system_error_led]

##=============================================================================
## LCD 16x2 HD44780 4-bit parallel interface on JP2 GPIO
## RW is tied to GND externally. Backlight is powered externally.
##=============================================================================
set_property PACKAGE_PIN D17 [get_ports lcd_rs]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rs]

set_property PACKAGE_PIN C13 [get_ports lcd_en]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_en]

set_property PACKAGE_PIN E16 [get_ports {lcd_d[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[0]}]

set_property PACKAGE_PIN D14 [get_ports {lcd_d[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[1]}]

set_property PACKAGE_PIN E13 [get_ports {lcd_d[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[2]}]

set_property PACKAGE_PIN F13 [get_ports {lcd_d[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[3]}]

##=============================================================================
## Common-cathode seven-segment display on JP1 GPIO
## seven_seg[0]..seven_seg[6] = a..g, active-high
##=============================================================================
set_property PACKAGE_PIN W21 [get_ports {seven_seg[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seven_seg[0]}]

set_property PACKAGE_PIN N17 [get_ports {seven_seg[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seven_seg[1]}]

set_property PACKAGE_PIN P19 [get_ports {seven_seg[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seven_seg[2]}]

set_property PACKAGE_PIN R18 [get_ports {seven_seg[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seven_seg[3]}]

set_property PACKAGE_PIN T21 [get_ports {seven_seg[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seven_seg[4]}]

set_property PACKAGE_PIN U22 [get_ports {seven_seg[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seven_seg[5]}]

set_property PACKAGE_PIN Y21 [get_ports {seven_seg[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seven_seg[6]}]

##=============================================================================
## UART error/status outputs on JP1 GPIO
##=============================================================================
set_property PACKAGE_PIN V18 [get_ports parser_checksum_error]
set_property IOSTANDARD LVCMOS33 [get_ports parser_checksum_error]

set_property PACKAGE_PIN V19 [get_ports parser_frame_error]
set_property IOSTANDARD LVCMOS33 [get_ports parser_frame_error]

set_property PACKAGE_PIN V17 [get_ports response_busy]
set_property IOSTANDARD LVCMOS33 [get_ports response_busy]

set_property PACKAGE_PIN W17 [get_ports rx_framing_error]
set_property IOSTANDARD LVCMOS33 [get_ports rx_framing_error]

set_property PACKAGE_PIN U17 [get_ports rx_overflow_error]
set_property IOSTANDARD LVCMOS33 [get_ports rx_overflow_error]

set_property PACKAGE_PIN U18 [get_ports rx_parity_error]
set_property IOSTANDARD LVCMOS33 [get_ports rx_parity_error]

##=============================================================================
## Unmapped top-level ports
##=============================================================================
## None. All top-level ports in parking_uart_top.v are assigned PACKAGE_PIN and
## IOSTANDARD constraints using documented MicroPhase Artyx A7 Lite pins.

set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

