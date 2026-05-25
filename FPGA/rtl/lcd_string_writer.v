`timescale 1ns/1ps

//============================================================================
// Module : lcd_string_writer
// Desc   : Writes two 16-character lines to an HD44780 LCD driver.
//============================================================================

module lcd_string_writer #(
    parameter CLK_FREQ = 50_000_000
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        update,
    input  wire [127:0] line0,
    input  wire [127:0] line1,
    output wire        busy,

    output wire        lcd_rs,
    output wire        lcd_en,
    output wire [3:0]  lcd_d
);

    localparam [3:0]
        S_IDLE       = 4'd0,
        S_LINE0_ADDR = 4'd1,
        S_LINE0_WAIT = 4'd2,
        S_LINE0_CHAR = 4'd3,
        S_LINE0_NEXT = 4'd4,
        S_LINE1_ADDR = 4'd5,
        S_LINE1_WAIT = 4'd6,
        S_LINE1_CHAR = 4'd7,
        S_LINE1_NEXT = 4'd8;

    reg [3:0] state;
    reg [4:0] char_idx;
    reg [127:0] line0_latched;
    reg [127:0] line1_latched;
    reg lcd_wr_en;
    reg lcd_wr_rs;
    reg [7:0] lcd_wr_data;

    wire lcd_busy;

    assign busy = (state != S_IDLE) || lcd_busy;

    lcd_hd44780 #(
        .CLK_FREQ (CLK_FREQ)
    ) u_lcd_hd44780 (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (lcd_wr_en),
        .wr_rs   (lcd_wr_rs),
        .wr_data (lcd_wr_data),
        .busy    (lcd_busy),
        .lcd_rs  (lcd_rs),
        .lcd_en  (lcd_en),
        .lcd_d   (lcd_d)
    );

    function [7:0] get_char;
        input [127:0] line;
        input [4:0] index;
        begin
            get_char = line[127 - (index * 8) -: 8];
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            char_idx      <= 5'd0;
            line0_latched <= 128'd0;
            line1_latched <= 128'd0;
            lcd_wr_en     <= 1'b0;
            lcd_wr_rs     <= 1'b0;
            lcd_wr_data   <= 8'd0;
        end else begin
            lcd_wr_en <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (update && !lcd_busy) begin
                        line0_latched <= line0;
                        line1_latched <= line1;
                        state         <= S_LINE0_ADDR;
                    end
                end

                S_LINE0_ADDR: begin
                    if (!lcd_busy) begin
                        lcd_wr_en   <= 1'b1;
                        lcd_wr_rs   <= 1'b0;
                        lcd_wr_data <= 8'h80;
                        char_idx    <= 5'd0;
                        state       <= S_LINE0_WAIT;
                    end
                end

                S_LINE0_WAIT: begin
                    if (!lcd_busy)
                        state <= S_LINE0_CHAR;
                end

                S_LINE0_CHAR: begin
                    if (!lcd_busy) begin
                        lcd_wr_en   <= 1'b1;
                        lcd_wr_rs   <= 1'b1;
                        lcd_wr_data <= get_char(line0_latched, char_idx);
                        state       <= S_LINE0_NEXT;
                    end
                end

                S_LINE0_NEXT: begin
                    if (!lcd_busy) begin
                        if (char_idx == 5'd15) begin
                            state <= S_LINE1_ADDR;
                        end else begin
                            char_idx <= char_idx + 1;
                            state    <= S_LINE0_CHAR;
                        end
                    end
                end

                S_LINE1_ADDR: begin
                    if (!lcd_busy) begin
                        lcd_wr_en   <= 1'b1;
                        lcd_wr_rs   <= 1'b0;
                        lcd_wr_data <= 8'hC0;
                        char_idx    <= 5'd0;
                        state       <= S_LINE1_WAIT;
                    end
                end

                S_LINE1_WAIT: begin
                    if (!lcd_busy)
                        state <= S_LINE1_CHAR;
                end

                S_LINE1_CHAR: begin
                    if (!lcd_busy) begin
                        lcd_wr_en   <= 1'b1;
                        lcd_wr_rs   <= 1'b1;
                        lcd_wr_data <= get_char(line1_latched, char_idx);
                        state       <= S_LINE1_NEXT;
                    end
                end

                S_LINE1_NEXT: begin
                    if (!lcd_busy) begin
                        if (char_idx == 5'd15) begin
                            state <= S_IDLE;
                        end else begin
                            char_idx <= char_idx + 1;
                            state    <= S_LINE1_CHAR;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
