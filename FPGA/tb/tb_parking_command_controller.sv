`timescale 1ns/1ps
//============================================================================
// Testbench for parking_command_controller
//============================================================================

module tb_parking_command_controller;

    localparam integer NUM_SLOTS    = 4;
    localparam integer MAX_PAYLOAD  = 16;
    localparam integer CLK_PERIOD_NS = 20;

    reg clk;
    reg rst_n;

    reg                        command_valid;
    reg  [7:0]                 command_id;
    reg  [MAX_PAYLOAD*8-1:0]   cmd_payload;
    reg  [7:0]                 cmd_payload_len;
    reg  [NUM_SLOTS-1:0]       sensor_status;
    reg                        resp_busy;
    reg                        entry_ir1_event;
    reg                        entry_ir2_event;
    reg                        exit_ir1_event;
    reg                        exit_ir2_event;

    wire                       entry_gate_open;
    wire                       entry_gate_close;
    wire                       exit_gate_open;
    wire                       exit_gate_close;
    wire                       resp_req;
    wire [7:0]                 resp_cmd;
    wire [MAX_PAYLOAD*8-1:0]   resp_payload;
    wire [7:0]                 resp_len;
    wire                       lcd_msg_valid;
    wire [127:0]               lcd_msg_line0;
    wire [127:0]               lcd_msg_line1;

    integer pass_count;
    integer fail_count;

    parking_command_controller #(
        .CLK_FREQ          (50_000_000),
        .NUM_SLOTS         (NUM_SLOTS),
        .MAX_PAYLOAD       (MAX_PAYLOAD),
        .GATE_TIMEOUT_CLKS (100)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .command_valid   (command_valid),
        .command_id      (command_id),
        .cmd_payload     (cmd_payload),
        .cmd_payload_len (cmd_payload_len),
        .sensor_status     (sensor_status),
        .entry_ir1_event   (entry_ir1_event),
        .entry_ir2_event   (entry_ir2_event),
        .exit_ir1_event    (exit_ir1_event),
        .exit_ir2_event    (exit_ir2_event),
        .entry_failsafe_event (1'b0),
        .exit_failsafe_event  (1'b0),
        .entry_gate_open   (entry_gate_open),
        .entry_gate_close  (entry_gate_close),
        .exit_gate_open    (exit_gate_open),
        .exit_gate_close   (exit_gate_close),
        .resp_busy       (resp_busy),
        .resp_req        (resp_req),
        .resp_cmd        (resp_cmd),
        .resp_payload    (resp_payload),
        .resp_len        (resp_len),
        .lcd_msg_valid   (lcd_msg_valid),
        .lcd_msg_line0   (lcd_msg_line0),
        .lcd_msg_line1   (lcd_msg_line1)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    task automatic issue_command(input [7:0] cid, input [7:0] p0, input [7:0] plen);
        begin
            @(posedge clk);
            command_valid   <= 1'b1;
            command_id      <= cid;
            cmd_payload     <= {MAX_PAYLOAD*8{1'b0}};
            cmd_payload[7:0] <= p0;
            cmd_payload_len <= plen;
            @(posedge clk);
            command_valid   <= 1'b0;
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
        $dumpfile("parking_command_controller.vcd");
        $dumpvars(0, tb_parking_command_controller);

        pass_count = 0;
        fail_count = 0;
        rst_n = 1'b0;
        command_valid = 1'b0;
        command_id = 8'd0;
        cmd_payload = {MAX_PAYLOAD*8{1'b0}};
        cmd_payload_len = 8'd0;
        sensor_status = {NUM_SLOTS{1'b0}};
        resp_busy = 1'b0;
        entry_ir1_event = 1'b0;
        entry_ir2_event = 1'b0;
        exit_ir1_event = 1'b0;
        exit_ir2_event = 1'b0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("============================================================");
        $display("Parking Command Controller Testbench");
        $display("============================================================");

        // --- Test 1: PING -> PONG ---
        $display("\n--- Test 1: PING -> PONG ---");
        issue_command(8'h7F, 8'd0, 8'd0);
        @(posedge clk);
        check(resp_req == 1'b1, "Test1: resp_req pulsed");
        check(resp_cmd == 8'h82, $sformatf("Test1: PONG cmd 0x82 (got 0x%02h)", resp_cmd));
        check(resp_len == 8'd0, "Test1: PONG has no payload");
        repeat (5) @(posedge clk);

        // --- Test 2: OPEN_GATE (entry) one-clock pulse ---
        $display("\n--- Test 2: OPEN_GATE (entry) one-clock pulse ---");
        issue_command(8'h01, 8'h00, 8'd1);  // payload=0x00 (entry), len=1
        @(posedge clk);
        check(entry_gate_open == 1'b1, "Test2: entry_gate_open HIGH on command cycle");
        check(entry_gate_close == 1'b0, "Test2: entry_gate_close LOW");
        check(exit_gate_open == 1'b0, "Test2: exit_gate_open LOW");
        check(resp_cmd == 8'h80, $sformatf("Test2: ACK (got 0x%02h)", resp_cmd));
        check(resp_payload[7:0] == 8'h01, $sformatf("Test2: ACK payload=0x01 (got 0x%02h)", resp_payload[7:0]));
        @(posedge clk);
        check(entry_gate_open == 1'b0, "Test2: entry_gate_open LOW next cycle (pulse)");
        repeat (5) @(posedge clk);

        // --- Test 3: CLOSE_GATE (entry) one-clock pulse ---
        $display("\n--- Test 3: CLOSE_GATE (entry) one-clock pulse ---");
        issue_command(8'h02, 8'h00, 8'd1);  // payload=0x00 (entry), len=1
        @(posedge clk);
        check(entry_gate_close == 1'b1, "Test3: entry_gate_close HIGH on command cycle");
        check(entry_gate_open == 1'b0, "Test3: entry_gate_open LOW");
        @(posedge clk);
        check(entry_gate_close == 1'b0, "Test3: entry_gate_close LOW next cycle (pulse)");
        repeat (5) @(posedge clk);

        // --- Test 4: REQUEST_STATUS ---
        $display("\n--- Test 4: REQUEST_STATUS ---");
        sensor_status = 4'b1010;
        repeat (3) @(posedge clk);
        issue_command(8'h05, 8'd0, 8'd0);
        @(posedge clk);
        check(resp_cmd == 8'h10, $sformatf("Test4: PARKING_STATUS cmd 0x10 (got 0x%02h)", resp_cmd));
        check(resp_payload[NUM_SLOTS-1:0] == 4'b1010,
              $sformatf("Test4: slot bits=0b1010 (got 0b%04b)", resp_payload[NUM_SLOTS-1:0]));
        repeat (5) @(posedge clk);

        // --- Test 5: Unknown command -> NACK ---
        $display("\n--- Test 5: Unknown command -> NACK ---");
        issue_command(8'hFF, 8'd0, 8'd0);
        @(posedge clk);
        check(resp_cmd == 8'h81, $sformatf("Test5: NACK cmd 0x81 (got 0x%02h)", resp_cmd));
        check(resp_payload[7:0] == 8'h01, $sformatf("Test5: NACK err=0x01 unknown (got 0x%02h)", resp_payload[7:0]));
        repeat (5) @(posedge clk);

        // --- Test 6: OPEN_GATE bad length -> NACK ---
        $display("\n--- Test 6: OPEN_GATE bad length -> NACK ---");
        issue_command(8'h01, 8'hAA, 8'd0);
        @(posedge clk);
        check(resp_cmd == 8'h81, $sformatf("Test6: NACK (got 0x%02h)", resp_cmd));
        check(resp_payload[7:0] == 8'h02, $sformatf("Test6: err=0x02 bad len (got 0x%02h)", resp_payload[7:0]));
        check(entry_gate_open == 1'b0, "Test6: entry_gate_open not pulsed on bad len");
        check(exit_gate_open == 1'b0, "Test6: exit_gate_open not pulsed on bad len");
        repeat (5) @(posedge clk);

        // --- Test 7: PING bad length -> NACK ---
        $display("\n--- Test 7: PING bad length -> NACK ---");
        issue_command(8'h7F, 8'hBB, 8'd1);
        @(posedge clk);
        check(resp_cmd == 8'h81, $sformatf("Test7: NACK (got 0x%02h)", resp_cmd));
        check(resp_payload[7:0] == 8'h02, $sformatf("Test7: err=0x02 (got 0x%02h)", resp_payload[7:0]));
        repeat (5) @(posedge clk);

        // --- Test 8: Response not lost when resp_busy ---
        $display("\n--- Test 8: Response queued when resp_busy ---");
        begin
            reg saw_resp;
            integer timeout;

            resp_busy = 1'b1;
            issue_command(8'h7F, 8'd0, 8'd0);  // PING while busy
            @(posedge clk);
            check(resp_req == 1'b0, "Test8: resp_req NOT asserted while busy");

            // Release busy after a few cycles
            repeat (5) @(posedge clk);
            resp_busy = 1'b0;

            saw_resp = 0;
            timeout = 0;
            while (timeout < 10) begin
                @(posedge clk);
                if (resp_req && resp_cmd == 8'h82) saw_resp = 1;
                timeout = timeout + 1;
            end
            check(saw_resp, "Test8: PONG delivered after resp_busy released");
        end
        repeat (5) @(posedge clk);

        // --- Test 9: Pending response is not overwritten while busy ---
        $display("\n--- Test 9: Pending response not overwritten while busy ---");
        begin
            reg saw_first;
            reg saw_second;
            integer timeout;

            resp_busy = 1'b1;
            issue_command(8'h7F, 8'd0, 8'd0);  // queues PONG
            @(posedge clk);
            issue_command(8'h01, 8'h00, 8'd1);  // must not overwrite or pulse gate
            @(posedge clk);
            check(resp_req == 1'b0, "Test9: no resp_req while still busy");
            check(entry_gate_open == 1'b0, "Test9: entry_gate_open not pulsed when response slot unavailable");

            repeat (5) @(posedge clk);
            resp_busy = 1'b0;

            saw_first = 0;
            saw_second = 0;
            timeout = 0;
            while (timeout < 10) begin
                @(posedge clk);
                if (resp_req && resp_cmd == 8'h82) saw_first = 1;
                if (resp_req && resp_cmd == 8'h80 && resp_payload[7:0] == 8'h01) saw_second = 1;
                timeout = timeout + 1;
            end
            check(saw_first, "Test9: original pending PONG preserved");
            check(!saw_second, "Test9: second command did not overwrite pending slot");
        end
        repeat (5) @(posedge clk);

        // --- Test 10: Sensor status does not override pending command response ---
        $display("\n--- Test 10: Sensor status waits behind pending command response ---");
        begin
            reg saw_pong;
            reg saw_status;
            integer timeout;

            resp_busy = 1'b1;
            issue_command(8'h7F, 8'd0, 8'd0);  // queues PONG
            sensor_status = 4'b0011;
            repeat (5) @(posedge clk);
            resp_busy = 1'b0;

            saw_pong = 0;
            saw_status = 0;
            timeout = 0;
            while (timeout < 20) begin
                @(posedge clk);
                if (resp_req && resp_cmd == 8'h82) saw_pong = 1;
                if (resp_req && resp_cmd == 8'h10) saw_status = 1;
                timeout = timeout + 1;
            end
            check(saw_pong, "Test10: pending PONG sent first");
            check(saw_status, "Test10: sensor status sent after pending response");
        end
        repeat (5) @(posedge clk);

        // --- Test 11: Sensor change -> auto PARKING_STATUS ---
        $display("\n--- Test 11: Sensor change -> auto PARKING_STATUS ---");
        begin
            reg saw_status;
            integer timeout;

            saw_status = 0;
            sensor_status = 4'b0101;
            resp_busy = 1'b0;

            timeout = 0;
            while (timeout < 20) begin
                @(posedge clk);
                if (resp_req && resp_cmd == 8'h10) begin
                    saw_status = 1;
                end
                timeout = timeout + 1;
            end

            check(saw_status, "Test11: PARKING_STATUS sent on sensor change");
        end

        repeat (50) @(posedge clk);
        $display("\n============================================================");
        $display("Parking Command Controller Testbench Complete: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("============================================================");

        if (fail_count == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule
