# Questa/ModelSim simulation Makefile for smart parking UART FPGA modules

TOP       ?= tb_parking_uart_top
RTL_DIR   = ../rtl
SIM_DIR   = ../tb
WORK_LIB  = work
WAVE_DO   = wave.do

VLOG      ?= vlog
VSIM      ?= vsim
VLIB      ?= vlib
VDEL      ?= vdel

RTL_SRCS  = $(RTL_DIR)/uart_rx.v \
            $(RTL_DIR)/uart_tx.v \
            $(RTL_DIR)/uart_frame_parser.v \
            $(RTL_DIR)/uart_response_tx.v \
            $(RTL_DIR)/ir_sensor_debounce.v \
            $(RTL_DIR)/parking_command_controller.v \
            $(RTL_DIR)/servo_pwm_controller.v \
            $(RTL_DIR)/lcd_hd44780.v \
            $(RTL_DIR)/lcd_string_writer.v \
            $(RTL_DIR)/lcd_content_mux.v \
            $(RTL_DIR)/seven_seg_decoder.v \
            $(RTL_DIR)/parking_uart_top.v

TB_SRCS   = $(SIM_DIR)/tb_uart_rx.sv \
            $(SIM_DIR)/tb_uart_tx.sv \
            $(SIM_DIR)/tb_uart_frame_parser.sv \
            $(SIM_DIR)/tb_uart_response_tx.sv \
            $(SIM_DIR)/tb_parking_command_controller.sv \
            $(SIM_DIR)/tb_ir_sensor_debounce.sv \
            $(SIM_DIR)/tb_servo_pwm_controller.sv \
            $(SIM_DIR)/tb_seven_seg_decoder.sv \
            $(SIM_DIR)/tb_lcd_hd44780.sv \
            $(SIM_DIR)/tb_lcd_string_writer.sv \
            $(SIM_DIR)/tb_lcd_content_mux.sv \
            $(SIM_DIR)/tb_parking_uart_top.sv

SRCS      = $(RTL_SRCS) $(TB_SRCS)

.PHONY: all compile sim wave clean help

all: sim

$(WORK_LIB):
	$(VLIB) $(WORK_LIB)

compile: $(WORK_LIB)
	$(VLOG) -sv -work $(WORK_LIB) $(SRCS)

sim: compile
	$(VSIM) -c -voptargs=+acc $(WORK_LIB).$(TOP) -do "run -all; quit -f"

wave: compile
	$(VSIM) -voptargs=+acc $(WORK_LIB).$(TOP) -do "do $(WAVE_DO)"

clean:
	rm -rf $(WORK_LIB) transcript vsim.wlf *.vcd *.log

help:
	@echo "Questa/ModelSim simulation targets:"
	@echo "  make sim  TOP=<testbench>     Compile and run in console"
	@echo "  make wave TOP=<testbench>     Compile and open waveform GUI"
	@echo "  make compile                  Compile all RTL and testbenches"
	@echo "  make clean                    Remove generated files"
	@echo ""
	@echo "Testbenches:"
	@echo "  tb_uart_rx"
	@echo "  tb_uart_tx"
	@echo "  tb_uart_frame_parser"
	@echo "  tb_uart_response_tx"
	@echo "  tb_parking_command_controller"
	@echo "  tb_ir_sensor_debounce"
	@echo "  tb_servo_pwm_controller"
	@echo "  tb_seven_seg_decoder"
	@echo "  tb_lcd_hd44780"
	@echo "  tb_lcd_string_writer"
	@echo "  tb_lcd_content_mux"
	@echo "  tb_parking_uart_top"
