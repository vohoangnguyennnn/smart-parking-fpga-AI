`timescale 1ns/1ps
//============================================================================
// Testbench for seven_seg_decoder
// Combinational decoder — exhaustive check of all 16 inputs
//============================================================================

module tb_seven_seg_decoder;

    reg  [3:0] digit;
    wire [6:0] seg;

    integer pass_count;
    integer fail_count;

    seven_seg_decoder dut (
        .digit (digit),
        .seg   (seg)
    );

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

    // Expected segment patterns for digits 0-9
    // seg[6:0] = {g, f, e, d, c, b, a}
    reg [6:0] expected [0:15];

    initial begin
        $dumpfile("seven_seg_decoder.vcd");
        $dumpvars(0, tb_seven_seg_decoder);

        pass_count = 0;
        fail_count = 0;

        expected[0]  = 7'b0111111;  // 0
        expected[1]  = 7'b0000110;  // 1
        expected[2]  = 7'b1011011;  // 2
        expected[3]  = 7'b1001111;  // 3
        expected[4]  = 7'b1100110;  // 4
        expected[5]  = 7'b1101101;  // 5
        expected[6]  = 7'b1111101;  // 6
        expected[7]  = 7'b0000111;  // 7
        expected[8]  = 7'b1111111;  // 8
        expected[9]  = 7'b1101111;  // 9
        expected[10] = 7'b0000000;  // invalid
        expected[11] = 7'b0000000;  // invalid
        expected[12] = 7'b0000000;  // invalid
        expected[13] = 7'b0000000;  // invalid
        expected[14] = 7'b0000000;  // invalid
        expected[15] = 7'b0000000;  // invalid

        $display("============================================================");
        $display("Seven Segment Common Cathode Testbench");
        $display("============================================================");

        // ===========================================================
        // Exhaustive test of all 16 input values
        // ===========================================================
        begin
            integer i;
            for (i = 0; i < 16; i = i + 1) begin
                digit = i[3:0];
                #10;  // combinational settle time
                check(seg == expected[i],
                      $sformatf("digit=%0d: seg=7'b%07b (expected 7'b%07b)", i, seg, expected[i]));
            end
        end

        // ===========================================================
        // Summary
        // ===========================================================
        #100;
        $display("\n============================================================");
        $display("Seven Seg Testbench Complete: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("============================================================");

        if (fail_count == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule
