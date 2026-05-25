`timescale 1ns/1ps

//============================================================================
// Module : uart_frame_parser
// Desc   : Parses frames: 0xAA CMD LEN PAYLOAD[LEN] CHECKSUM
//          Checksum = XOR of CMD, LEN, and all payload bytes.
//============================================================================

module uart_frame_parser #(
    parameter MAX_PAYLOAD   = 16,
    parameter TIMEOUT_CLKS  = 5_000_000   // ~100 ms at 50 MHz
) (
    input  wire       clk,
    input  wire       rst_n,

    // RX FIFO interface
    input  wire [7:0] rx_data,
    input  wire       rx_valid,      // data on rx_data is valid this cycle
    output reg        rx_rd_en,      // request next byte from FIFO

    // parsed command outputs (one-cycle pulses)
    output reg                        command_valid,
    output reg  [7:0]                 command_id,
    output reg  [MAX_PAYLOAD*8-1:0]   payload,
    output reg  [7:0]                 payload_len,

    // error pulses (one cycle)
    output reg        checksum_error,
    output reg        frame_error
);

    localparam [2:0] S_IDLE     = 3'd0,
                     S_CMD      = 3'd1,
                     S_LEN      = 3'd2,
                     S_PAYLOAD  = 3'd3,
                     S_CHECKSUM = 3'd4;

    localparam integer TIMEOUT_W = $clog2(TIMEOUT_CLKS + 1);
    localparam [TIMEOUT_W-1:0] TIMEOUT_LIMIT = TIMEOUT_CLKS;

    reg [2:0] state;
    reg [7:0] cmd_reg;
    reg [7:0] len_reg;
    reg [7:0] byte_cnt;
    reg [7:0] running_xor;
    reg [TIMEOUT_W-1:0] timeout_cnt;

    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            rx_rd_en       <= 1'b0;
            command_valid  <= 1'b0;
            command_id     <= 8'd0;
            payload        <= {MAX_PAYLOAD*8{1'b0}};
            payload_len    <= 8'd0;
            checksum_error <= 1'b0;
            frame_error    <= 1'b0;
            cmd_reg        <= 8'd0;
            len_reg        <= 8'd0;
            byte_cnt       <= 8'd0;
            running_xor    <= 8'd0;
            timeout_cnt    <= {TIMEOUT_W{1'b0}};
        end else begin
            // default: clear one-cycle pulses
            command_valid  <= 1'b0;
            checksum_error <= 1'b0;
            frame_error    <= 1'b0;
            rx_rd_en       <= 1'b0;

            if (state != S_IDLE && timeout_cnt == TIMEOUT_LIMIT) begin
                frame_error <= 1'b1;
                state       <= S_IDLE;
                timeout_cnt <= {TIMEOUT_W{1'b0}};
            end else begin
                if (state != S_IDLE) begin
                    timeout_cnt <= timeout_cnt + 1'b1;
                end

                case (state)
                    S_IDLE: begin
                        timeout_cnt <= {TIMEOUT_W{1'b0}};
                        // continuously request bytes while idle to find 0xAA
                        rx_rd_en <= 1'b1;
                        if (rx_valid && rx_data == 8'hAA) begin
                            state       <= S_CMD;
                            running_xor <= 8'd0;
                            payload     <= {MAX_PAYLOAD*8{1'b0}};
                            rx_rd_en    <= 1'b1;
                        end
                    end

                    S_CMD: begin
                        rx_rd_en <= 1'b1;
                        if (rx_valid) begin
                            cmd_reg     <= rx_data;
                            running_xor <= rx_data;
                            state       <= S_LEN;
                            timeout_cnt <= {TIMEOUT_W{1'b0}};
                        end
                    end

                    S_LEN: begin
                        rx_rd_en <= 1'b1;
                        if (rx_valid) begin
                            len_reg     <= rx_data;
                            running_xor <= running_xor ^ rx_data;
                            byte_cnt    <= 8'd0;
                            timeout_cnt <= {TIMEOUT_W{1'b0}};
                            if (rx_data > MAX_PAYLOAD) begin
                                frame_error <= 1'b1;
                                state       <= S_IDLE;
                            end else if (rx_data == 8'd0) begin
                                state <= S_CHECKSUM;
                            end else begin
                                state <= S_PAYLOAD;
                            end
                        end
                    end

                    S_PAYLOAD: begin
                        rx_rd_en <= 1'b1;
                        if (rx_valid) begin
                            // Store byte into payload vector; byte 0 is payload[7:0].
                            for (i = 0; i < MAX_PAYLOAD; i = i + 1) begin
                                if (byte_cnt == i[7:0]) begin
                                    payload[i*8 +: 8] <= rx_data;
                                end
                            end
                            running_xor <= running_xor ^ rx_data;
                            byte_cnt    <= byte_cnt + 8'd1;
                            timeout_cnt <= {TIMEOUT_W{1'b0}};
                            if (byte_cnt + 8'd1 == len_reg) begin
                                state <= S_CHECKSUM;
                            end
                        end
                    end

                    S_CHECKSUM: begin
                        rx_rd_en <= 1'b1;
                        if (rx_valid) begin
                            if (rx_data == running_xor) begin
                                command_valid <= 1'b1;
                                command_id    <= cmd_reg;
                                payload_len   <= len_reg;
                            end else begin
                                checksum_error <= 1'b1;
                            end
                            state       <= S_IDLE;
                            timeout_cnt <= {TIMEOUT_W{1'b0}};
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
