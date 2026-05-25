`timescale 1ns/1ps

module tb_lcd_string_writer;

    localparam CLK_FREQ = 1_000_000;
    localparam CLK_PERIOD_NS = 1000;

    reg clk;
    reg rst_n;
    reg update;
    reg [127:0] line0;
    reg [127:0] line1;
    wire busy;
    wire lcd_rs;
    wire lcd_en;
    wire [3:0] lcd_d;

    integer capture_count;
    reg captured_rs [0:127];
    reg [3:0] captured_d [0:127];

    lcd_string_writer #(
        .CLK_FREQ (CLK_FREQ)
    ) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .update (update),
        .line0  (line0),
        .line1  (line1),
        .busy   (busy),
        .lcd_rs (lcd_rs),
        .lcd_en (lcd_en),
        .lcd_d  (lcd_d)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    always @(posedge lcd_en) begin
        if (capture_count < 128) begin
            captured_rs[capture_count] = lcd_rs;
            captured_d[capture_count]  = lcd_d;
        end
        capture_count = capture_count + 1;
    end

    task pulse_update;
        begin
            @(posedge clk);
            update <= 1'b1;
            @(posedge clk);
            update <= 1'b0;
            wait (busy == 1'b1);
            wait (busy == 1'b0);
        end
    endtask

    task expect_byte;
        input integer nibble_index;
        input exp_rs;
        input [7:0] exp_data;
        begin
            if (captured_rs[nibble_index] !== exp_rs ||
                captured_d[nibble_index] !== exp_data[7:4] ||
                captured_rs[nibble_index + 1] !== exp_rs ||
                captured_d[nibble_index + 1] !== exp_data[3:0]) begin
                $display("FAIL byte at nibble[%0d]: got rs=%0b d=%h, rs=%0b d=%h expected rs=%0b data=%h",
                         nibble_index,
                         captured_rs[nibble_index], captured_d[nibble_index],
                         captured_rs[nibble_index + 1], captured_d[nibble_index + 1],
                         exp_rs, exp_data);
                $finish;
            end
        end
    endtask

    integer i;
    integer base;

    initial begin
        rst_n = 1'b0;
        update = 1'b0;
        line0 = "ABCDEFGHIJKLMNOP";
        line1 = "abcdefghijklmnop";
        capture_count = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        wait (busy == 1'b0);

        if (capture_count != 12) begin
            $display("FAIL init capture_count=%0d expected 12", capture_count);
            $finish;
        end

        pulse_update();

        if (capture_count != 80) begin
            $display("FAIL total capture_count=%0d expected 80", capture_count);
            $finish;
        end

        base = 12;
        expect_byte(base, 1'b0, 8'h80);
        base = base + 2;
        for (i = 0; i < 16; i = i + 1) begin
            expect_byte(base + (i * 2), 1'b1, 8'h41 + i[7:0]);
        end

        base = 12 + 34;
        expect_byte(base, 1'b0, 8'hC0);
        base = base + 2;
        for (i = 0; i < 16; i = i + 1) begin
            expect_byte(base + (i * 2), 1'b1, 8'h61 + i[7:0]);
        end

        $display("PASS tb_lcd_string_writer");
        $finish;
    end

endmodule
