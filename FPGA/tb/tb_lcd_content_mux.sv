`timescale 1ns/1ps

module tb_lcd_content_mux;

    localparam CLK_FREQ = 1_000_000;
    localparam NUM_SLOTS = 4;
    localparam MSG_HOLD_CLKS = 20;
    localparam CLK_PERIOD_NS = 1000;
    localparam TIMEOUT = 200;

    reg clk;
    reg rst_n;
    reg [NUM_SLOTS-1:0] slot_occupied;
    reg writer_busy;
    reg msg_valid;
    reg [127:0] msg_line0;
    reg [127:0] msg_line1;
    wire lcd_update;
    wire [127:0] lcd_line0;
    wire [127:0] lcd_line1;

    integer update_count;
    integer fail;

    lcd_content_mux #(
        .CLK_FREQ      (CLK_FREQ),
        .NUM_SLOTS     (NUM_SLOTS),
        .MSG_HOLD_CLKS (MSG_HOLD_CLKS)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .slot_occupied (slot_occupied),
        .writer_busy   (writer_busy),
        .msg_valid     (msg_valid),
        .msg_line0     (msg_line0),
        .msg_line1     (msg_line1),
        .lcd_update    (lcd_update),
        .lcd_line0     (lcd_line0),
        .lcd_line1     (lcd_line1)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    always @(posedge clk) begin
        if (lcd_update)
            update_count <= update_count + 1;
    end

    task expect_lines;
        input [127:0] exp_line0;
        input [127:0] exp_line1;
        input [8*32-1:0] label;
        begin
            if (lcd_line0 !== exp_line0 || lcd_line1 !== exp_line1) begin
                $display("FAIL [%0s]", label);
                $display("  got line0='%s'", lcd_line0);
                $display("  got line1='%s'", lcd_line1);
                $display("  exp line0='%s'", exp_line0);
                $display("  exp line1='%s'", exp_line1);
                $finish;
            end else begin
                $display("OK   [%0s]", label);
            end
        end
    endtask

    task wait_for_update;
        integer cyc;
        begin
            fail = 0;
            for (cyc = 0; cyc < TIMEOUT; cyc = cyc + 1) begin
                @(posedge clk);
                if (lcd_update) begin
                    fail = 0;
                    cyc = TIMEOUT;
                end
            end
            if (fail) begin
                $display("FAIL timeout waiting for lcd_update");
                $finish;
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        slot_occupied = 4'b0000;
        writer_busy = 1'b0;
        msg_valid = 1'b0;
        msg_line0 = "NHAN DIEN ENTRY ";
        msg_line1 = "VUI LONG DOI... ";
        update_count = 0;
        fail = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        // --- Test 1: initial idle after reset ---
        wait_for_update();
        expect_lines("WELCOME         ", "Occ:0 Free:4    ", "idle after reset");

        // --- Test 2: slot change -> idle update ---
        repeat (3) @(posedge clk);
        @(negedge clk);
        slot_occupied = 4'b0011;
        wait_for_update();
        expect_lines("WELCOME         ", "Occ:2 Free:2    ", "slot change");

        // --- Test 3: msg_valid -> temporary message ---
        repeat (3) @(posedge clk);
        @(negedge clk);
        msg_valid = 1'b1;
        @(negedge clk);
        msg_valid = 1'b0;
        wait_for_update();
        expect_lines("NHAN DIEN ENTRY ", "VUI LONG DOI... ", "message display");

        // --- Test 4: timeout -> back to idle ---
        repeat (MSG_HOLD_CLKS + 5) @(posedge clk);
        wait_for_update();
        expect_lines("WELCOME         ", "Occ:2 Free:2    ", "back to idle");

        // --- Test 5: writer_busy blocks lcd_update ---
        repeat (3) @(posedge clk);
        @(negedge clk);
        writer_busy = 1'b1;
        slot_occupied = 4'b1111;
        repeat (10) @(posedge clk);
        if (lcd_update) begin
            $display("FAIL lcd_update while writer_busy=1");
            $finish;
        end
        $display("OK   [writer_busy blocks update]");
        @(negedge clk);
        writer_busy = 1'b0;
        wait_for_update();
        expect_lines("WELCOME         ", "Occ:4 Free:0    ", "after writer_busy release");

        $display("PASS tb_lcd_content_mux");
        $finish;
    end

endmodule
