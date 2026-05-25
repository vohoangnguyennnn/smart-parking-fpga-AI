`timescale 1ns/1ps
//============================================================================
// Testbench for uart_tx — 8N1 transmitter
//============================================================================

module tb_uart_tx;

    localparam integer CLK_FREQ      = 50_000_000;
    localparam integer BAUD          = 115_200;
    localparam integer CLK_PERIOD_NS = 20;
    localparam integer BIT_TIME_NS   = 1_000_000_000 / BAUD;

    reg        clk;
    reg        rst_n;
    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx;
    wire       tx_busy;
    wire       tx_done;

    integer pass_count;
    integer fail_count;

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD     (BAUD)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_data  (tx_data),
        .tx_start (tx_start),
        .tx       (tx),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    // ---------------------------------------------------------------
    // Sample the TX line at the center of each bit period and reconstruct
    // ---------------------------------------------------------------
    task automatic uart_receive_byte(output [7:0] rx_byte, output logic stop_ok);
        integer i;
        begin
            // wait for start bit (tx goes low)
            @(negedge tx);
            // center of start bit
            #(BIT_TIME_NS / 2);
            // sample data bits
            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_TIME_NS);
                rx_byte[i] = tx;
            end
            // sample stop bit
            #(BIT_TIME_NS);
            stop_ok = tx;
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
        $dumpfile("uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);

        pass_count = 0;
        fail_count = 0;
        tx_data    = 8'd0;
        tx_start   = 1'b0;
        rst_n      = 1'b1;
        repeat (2) @(posedge clk);
        rst_n      = 1'b0;
        repeat (10) @(posedge clk);
        rst_n      = 1'b1;
        repeat (5) @(posedge clk);

        $display("============================================================");
        $display("UART TX Testbench");
        $display("============================================================");

        // ===========================================================
        // TEST 1: Transmit 0x55 and verify line sampling
        // ===========================================================
        $display("\n--- Test 1: Transmit 0x55 ---");
        begin
            reg [7:0] got;
            reg       stop;

            fork
                begin
                    @(posedge clk);
                    tx_data  = 8'h55;
                    tx_start = 1'b1;
                    @(posedge clk);
                    tx_start = 1'b0;
                end
                uart_receive_byte(got, stop);
            join

            check(got == 8'h55, $sformatf("Test1: received 0x55 (got 0x%02h)", got));
            check(stop == 1'b1, "Test1: stop bit is high");
        end

        wait (tx_busy == 1'b0);
        repeat (5) @(posedge clk);

        // ===========================================================
        // TEST 2: Transmit 0xA3 and check tx_done pulse
        // ===========================================================
        $display("\n--- Test 2: Transmit 0xA3 + tx_done ---");
        begin
            reg [7:0] got;
            reg       stop;
            reg       saw_done;

            saw_done = 0;

            fork
                begin
                    @(posedge clk);
                    tx_data  = 8'hA3;
                    tx_start = 1'b1;
                    @(posedge clk);
                    tx_start = 1'b0;
                end
                uart_receive_byte(got, stop);
                begin
                    wait (tx_busy == 1'b1);
                    wait (tx_busy == 1'b0);
                    saw_done = 1;
                end
            join

            check(got == 8'hA3, $sformatf("Test2: received 0xA3 (got 0x%02h)", got));
            check(stop == 1'b1, "Test2: stop bit is high");
            check(saw_done, "Test2: tx_done pulsed");
        end

        wait (tx_busy == 1'b0);
        repeat (5) @(posedge clk);

        // ===========================================================
        // TEST 3: tx_busy stays high during transmission
        // ===========================================================
        $display("\n--- Test 3: tx_busy during transmission ---");
        begin
            reg was_busy;

            was_busy = 0;
            @(posedge clk);
            tx_data  = 8'hFF;
            tx_start = 1'b1;
            @(posedge clk);
            tx_start = 1'b0;

            repeat (10) @(posedge clk);
            was_busy = tx_busy;

            // wait for tx_done
            @(posedge tx_done);
            repeat (2) @(posedge clk);

            check(was_busy, "Test3: tx_busy was high during transmission");
            check(!tx_busy, "Test3: tx_busy low after tx_done");
        end

        // ===========================================================
        // Summary
        // ===========================================================
        repeat (50) @(posedge clk);
        $display("\n============================================================");
        $display("UART TX Testbench Complete: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("============================================================");

        if (fail_count == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule
