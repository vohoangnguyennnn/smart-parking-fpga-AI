onerror {resume}
view wave
quietly WaveActivateNextPane {} 0

proc wave_exists {path} {
    return [expr {[llength [find signals $path]] != 0}]
}

proc add_signal {args} {
    set path [lindex $args end]
    if {[wave_exists $path]} {
        eval add wave -noupdate $args
    }
}

proc add_group {name signals} {
    set added 0
    foreach item $signals {
        set path [lindex $item end]
        if {[wave_exists $path]} {
            if {$added == 0} {
                add wave -noupdate -divider $name
                set added 1
            }
            eval add wave -noupdate $item
        }
    }
}

# tb_uart_rx waveform
add_group {UART RX TB} {
    {/tb_uart_rx/clk}
    {/tb_uart_rx/rst_n}
    {/tb_uart_rx/rx}
    {/tb_uart_rx/rd_en}
    {-radix hex /tb_uart_rx/rd_data}
    {/tb_uart_rx/rd_valid}
    {/tb_uart_rx/fifo_empty}
    {/tb_uart_rx/fifo_full}
    {-radix unsigned /tb_uart_rx/fifo_level}
    {/tb_uart_rx/framing_error}
    {/tb_uart_rx/parity_error}
    {/tb_uart_rx/overflow_error}
    {-radix hex /tb_uart_rx/data}
    {/tb_uart_rx/data_valid}
    {-radix unsigned /tb_uart_rx/dut/state}
    {-radix unsigned /tb_uart_rx/dut/sample_cnt}
    {-radix unsigned /tb_uart_rx/dut/os_cnt}
    {-radix unsigned /tb_uart_rx/dut/bit_idx}
    {-radix hex /tb_uart_rx/dut/shift_reg}
}

# tb_uart_tx waveform
add_group {UART TX TB} {
    {/tb_uart_tx/clk}
    {/tb_uart_tx/rst_n}
    {-radix hex /tb_uart_tx/tx_data}
    {/tb_uart_tx/tx_start}
    {/tb_uart_tx/tx}
    {/tb_uart_tx/tx_busy}
    {/tb_uart_tx/tx_done}
    {-radix unsigned /tb_uart_tx/dut/state}
    {-radix unsigned /tb_uart_tx/dut/clk_cnt}
    {-radix unsigned /tb_uart_tx/dut/bit_idx}
    {-radix hex /tb_uart_tx/dut/shift_reg}
}

# tb_uart_frame_parser waveform
add_group {UART Frame Parser TB} {
    {/tb_uart_frame_parser/clk}
    {/tb_uart_frame_parser/rst_n}
    {-radix hex /tb_uart_frame_parser/rx_data}
    {/tb_uart_frame_parser/rx_valid}
    {/tb_uart_frame_parser/rx_rd_en}
    {/tb_uart_frame_parser/command_valid}
    {-radix hex /tb_uart_frame_parser/command_id}
    {-radix unsigned /tb_uart_frame_parser/payload_len}
    {-radix hex /tb_uart_frame_parser/payload}
    {/tb_uart_frame_parser/checksum_error}
    {/tb_uart_frame_parser/frame_error}
    {-radix unsigned /tb_uart_frame_parser/dut/state}
    {-radix unsigned /tb_uart_frame_parser/dut/byte_cnt}
    {-radix hex /tb_uart_frame_parser/dut/running_xor}
}

# tb_lcd_content_mux waveform
add_group {LCD Content Mux TB} {
    {/tb_lcd_content_mux/clk}
    {/tb_lcd_content_mux/rst_n}
    {-radix binary /tb_lcd_content_mux/slot_occupied}
    {/tb_lcd_content_mux/writer_busy}
    {/tb_lcd_content_mux/msg_valid}
    {-radix ascii /tb_lcd_content_mux/msg_line0}
    {-radix ascii /tb_lcd_content_mux/msg_line1}
    {/tb_lcd_content_mux/lcd_update}
    {-radix ascii /tb_lcd_content_mux/lcd_line0}
    {-radix ascii /tb_lcd_content_mux/lcd_line1}
    {-radix unsigned /tb_lcd_content_mux/dut/hold_cnt}
    {/tb_lcd_content_mux/dut/message_active}
    {/tb_lcd_content_mux/dut/pending_update}
    {-radix binary /tb_lcd_content_mux/dut/slot_prev}
    {-radix ascii /tb_lcd_content_mux/dut/active_line0}
    {-radix ascii /tb_lcd_content_mux/dut/active_line1}
}

# tb_lcd_string_writer waveform
add_group {LCD String Writer TB} {
    {/tb_lcd_string_writer/clk}
    {/tb_lcd_string_writer/rst_n}
    {/tb_lcd_string_writer/update}
    {-radix ascii /tb_lcd_string_writer/line0}
    {-radix ascii /tb_lcd_string_writer/line1}
    {/tb_lcd_string_writer/busy}
    {/tb_lcd_string_writer/lcd_rs}
    {/tb_lcd_string_writer/lcd_en}
    {-radix hex /tb_lcd_string_writer/lcd_d}
    {-radix unsigned /tb_lcd_string_writer/dut/state}
    {-radix unsigned /tb_lcd_string_writer/dut/char_idx}
    {/tb_lcd_string_writer/dut/lcd_wr_en}
    {/tb_lcd_string_writer/dut/lcd_wr_rs}
    {-radix hex /tb_lcd_string_writer/dut/lcd_wr_data}
    {-radix unsigned /tb_lcd_string_writer/dut/u_lcd_hd44780/state}
}

# tb_lcd_hd44780 waveform
add_group {LCD HD44780 TB} {
    {/tb_lcd_hd44780/clk}
    {/tb_lcd_hd44780/rst_n}
    {/tb_lcd_hd44780/wr_en}
    {/tb_lcd_hd44780/wr_rs}
    {-radix hex /tb_lcd_hd44780/wr_data}
    {/tb_lcd_hd44780/busy}
    {/tb_lcd_hd44780/lcd_rs}
    {/tb_lcd_hd44780/lcd_en}
    {-radix hex /tb_lcd_hd44780/lcd_d}
    {-radix unsigned /tb_lcd_hd44780/dut/state}
    {-radix unsigned /tb_lcd_hd44780/dut/return_state}
    {-radix unsigned /tb_lcd_hd44780/dut/delay_cnt}
    {-radix hex /tb_lcd_hd44780/dut/send_data}
    {/tb_lcd_hd44780/dut/send_rs}
    {/tb_lcd_hd44780/dut/single_nibble}
}

# tb_parking_command_controller waveform
add_group {Parking Controller TB} {
    {/tb_parking_command_controller/clk}
    {/tb_parking_command_controller/rst_n}
    {/tb_parking_command_controller/command_valid}
    {-radix hex /tb_parking_command_controller/command_id}
    {-radix unsigned /tb_parking_command_controller/cmd_payload_len}
    {-radix hex /tb_parking_command_controller/cmd_payload}
    {-radix binary /tb_parking_command_controller/sensor_status}
    {/tb_parking_command_controller/resp_busy}
    {/tb_parking_command_controller/resp_req}
    {-radix hex /tb_parking_command_controller/resp_cmd}
    {-radix unsigned /tb_parking_command_controller/resp_len}
    {-radix hex /tb_parking_command_controller/resp_payload}
    {/tb_parking_command_controller/entry_gate_open}
    {/tb_parking_command_controller/entry_gate_close}
    {/tb_parking_command_controller/exit_gate_open}
    {/tb_parking_command_controller/exit_gate_close}
    {/tb_parking_command_controller/lcd_msg_valid}
    {-radix ascii /tb_parking_command_controller/lcd_msg_line0}
    {-radix ascii /tb_parking_command_controller/lcd_msg_line1}
    {/tb_parking_command_controller/dut/pending_valid}
    {-radix hex /tb_parking_command_controller/dut/pending_cmd}
    {/tb_parking_command_controller/dut/sensor_changed}
    {/tb_parking_command_controller/dut/entry_gate_open_active}
    {/tb_parking_command_controller/dut/exit_gate_open_active}
    {-radix unsigned /tb_parking_command_controller/dut/entry_timeout_cnt}
    {-radix unsigned /tb_parking_command_controller/dut/exit_timeout_cnt}
}

# tb_parking_uart_top waveform
add_group {Clock Reset} {
    {/tb_parking_uart_top/clk}
    {/tb_parking_uart_top/rst_n}
    {/tb_parking_uart_top/system_alive_led}
    {/tb_parking_uart_top/system_error_led}
}

add_group {Top UART Pins} {
    {/tb_parking_uart_top/uart_rx_i}
    {/tb_parking_uart_top/uart_tx_o}
    {/tb_parking_uart_top/tx_busy}
    {/tb_parking_uart_top/response_busy}
}

add_group {UART RX Decode} {
    {-radix hex /tb_parking_uart_top/dut/rx_data_raw}
    {/tb_parking_uart_top/dut/rx_data_valid_raw}
    {-radix hex /tb_parking_uart_top/dut/rx_rd_data}
    {/tb_parking_uart_top/dut/rx_rd_valid}
    {/tb_parking_uart_top/dut/rx_rd_en}
    {/tb_parking_uart_top/dut/rx_fifo_empty}
    {-color Red /tb_parking_uart_top/rx_overflow_error}
    {-color Red /tb_parking_uart_top/rx_framing_error}
    {-color Orange /tb_parking_uart_top/rx_parity_error}
}

add_group {Frame Parser} {
    {-radix unsigned /tb_parking_uart_top/dut/u_parser/state}
    {-radix hex /tb_parking_uart_top/dut/u_parser/rx_data}
    {/tb_parking_uart_top/dut/u_parser/rx_valid}
    {-radix hex /tb_parking_uart_top/dut/u_parser/cmd_reg}
    {-radix unsigned /tb_parking_uart_top/dut/u_parser/len_reg}
    {-radix unsigned /tb_parking_uart_top/dut/u_parser/byte_cnt}
    {-radix hex /tb_parking_uart_top/dut/u_parser/running_xor}
    {/tb_parking_uart_top/dut/cmd_valid}
    {-radix hex /tb_parking_uart_top/dut/cmd_id}
    {-radix unsigned /tb_parking_uart_top/dut/cmd_payload_len}
    {-radix hex /tb_parking_uart_top/dut/cmd_payload}
    {-color Red /tb_parking_uart_top/parser_checksum_error}
    {-color Red /tb_parking_uart_top/parser_frame_error}
}

add_group {Command Controller} {
    {/tb_parking_uart_top/dut/u_ctrl/command_valid}
    {-radix hex /tb_parking_uart_top/dut/u_ctrl/command_id}
    {-radix unsigned /tb_parking_uart_top/dut/u_ctrl/cmd_payload_len}
    {/tb_parking_uart_top/dut/u_ctrl/resp_busy}
    {/tb_parking_uart_top/dut/ctrl_resp_req}
    {-radix hex /tb_parking_uart_top/dut/ctrl_resp_cmd}
    {-radix unsigned /tb_parking_uart_top/dut/ctrl_resp_len}
    {-radix hex /tb_parking_uart_top/dut/ctrl_resp_payload}
    {/tb_parking_uart_top/dut/u_ctrl/pending_valid}
    {-radix hex /tb_parking_uart_top/dut/u_ctrl/pending_cmd}
    {/tb_parking_uart_top/dut/entry_gate_open}
    {/tb_parking_uart_top/dut/entry_gate_close}
    {/tb_parking_uart_top/dut/exit_gate_open}
    {/tb_parking_uart_top/dut/exit_gate_close}
}

add_group {Sensors Gate Events} {
    {-radix binary /tb_parking_uart_top/ir_sensors_raw}
    {-radix binary /tb_parking_uart_top/slot_occupied}
    {/tb_parking_uart_top/entry_ir1_raw}
    {/tb_parking_uart_top/entry_ir2_raw}
    {/tb_parking_uart_top/exit_ir1_raw}
    {/tb_parking_uart_top/exit_ir2_raw}
    {-radix binary /tb_parking_uart_top/dut/barrier_ir_active}
    {/tb_parking_uart_top/dut/entry_ir1_event}
    {/tb_parking_uart_top/dut/entry_ir2_event}
    {/tb_parking_uart_top/dut/exit_ir1_event}
    {/tb_parking_uart_top/dut/exit_ir2_event}
    {/tb_parking_uart_top/dut/u_ctrl/entry_gate_open_active}
    {/tb_parking_uart_top/dut/u_ctrl/exit_gate_open_active}
    {-radix unsigned /tb_parking_uart_top/dut/u_ctrl/entry_timeout_cnt}
    {-radix unsigned /tb_parking_uart_top/dut/u_ctrl/exit_timeout_cnt}
}

add_group {Response TX Path} {
    {-radix unsigned /tb_parking_uart_top/dut/u_resp_tx/state}
    {-radix unsigned /tb_parking_uart_top/dut/u_resp_tx/field}
    {/tb_parking_uart_top/dut/u_resp_tx/pending}
    {-radix hex /tb_parking_uart_top/dut/u_resp_tx/buf_cmd}
    {-radix unsigned /tb_parking_uart_top/dut/u_resp_tx/buf_len}
    {-radix hex /tb_parking_uart_top/dut/u_resp_tx/tx_data}
    {/tb_parking_uart_top/dut/u_resp_tx/tx_start}
    {/tb_parking_uart_top/dut/utx_busy}
    {-radix unsigned /tb_parking_uart_top/dut/u_uart_tx/state}
    {-radix hex /tb_parking_uart_top/dut/u_uart_tx/tx_data}
    {/tb_parking_uart_top/uart_tx_o}
}

add_group {LCD Subsystem} {
    {/tb_parking_uart_top/dut/ctrl_lcd_msg_valid}
    {-radix ascii /tb_parking_uart_top/dut/ctrl_lcd_msg_line0}
    {-radix ascii /tb_parking_uart_top/dut/ctrl_lcd_msg_line1}
    {/tb_parking_uart_top/dut/u_ctrl/lcd_line0_ready}
    {/tb_parking_uart_top/dut/u_ctrl/lcd_line1_ready}
    {/tb_parking_uart_top/dut/u_lcd_content_mux/message_active}
    {/tb_parking_uart_top/dut/u_lcd_content_mux/pending_update}
    {-radix unsigned /tb_parking_uart_top/dut/u_lcd_content_mux/hold_cnt}
    {/tb_parking_uart_top/dut/lcd_update}
    {-radix ascii /tb_parking_uart_top/dut/lcd_line0}
    {-radix ascii /tb_parking_uart_top/dut/lcd_line1}
    {/tb_parking_uart_top/dut/lcd_writer_busy}
    {-radix unsigned /tb_parking_uart_top/dut/u_lcd_string_writer/state}
    {-radix unsigned /tb_parking_uart_top/dut/u_lcd_string_writer/char_idx}
    {-radix unsigned /tb_parking_uart_top/dut/u_lcd_string_writer/u_lcd_hd44780/state}
    {/tb_parking_uart_top/lcd_rs}
    {/tb_parking_uart_top/lcd_en}
    {-radix hex /tb_parking_uart_top/lcd_d}
}

add_group {Servo PWM} {
    {/tb_parking_uart_top/entry_servo_pwm}
    {/tb_parking_uart_top/exit_servo_pwm}
    {-radix unsigned /tb_parking_uart_top/dut/u_servo_pwm_controller/pwm_cnt}
    {-radix unsigned /tb_parking_uart_top/dut/u_servo_pwm_controller/entry_pw}
    {-radix unsigned /tb_parking_uart_top/dut/u_servo_pwm_controller/exit_pw}
}

# tb_uart_response_tx waveform
add_group {UART Response TX TB} {
    {/tb_uart_response_tx/clk}
    {/tb_uart_response_tx/rst_n}
    {/tb_uart_response_tx/resp_req}
    {-radix hex /tb_uart_response_tx/resp_cmd}
    {-radix unsigned /tb_uart_response_tx/resp_len}
    {-radix hex /tb_uart_response_tx/resp_payload}
    {/tb_uart_response_tx/parser_checksum_error}
    {/tb_uart_response_tx/parser_frame_error}
    {/tb_uart_response_tx/tx_busy}
    {-radix hex /tb_uart_response_tx/tx_data}
    {/tb_uart_response_tx/tx_start}
    {/tb_uart_response_tx/busy}
    {-radix unsigned /tb_uart_response_tx/dut/state}
    {-radix unsigned /tb_uart_response_tx/dut/field}
    {-radix hex /tb_uart_response_tx/dut/buf_cmd}
    {-radix unsigned /tb_uart_response_tx/dut/buf_len}
    {-radix unsigned /tb_uart_response_tx/dut/byte_idx}
    {-radix hex /tb_uart_response_tx/dut/chksum}
    {/tb_uart_response_tx/dut/pending}
    {-radix hex /tb_uart_response_tx/dut/pend_cmd}
}

# tb_ir_sensor_debounce waveform
add_group {IR Sensor Debounce TB} {
    {/tb_ir_sensor_debounce/clk}
    {/tb_ir_sensor_debounce/rst_n}
    {-radix binary /tb_ir_sensor_debounce/ir_sensors_raw}
    {-radix binary /tb_ir_sensor_debounce/slot_occupied}
    {-radix binary /tb_ir_sensor_debounce/dut/sync_0}
    {-radix binary /tb_ir_sensor_debounce/dut/sync_1}
    {-radix binary /tb_ir_sensor_debounce/dut/candidate}
}

# tb_servo_pwm_controller waveform
add_group {Servo PWM Controller TB} {
    {/tb_servo_pwm_controller/clk}
    {/tb_servo_pwm_controller/rst_n}
    {/tb_servo_pwm_controller/entry_gate_open}
    {/tb_servo_pwm_controller/entry_gate_close}
    {/tb_servo_pwm_controller/exit_gate_open}
    {/tb_servo_pwm_controller/exit_gate_close}
    {/tb_servo_pwm_controller/entry_servo_pwm}
    {/tb_servo_pwm_controller/exit_servo_pwm}
    {-radix unsigned /tb_servo_pwm_controller/dut/pwm_cnt}
    {-radix unsigned /tb_servo_pwm_controller/dut/entry_pw}
    {-radix unsigned /tb_servo_pwm_controller/dut/exit_pw}
}

# tb_seven_seg_decoder waveform
add_group {Seven Seg CC TB} {
    {-radix unsigned /tb_seven_seg_decoder/digit}
    {-radix binary /tb_seven_seg_decoder/seg}
}

TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 260
configure wave -valuecolwidth 140
configure wave -timelineunits ns
update
run -all
wave zoom full
