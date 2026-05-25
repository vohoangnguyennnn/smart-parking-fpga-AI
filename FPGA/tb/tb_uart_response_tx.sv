`timescale 1ns/1ps
//============================================================================
// Testbench for uart_response_tx
// Verifies frame format: 0xAA CMD LEN PAYLOAD... CHECKSUM (XOR)
//============================================================================

module tb_uart_response_tx;

    localparam integer MAX_PAYLOAD  = 16;
    localparam integer CLK_PERIOD_NS = 20;

    reg        clk;
    reg        rst_n;

    reg                        resp_req;
    reg  [7:0]                 resp_cmd;
    reg  [MAX_PAYLOAD*8-1:0]   resp_payload;
    reg  [7:0]                 resp_len;

    reg        parser_checksum_error;
    reg        parser_frame_error;

    // Simulated tx_busy — driven by a simple model
    reg        tx_busy;
    wire [7:0] tx_data;
    wire       tx_start;
    wire       busy;

    integer pass_count;
    integer fail_count;

    // Capture transmitted bytes
    reg [7:0] captured [0:31];
    integer   cap_idx;

    uart_response_tx #(
        .MAX_PAYLOAD (MAX_PAYLOAD)
    ) dut (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .resp_req              (resp_req),
        .resp_cmd              (resp_cmd),
        .resp_payload          (resp_payload),
        .resp_len              (resp_len),
        .parser_checksum_error (parser_checksum_error),
        .parser_frame_error    (parser_frame_error),
        .tx_busy               (tx_busy),
        .tx_data               (tx_data),
        .tx_start              (tx_start),
        .busy                  (busy)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    // ---------------------------------------------------------------
    // Simple TX busy model: when tx_start pulses, hold tx_busy
    // for a few cycles to simulate uart_tx behavior
    // ---------------------------------------------------------------
    localparam integer TX_BUSY_CYCLES = 5;
    always @(posedge clk) begin
        if (!rst_n) begin
            tx_busy <= 1'b0;
        end else if (tx_start && !tx_busy) begin
            tx_busy <= 1'b1;
        end
    end

    // Release tx_busy after TX_BUSY_CYCLES
    reg [3:0] busy_cnt;
    always @(posedge clk) begin
        if (!rst_n) begin
            busy_cnt <= 4'd0;
        end else if (tx_start && !tx_busy) begin
            busy_cnt <= 4'd1;
        end else if (tx_busy) begin
            if (busy_cnt == TX_BUSY_CYCLES) begin
                tx_busy  <= 1'b0;
                busy_cnt <= 4'd0;
            end else begin
                busy_cnt <= busy_cnt + 4'd1;
            end
        end
    end

    // ---------------------------------------------------------------
    // Capture every byte that tx_start sends
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (tx_start && !tx_busy) begin
            captured[cap_idx] <= tx_data;
            cap_idx <= cap_idx + 1;
        end
    end

    // ---------------------------------------------------------------
    // Helper: wait until DUT is idle
    // ---------------------------------------------------------------
    task automatic wait_idle();
        integer timeout;
        begin
            timeout = 0;
            while (busy && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            repeat (3) @(posedge clk);  // settle
        end
    endtask

    // ---------------------------------------------------------------
    // Helper: issue a response request (one-clock pulse)
    // ---------------------------------------------------------------
    task automatic issue_resp(input [7:0] cmd, input [7:0] len,
                              input [MAX_PAYLOAD*8-1:0] pl);
        begin
            @(posedge clk);
            resp_req     <= 1'b1;
            resp_cmd     <= cmd;
            resp_len     <= len;
            resp_payload <= pl;
            @(posedge clk);
            resp_req     <= 1'b0;
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

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    initial begin
        $dumpfile("uart_response_tx.vcd");
        $dumpvars(0, tb_uart_response_tx);

        pass_count = 0;
        fail_count = 0;
        cap_idx    = 0;
        resp_req   = 1'b0;
        resp_cmd   = 8'd0;
        resp_payload = {MAX_PAYLOAD*8{1'b0}};
        resp_len   = 8'd0;
        parser_checksum_error = 1'b0;
        parser_frame_error    = 1'b0;
        tx_busy    = 1'b0;

        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("============================================================");
        $display("UART Response TX Testbench");
        $display("============================================================");

        // ===========================================================
        // TEST 1: Normal response — CMD=0x80 (ACK), LEN=2, payload=0x01 0x02
        // Frame: AA 80 02 01 02 CHKSUM
        // CHKSUM = 80 ^ 02 ^ 01 ^ 02 = 81
        // ===========================================================
        $display("\n--- Test 1: Normal response frame ---");
        begin
            reg [MAX_PAYLOAD*8-1:0] pl;
            reg [7:0] expected_chk;

            pl = {MAX_PAYLOAD*8{1'b0}};
            pl[7:0]  = 8'h01;
            pl[15:8] = 8'h02;
            expected_chk = 8'h80 ^ 8'h02 ^ 8'h01 ^ 8'h02;

            cap_idx = 0;
            issue_resp(8'h80, 8'd2, pl);
            wait_idle();

            check(cap_idx == 6, $sformatf("Test1: 6 bytes sent (got %0d)", cap_idx));
            check(captured[0] == 8'hAA, $sformatf("Test1: byte0=0xAA (got 0x%02h)", captured[0]));
            check(captured[1] == 8'h80, $sformatf("Test1: byte1=CMD 0x80 (got 0x%02h)", captured[1]));
            check(captured[2] == 8'h02, $sformatf("Test1: byte2=LEN 0x02 (got 0x%02h)", captured[2]));
            check(captured[3] == 8'h01, $sformatf("Test1: byte3=payload[0] 0x01 (got 0x%02h)", captured[3]));
            check(captured[4] == 8'h02, $sformatf("Test1: byte4=payload[1] 0x02 (got 0x%02h)", captured[4]));
            check(captured[5] == expected_chk, $sformatf("Test1: byte5=CHKSUM 0x%02h (got 0x%02h)", expected_chk, captured[5]));
        end

        repeat (10) @(posedge clk);

        // ===========================================================
        // TEST 2: Zero-length payload
        // Frame: AA 82 00 CHKSUM
        // CHKSUM = 82 ^ 00 = 82
        // ===========================================================
        $display("\n--- Test 2: Zero-length payload ---");
        begin
            reg [7:0] expected_chk;

            expected_chk = 8'h82 ^ 8'h00;
            cap_idx = 0;
            issue_resp(8'h82, 8'd0, {MAX_PAYLOAD*8{1'b0}});
            wait_idle();

            check(cap_idx == 4, $sformatf("Test2: 4 bytes sent (got %0d)", cap_idx));
            check(captured[0] == 8'hAA, $sformatf("Test2: byte0=0xAA (got 0x%02h)", captured[0]));
            check(captured[1] == 8'h82, $sformatf("Test2: byte1=CMD 0x82 (got 0x%02h)", captured[1]));
            check(captured[2] == 8'h00, $sformatf("Test2: byte2=LEN 0x00 (got 0x%02h)", captured[2]));
            check(captured[3] == expected_chk, $sformatf("Test2: byte3=CHKSUM 0x%02h (got 0x%02h)", expected_chk, captured[3]));
        end

        repeat (10) @(posedge clk);

        // ===========================================================
        // TEST 3: NACK on parser checksum error
        // Frame: AA 81 01 03 CHKSUM
        // ===========================================================
        $display("\n--- Test 3: NACK on checksum error ---");
        begin
            reg [7:0] expected_chk;

            expected_chk = 8'h81 ^ 8'h01 ^ 8'h03;
            cap_idx = 0;

            @(posedge clk);
            parser_checksum_error <= 1'b1;
            @(posedge clk);
            parser_checksum_error <= 1'b0;

            wait_idle();

            check(cap_idx == 5, $sformatf("Test3: 5 bytes sent (got %0d)", cap_idx));
            check(captured[0] == 8'hAA, $sformatf("Test3: byte0=0xAA (got 0x%02h)", captured[0]));
            check(captured[1] == 8'h81, $sformatf("Test3: byte1=NACK 0x81 (got 0x%02h)", captured[1]));
            check(captured[2] == 8'h01, $sformatf("Test3: byte2=LEN 0x01 (got 0x%02h)", captured[2]));
            check(captured[3] == 8'h03, $sformatf("Test3: byte3=ERR_CHECKSUM 0x03 (got 0x%02h)", captured[3]));
            check(captured[4] == expected_chk, $sformatf("Test3: byte4=CHKSUM 0x%02h (got 0x%02h)", expected_chk, captured[4]));
        end

        repeat (10) @(posedge clk);

        // ===========================================================
        // TEST 4: NACK on parser frame error
        // Frame: AA 81 01 04 CHKSUM
        // ===========================================================
        $display("\n--- Test 4: NACK on frame error ---");
        begin
            reg [7:0] expected_chk;

            expected_chk = 8'h81 ^ 8'h01 ^ 8'h04;
            cap_idx = 0;

            @(posedge clk);
            parser_frame_error <= 1'b1;
            @(posedge clk);
            parser_frame_error <= 1'b0;

            wait_idle();

            check(cap_idx == 5, $sformatf("Test4: 5 bytes sent (got %0d)", cap_idx));
            check(captured[0] == 8'hAA, $sformatf("Test4: byte0=0xAA (got 0x%02h)", captured[0]));
            check(captured[1] == 8'h81, $sformatf("Test4: byte1=NACK 0x81 (got 0x%02h)", captured[1]));
            check(captured[3] == 8'h04, $sformatf("Test4: byte3=ERR_FRAME 0x04 (got 0x%02h)", captured[3]));
            check(captured[4] == expected_chk, $sformatf("Test4: byte4=CHKSUM 0x%02h (got 0x%02h)", expected_chk, captured[4]));
        end

        repeat (10) @(posedge clk);

        // ===========================================================
        // TEST 5: busy signal asserted during transmission
        // ===========================================================
        $display("\n--- Test 5: busy signal ---");
        begin
            reg was_busy;

            cap_idx = 0;
            was_busy = 0;

            issue_resp(8'h82, 8'd0, {MAX_PAYLOAD*8{1'b0}});
            repeat (3) @(posedge clk);
            was_busy = busy;

            wait_idle();

            check(was_busy, "Test5: busy HIGH during transmission");
            check(!busy,    "Test5: busy LOW after completion");
        end

        repeat (10) @(posedge clk);

        // ===========================================================
        // TEST 6: Pending request — new resp_req while busy
        // ===========================================================
        $display("\n--- Test 6: Pending request queued while busy ---");
        begin
            reg [MAX_PAYLOAD*8-1:0] pl1, pl2;
            integer first_cap, second_start;

            pl1 = {MAX_PAYLOAD*8{1'b0}};
            pl1[7:0] = 8'hAA;
            pl2 = {MAX_PAYLOAD*8{1'b0}};
            pl2[7:0] = 8'hBB;

            cap_idx = 0;

            // First request
            issue_resp(8'h80, 8'd1, pl1);
            repeat (3) @(posedge clk);

            // Second request while first is being sent
            check(busy, "Test6: DUT busy during first frame");
            issue_resp(8'h10, 8'd1, pl2);

            // Wait for both to complete
            wait_idle();

            // First frame: AA 80 01 AA chk  (5 bytes)
            // Second frame: AA 10 01 BB chk (5 bytes)
            check(cap_idx == 10, $sformatf("Test6: 10 bytes total (got %0d)", cap_idx));
            // Verify first frame start
            check(captured[0] == 8'hAA, "Test6: first frame byte0=0xAA");
            check(captured[1] == 8'h80, $sformatf("Test6: first frame CMD=0x80 (got 0x%02h)", captured[1]));
            // Verify second frame start
            check(captured[5] == 8'hAA, "Test6: second frame byte0=0xAA");
            check(captured[6] == 8'h10, $sformatf("Test6: second frame CMD=0x10 (got 0x%02h)", captured[6]));
            check(captured[8] == 8'hBB, $sformatf("Test6: second frame payload=0xBB (got 0x%02h)", captured[8]));
        end

        repeat (10) @(posedge clk);

        // ===========================================================
        // TEST 7: resp_len > MAX_PAYLOAD is clamped
        // ===========================================================
        $display("\n--- Test 7: resp_len clamped to MAX_PAYLOAD ---");
        begin
            cap_idx = 0;
            issue_resp(8'h80, 8'd20, {MAX_PAYLOAD*8{1'b0}});  // 20 > 16
            wait_idle();

            // Expected: AA CMD LEN=16 + 16 payload bytes + CHKSUM = 20 bytes
            check(cap_idx == (3 + MAX_PAYLOAD + 1),
                  $sformatf("Test7: frame size clamped (%0d bytes, expected %0d)", cap_idx, 3 + MAX_PAYLOAD + 1));
            check(captured[2] == MAX_PAYLOAD[7:0],
                  $sformatf("Test7: LEN field=%0d (got %0d)", MAX_PAYLOAD, captured[2]));
        end

        // ===========================================================
        // Summary
        // ===========================================================
        repeat (50) @(posedge clk);
        $display("\n============================================================");
        $display("UART Response TX Testbench Complete: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("============================================================");

        if (fail_count == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule
