`timescale 1ns/1ps
//============================================================================
// Testbench for ir_sensor_debounce
// Uses small DEBOUNCE_CLKS for fast simulation
//============================================================================

module tb_ir_sensor_debounce;

    localparam integer NUM_SLOTS      = 4;
    localparam integer DEBOUNCE_CLKS  = 10;
    localparam integer CLK_PERIOD_NS  = 20;

    reg                     clk;
    reg                     rst_n;
    reg  [NUM_SLOTS-1:0]    ir_sensors_raw;
    wire [NUM_SLOTS-1:0]    slot_occupied;

    integer pass_count;
    integer fail_count;

    ir_sensor_debounce #(
        .NUM_SLOTS     (NUM_SLOTS),
        .DEBOUNCE_CLKS (DEBOUNCE_CLKS)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .ir_sensors_raw (ir_sensors_raw),
        .slot_occupied  (slot_occupied)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

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
        $dumpfile("ir_sensor_debounce.vcd");
        $dumpvars(0, tb_ir_sensor_debounce);

        pass_count     = 0;
        fail_count     = 0;
        ir_sensors_raw = {NUM_SLOTS{1'b1}};  // idle = all HIGH (active-low)
        rst_n          = 1'b1;
        repeat (2) @(posedge clk);
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("============================================================");
        $display("IR Sensor Debounce Testbench — NUM_SLOTS=%0d, DEBOUNCE=%0d",
                 NUM_SLOTS, DEBOUNCE_CLKS);
        $display("============================================================");

        // ===========================================================
        // TEST 1: All slots idle after reset
        // ===========================================================
        $display("\n--- Test 1: Reset state ---");
        check(slot_occupied == {NUM_SLOTS{1'b0}}, "Test1: all slots empty after reset");

        // ===========================================================
        // TEST 2: Stable LOW on slot 0 → occupied after debounce
        // (active-low: sensor=0 means car present → slot_occupied=1)
        // ===========================================================
        $display("\n--- Test 2: Slot 0 stable LOW → occupied ---");
        begin
            ir_sensors_raw[0] = 1'b0;  // car present

            // 2 FF sync + DEBOUNCE_CLKS - need enough cycles
            repeat (DEBOUNCE_CLKS + 10) @(posedge clk);

            check(slot_occupied[0] == 1'b1,
                  $sformatf("Test2: slot_occupied[0]=1 (got %0b)", slot_occupied[0]));
            check(slot_occupied[3:1] == 3'b000,
                  "Test2: other slots still empty");
        end

        repeat (5) @(posedge clk);

        // ===========================================================
        // TEST 3: Glitch on slot 1 — too short to pass debounce
        // ===========================================================
        $display("\n--- Test 3: Glitch rejected on slot 1 ---");
        begin
            // Pull LOW for less than DEBOUNCE_CLKS, then release
            ir_sensors_raw[1] = 1'b0;
            repeat (DEBOUNCE_CLKS / 2) @(posedge clk);
            ir_sensors_raw[1] = 1'b1;

            // Wait for any residual
            repeat (DEBOUNCE_CLKS + 10) @(posedge clk);

            check(slot_occupied[1] == 1'b0,
                  "Test3: slot 1 not occupied after glitch");
        end

        repeat (5) @(posedge clk);

        // ===========================================================
        // TEST 4: Multiple slots active independently
        // ===========================================================
        $display("\n--- Test 4: Slots 0,2 occupied, 1,3 empty ---");
        begin
            // Slot 0 already LOW from Test 2
            ir_sensors_raw[2] = 1'b0;  // car present
            ir_sensors_raw[1] = 1'b1;  // empty
            ir_sensors_raw[3] = 1'b1;  // empty

            repeat (DEBOUNCE_CLKS + 10) @(posedge clk);

            check(slot_occupied[0] == 1'b1, "Test4: slot 0 occupied");
            check(slot_occupied[1] == 1'b0, "Test4: slot 1 empty");
            check(slot_occupied[2] == 1'b1, "Test4: slot 2 occupied");
            check(slot_occupied[3] == 1'b0, "Test4: slot 3 empty");
        end

        repeat (5) @(posedge clk);

        // ===========================================================
        // TEST 5: Car leaves — slot 0 goes HIGH → slot becomes empty
        // ===========================================================
        $display("\n--- Test 5: Slot 0 car leaves → empty ---");
        begin
            ir_sensors_raw[0] = 1'b1;  // car leaves

            repeat (DEBOUNCE_CLKS + 10) @(posedge clk);

            check(slot_occupied[0] == 1'b0,
                  "Test5: slot 0 empty after car leaves");
        end

        repeat (5) @(posedge clk);

        // ===========================================================
        // TEST 6: All slots occupied simultaneously
        // ===========================================================
        $display("\n--- Test 6: All slots occupied ---");
        begin
            ir_sensors_raw = {NUM_SLOTS{1'b0}};  // all LOW

            repeat (DEBOUNCE_CLKS + 10) @(posedge clk);

            check(slot_occupied == {NUM_SLOTS{1'b1}},
                  $sformatf("Test6: all occupied (got 0b%04b)", slot_occupied));
        end

        repeat (5) @(posedge clk);

        // ===========================================================
        // TEST 7: All slots released simultaneously
        // ===========================================================
        $display("\n--- Test 7: All slots released ---");
        begin
            ir_sensors_raw = {NUM_SLOTS{1'b1}};  // all HIGH

            repeat (DEBOUNCE_CLKS + 10) @(posedge clk);

            check(slot_occupied == {NUM_SLOTS{1'b0}},
                  $sformatf("Test7: all empty (got 0b%04b)", slot_occupied));
        end

        // ===========================================================
        // Summary
        // ===========================================================
        repeat (50) @(posedge clk);
        $display("\n============================================================");
        $display("IR Sensor Debounce Testbench Complete: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("============================================================");

        if (fail_count == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule
