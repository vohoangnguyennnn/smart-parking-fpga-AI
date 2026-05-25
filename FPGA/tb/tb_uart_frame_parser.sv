`timescale 1ns/1ps
//============================================================================
// Testbench for uart_frame_parser
//============================================================================

module tb_uart_frame_parser;

    localparam integer MAX_PAYLOAD  = 16;
    localparam integer TIMEOUT_CLKS = 200;
    localparam integer CLK_PERIOD_NS = 20;

    reg clk;
    reg rst_n;

    reg  [7:0] rx_data;
    reg        rx_valid;
    wire       rx_rd_en;

    wire                       command_valid;
    wire [7:0]                 command_id;
    wire [MAX_PAYLOAD*8-1:0]   payload;
    wire [7:0]                 payload_len;
    wire                       checksum_error;
    wire                       frame_error;

    integer pass_count;
    integer fail_count;

    uart_frame_parser #(
        .MAX_PAYLOAD  (MAX_PAYLOAD),
        .TIMEOUT_CLKS (TIMEOUT_CLKS)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .rx_data         (rx_data),
        .rx_valid        (rx_valid),
        .rx_rd_en        (rx_rd_en),
        .command_valid   (command_valid),
        .command_id      (command_id),
        .payload         (payload),
        .payload_len     (payload_len),
        .checksum_error  (checksum_error),
        .frame_error     (frame_error)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    task automatic send_byte(input [7:0] value);
        begin
            @(posedge clk);
            rx_data  <= value;
            rx_valid <= 1'b1;
            @(posedge clk);
            rx_valid <= 1'b0;
            rx_data  <= 8'd0;
            repeat (2) @(posedge clk);
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
        $dumpfile("uart_frame_parser.vcd");
        $dumpvars(0, tb_uart_frame_parser);

        pass_count = 0;
        fail_count = 0;
        rx_data    = 8'd0;
        rx_valid   = 1'b0;
        rst_n      = 1'b1;
        repeat (2) @(posedge clk);
        rst_n      = 1'b0;
        repeat (10) @(posedge clk);
        rst_n      = 1'b1;
        repeat (5) @(posedge clk);

        $display("============================================================");
        $display("UART Frame Parser Testbench");
        $display("============================================================");

        // Frame: AA 01 02 A5 5A FC (checksum = 01^02^A5^5A)
        $display("\n--- Test 1: valid frame ---");
        begin
            reg saw_valid;
            integer timeout;

            saw_valid = 0;
            fork
                begin
                    send_byte(8'hAA);
                    send_byte(8'h01);
                    send_byte(8'h02);
                    send_byte(8'hA5);
                    send_byte(8'h5A);
                    send_byte(8'hFC);
                end
                begin
                    timeout = 0;
                    while (timeout < 200) begin
                        @(posedge clk);
                        if (command_valid) saw_valid = 1;
                        timeout = timeout + 1;
                    end
                end
            join

            check(saw_valid, "Test1: command_valid pulsed");
            check(command_id == 8'h01, $sformatf("Test1: command_id 0x01 (got 0x%02h)", command_id));
            check(payload_len == 8'd2, $sformatf("Test1: payload_len 2 (got %0d)", payload_len));
            check(payload[7:0] == 8'hA5 && payload[15:8] == 8'h5A,
                  $sformatf("Test1: payload bytes A5 5A (got %02h %02h)", payload[7:0], payload[15:8]));
        end

        repeat (20) @(posedge clk);

        // Bad checksum: AA 01 01 55 00 (correct would be 55)
        $display("\n--- Test 2: bad checksum ---");
        begin
            reg saw_checksum_error;
            reg saw_valid;
            integer timeout;

            saw_checksum_error = 0;
            saw_valid = 0;
            fork
                begin
                    send_byte(8'hAA);
                    send_byte(8'h01);
                    send_byte(8'h01);
                    send_byte(8'h55);
                    send_byte(8'h00);
                end
                begin
                    timeout = 0;
                    while (timeout < 200) begin
                        @(posedge clk);
                        if (checksum_error) saw_checksum_error = 1;
                        if (command_valid) saw_valid = 1;
                        timeout = timeout + 1;
                    end
                end
            join

            check(saw_checksum_error, "Test2: checksum_error pulsed");
            check(!saw_valid, "Test2: command_valid did not pulse");
        end

        repeat (20) @(posedge clk);

        // Frame length too large
        $display("\n--- Test 3: payload too long ---");
        begin
            reg saw_frame_error;
            integer timeout;

            saw_frame_error = 0;
            fork
                begin
                    send_byte(8'hAA);
                    send_byte(8'h01);
                    send_byte(8'd17);
                end
                begin
                    timeout = 0;
                    while (timeout < 200) begin
                        @(posedge clk);
                        if (frame_error) saw_frame_error = 1;
                        timeout = timeout + 1;
                    end
                end
            join

            check(saw_frame_error, "Test3: frame_error pulsed for long LEN");
        end

        repeat (50) @(posedge clk);
        $display("\n============================================================");
        $display("UART Frame Parser Testbench Complete: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("============================================================");

        if (fail_count == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule
