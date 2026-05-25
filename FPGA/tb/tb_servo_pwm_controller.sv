`timescale 1ns/1ps
//============================================================================
// Testbench for servo_pwm_controller
// Uses reduced timing parameters for fast simulation
//============================================================================

module tb_servo_pwm_controller;

    localparam integer CLK_PERIOD_NS  = 20;
    localparam integer PERIOD_CYCLES  = 20;
    localparam integer CLOSED_CYCLES  = 4;
    localparam integer OPEN_CYCLES    = 8;

    reg clk;
    reg rst_n;

    reg entry_gate_open;
    reg entry_gate_close;
    reg exit_gate_open;
    reg exit_gate_close;

    wire entry_servo_pwm;
    wire exit_servo_pwm;

    integer pass_count;
    integer fail_count;

    servo_pwm_controller #(
        .CLK_FREQ      (1000),
        .PERIOD_CYCLES (PERIOD_CYCLES),
        .CLOSED_CYCLES (CLOSED_CYCLES),
        .OPEN_CYCLES   (OPEN_CYCLES)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .entry_gate_open  (entry_gate_open),
        .entry_gate_close (entry_gate_close),
        .exit_gate_open   (exit_gate_open),
        .exit_gate_close  (exit_gate_close),
        .entry_servo_pwm  (entry_servo_pwm),
        .exit_servo_pwm   (exit_servo_pwm)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    task automatic pulse_entry_open();
        begin
            @(posedge clk);
            entry_gate_open <= 1'b1;
            @(posedge clk);
            entry_gate_open <= 1'b0;
        end
    endtask

    task automatic pulse_entry_close();
        begin
            @(posedge clk);
            entry_gate_close <= 1'b1;
            @(posedge clk);
            entry_gate_close <= 1'b0;
        end
    endtask

    task automatic pulse_exit_open();
        begin
            @(posedge clk);
            exit_gate_open <= 1'b1;
            @(posedge clk);
            exit_gate_open <= 1'b0;
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

    task automatic measure_high_cycles(input bit select_entry, output integer high_count);
        integer i;
        begin
            high_count = 0;
            // Measure exactly one PWM period
            for (i = 0; i < PERIOD_CYCLES; i = i + 1) begin
                @(posedge clk);
                if (select_entry) begin
                    if (entry_servo_pwm)
                        high_count = high_count + 1;
                end else begin
                    if (exit_servo_pwm)
                        high_count = high_count + 1;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("servo_pwm_controller.vcd");
        $dumpvars(0, tb_servo_pwm_controller);

        pass_count = 0;
        fail_count = 0;
        entry_gate_open  = 1'b0;
        entry_gate_close = 1'b0;
        exit_gate_open   = 1'b0;
        exit_gate_close  = 1'b0;

        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("============================================================");
        $display("Servo PWM Controller Testbench");
        $display("============================================================");

        // ===========================================================
        // TEST 1: Reset state
        // ===========================================================
        $display("\n--- Test 1: Reset state ---");
        check(entry_servo_pwm == 1'b0, "Test1: entry_servo_pwm low immediately after reset");
        check(exit_servo_pwm  == 1'b0, "Test1: exit_servo_pwm low immediately after reset");

        repeat (PERIOD_CYCLES) @(posedge clk);

        // ===========================================================
        // TEST 2: Default closed pulse width
        // ===========================================================
        $display("\n--- Test 2: Default CLOSED pulse width ---");
        begin
            integer high_count;
            measure_high_cycles(1'b1, high_count);
            check(high_count == CLOSED_CYCLES,
                  $sformatf("Test2: entry closed width=%0d cycles (got %0d)", CLOSED_CYCLES, high_count));

            measure_high_cycles(1'b0, high_count);
            check(high_count == CLOSED_CYCLES,
                  $sformatf("Test2: exit closed width=%0d cycles (got %0d)", CLOSED_CYCLES, high_count));
        end

        // ===========================================================
        // TEST 3: entry_gate_open changes width to OPEN_CYCLES
        // ===========================================================
        $display("\n--- Test 3: Entry open command ---");
        begin
            integer high_count;
            pulse_entry_open();
            repeat (PERIOD_CYCLES) @(posedge clk);
            measure_high_cycles(1'b1, high_count);
            check(high_count == OPEN_CYCLES,
                  $sformatf("Test3: entry open width=%0d cycles (got %0d)", OPEN_CYCLES, high_count));
        end

        // ===========================================================
        // TEST 4: entry_gate_close returns width to CLOSED_CYCLES
        // ===========================================================
        $display("\n--- Test 4: Entry close command ---");
        begin
            integer high_count;
            pulse_entry_close();
            repeat (PERIOD_CYCLES) @(posedge clk);
            measure_high_cycles(1'b1, high_count);
            check(high_count == CLOSED_CYCLES,
                  $sformatf("Test4: entry close width=%0d cycles (got %0d)", CLOSED_CYCLES, high_count));
        end

        // ===========================================================
        // TEST 5: Close wins over open when simultaneous
        // ===========================================================
        $display("\n--- Test 5: close wins over open ---");
        begin
            integer high_count;
            @(posedge clk);
            entry_gate_open  <= 1'b1;
            entry_gate_close <= 1'b1;
            @(posedge clk);
            entry_gate_open  <= 1'b0;
            entry_gate_close <= 1'b0;

            repeat (PERIOD_CYCLES) @(posedge clk);
            measure_high_cycles(1'b1, high_count);
            check(high_count == CLOSED_CYCLES,
                  $sformatf("Test5: simultaneous open/close => CLOSED (%0d, got %0d)", CLOSED_CYCLES, high_count));
        end

        // ===========================================================
        // TEST 6: Entry and exit are independent
        // ===========================================================
        $display("\n--- Test 6: Entry/exit independent ---");
        begin
            integer entry_high;
            integer exit_high;

            pulse_entry_open();
            pulse_exit_open();
            pulse_entry_close();
            repeat (PERIOD_CYCLES) @(posedge clk);

            measure_high_cycles(1'b1, entry_high);
            measure_high_cycles(1'b0, exit_high);

            check(entry_high == CLOSED_CYCLES,
                  $sformatf("Test6: entry closed=%0d (got %0d)", CLOSED_CYCLES, entry_high));
            check(exit_high == OPEN_CYCLES,
                  $sformatf("Test6: exit open=%0d (got %0d)", OPEN_CYCLES, exit_high));
        end

        // ===========================================================
        // TEST 7: PWM period repeats correctly
        // ===========================================================
        $display("\n--- Test 7: PWM period ---");
        begin
            integer cycles_between_edges;
            cycles_between_edges = 0;

            wait (entry_servo_pwm == 1'b1);
            @(negedge entry_servo_pwm);
            @(posedge entry_servo_pwm);
            while (entry_servo_pwm !== 1'b0) @(posedge clk);
            @(posedge entry_servo_pwm);

            cycles_between_edges = 0;
            @(posedge clk);
            while (entry_servo_pwm != 1'b1) begin
                cycles_between_edges = cycles_between_edges + 1;
                @(posedge clk);
            end

            check(cycles_between_edges <= PERIOD_CYCLES,
                  $sformatf("Test7: PWM period repeats within %0d cycles (measured %0d)", PERIOD_CYCLES, cycles_between_edges));
        end

        // ===========================================================
        // Summary
        // ===========================================================
        repeat (50) @(posedge clk);
        $display("\n============================================================");
        $display("Servo PWM Controller Testbench Complete: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("============================================================");

        if (fail_count == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule
