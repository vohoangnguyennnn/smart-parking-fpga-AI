`timescale 1ns/1ps

//============================================================================
// Module : lcd_hd44780
// Desc   : HD44780 LCD 4-bit parallel byte writer with power-on init.
//============================================================================

module lcd_hd44780 #(
    parameter CLK_FREQ = 50_000_000
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       wr_en,
    input  wire       wr_rs,
    input  wire [7:0] wr_data,
    output wire       busy,

    output reg        lcd_rs,
    output reg        lcd_en,
    output reg  [3:0] lcd_d
);

    localparam integer DELAY_20MS_CLKS = CLK_FREQ / 50;
    localparam integer DELAY_5MS_CLKS  = CLK_FREQ / 200;
    localparam integer DELAY_40US_CLKS = CLK_FREQ / 25000;
    localparam integer DELAY_2MS_CLKS  = CLK_FREQ / 500;
    localparam integer EN_HOLD_CLKS    = CLK_FREQ / 1_000_000;  // ~1 us
    localparam integer DELAY_W         = $clog2(DELAY_20MS_CLKS + 1);
    localparam integer EN_W            = $clog2(EN_HOLD_CLKS + 1);

    localparam [3:0]
        S_POWER_WAIT   = 4'd0,
        S_INIT_8BIT_1  = 4'd1,
        S_INIT_8BIT_2  = 4'd2,
        S_INIT_8BIT_3  = 4'd3,
        S_INIT_4BIT    = 4'd4,
        S_INIT_FUNC    = 4'd5,
        S_INIT_DISPLAY = 4'd6,
        S_INIT_CLEAR   = 4'd7,
        S_INIT_ENTRY   = 4'd8,
        S_IDLE         = 4'd9,
        S_SEND_HIGH    = 4'd10,
        S_SEND_LOW     = 4'd11,
        S_WAIT         = 4'd12,
        S_EN_HOLD      = 4'd13;

    reg [3:0] state;
    reg [3:0] return_state;
    reg [3:0] en_done_state;
    reg [DELAY_W-1:0] delay_cnt;
    reg [EN_W-1:0] en_hold_cnt;
    reg [7:0] send_data;
    reg       send_rs;
    reg       single_nibble;

    assign busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= S_POWER_WAIT;
            return_state  <= S_INIT_8BIT_1;
            en_done_state <= S_WAIT;
            delay_cnt     <= DELAY_20MS_CLKS[DELAY_W-1:0];
            en_hold_cnt   <= {EN_W{1'b0}};
            send_data     <= 8'd0;
            send_rs       <= 1'b0;
            single_nibble <= 1'b0;
            lcd_rs        <= 1'b0;
            lcd_en        <= 1'b0;
            lcd_d         <= 4'd0;
        end else begin
            lcd_en <= 1'b0;

            case (state)
                S_POWER_WAIT: begin
                    if (delay_cnt == 0)
                        state <= S_INIT_8BIT_1;
                    else
                        delay_cnt <= delay_cnt - 1;
                end

                S_INIT_8BIT_1: begin
                    send_data     <= 8'h30;
                    send_rs       <= 1'b0;
                    single_nibble <= 1'b1;
                    return_state  <= S_INIT_8BIT_2;
                    state         <= S_SEND_HIGH;
                end

                S_INIT_8BIT_2: begin
                    send_data     <= 8'h30;
                    send_rs       <= 1'b0;
                    single_nibble <= 1'b1;
                    return_state  <= S_INIT_8BIT_3;
                    state         <= S_SEND_HIGH;
                end

                S_INIT_8BIT_3: begin
                    send_data     <= 8'h30;
                    send_rs       <= 1'b0;
                    single_nibble <= 1'b1;
                    return_state  <= S_INIT_4BIT;
                    state         <= S_SEND_HIGH;
                end

                S_INIT_4BIT: begin
                    send_data     <= 8'h20;
                    send_rs       <= 1'b0;
                    single_nibble <= 1'b1;
                    return_state  <= S_INIT_FUNC;
                    state         <= S_SEND_HIGH;
                end

                S_INIT_FUNC: begin
                    send_data     <= 8'h28;
                    send_rs       <= 1'b0;
                    single_nibble <= 1'b0;
                    return_state  <= S_INIT_DISPLAY;
                    state         <= S_SEND_HIGH;
                end

                S_INIT_DISPLAY: begin
                    send_data     <= 8'h0C;
                    send_rs       <= 1'b0;
                    single_nibble <= 1'b0;
                    return_state  <= S_INIT_CLEAR;
                    state         <= S_SEND_HIGH;
                end

                S_INIT_CLEAR: begin
                    send_data     <= 8'h01;
                    send_rs       <= 1'b0;
                    single_nibble <= 1'b0;
                    return_state  <= S_INIT_ENTRY;
                    state         <= S_SEND_HIGH;
                end

                S_INIT_ENTRY: begin
                    send_data     <= 8'h06;
                    send_rs       <= 1'b0;
                    single_nibble <= 1'b0;
                    return_state  <= S_IDLE;
                    state         <= S_SEND_HIGH;
                end

                S_IDLE: begin
                    if (wr_en) begin
                        send_data     <= wr_data;
                        send_rs       <= wr_rs;
                        single_nibble <= 1'b0;
                        return_state  <= S_IDLE;
                        state         <= S_SEND_HIGH;
                    end
                end

                S_SEND_HIGH: begin
                    lcd_rs <= send_rs;
                    lcd_d  <= send_data[7:4];
                    lcd_en <= 1'b1;
                    en_hold_cnt <= EN_HOLD_CLKS[EN_W-1:0];
                    if (single_nibble) begin
                        delay_cnt     <= DELAY_5MS_CLKS[DELAY_W-1:0];
                        en_done_state <= S_WAIT;
                    end else begin
                        en_done_state <= S_SEND_LOW;
                    end
                    state <= S_EN_HOLD;
                end

                S_SEND_LOW: begin
                    lcd_rs <= send_rs;
                    lcd_d  <= send_data[3:0];
                    lcd_en <= 1'b1;
                    en_hold_cnt   <= EN_HOLD_CLKS[EN_W-1:0];
                    en_done_state <= S_WAIT;
                    if (!send_rs && (send_data == 8'h01 || send_data == 8'h02))
                        delay_cnt <= DELAY_2MS_CLKS[DELAY_W-1:0];
                    else
                        delay_cnt <= DELAY_40US_CLKS[DELAY_W-1:0];
                    state <= S_EN_HOLD;
                end

                S_EN_HOLD: begin
                    lcd_en <= 1'b1;
                    if (en_hold_cnt == 0) begin
                        lcd_en <= 1'b0;
                        state  <= en_done_state;
                    end else begin
                        en_hold_cnt <= en_hold_cnt - 1;
                    end
                end

                S_WAIT: begin
                    if (delay_cnt == 0)
                        state <= return_state;
                    else
                        delay_cnt <= delay_cnt - 1;
                end

                default: begin
                    state <= S_POWER_WAIT;
                end
            endcase
        end
    end

endmodule
