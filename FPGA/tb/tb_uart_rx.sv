`timescale 1ns/1ps
//============================================================================
// Testbench for uart_rx with oversampling, FIFO, error flags, parity
//============================================================================

module tb_uart_rx;

    // ---------------------------------------------------------------
    // Parameters — default DUT uses 8N1, 16× oversampling, FIFO=16
    // ---------------------------------------------------------------
    localparam integer CLK_FREQ      = 50_000_000;
    localparam integer BAUD          = 115_200;
    localparam integer OVERSAMPLE    = 16;
    localparam integer FIFO_DEPTH    = 4;       // small depth to test overflow easily
    localparam integer CLK_PERIOD_NS = 20;      // 50 MHz
    localparam integer BIT_TIME_NS   = 1_000_000_000 / BAUD;

    // ---------------------------------------------------------------
    // DUT signals (no parity instance)
    // ---------------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg        rx;
    reg        rd_en;
    wire [7:0] rd_data;
    wire       rd_valid;
    wire       fifo_empty;
    wire       fifo_full;
    wire [$clog2(FIFO_DEPTH+1)-1:0] fifo_level;
    wire       framing_error;
    wire       parity_error;
    wire       overflow_error;
    wire [7:0] data;
    wire       data_valid;

    integer pass_count;
    integer fail_count;

    // ---------------------------------------------------------------
    // DUT instantiation — no parity
    // ---------------------------------------------------------------
    uart_rx #(
        .CLK_FREQ   (CLK_FREQ),
        .BAUD       (BAUD),
        .OVERSAMPLE (OVERSAMPLE),
        .FIFO_DEPTH (FIFO_DEPTH),
        .PARITY_EN  (0),
        .PARITY_ODD (0)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .rx            (rx),
        .rd_en         (rd_en),
        .rd_data       (rd_data),
        .rd_valid      (rd_valid),
        .fifo_empty    (fifo_empty),
        .fifo_full     (fifo_full),
        .fifo_level    (fifo_level),
        .framing_error (framing_error),
        .parity_error  (parity_error),
        .overflow_error(overflow_error),
        .data          (data),
        .data_valid    (data_valid)
    );

    // ---------------------------------------------------------------
    // Parity DUT signals
    // ---------------------------------------------------------------
    localparam integer PAR_FIFO_DEPTH = 4;
    reg        par_rx;
    reg        par_rd_en;
    wire [7:0] par_rd_data;
    wire       par_rd_valid;
    wire       par_fifo_empty;
    wire       par_fifo_full;
    wire [$clog2(PAR_FIFO_DEPTH+1)-1:0] par_fifo_level;
    wire       par_framing_error;
    wire       par_parity_error;
    wire       par_overflow_error;
    wire [7:0] par_data;
    wire       par_data_valid;

    uart_rx #(
        .CLK_FREQ   (CLK_FREQ),
        .BAUD       (BAUD),
        .OVERSAMPLE (OVERSAMPLE),
        .FIFO_DEPTH (PAR_FIFO_DEPTH),
        .PARITY_EN  (1),
        .PARITY_ODD (0)
    ) dut_parity (
        .clk           (clk),
        .rst_n         (rst_n),
        .rx            (par_rx),
        .rd_en         (par_rd_en),
        .rd_data       (par_rd_data),
        .rd_valid      (par_rd_valid),
        .fifo_empty    (par_fifo_empty),
        .fifo_full     (par_fifo_full),
        .fifo_level    (par_fifo_level),
        .framing_error (par_framing_error),
        .parity_error  (par_parity_error),
        .overflow_error(par_overflow_error),
        .data          (par_data),
        .data_valid    (par_data_valid)
    );

    // ---------------------------------------------------------------
    // 50 MHz clock
    // ---------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    // ---------------------------------------------------------------
    // UART TX model — 8N1, LSB-first (for non-parity DUT)
    // ---------------------------------------------------------------
    task automatic uart_send_byte(input [7:0] tx_data);
        integer i;
        begin
            rx = 1'b0;                     // start bit
            #(BIT_TIME_NS);
            for (i = 0; i < 8; i = i + 1) begin
                rx = tx_data[i];
                #(BIT_TIME_NS);
            end
            rx = 1'b1;                     // stop bit
            #(BIT_TIME_NS);
        end
    endtask

    // ---------------------------------------------------------------
    // UART TX model — 8E1 (with even parity)
    // ---------------------------------------------------------------
    task automatic uart_send_byte_parity(input [7:0] tx_data, input parity_bit);
        integer i;
        begin
            par_rx = 1'b0;                 // start bit
            #(BIT_TIME_NS);
            for (i = 0; i < 8; i = i + 1) begin
                par_rx = tx_data[i];
                #(BIT_TIME_NS);
            end
            par_rx = parity_bit;           // parity bit
            #(BIT_TIME_NS);
            par_rx = 1'b1;                 // stop bit
            #(BIT_TIME_NS);
        end
    endtask

    // ---------------------------------------------------------------
    // UART TX with bad stop bit (framing error)
    // ---------------------------------------------------------------
    task automatic uart_send_byte_bad_stop(input [7:0] tx_data);
        integer i;
        begin
            rx = 1'b0;
            #(BIT_TIME_NS);
            for (i = 0; i < 8; i = i + 1) begin
                rx = tx_data[i];
                #(BIT_TIME_NS);
            end
            rx = 1'b0;                     // BAD stop bit
            #(BIT_TIME_NS);
            rx = 1'b1;                     // return to idle
        end
    endtask

    // ---------------------------------------------------------------
    // Wait for data_valid pulse with timeout
    // ---------------------------------------------------------------
    task automatic wait_data_valid(output [7:0] got_data, output got_valid);
        integer timeout;
        begin : wait_loop
            timeout = 0;
            got_valid = 0;
            got_data  = 8'hxx;
            while (timeout < 60000) begin
                @(posedge clk);
                if (data_valid) begin
                    got_data  = data;
                    got_valid = 1;
                    disable wait_loop;
                end
                timeout = timeout + 1;
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Check helper
    // ---------------------------------------------------------------
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

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    initial begin
        $dumpfile("uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);

        pass_count = 0;
        fail_count = 0;
        rx         = 1'b1;
        par_rx     = 1'b1;
        rd_en      = 1'b0;
        par_rd_en  = 1'b0;
        rst_n      = 1'b1;
        repeat (2) @(posedge clk);
        rst_n      = 1'b0;
        repeat (10) @(posedge clk);
        rst_n      = 1'b1;
        repeat (10) @(posedge clk);

        $display("============================================================");
        $display("UART RX Testbench — Oversampling=%0d, FIFO=%0d", OVERSAMPLE, FIFO_DEPTH);
        $display("============================================================");

        // ===========================================================
        // TEST 1: Normal receive with oversampling
        // ===========================================================
        $display("\n--- Test 1: Normal receive with oversampling ---");
        begin
            reg [7:0] got;
            reg       valid;

            fork
                uart_send_byte(8'h41);
                wait_data_valid(got, valid);
            join

            check(valid && got == 8'h41, "Test1: received 0x41 ('A')");
        end

        // drain FIFO
        repeat (2) @(posedge clk);
        rd_en = 1'b1;
        @(posedge clk);
        rd_en = 1'b0;
        repeat (5) @(posedge clk);

        // ===========================================================
        // TEST 2: Back-to-back frames + FIFO buffering
        // ===========================================================
        $display("\n--- Test 2: Back-to-back frames + FIFO read ---");
        begin
            // Send 3 bytes quickly — they should all land in FIFO
            uart_send_byte(8'h10);
            uart_send_byte(8'h20);
            uart_send_byte(8'h30);

            // wait for last frame to settle
            repeat (200) @(posedge clk);

            check(!fifo_empty, "Test2: FIFO is not empty after 3 bytes");
            check(fifo_level == 3, $sformatf("Test2: FIFO level == 3 (got %0d)", fifo_level));

            // Read all 3 bytes via rd_en
            rd_en = 1'b1; @(posedge clk); rd_en = 1'b0; @(posedge clk);
            check(rd_valid && rd_data == 8'h10, $sformatf("Test2: read byte 0 == 0x10 (got 0x%02h)", rd_data));

            rd_en = 1'b1; @(posedge clk); rd_en = 1'b0; @(posedge clk);
            check(rd_valid && rd_data == 8'h20, $sformatf("Test2: read byte 1 == 0x20 (got 0x%02h)", rd_data));

            rd_en = 1'b1; @(posedge clk); rd_en = 1'b0; @(posedge clk);
            check(rd_valid && rd_data == 8'h30, $sformatf("Test2: read byte 2 == 0x30 (got 0x%02h)", rd_data));

            check(fifo_empty, "Test2: FIFO empty after reading all bytes");
        end

        repeat (20) @(posedge clk);

        // ===========================================================
        // TEST 3: FIFO full behavior (no corruption)
        // ===========================================================
        $display("\n--- Test 3: FIFO full behavior ---");
        begin
            integer k;
            reg [7:0] got;
            reg       valid;
            reg       saw_overflow;

            saw_overflow = 0;

            // Send FIFO_DEPTH + 2 bytes to overflow
            fork
                for (k = 0; k < FIFO_DEPTH + 2; k = k + 1) begin
                    uart_send_byte(k[7:0]);
                end
                begin : overflow_mon
                    forever begin
                        @(posedge clk);
                        if (overflow_error) saw_overflow = 1;
                    end
                end
            join_any
            disable overflow_mon;

            repeat (200) @(posedge clk);

            // Level should be capped at FIFO_DEPTH
            check(fifo_full, "Test3: FIFO reports full");
            check(fifo_level == FIFO_DEPTH, $sformatf("Test3: FIFO level == %0d (got %0d)", FIFO_DEPTH, fifo_level));
            check(saw_overflow, "Test3: overflow_error pulsed when FIFO full");

            // Read out and verify first FIFO_DEPTH bytes are correct (overflow bytes dropped)
            for (k = 0; k < FIFO_DEPTH; k = k + 1) begin
                rd_en = 1'b1; @(posedge clk); rd_en = 1'b0; @(posedge clk);
                check(rd_valid && rd_data == k[7:0],
                      $sformatf("Test3: FIFO[%0d] == 0x%02h (got 0x%02h)", k, k[7:0], rd_data));
            end

            check(fifo_empty, "Test3: FIFO empty after draining");
        end

        repeat (20) @(posedge clk);

        // ===========================================================
        // TEST 4: Framing error (bad stop bit)
        // ===========================================================
        $display("\n--- Test 4: Framing error (bad stop bit) ---");
        begin
            reg saw_frame_err;
            integer timeout;

            saw_frame_err = 0;

            fork
                uart_send_byte_bad_stop(8'hFF);
                begin
                    timeout = 0;
                    while (timeout < 60000) begin
                        @(posedge clk);
                        if (framing_error) saw_frame_err = 1;
                        timeout = timeout + 1;
                    end
                end
            join_any
            disable fork;

            // wait for any remaining propagation
            repeat (200) @(posedge clk);

            check(saw_frame_err, "Test4: framing_error pulsed on bad stop bit");
            check(fifo_empty, "Test4: byte not pushed to FIFO on framing error");
        end

        repeat (20) @(posedge clk);
        rx = 1'b1;  // ensure idle

        // ===========================================================
        // TEST 5: Parity enabled — pass + fail (even parity DUT)
        // ===========================================================
        $display("\n--- Test 5: Parity pass/fail (even parity) ---");

        // 5a: Correct even parity for 0x41 = 01000001 → popcount=2 → even parity bit = 0
        begin
            reg [7:0] got;
            reg       valid;
            reg       saw_par_err;
            integer   timeout;

            got         = 8'h00;
            valid       = 0;
            saw_par_err = 0;

            fork
                uart_send_byte_parity(8'h41, 1'b0); // correct even parity
                begin
                    timeout = 0;
                    while (timeout < 60000) begin
                        @(posedge clk);
                        if (par_data_valid) begin
                            got   = par_data;
                            valid = 1;
                        end
                        if (par_parity_error) saw_par_err = 1;
                        timeout = timeout + 1;
                    end
                end
            join_any
            disable fork;

            repeat (100) @(posedge clk);

            check(valid && got == 8'h41, $sformatf("Test5a: parity-ok received 0x41 (got 0x%02h)", got));
            check(!saw_par_err, "Test5a: no parity_error on correct parity");

            // drain parity FIFO
            par_rd_en = 1'b1; @(posedge clk); par_rd_en = 1'b0; @(posedge clk);
        end

        repeat (20) @(posedge clk);

        // 5b: Wrong parity for 0x41 — send parity_bit = 1 (should be 0 for even)
        begin
            reg saw_par_err;
            integer timeout;

            saw_par_err = 0;

            fork
                uart_send_byte_parity(8'h41, 1'b1); // WRONG parity
                begin
                    timeout = 0;
                    while (timeout < 60000) begin
                        @(posedge clk);
                        if (par_parity_error) saw_par_err = 1;
                        timeout = timeout + 1;
                    end
                end
            join_any
            disable fork;

            repeat (100) @(posedge clk);

            check(saw_par_err, "Test5b: parity_error pulsed on wrong parity");
            check(par_fifo_empty, "Test5b: byte not pushed to FIFO on parity error");
        end

        repeat (20) @(posedge clk);

        // ===========================================================
        // TEST 6: Start-bit glitch rejection
        // ===========================================================
        $display("\n--- Test 6: Start-bit glitch rejection ---");
        begin
            reg [7:0] got;
            reg       valid;
            integer   timeout;
            integer   quarter_bit;

            valid = 0;
            got   = 8'hxx;
            quarter_bit = BIT_TIME_NS / 4;

            // Generate a short glitch (1/4 bit time LOW then HIGH)
            rx = 1'b0;
            #(quarter_bit);
            rx = 1'b1;

            // Wait a bit — nothing should come out
            repeat (2000) @(posedge clk);

            check(fifo_empty, "Test6a: glitch did not produce a byte");

            // Now send a real byte to confirm the receiver still works
            fork
                uart_send_byte(8'hBE);
                wait_data_valid(got, valid);
            join

            check(valid && got == 8'hBE, $sformatf("Test6b: normal byte after glitch == 0xBE (got 0x%02h)", got));

            // drain
            rd_en = 1'b1; @(posedge clk); rd_en = 1'b0; @(posedge clk);
        end

        // ===========================================================
        // Summary
        // ===========================================================
        repeat (50) @(posedge clk);
        $display("\n============================================================");
        $display("UART RX Testbench Complete: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("============================================================");

        if (fail_count == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule
