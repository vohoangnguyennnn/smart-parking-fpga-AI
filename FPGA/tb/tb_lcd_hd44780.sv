`timescale 1ns/1ps

module tb_lcd_hd44780;

    localparam CLK_FREQ = 1_000_000;
    localparam CLK_PERIOD_NS = 1000;

    reg clk;
    reg rst_n;
    reg wr_en;
    reg wr_rs;
    reg [7:0] wr_data;
    wire busy;
    wire lcd_rs;
    wire lcd_en;
    wire [3:0] lcd_d;

    integer capture_count;
    reg [4:0] captured_rs [0:31];
    reg [3:0] captured_d  [0:31];

    // EN pulse width measurement
    realtime en_rise_time;
    real     en_min_pulse_ns;
    integer  en_pulse_count;

    lcd_hd44780 #(
        .CLK_FREQ (CLK_FREQ)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (wr_en),
        .wr_rs   (wr_rs),
        .wr_data (wr_data),
        .busy    (busy),
        .lcd_rs  (lcd_rs),
        .lcd_en  (lcd_en),
        .lcd_d   (lcd_d)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    always @(posedge lcd_en) begin
        if (capture_count < 32) begin
            captured_rs[capture_count] = lcd_rs;
            captured_d[capture_count]  = lcd_d;
        end
        capture_count = capture_count + 1;
        en_rise_time = $realtime;
    end

    always @(negedge lcd_en) begin
        if (en_pulse_count > 0 || capture_count > 0) begin
            automatic real pulse_ns = $realtime - en_rise_time;
            if (en_pulse_count == 0 || pulse_ns < en_min_pulse_ns)
                en_min_pulse_ns = pulse_ns;
            en_pulse_count = en_pulse_count + 1;
        end
    end

    task expect_nibble;
        input integer index;
        input exp_rs;
        input [3:0] exp_d;
        begin
            if (captured_rs[index] !== exp_rs || captured_d[index] !== exp_d) begin
                $display("FAIL nibble[%0d]: rs=%0b d=%h, expected rs=%0b d=%h",
                         index, captured_rs[index], captured_d[index], exp_rs, exp_d);
                $finish;
            end
        end
    endtask

    task write_byte;
        input in_rs;
        input [7:0] in_data;
        begin
            @(posedge clk);
            wr_rs   <= in_rs;
            wr_data <= in_data;
            wr_en   <= 1'b1;
            @(posedge clk);
            wr_en   <= 1'b0;
            wait (busy == 1'b1);
            wait (busy == 1'b0);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        wr_en = 1'b0;
        wr_rs = 1'b0;
        wr_data = 8'd0;
        capture_count = 0;
        en_min_pulse_ns = 1.0e9;
        en_pulse_count = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        wait (busy == 1'b0);

        if (capture_count != 12) begin
            $display("FAIL init capture_count=%0d, expected 12", capture_count);
            $finish;
        end

        expect_nibble(0,  1'b0, 4'h3);
        expect_nibble(1,  1'b0, 4'h3);
        expect_nibble(2,  1'b0, 4'h3);
        expect_nibble(3,  1'b0, 4'h2);
        expect_nibble(4,  1'b0, 4'h2);
        expect_nibble(5,  1'b0, 4'h8);
        expect_nibble(6,  1'b0, 4'h0);
        expect_nibble(7,  1'b0, 4'hc);
        expect_nibble(8,  1'b0, 4'h0);
        expect_nibble(9,  1'b0, 4'h1);
        expect_nibble(10, 1'b0, 4'h0);
        expect_nibble(11, 1'b0, 4'h6);

        write_byte(1'b1, 8'h41);

        if (capture_count != 14) begin
            $display("FAIL write capture_count=%0d, expected 14", capture_count);
            $finish;
        end

        expect_nibble(12, 1'b1, 4'h4);
        expect_nibble(13, 1'b1, 4'h1);

        // --- Test 2: write command 0x80 (set DDRAM addr) ---
        write_byte(1'b0, 8'h80);
        expect_nibble(14, 1'b0, 4'h8);
        expect_nibble(15, 1'b0, 4'h0);

        // --- Test 3: write data 'B' = 0x42 ---
        write_byte(1'b1, 8'h42);
        expect_nibble(16, 1'b1, 4'h4);
        expect_nibble(17, 1'b1, 4'h2);

        if (en_min_pulse_ns < 230.0) begin
            $display("FAIL EN pulse too short: min=%0.1f ns, expected >=230 ns", en_min_pulse_ns);
            $finish;
        end

        $display("PASS tb_lcd_hd44780: min EN pulse=%0.1f ns", en_min_pulse_ns);
        $finish;
    end

endmodule
