`timescale 1ns/1ps

//============================================================================
// Module : parking_command_controller
// Desc   : Processes parsed UART commands for smart parking.
//          Controls gate/barrier and reads sensor status.
//============================================================================

module parking_command_controller #(
    parameter CLK_FREQ          = 50_000_000,
    parameter NUM_SLOTS         = 4,
    parameter MAX_PAYLOAD       = 16,
    parameter GATE_TIMEOUT_CLKS = CLK_FREQ * 5
) (
    input  wire       clk,
    input  wire       rst_n,

    // from frame_parser
    input  wire                        command_valid,
    input  wire [7:0]                  command_id,
    input  wire [MAX_PAYLOAD*8-1:0]    cmd_payload,
    input  wire [7:0]                  cmd_payload_len,

    // sensor status from ir_sensor_debounce
    input  wire [NUM_SLOTS-1:0]        sensor_status,

    // barrier IR events
    input  wire                        entry_ir1_event,
    input  wire                        entry_ir2_event,
    input  wire                        exit_ir1_event,
    input  wire                        exit_ir2_event,

    // failsafe button events (one-cycle pulses)
    input  wire                        entry_failsafe_event,
    input  wire                        exit_failsafe_event,

    // hardware outputs
    output reg                         entry_gate_open,
    output reg                         entry_gate_close,
    output reg                         exit_gate_open,
    output reg                         exit_gate_close,

    // response request to uart_response_tx
    input  wire                        resp_busy,
    output reg                         resp_req,
    output reg  [7:0]                  resp_cmd,
    output reg  [MAX_PAYLOAD*8-1:0]    resp_payload,
    output reg  [7:0]                  resp_len,

    // LCD message outputs
    output reg                         lcd_msg_valid,
    output reg  [127:0]                lcd_msg_line0,
    output reg  [127:0]                lcd_msg_line1
);

    // command IDs
    localparam [7:0] CMD_OPEN_GATE      = 8'h01;
    localparam [7:0] CMD_CLOSE_GATE     = 8'h02;
    localparam [7:0] CMD_REQUEST_STATUS = 8'h05;
    localparam [7:0] CMD_LCD_LINE0      = 8'h06;
    localparam [7:0] CMD_LCD_LINE1      = 8'h07;
    localparam [7:0] CMD_PING           = 8'h7F;

    // response command IDs
    localparam [7:0] RSP_PARKING_STATUS = 8'h10;
    localparam [7:0] RSP_GATE_EVENT     = 8'h11;
    localparam [7:0] RSP_FAILSAFE_EVENT = 8'h12;
    localparam [7:0] RSP_ACK            = 8'h80;
    localparam [7:0] RSP_NACK           = 8'h81;
    localparam [7:0] RSP_PONG           = 8'h82;

    // NACK error codes
    localparam [7:0] ERR_UNKNOWN_CMD    = 8'h01;
    localparam [7:0] ERR_BAD_LENGTH     = 8'h02;
    localparam [7:0] ERR_BAD_GATE       = 8'h03;

    reg [NUM_SLOTS-1:0] sensor_prev;
    reg                 sensor_changed;
    reg                 entry_ir1_pending;
    reg                 exit_ir1_pending;
    reg                 entry_failsafe_pending;
    reg                 exit_failsafe_pending;

    reg                      pending_valid;
    reg [7:0]                pending_cmd;
    reg [MAX_PAYLOAD*8-1:0]  pending_payload;
    reg [7:0]                pending_len;

    reg                      cmd_resp_valid;
    reg [7:0]                cmd_resp_cmd;
    reg [MAX_PAYLOAD*8-1:0]  cmd_resp_payload;
    reg [7:0]                cmd_resp_len;
    reg                      cmd_do_open;
    reg                      cmd_do_close;
    reg                      cmd_gate_sel;  // 0=entry, 1=exit
    reg                      cmd_lcd_line0_wr;
    reg                      cmd_lcd_line1_wr;

    reg                      lcd_line0_ready;
    reg                      lcd_line1_ready;

    localparam integer GATE_TIMEOUT_W = (GATE_TIMEOUT_CLKS <= 1) ? 1 : $clog2(GATE_TIMEOUT_CLKS + 1);
    localparam [GATE_TIMEOUT_W-1:0] GATE_TIMEOUT_LIMIT = GATE_TIMEOUT_CLKS[GATE_TIMEOUT_W-1:0];

    reg                         entry_gate_open_active;
    reg                         exit_gate_open_active;
    reg [GATE_TIMEOUT_W-1:0]    entry_timeout_cnt;
    reg [GATE_TIMEOUT_W-1:0]    exit_timeout_cnt;

    wire entry_timeout_event = entry_gate_open_active && (entry_timeout_cnt == GATE_TIMEOUT_LIMIT);
    wire exit_timeout_event  = exit_gate_open_active  && (exit_timeout_cnt  == GATE_TIMEOUT_LIMIT);

    always @(*) begin
        cmd_resp_valid   = 1'b0;
        cmd_resp_cmd     = 8'd0;
        cmd_resp_payload = {MAX_PAYLOAD*8{1'b0}};
        cmd_resp_len     = 8'd0;
        cmd_do_open      = 1'b0;
        cmd_do_close     = 1'b0;
        cmd_gate_sel     = 1'b0;
        cmd_lcd_line0_wr = 1'b0;
        cmd_lcd_line1_wr = 1'b0;

        if (command_valid) begin
            cmd_resp_valid = 1'b1;
            case (command_id)
                CMD_OPEN_GATE: begin
                    if (cmd_payload_len != 8'd1) begin
                        cmd_resp_cmd = RSP_NACK;
                        cmd_resp_payload[7:0] = ERR_BAD_LENGTH;
                        cmd_resp_len = 8'd1;
                    end else if (cmd_payload[7:0] > 8'h01) begin
                        cmd_resp_cmd = RSP_NACK;
                        cmd_resp_payload[7:0] = ERR_BAD_GATE;
                        cmd_resp_len = 8'd1;
                    end else begin
                        cmd_resp_cmd = RSP_ACK;
                        cmd_resp_payload[7:0] = CMD_OPEN_GATE;
                        cmd_resp_len = 8'd1;
                        cmd_do_open = 1'b1;
                        cmd_gate_sel = cmd_payload[0];
                    end
                end

                CMD_CLOSE_GATE: begin
                    if (cmd_payload_len != 8'd1) begin
                        cmd_resp_cmd = RSP_NACK;
                        cmd_resp_payload[7:0] = ERR_BAD_LENGTH;
                        cmd_resp_len = 8'd1;
                    end else if (cmd_payload[7:0] > 8'h01) begin
                        cmd_resp_cmd = RSP_NACK;
                        cmd_resp_payload[7:0] = ERR_BAD_GATE;
                        cmd_resp_len = 8'd1;
                    end else begin
                        cmd_resp_cmd = RSP_ACK;
                        cmd_resp_payload[7:0] = CMD_CLOSE_GATE;
                        cmd_resp_len = 8'd1;
                        cmd_do_close = 1'b1;
                        cmd_gate_sel = cmd_payload[0];
                    end
                end

                CMD_REQUEST_STATUS: begin
                    if (cmd_payload_len == 8'd0) begin
                        cmd_resp_cmd = RSP_PARKING_STATUS;
                        cmd_resp_payload[NUM_SLOTS-1:0] = sensor_status;
                        cmd_resp_len = 8'd1;
                    end else begin
                        cmd_resp_cmd = RSP_NACK;
                        cmd_resp_payload[7:0] = ERR_BAD_LENGTH;
                        cmd_resp_len = 8'd1;
                    end
                end

                CMD_PING: begin
                    if (cmd_payload_len == 8'd0) begin
                        cmd_resp_cmd = RSP_PONG;
                        cmd_resp_len = 8'd0;
                    end else begin
                        cmd_resp_cmd = RSP_NACK;
                        cmd_resp_payload[7:0] = ERR_BAD_LENGTH;
                        cmd_resp_len = 8'd1;
                    end
                end

                CMD_LCD_LINE0: begin
                    if (cmd_payload_len == 8'd16) begin
                        cmd_resp_cmd = RSP_ACK;
                        cmd_resp_payload[7:0] = CMD_LCD_LINE0;
                        cmd_resp_len = 8'd1;
                        cmd_lcd_line0_wr = 1'b1;
                    end else begin
                        cmd_resp_cmd = RSP_NACK;
                        cmd_resp_payload[7:0] = ERR_BAD_LENGTH;
                        cmd_resp_len = 8'd1;
                    end
                end

                CMD_LCD_LINE1: begin
                    if (cmd_payload_len == 8'd16) begin
                        cmd_resp_cmd = RSP_ACK;
                        cmd_resp_payload[7:0] = CMD_LCD_LINE1;
                        cmd_resp_len = 8'd1;
                        cmd_lcd_line1_wr = 1'b1;
                    end else begin
                        cmd_resp_cmd = RSP_NACK;
                        cmd_resp_payload[7:0] = ERR_BAD_LENGTH;
                        cmd_resp_len = 8'd1;
                    end
                end

                default: begin
                    cmd_resp_cmd = RSP_NACK;
                    cmd_resp_payload[7:0] = ERR_UNKNOWN_CMD;
                    cmd_resp_len = 8'd1;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            entry_gate_open  <= 1'b0;
            entry_gate_close <= 1'b0;
            exit_gate_open   <= 1'b0;
            exit_gate_close  <= 1'b0;
            resp_req        <= 1'b0;
            resp_cmd        <= 8'd0;
            resp_payload    <= {MAX_PAYLOAD*8{1'b0}};
            resp_len        <= 8'd0;
            sensor_prev     <= {NUM_SLOTS{1'b0}};
            sensor_changed  <= 1'b0;
            pending_valid   <= 1'b0;
            pending_cmd     <= 8'd0;
            pending_payload <= {MAX_PAYLOAD*8{1'b0}};
            pending_len     <= 8'd0;
            entry_gate_open_active <= 1'b0;
            exit_gate_open_active  <= 1'b0;
            entry_timeout_cnt      <= {GATE_TIMEOUT_W{1'b0}};
            exit_timeout_cnt       <= {GATE_TIMEOUT_W{1'b0}};
            entry_ir1_pending      <= 1'b0;
            exit_ir1_pending       <= 1'b0;
            entry_failsafe_pending <= 1'b0;
            exit_failsafe_pending  <= 1'b0;
            lcd_msg_valid          <= 1'b0;
            lcd_msg_line0          <= 128'd0;
            lcd_msg_line1          <= 128'd0;
            lcd_line0_ready        <= 1'b0;
            lcd_line1_ready        <= 1'b0;
        end else begin
            entry_gate_open  <= 1'b0;
            entry_gate_close <= 1'b0;
            exit_gate_open   <= 1'b0;
            exit_gate_close  <= 1'b0;
            resp_req         <= 1'b0;
            lcd_msg_valid    <= 1'b0;

            if (cmd_lcd_line0_wr) begin
                lcd_msg_line0   <= cmd_payload[127:0];
                lcd_line0_ready <= 1'b1;
                if (lcd_line1_ready) begin
                    lcd_msg_valid   <= 1'b1;
                    lcd_line0_ready <= 1'b0;
                    lcd_line1_ready <= 1'b0;
                end
            end
            if (cmd_lcd_line1_wr) begin
                lcd_msg_line1   <= cmd_payload[127:0];
                lcd_line1_ready <= 1'b1;
                if (lcd_line0_ready) begin
                    lcd_msg_valid   <= 1'b1;
                    lcd_line0_ready <= 1'b0;
                    lcd_line1_ready <= 1'b0;
                end
            end

            if (entry_ir1_event) begin
                entry_ir1_pending <= 1'b1;
            end
            if (exit_ir1_event) begin
                exit_ir1_pending <= 1'b1;
            end

            // --- failsafe: open gate immediately, queue notification ---
            if (entry_failsafe_event) begin
                entry_gate_open        <= 1'b1;
                entry_gate_open_active <= 1'b1;
                entry_timeout_cnt      <= {GATE_TIMEOUT_W{1'b0}};
                entry_failsafe_pending <= 1'b1;
            end
            if (exit_failsafe_event) begin
                exit_gate_open        <= 1'b1;
                exit_gate_open_active <= 1'b1;
                exit_timeout_cnt      <= {GATE_TIMEOUT_W{1'b0}};
                exit_failsafe_pending <= 1'b1;
            end

            // --- gate timeout counters ---
            if (entry_gate_open_active) begin
                if (entry_timeout_cnt < GATE_TIMEOUT_LIMIT)
                    entry_timeout_cnt <= entry_timeout_cnt + 1;
            end
            if (exit_gate_open_active) begin
                if (exit_timeout_cnt < GATE_TIMEOUT_LIMIT)
                    exit_timeout_cnt <= exit_timeout_cnt + 1;
            end

            // --- command processing: gate side-effects (always accepted) ---
            if (command_valid) begin
                if (cmd_do_open) begin
                    if (cmd_gate_sel) begin
                        exit_gate_open         <= 1'b1;
                        exit_gate_open_active  <= 1'b1;
                        exit_timeout_cnt       <= {GATE_TIMEOUT_W{1'b0}};
                    end else begin
                        entry_gate_open        <= 1'b1;
                        entry_gate_open_active <= 1'b1;
                        entry_timeout_cnt      <= {GATE_TIMEOUT_W{1'b0}};
                    end
                end
                if (cmd_do_close) begin
                    if (cmd_gate_sel) begin
                        exit_gate_close       <= 1'b1;
                        exit_gate_open_active <= 1'b0;
                        exit_timeout_cnt      <= {GATE_TIMEOUT_W{1'b0}};
                    end else begin
                        entry_gate_close       <= 1'b1;
                        entry_gate_open_active <= 1'b0;
                        entry_timeout_cnt      <= {GATE_TIMEOUT_W{1'b0}};
                    end
                end
                if (command_id == CMD_REQUEST_STATUS && cmd_payload_len == 8'd0) begin
                    sensor_changed <= 1'b0;
                end
            end

            // --- IR2 auto-close ---
            if (entry_ir2_event) begin
                entry_gate_close       <= 1'b1;
                entry_gate_open_active <= 1'b0;
                entry_timeout_cnt      <= {GATE_TIMEOUT_W{1'b0}};
            end
            if (exit_ir2_event) begin
                exit_gate_close       <= 1'b1;
                exit_gate_open_active <= 1'b0;
                exit_timeout_cnt      <= {GATE_TIMEOUT_W{1'b0}};
            end

            // --- gate timeout auto-close ---
            if (entry_timeout_event) begin
                entry_gate_close       <= 1'b1;
                entry_gate_open_active <= 1'b0;
                entry_timeout_cnt      <= {GATE_TIMEOUT_W{1'b0}};
            end
            if (exit_timeout_event) begin
                exit_gate_close       <= 1'b1;
                exit_gate_open_active <= 1'b0;
                exit_timeout_cnt      <= {GATE_TIMEOUT_W{1'b0}};
            end

            // --- response priority ---
            // 1. pending command response
            if (pending_valid && !resp_busy) begin
                resp_req     <= 1'b1;
                resp_cmd     <= pending_cmd;
                resp_payload <= pending_payload;
                resp_len     <= pending_len;
                pending_valid <= 1'b0;
            end
            // 2. new command response
            else if (cmd_resp_valid) begin
                if (!resp_busy && !pending_valid) begin
                    // gửi thẳng
                    resp_req     <= 1'b1;
                    resp_cmd     <= cmd_resp_cmd;
                    resp_payload <= cmd_resp_payload;
                    resp_len     <= cmd_resp_len;
                end else begin
                    // buffer vào pending (ghi đè nếu pending đầy)
                    pending_valid   <= 1'b1;
                    pending_cmd     <= cmd_resp_cmd;
                    pending_payload <= cmd_resp_payload;
                    pending_len     <= cmd_resp_len;
                end
            end
            // 3. gate IR1 events (entry wins if simultaneous)
            else if (entry_ir1_pending && !resp_busy && !pending_valid) begin
                resp_req     <= 1'b1;
                resp_cmd     <= RSP_GATE_EVENT;
                resp_payload <= {{(MAX_PAYLOAD*8-8){1'b0}}, 8'h00};
                resp_len     <= 8'd1;
                entry_ir1_pending <= entry_ir1_event;
            end
            else if (exit_ir1_pending && !resp_busy && !pending_valid) begin
                resp_req     <= 1'b1;
                resp_cmd     <= RSP_GATE_EVENT;
                resp_payload <= {{(MAX_PAYLOAD*8-8){1'b0}}, 8'h01};
                resp_len     <= 8'd1;
                exit_ir1_pending <= exit_ir1_event;
            end
            // 4. failsafe events
            else if (entry_failsafe_pending && !resp_busy && !pending_valid) begin
                resp_req     <= 1'b1;
                resp_cmd     <= RSP_FAILSAFE_EVENT;
                resp_payload <= {{(MAX_PAYLOAD*8-8){1'b0}}, 8'h00};
                resp_len     <= 8'd1;
                entry_failsafe_pending <= 1'b0;
            end
            else if (exit_failsafe_pending && !resp_busy && !pending_valid) begin
                resp_req     <= 1'b1;
                resp_cmd     <= RSP_FAILSAFE_EVENT;
                resp_payload <= {{(MAX_PAYLOAD*8-8){1'b0}}, 8'h01};
                resp_len     <= 8'd1;
                exit_failsafe_pending <= 1'b0;
            end
            // 5. slot sensor auto-report
            else if (!command_valid && sensor_changed && !resp_busy && !pending_valid) begin
                resp_req     <= 1'b1;
                resp_cmd     <= RSP_PARKING_STATUS;
                resp_payload <= {{(MAX_PAYLOAD*8-NUM_SLOTS){1'b0}}, sensor_status};
                resp_len     <= 8'd1;
                sensor_changed <= 1'b0;
            end

            sensor_prev <= sensor_status;
            if (sensor_status != sensor_prev) begin
                sensor_changed <= 1'b1;
            end
        end
    end

endmodule
