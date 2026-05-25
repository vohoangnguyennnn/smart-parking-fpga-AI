`timescale 1ns/1ps
//============================================================================
// Testbench for parking_uart_top
//============================================================================

module tb_parking_uart_top;

    localparam integer CLK_FREQ      = 50_000_000;
    localparam integer BAUD          = 115_200;
    localparam integer CLK_PERIOD_NS = 20;
    localparam integer BIT_TIME_NS   = 1_000_000_000 / BAUD;
    localparam integer MAX_PAYLOAD   = 16;
    localparam integer NUM_SLOTS     = 4;

    reg clk;
    reg rst_n;
    reg uart_rx_i;
    reg [NUM_SLOTS-1:0] ir_sensors_raw;
    reg entry_ir1_raw;
    reg entry_ir2_raw;
    reg exit_ir1_raw;
    reg exit_ir2_raw;
    reg entry_failsafe_btn_raw;
    reg exit_failsafe_btn_raw;
    wire uart_tx_o;
    wire entry_servo_pwm;
    wire exit_servo_pwm;
    wire [NUM_SLOTS-1:0] slot_occupied;
    wire lcd_rs;
    wire lcd_en;
    wire [3:0] lcd_d;
    wire [6:0] seven_seg;
    wire rx_overflow_error;
    wire rx_framing_error;
    wire rx_parity_error;
    wire parser_checksum_error;
    wire parser_frame_error;
    wire tx_busy;
    wire response_busy;
    wire system_alive_led;
    wire system_error_led;

    integer pass_count;
    integer fail_count;

    parking_uart_top #(
        .CLK_FREQ      (CLK_FREQ),
        .BAUD          (BAUD),
        .OVERSAMPLE    (16),
        .FIFO_DEPTH    (16),
        .MAX_PAYLOAD   (MAX_PAYLOAD),
        .NUM_SLOTS     (NUM_SLOTS),
        .DEBOUNCE_CLKS     (4),
        .TIMEOUT_CLKS      (50000),
        .GATE_TIMEOUT_CLKS (1000)
    ) dut (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .uart_rx_i             (uart_rx_i),
        .uart_tx_o             (uart_tx_o),
        .ir_sensors_raw        (ir_sensors_raw),
        .entry_ir1_raw         (entry_ir1_raw),
        .entry_ir2_raw         (entry_ir2_raw),
        .exit_ir1_raw          (exit_ir1_raw),
        .exit_ir2_raw          (exit_ir2_raw),
        .entry_failsafe_btn_raw (entry_failsafe_btn_raw),
        .exit_failsafe_btn_raw  (exit_failsafe_btn_raw),
        .entry_servo_pwm       (entry_servo_pwm),
        .exit_servo_pwm        (exit_servo_pwm),
        .slot_occupied         (slot_occupied),
        .lcd_rs                (lcd_rs),
        .lcd_en                (lcd_en),
        .lcd_d                 (lcd_d),
        .seven_seg             (seven_seg),
        .rx_overflow_error     (rx_overflow_error),
        .rx_framing_error      (rx_framing_error),
        .rx_parity_error       (rx_parity_error),
        .parser_checksum_error (parser_checksum_error),
        .parser_frame_error    (parser_frame_error),
        .tx_busy               (tx_busy),
        .response_busy         (response_busy),
        .system_alive_led      (system_alive_led),
        .system_error_led      (system_error_led)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    task automatic uart_send_byte(input [7:0] tx_data);
        integer i;
        begin
            uart_rx_i = 1'b0;
            #(BIT_TIME_NS);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_i = tx_data[i];
                #(BIT_TIME_NS);
            end
            uart_rx_i = 1'b1;
            #(BIT_TIME_NS);
        end
    endtask

    task automatic send_frame(input [7:0] cmd, input [7:0] len, input [7:0] p0, input good_checksum);
        reg [7:0] chk;
        begin
            chk = cmd ^ len;
            uart_send_byte(8'hAA);
            uart_send_byte(cmd);
            uart_send_byte(len);
            if (len >= 8'd1) begin
                uart_send_byte(p0);
                chk = chk ^ p0;
            end
            if (!good_checksum) chk = chk ^ 8'hFF;
            uart_send_byte(chk);
        end
    endtask

    task automatic uart_receive_byte(output [7:0] rx_byte);
        integer i;
        begin
            @(negedge uart_tx_o);
            #(BIT_TIME_NS / 2);
            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_TIME_NS);
                rx_byte[i] = uart_tx_o;
            end
            #(BIT_TIME_NS);
        end
    endtask

    task automatic receive_response(output [7:0] cmd, output [7:0] len, output [7:0] p0, output [7:0] chk);
        reg [7:0] start;
        begin
            p0 = 8'd0;
            uart_receive_byte(start);
            uart_receive_byte(cmd);
            uart_receive_byte(len);
            if (len >= 8'd1) begin
                uart_receive_byte(p0);
            end
            uart_receive_byte(chk);
        end
    endtask

    task automatic check(input logic condition, input string msg);
        begin
            if (condition) begin
                $display("PASS: %s", msg);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %s", msg);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("parking_uart_top.vcd");
        $dumpvars(0, tb_parking_uart_top);

        pass_count = 0;
        fail_count = 0;
        uart_rx_i = 1'b1;
        ir_sensors_raw = {NUM_SLOTS{1'b1}};
        entry_ir1_raw = 1'b1;
        entry_ir2_raw = 1'b1;
        exit_ir1_raw = 1'b1;
        exit_ir2_raw = 1'b1;
        entry_failsafe_btn_raw = 1'b1;
        exit_failsafe_btn_raw = 1'b1;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        $display("============================================================");
        $display("Parking UART Top Testbench");
        $display("============================================================");

        // ===========================================================
        // TEST 1: PING -> PONG
        // ===========================================================
        $display("\n--- Test 1: PING -> PONG ---");
        begin
            reg [7:0] rcmd, rlen, rp0, rchk;

            fork
                send_frame(8'h7F, 8'd0, 8'd0, 1'b1);
                receive_response(rcmd, rlen, rp0, rchk);
            join

            check(rcmd == 8'h82, $sformatf("Test1: PONG cmd 0x82 (got 0x%02h)", rcmd));
            check(rlen == 8'd0, $sformatf("Test1: PONG len=0 (got %0d)", rlen));
        end

        repeat (200) @(posedge clk);

        // ===========================================================
        // TEST 2: OPEN_GATE entry -> ACK (servo PWM remains continuous)
        // ===========================================================
        $display("\n--- Test 2: OPEN_GATE entry -> ACK ---");
        begin
            reg [7:0] rcmd, rlen, rp0, rchk;

            fork
                send_frame(8'h01, 8'd1, 8'h00, 1'b1);
                receive_response(rcmd, rlen, rp0, rchk);
            join

            repeat (100) @(posedge clk);
            check(rcmd == 8'h80, $sformatf("Test2: ACK cmd (got 0x%02h)", rcmd));
            check(rlen == 8'd1, $sformatf("Test2: ACK len=1 (got %0d)", rlen));
            check(rp0 == 8'h01, $sformatf("Test2: ACK payload=0x01 (got 0x%02h)", rp0));
        end

        repeat (200) @(posedge clk);

        // ===========================================================
        // TEST 3: Bad checksum -> NACK with payload 0x03
        // ===========================================================
        $display("\n--- Test 3: Bad checksum -> NACK(0x03) ---");
        begin
            reg [7:0] rcmd, rlen, rp0, rchk;
            reg saw_checksum_error;
            reg resp_done;

            saw_checksum_error = 0;
            resp_done = 0;

            fork
                send_frame(8'h01, 8'd0, 8'd0, 1'b0);
                begin
                    receive_response(rcmd, rlen, rp0, rchk);
                    resp_done = 1;
                end
                begin : chk_mon
                    forever begin
                        @(posedge clk);
                        if (parser_checksum_error) saw_checksum_error = 1;
                    end
                end
            join_any
            wait (resp_done);
            disable chk_mon;

            repeat (100) @(posedge clk);
            check(saw_checksum_error, "Test3: parser_checksum_error pulsed");
            check(rcmd == 8'h81, $sformatf("Test3: NACK cmd 0x81 (got 0x%02h)", rcmd));
            check(rlen == 8'd1, $sformatf("Test3: NACK len=1 (got %0d)", rlen));
            check(rp0 == 8'h03, $sformatf("Test3: NACK payload=0x03 checksum (got 0x%02h)", rp0));
        end

        repeat (200) @(posedge clk);

        // ===========================================================
        // TEST 4: Frame error (payload too long) -> NACK with payload 0x04
        // ===========================================================
        $display("\n--- Test 4: Frame error -> NACK(0x04) ---");
        begin
            reg [7:0] rcmd, rlen, rp0, rchk;
            reg saw_frame_error;
            reg resp_done;

            saw_frame_error = 0;
            resp_done = 0;

            fork
                begin
                    // Send frame with LEN > MAX_PAYLOAD to trigger frame_error
                    uart_send_byte(8'hAA);
                    uart_send_byte(8'h01);
                    uart_send_byte(8'd17);  // LEN=17 > MAX_PAYLOAD=16
                    // Parser will abort with frame_error, no more bytes needed
                end
                begin
                    receive_response(rcmd, rlen, rp0, rchk);
                    resp_done = 1;
                end
                begin : frm_mon
                    forever begin
                        @(posedge clk);
                        if (parser_frame_error) saw_frame_error = 1;
                    end
                end
            join_any
            wait (resp_done);
            disable frm_mon;

            repeat (100) @(posedge clk);
            check(saw_frame_error, "Test4: parser_frame_error pulsed");
            check(rcmd == 8'h81, $sformatf("Test4: NACK cmd 0x81 (got 0x%02h)", rcmd));
            check(rlen == 8'd1, $sformatf("Test4: NACK len=1 (got %0d)", rlen));
            check(rp0 == 8'h04, $sformatf("Test4: NACK payload=0x04 frame (got 0x%02h)", rp0));
        end

        repeat (200) @(posedge clk);

        // ===========================================================
        // TEST 5: REQUEST_STATUS -> PARKING_STATUS
        // ===========================================================
        $display("\n--- Test 5: REQUEST_STATUS -> PARKING_STATUS ---");
        begin
            reg [7:0] rcmd, rlen, rp0, rchk;

            ir_sensors_raw = 4'b1010;

            wait (response_busy == 1'b1 || tx_busy == 1'b1);
            wait (response_busy == 1'b0 && tx_busy == 1'b0 && uart_tx_o == 1'b1);
            repeat (20) @(posedge clk);

            fork
                send_frame(8'h05, 8'd0, 8'd0, 1'b1);
                receive_response(rcmd, rlen, rp0, rchk);
            join

            check(rcmd == 8'h10, $sformatf("Test5: PARKING_STATUS cmd 0x10 (got 0x%02h)", rcmd));
            check(rlen == 8'd1, $sformatf("Test5: PARKING_STATUS len=1 (got %0d)", rlen));
            check(rp0[NUM_SLOTS-1:0] == 4'b0101,
                  $sformatf("Test5: slot bits=0b0101 (got 0b%04b)", rp0[NUM_SLOTS-1:0]));
        end

        repeat (50) @(posedge clk);
        $display("\n============================================================");
        $display("Parking UART Top Testbench Complete: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("============================================================");

        if (fail_count == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule
