`timescale 1ns/1ps

//============================================================================
// Module : uart_tx
// Desc   : Vendor-neutral UART transmitter — 8N1, parameterised baud.
//============================================================================

module uart_tx #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD     = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        tx,
    output wire       tx_busy,
    output reg        tx_done
);

    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD;
    localparam integer CNT_W        = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);
    localparam [CNT_W-1:0] BIT_LIMIT = (CLKS_PER_BIT - 1);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0] state;
    reg [CNT_W-1:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] shift_reg;

    assign tx_busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            tx        <= 1'b1;
            tx_done   <= 1'b0;
            clk_cnt   <= {CNT_W{1'b0}};
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
        end else begin
            tx_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        state     <= S_START;
                        clk_cnt   <= {CNT_W{1'b0}};
                    end
                end

                S_START: begin
                    tx <= 1'b0;
                    if (clk_cnt == BIT_LIMIT) begin
                        clk_cnt <= {CNT_W{1'b0}};
                        bit_idx <= 3'd0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                S_DATA: begin
                    tx <= shift_reg[bit_idx];
                    if (clk_cnt == BIT_LIMIT) begin
                        clk_cnt <= {CNT_W{1'b0}};
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                S_STOP: begin
                    tx <= 1'b1;
                    if (clk_cnt == BIT_LIMIT) begin
                        clk_cnt <= {CNT_W{1'b0}};
                        tx_done <= 1'b1;
                        state   <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
