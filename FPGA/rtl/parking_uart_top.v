`timescale 1ns/1ps

//============================================================================
// Module : parking_uart_top
// Desc   : Smart parking UART subsystem for ESP32 WiFi bridge.
//============================================================================

module parking_uart_top #(
    parameter CLK_FREQ      = 50_000_000,
    parameter BAUD          = 115_200,
    parameter OVERSAMPLE    = 16,
    parameter FIFO_DEPTH    = 16,
    parameter MAX_PAYLOAD   = 16,
    parameter NUM_SLOTS     = 4,
    parameter DEBOUNCE_CLKS = 500_000,
    parameter TIMEOUT_CLKS  = 5_000_000,
    parameter GATE_TIMEOUT_CLKS = CLK_FREQ * 5
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // UART pins
    input  wire                    uart_rx_i,
    output wire                    uart_tx_o,

    // parking hardware
    input  wire [NUM_SLOTS-1:0]    ir_sensors_raw,
    input  wire                    entry_ir1_raw,
    input  wire                    entry_ir2_raw,
    input  wire                    exit_ir1_raw,
    input  wire                    exit_ir2_raw,

    // failsafe buttons (active-low, external pull-up)
    input  wire                    entry_failsafe_btn_raw,
    input  wire                    exit_failsafe_btn_raw,

    output wire                    entry_servo_pwm,
    output wire                    exit_servo_pwm,
    output wire [NUM_SLOTS-1:0]    slot_occupied,

    // LCD 16x2 HD44780 4-bit parallel interface
    output wire                    lcd_rs,
    output wire                    lcd_en,
    output wire [3:0]              lcd_d,

    // common-cathode seven-segment display
    output wire [6:0]              seven_seg,

    // status / errors (active-high one-cycle pulses)
    output wire                    rx_overflow_error,
    output wire                    rx_framing_error,
    output wire                    rx_parity_error,
    output wire                    parser_checksum_error,
    output wire                    parser_frame_error,
    output wire                    tx_busy,
    output wire                    response_busy,
    output wire                    system_alive_led,
    output wire                    system_error_led
);

    // ---- power-on reset (holds rst low for first 16 clocks) ----
    reg [3:0] por_cnt = 4'd0;
    wire      por_done = (por_cnt == 4'd15);
    always @(posedge clk) begin
        if (!por_done)
            por_cnt <= por_cnt + 1'b1;
    end
    wire rst_n_int = rst_n & por_done;

    // uart_rx -> frame_parser
    wire [7:0] rx_rd_data;
    wire       rx_rd_valid;
    wire       rx_fifo_empty;
    wire       rx_rd_en;

    // uart_rx bypass outputs
    wire [7:0] rx_data_raw;
    wire       rx_data_valid_raw;

    // frame_parser -> parking_command_controller
    wire                        cmd_valid;
    wire [7:0]                  cmd_id;
    wire [MAX_PAYLOAD*8-1:0]    cmd_payload;
    wire [7:0]                  cmd_payload_len;

    // barrier IR debounce -> parking_command_controller
    wire [3:0]                  barrier_ir_raw;
    wire [3:0]                  barrier_ir_active;
    reg  [3:0]                  barrier_ir_active_prev;
    wire                        entry_ir1_event;
    wire                        entry_ir2_event;
    wire                        exit_ir1_event;
    wire                        exit_ir2_event;

    // parking_command_controller -> servo_pwm_controller
    wire                        entry_gate_open;
    wire                        entry_gate_close;
    wire                        exit_gate_open;
    wire                        exit_gate_close;

    // parking_command_controller -> uart_response_tx
    wire                        ctrl_resp_req;
    wire [7:0]                  ctrl_resp_cmd;
    wire [MAX_PAYLOAD*8-1:0]    ctrl_resp_payload;
    wire [7:0]                  ctrl_resp_len;

    // uart_response_tx -> uart_tx
    wire [7:0] resp_tx_data;
    wire       resp_tx_start;
    wire       utx_busy;
    wire       resp_busy_w;

    assign tx_busy       = utx_busy;
    assign response_busy = resp_busy_w;

    // parking_command_controller -> lcd_content_mux
    wire                        ctrl_lcd_msg_valid;
    wire [127:0]                ctrl_lcd_msg_line0;
    wire [127:0]                ctrl_lcd_msg_line1;

    // lcd_content_mux -> lcd_string_writer
    wire                        lcd_update;
    wire [127:0]                lcd_line0;
    wire [127:0]                lcd_line1;
    wire                        lcd_writer_busy;

    wire [3:0]                  occupied_count;
    wire [3:0]                  free_count;

    assign occupied_count = slot_occupied[0] + slot_occupied[1] + slot_occupied[2] + slot_occupied[3];
    assign free_count     = NUM_SLOTS[3:0] - occupied_count;

    seven_seg_decoder u_seven_seg_decoder (
        .digit (free_count),
        .seg   (seven_seg)
    );

    uart_rx #(
        .CLK_FREQ   (CLK_FREQ),
        .BAUD       (BAUD),
        .OVERSAMPLE (OVERSAMPLE),
        .FIFO_DEPTH (FIFO_DEPTH),
        .PARITY_EN  (0),
        .PARITY_ODD (0)
    ) u_uart_rx (
        .clk            (clk),
        .rst_n          (rst_n_int),
        .rx             (uart_rx_i),
        .rd_en          (rx_rd_en),
        .rd_data        (rx_rd_data),
        .rd_valid       (rx_rd_valid),
        .fifo_empty     (rx_fifo_empty),
        .fifo_full      (),
        .fifo_level     (),
        .framing_error  (rx_framing_error),
        .parity_error   (rx_parity_error),
        .overflow_error (rx_overflow_error),
        .data           (rx_data_raw),
        .data_valid     (rx_data_valid_raw)
    );

    uart_frame_parser #(
        .MAX_PAYLOAD  (MAX_PAYLOAD),
        .TIMEOUT_CLKS (TIMEOUT_CLKS)
    ) u_parser (
        .clk             (clk),
        .rst_n           (rst_n_int),
        .rx_data         (rx_rd_data),
        .rx_valid        (rx_rd_valid),
        .rx_rd_en        (rx_rd_en),
        .command_valid   (cmd_valid),
        .command_id      (cmd_id),
        .payload         (cmd_payload),
        .payload_len     (cmd_payload_len),
        .checksum_error  (parser_checksum_error),
        .frame_error     (parser_frame_error)
    );

    ir_sensor_debounce #(
        .NUM_SLOTS     (NUM_SLOTS),
        .DEBOUNCE_CLKS (DEBOUNCE_CLKS)
    ) u_ir_sensor_debounce (
        .clk            (clk),
        .rst_n          (rst_n_int),
        .ir_sensors_raw (ir_sensors_raw),
        .slot_occupied  (slot_occupied)
    );

    // barrier IR debounce (reuse same module, 4 sensors)
    assign barrier_ir_raw = {exit_ir2_raw, exit_ir1_raw, entry_ir2_raw, entry_ir1_raw};

    ir_sensor_debounce #(
        .NUM_SLOTS     (4),
        .DEBOUNCE_CLKS (DEBOUNCE_CLKS)
    ) u_barrier_ir_debounce (
        .clk            (clk),
        .rst_n          (rst_n_int),
        .ir_sensors_raw (barrier_ir_raw),
        .slot_occupied  (barrier_ir_active)
    );

    // falling-edge detection: active-low sensors, so HIGH->LOW on raw
    // means active goes 0->1 in debounced domain; detect rising edge of active
    always @(posedge clk) begin
        if (!rst_n_int)
            barrier_ir_active_prev <= 4'b0;
        else
            barrier_ir_active_prev <= barrier_ir_active;
    end

    assign entry_ir1_event = barrier_ir_active[0] & ~barrier_ir_active_prev[0];
    assign entry_ir2_event = barrier_ir_active[1] & ~barrier_ir_active_prev[1];
    assign exit_ir1_event  = barrier_ir_active[2] & ~barrier_ir_active_prev[2];
    assign exit_ir2_event  = barrier_ir_active[3] & ~barrier_ir_active_prev[3];

    // failsafe button sync + debounce + edge detect (active-low)
    reg  [1:0] entry_fs_sync;
    reg  [1:0] exit_fs_sync;
    wire [1:0] fs_debounce_raw;
    wire [1:0] fs_debounce_out;
    reg  [1:0] fs_debounce_prev;
    wire       entry_failsafe_event;
    wire       exit_failsafe_event;

    assign fs_debounce_raw = {exit_fs_sync[1], entry_fs_sync[1]};

    always @(posedge clk) begin
        if (!rst_n_int) begin
            entry_fs_sync <= 2'b11;
            exit_fs_sync  <= 2'b11;
        end else begin
            entry_fs_sync <= {entry_fs_sync[0], entry_failsafe_btn_raw};
            exit_fs_sync  <= {exit_fs_sync[0], exit_failsafe_btn_raw};
        end
    end

    ir_sensor_debounce #(
        .NUM_SLOTS     (2),
        .DEBOUNCE_CLKS (DEBOUNCE_CLKS)
    ) u_failsafe_debounce (
        .clk            (clk),
        .rst_n          (rst_n_int),
        .ir_sensors_raw (fs_debounce_raw),
        .slot_occupied  (fs_debounce_out)
    );

    always @(posedge clk) begin
        if (!rst_n_int)
            fs_debounce_prev <= 2'b0;
        else
            fs_debounce_prev <= fs_debounce_out;
    end

    assign entry_failsafe_event = fs_debounce_out[0] & ~fs_debounce_prev[0];
    assign exit_failsafe_event  = fs_debounce_out[1] & ~fs_debounce_prev[1];

    parking_command_controller #(
        .CLK_FREQ          (CLK_FREQ),
        .NUM_SLOTS         (NUM_SLOTS),
        .MAX_PAYLOAD       (MAX_PAYLOAD),
        .GATE_TIMEOUT_CLKS (GATE_TIMEOUT_CLKS)
    ) u_ctrl (
        .clk             (clk),
        .rst_n           (rst_n_int),
        .command_valid   (cmd_valid),
        .command_id      (cmd_id),
        .cmd_payload     (cmd_payload),
        .cmd_payload_len   (cmd_payload_len),
        .sensor_status     (slot_occupied),
        .entry_ir1_event   (entry_ir1_event),
        .entry_ir2_event   (entry_ir2_event),
        .exit_ir1_event    (exit_ir1_event),
        .exit_ir2_event    (exit_ir2_event),
        .entry_failsafe_event (entry_failsafe_event),
        .exit_failsafe_event  (exit_failsafe_event),
        .entry_gate_open   (entry_gate_open),
        .entry_gate_close  (entry_gate_close),
        .exit_gate_open    (exit_gate_open),
        .exit_gate_close   (exit_gate_close),
        .resp_busy       (resp_busy_w),
        .resp_req        (ctrl_resp_req),
        .resp_cmd        (ctrl_resp_cmd),
        .resp_payload    (ctrl_resp_payload),
        .resp_len        (ctrl_resp_len),
        .lcd_msg_valid   (ctrl_lcd_msg_valid),
        .lcd_msg_line0   (ctrl_lcd_msg_line0),
        .lcd_msg_line1   (ctrl_lcd_msg_line1)
    );

    lcd_content_mux #(
        .CLK_FREQ  (CLK_FREQ),
        .NUM_SLOTS (NUM_SLOTS)
    ) u_lcd_content_mux (
        .clk           (clk),
        .rst_n         (rst_n_int),
        .slot_occupied (slot_occupied),
        .writer_busy   (lcd_writer_busy),
        .msg_valid     (ctrl_lcd_msg_valid),
        .msg_line0     (ctrl_lcd_msg_line0),
        .msg_line1     (ctrl_lcd_msg_line1),
        .lcd_update    (lcd_update),
        .lcd_line0     (lcd_line0),
        .lcd_line1     (lcd_line1)
    );

    lcd_string_writer #(
        .CLK_FREQ (CLK_FREQ)
    ) u_lcd_string_writer (
        .clk     (clk),
        .rst_n   (rst_n_int),
        .update  (lcd_update),
        .line0   (lcd_line0),
        .line1   (lcd_line1),
        .busy    (lcd_writer_busy),
        .lcd_rs  (lcd_rs),
        .lcd_en  (lcd_en),
        .lcd_d   (lcd_d)
    );

    servo_pwm_controller #(
        .CLK_FREQ (CLK_FREQ)
    ) u_servo_pwm_controller (
        .clk              (clk),
        .rst_n            (rst_n_int),
        .entry_gate_open  (entry_gate_open),
        .entry_gate_close (entry_gate_close),
        .exit_gate_open   (exit_gate_open),
        .exit_gate_close  (exit_gate_close),
        .entry_servo_pwm  (entry_servo_pwm),
        .exit_servo_pwm   (exit_servo_pwm)
    );

    uart_response_tx #(
        .MAX_PAYLOAD (MAX_PAYLOAD)
    ) u_resp_tx (
        .clk                   (clk),
        .rst_n                 (rst_n_int),
        .resp_req              (ctrl_resp_req),
        .resp_cmd              (ctrl_resp_cmd),
        .resp_payload          (ctrl_resp_payload),
        .resp_len              (ctrl_resp_len),
        .parser_checksum_error (parser_checksum_error),
        .parser_frame_error    (parser_frame_error),
        .tx_busy               (utx_busy),
        .tx_data               (resp_tx_data),
        .tx_start              (resp_tx_start),
        .busy                  (resp_busy_w)
    );

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD     (BAUD)
    ) u_uart_tx (
        .clk      (clk),
        .rst_n    (rst_n_int),
        .tx_data  (resp_tx_data),
        .tx_start (resp_tx_start),
        .tx       (uart_tx_o),
        .tx_busy  (utx_busy),
        .tx_done  ()
    );

    localparam integer ALIVE_TOGGLE_CLKS = CLK_FREQ / 2;
    localparam integer ALIVE_CNT_W = (ALIVE_TOGGLE_CLKS <= 1) ? 1 : $clog2(ALIVE_TOGGLE_CLKS);
    localparam [ALIVE_CNT_W-1:0] ALIVE_TOGGLE_LIMIT = ALIVE_TOGGLE_CLKS - 1;

    reg [ALIVE_CNT_W-1:0] alive_cnt;
    reg                   alive_led_r;
    reg                   error_led_r;

    always @(posedge clk) begin
        if (!rst_n_int) begin
            alive_cnt   <= {ALIVE_CNT_W{1'b0}};
            alive_led_r <= 1'b0;
        end else if (alive_cnt == ALIVE_TOGGLE_LIMIT) begin
            alive_cnt   <= {ALIVE_CNT_W{1'b0}};
            alive_led_r <= ~alive_led_r;
        end else begin
            alive_cnt <= alive_cnt + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n_int) begin
            error_led_r <= 1'b0;
        end else if (rx_overflow_error || rx_framing_error || rx_parity_error ||
                     parser_checksum_error || parser_frame_error) begin
            error_led_r <= 1'b1;
        end
    end

    assign system_alive_led = alive_led_r;
    assign system_error_led = error_led_r;

endmodule
