`timescale 1ns/1ps

//============================================================================
// Module : uart_rx
// Desc   : Vendor-neutral UART receiver with oversampling, FIFO, and errors.
//============================================================================

module uart_rx #(
    parameter CLK_FREQ   = 50_000_000,
    parameter BAUD       = 115_200,
    parameter OVERSAMPLE = 16,
    parameter FIFO_DEPTH = 16,
    parameter PARITY_EN  = 0,
    parameter PARITY_ODD = 0
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,

    input  wire       rd_en,
    output reg  [7:0] rd_data,
    output reg        rd_valid,
    output wire       fifo_empty,
    output wire       fifo_full,
    output wire [$clog2(FIFO_DEPTH+1)-1:0] fifo_level,

    output reg        framing_error,
    output reg        parity_error,
    output reg        overflow_error,

    output reg  [7:0] data,
    output reg        data_valid
);

    // ---- portable width calculations (no parameter bit-slicing) ----
    localparam integer CLKS_PER_SAMPLE = CLK_FREQ / (BAUD * OVERSAMPLE);
    localparam integer SAMPLE_CNT_MAX  = (CLKS_PER_SAMPLE < 1) ? 1 : CLKS_PER_SAMPLE;
    localparam integer SAMPLE_CNT_W    = (SAMPLE_CNT_MAX <= 1) ? 1 : $clog2(SAMPLE_CNT_MAX);
    localparam integer OS_CNT_W        = (OVERSAMPLE <= 2) ? 2 : $clog2(OVERSAMPLE);
    localparam integer FIFO_ADDR_W     = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);
    localparam integer FIFO_LEVEL_W    = $clog2(FIFO_DEPTH + 1);
    localparam integer CENTER          = OVERSAMPLE / 2;

    // ---- pre-computed limit values (pure integer, no bit-slicing) ----
    localparam [SAMPLE_CNT_W-1:0] SAMPLE_LIMIT  = (SAMPLE_CNT_MAX - 1);
    localparam [OS_CNT_W-1:0]     OS_LIMIT       = (OVERSAMPLE - 1);
    localparam [FIFO_ADDR_W-1:0]  FIFO_LAST_ADDR = (FIFO_DEPTH - 1);
    localparam [FIFO_LEVEL_W-1:0] FIFO_MAX_LEVEL = FIFO_DEPTH;

    initial begin
        if (OVERSAMPLE != 8 && OVERSAMPLE != 16) begin
            $error("uart_rx: OVERSAMPLE must be 8 or 16");
        end
        if (FIFO_DEPTH < 2) begin
            $error("uart_rx: FIFO_DEPTH must be at least 2");
        end
        if (CLKS_PER_SAMPLE < 1) begin
            $error("uart_rx: CLK_FREQ must be at least BAUD*OVERSAMPLE");
        end
    end

    localparam [2:0] S_IDLE   = 3'd0,
                     S_START  = 3'd1,
                     S_DATA   = 3'd2,
                     S_PARITY = 3'd3,
                     S_STOP   = 3'd4,
                     S_DONE   = 3'd5;

    reg [2:0] state;
    reg [SAMPLE_CNT_W-1:0] sample_cnt;
    reg [OS_CNT_W-1:0] os_cnt;
    reg [2:0] bit_idx;
    reg [7:0] shift_reg;
    reg parity_sample;
    reg sample_a;
    reg sample_b;
    reg sample_c;
    reg stop_ok;
    reg par_ok;

    reg rx_meta;
    reg rx_sync;
    reg rx_prev;

    reg [7:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [FIFO_ADDR_W-1:0] wr_ptr;
    reg [FIFO_ADDR_W-1:0] rd_ptr;
    reg [FIFO_LEVEL_W-1:0] fifo_count;

    wire sample_tick = (sample_cnt == SAMPLE_LIMIT);
    wire majority    = (sample_a & sample_b) | (sample_a & sample_c) | (sample_b & sample_c);
    wire start_edge  = rx_prev & ~rx_sync;
    wire pop_byte;
    wire expected_parity;

    assign fifo_empty = (fifo_count == {FIFO_LEVEL_W{1'b0}});
    assign fifo_full  = (fifo_count == FIFO_MAX_LEVEL);
    assign fifo_level = fifo_count;
    assign pop_byte   = rd_en && !fifo_empty;
    assign expected_parity = PARITY_ODD ? ~(^shift_reg) : (^shift_reg);

    // ---- metastability synchroniser ----
    always @(posedge clk) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_prev <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
            rx_prev <= rx_sync;
        end
    end

    // ---- FIFO read / write + push from registered S_DONE ----
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_data        <= 8'd0;
            rd_valid       <= 1'b0;
            data           <= 8'd0;
            data_valid     <= 1'b0;
            overflow_error <= 1'b0;
            wr_ptr         <= {FIFO_ADDR_W{1'b0}};
            rd_ptr         <= {FIFO_ADDR_W{1'b0}};
            fifo_count     <= {FIFO_LEVEL_W{1'b0}};
        end else begin
            rd_valid       <= 1'b0;
            data_valid     <= 1'b0;
            overflow_error <= 1'b0;

            if (pop_byte) begin
                rd_data  <= fifo_mem[rd_ptr];
                rd_valid <= 1'b1;
                rd_ptr   <= (rd_ptr == FIFO_LAST_ADDR) ? {FIFO_ADDR_W{1'b0}} : rd_ptr + 1'b1;
            end

            // push happens in S_DONE (one cycle after stop bit majority is registered)
            if (state == S_DONE && stop_ok && (!PARITY_EN || par_ok)) begin
                if (!fifo_full) begin
                    fifo_mem[wr_ptr] <= shift_reg;
                    wr_ptr     <= (wr_ptr == FIFO_LAST_ADDR) ? {FIFO_ADDR_W{1'b0}} : wr_ptr + 1'b1;
                    data       <= shift_reg;
                    data_valid <= 1'b1;
                end else begin
                    overflow_error <= 1'b1;
                end
            end

            // fifo_count bookkeeping
            case ({(state == S_DONE && stop_ok && (!PARITY_EN || par_ok) && !fifo_full), pop_byte})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: fifo_count <= fifo_count - 1'b1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

    // ---- main receive FSM ----
    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            sample_cnt    <= {SAMPLE_CNT_W{1'b0}};
            os_cnt        <= {OS_CNT_W{1'b0}};
            bit_idx       <= 3'd0;
            shift_reg     <= 8'd0;
            parity_sample <= 1'b0;
            sample_a      <= 1'b1;
            sample_b      <= 1'b1;
            sample_c      <= 1'b1;
            stop_ok       <= 1'b0;
            par_ok        <= 1'b0;
            framing_error <= 1'b0;
            parity_error  <= 1'b0;
        end else begin
            framing_error <= 1'b0;
            parity_error  <= 1'b0;

            // sample counter
            if (state == S_IDLE || state == S_DONE) begin
                sample_cnt <= {SAMPLE_CNT_W{1'b0}};
            end else if (sample_tick) begin
                sample_cnt <= {SAMPLE_CNT_W{1'b0}};
            end else begin
                sample_cnt <= sample_cnt + 1'b1;
            end

            case (state)
                S_IDLE: begin
                    os_cnt  <= {OS_CNT_W{1'b0}};
                    bit_idx <= 3'd0;
                    stop_ok <= 1'b0;
                    par_ok  <= 1'b0;
                    if (start_edge) begin
                        state    <= S_START;
                        sample_a <= 1'b1;
                        sample_b <= 1'b1;
                        sample_c <= 1'b1;
                    end
                end

                S_START: begin
                    if (sample_tick) begin
                        if (os_cnt == (CENTER-1)) sample_a <= rx_sync;
                        if (os_cnt == CENTER)     sample_b <= rx_sync;
                        if (os_cnt == (CENTER+1)) sample_c <= rx_sync;

                        if (os_cnt == OS_LIMIT) begin
                            os_cnt <= {OS_CNT_W{1'b0}};
                            if (!majority) begin
                                state <= S_DATA;
                                sample_a <= 1'b1;
                                sample_b <= 1'b1;
                                sample_c <= 1'b1;
                            end else begin
                                state <= S_IDLE;
                            end
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end

                S_DATA: begin
                    if (sample_tick) begin
                        if (os_cnt == (CENTER-1)) sample_a <= rx_sync;
                        if (os_cnt == CENTER)     sample_b <= rx_sync;
                        if (os_cnt == (CENTER+1)) sample_c <= rx_sync;

                        if (os_cnt == OS_LIMIT) begin
                            os_cnt <= {OS_CNT_W{1'b0}};
                            shift_reg[bit_idx] <= majority;
                            sample_a <= 1'b1;
                            sample_b <= 1'b1;
                            sample_c <= 1'b1;
                            if (bit_idx == 3'd7) begin
                                bit_idx <= 3'd0;
                                state <= PARITY_EN ? S_PARITY : S_STOP;
                            end else begin
                                bit_idx <= bit_idx + 1'b1;
                            end
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end

                S_PARITY: begin
                    if (sample_tick) begin
                        if (os_cnt == (CENTER-1)) sample_a <= rx_sync;
                        if (os_cnt == CENTER)     sample_b <= rx_sync;
                        if (os_cnt == (CENTER+1)) sample_c <= rx_sync;

                        if (os_cnt == OS_LIMIT) begin
                            os_cnt <= {OS_CNT_W{1'b0}};
                            parity_sample <= majority;
                            sample_a <= 1'b1;
                            sample_b <= 1'b1;
                            sample_c <= 1'b1;
                            state <= S_STOP;
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end

                S_STOP: begin
                    if (sample_tick) begin
                        if (os_cnt == (CENTER-1)) sample_a <= rx_sync;
                        if (os_cnt == CENTER)     sample_b <= rx_sync;
                        if (os_cnt == (CENTER+1)) sample_c <= rx_sync;

                        if (os_cnt == OS_LIMIT) begin
                            os_cnt <= {OS_CNT_W{1'b0}};
                            // register stop-bit and parity results for next-cycle push
                            stop_ok <= majority;
                            par_ok  <= (parity_sample == expected_parity);
                            if (!majority) begin
                                framing_error <= 1'b1;
                            end else if (PARITY_EN && (parity_sample != expected_parity)) begin
                                parity_error <= 1'b1;
                            end
                            sample_a <= 1'b1;
                            sample_b <= 1'b1;
                            sample_c <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end

                // S_DONE: single-cycle state — FIFO push happens in the FIFO block
                S_DONE: begin
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
