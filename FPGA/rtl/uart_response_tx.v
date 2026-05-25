`timescale 1ns/1ps

//============================================================================
// Module : uart_response_tx
// Desc   : Builds and sends response frames: 0xAA CMD LEN PAYLOAD CHECKSUM.
//          Also generates NACK frames on parser checksum/frame errors.
//============================================================================

module uart_response_tx #(
    parameter MAX_PAYLOAD = 16
) (
    input  wire       clk,
    input  wire       rst_n,

    // response request from command_controller
    input  wire                        resp_req,
    input  wire [7:0]                  resp_cmd,
    input  wire [MAX_PAYLOAD*8-1:0]    resp_payload,
    input  wire [7:0]                  resp_len,

    // parser error inputs (one-cycle pulses)
    input  wire       parser_checksum_error,
    input  wire       parser_frame_error,

    // UART TX interface
    input  wire       tx_busy,
    output reg  [7:0] tx_data,
    output reg        tx_start,

    // status
    output wire       busy
);

    localparam [7:0] START_BYTE       = 8'hAA;
    localparam [7:0] RSP_NACK         = 8'h81;
    localparam [7:0] ERR_CHECKSUM     = 8'h03;
    localparam [7:0] ERR_FRAME        = 8'h04;

    localparam [1:0] S_IDLE = 2'd0,
                     S_SEND = 2'd1,
                     S_WAIT = 2'd2;

    localparam [2:0] F_START   = 3'd0,
                     F_CMD     = 3'd1,
                     F_LEN     = 3'd2,
                     F_PAYLOAD = 3'd3,
                     F_CHKSUM  = 3'd4;

    reg [1:0] state;
    reg [2:0] field;
    reg       wait_seen_busy;

    reg [7:0] buf_cmd;
    reg [MAX_PAYLOAD*8-1:0] buf_payload;
    reg [7:0] buf_len;
    reg [7:0] byte_idx;
    reg [7:0] chksum;

    reg       pending;
    reg [7:0] pend_cmd;
    reg [MAX_PAYLOAD*8-1:0] pend_payload;
    reg [7:0] pend_len;

    assign busy = (state != S_IDLE) || pending;

    always @(posedge clk) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            field          <= F_START;
            wait_seen_busy <= 1'b0;
            tx_data        <= 8'd0;
            tx_start       <= 1'b0;
            buf_cmd        <= 8'd0;
            buf_payload    <= {MAX_PAYLOAD*8{1'b0}};
            buf_len        <= 8'd0;
            byte_idx       <= 8'd0;
            chksum         <= 8'd0;
            pending        <= 1'b0;
            pend_cmd       <= 8'd0;
            pend_payload   <= {MAX_PAYLOAD*8{1'b0}};
            pend_len       <= 8'd0;
        end else begin
            tx_start <= 1'b0;

            // Queue one response if a request arrives while this module is busy.
            if (state != S_IDLE) begin
                if (parser_checksum_error || parser_frame_error) begin
                    pending      <= 1'b1;
                    pend_cmd     <= RSP_NACK;
                    pend_payload <= {{(MAX_PAYLOAD*8-8){1'b0}}, parser_checksum_error ? ERR_CHECKSUM : ERR_FRAME};
                    pend_len     <= 8'd1;
                end else if (resp_req) begin
                    pending      <= 1'b1;
                    pend_cmd     <= resp_cmd;
                    pend_payload <= resp_payload;
                    pend_len     <= (resp_len > MAX_PAYLOAD) ? MAX_PAYLOAD[7:0] : resp_len;
                end
            end

            case (state)
                S_IDLE: begin
                    wait_seen_busy <= 1'b0;
                    if (parser_checksum_error || parser_frame_error) begin
                        buf_cmd     <= RSP_NACK;
                        buf_payload <= {{(MAX_PAYLOAD*8-8){1'b0}}, parser_checksum_error ? ERR_CHECKSUM : ERR_FRAME};
                        buf_len     <= 8'd1;
                        field       <= F_START;
                        state       <= S_SEND;
                    end else if (resp_req) begin
                        buf_cmd     <= resp_cmd;
                        buf_payload <= resp_payload;
                        buf_len     <= (resp_len > MAX_PAYLOAD) ? MAX_PAYLOAD[7:0] : resp_len;
                        field       <= F_START;
                        state       <= S_SEND;
                    end else if (pending) begin
                        buf_cmd     <= pend_cmd;
                        buf_payload <= pend_payload;
                        buf_len     <= pend_len;
                        pending     <= 1'b0;
                        field       <= F_START;
                        state       <= S_SEND;
                    end
                end

                S_SEND: begin
                    if (!tx_busy) begin
                        tx_start       <= 1'b1;
                        wait_seen_busy <= 1'b0;
                        case (field)
                            F_START: tx_data <= START_BYTE;
                            F_CMD: begin
                                tx_data <= buf_cmd;
                                chksum  <= buf_cmd;
                            end
                            F_LEN: begin
                                tx_data <= buf_len;
                                chksum  <= chksum ^ buf_len;
                            end
                            F_PAYLOAD: begin
                                tx_data <= buf_payload[byte_idx*8 +: 8];
                                chksum  <= chksum ^ buf_payload[byte_idx*8 +: 8];
                            end
                            F_CHKSUM: tx_data <= chksum;
                            default:  tx_data <= 8'd0;
                        endcase
                        state <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (tx_busy) begin
                        wait_seen_busy <= 1'b1;
                    end else if (wait_seen_busy) begin
                        case (field)
                            F_START: begin
                                field <= F_CMD;
                                state <= S_SEND;
                            end
                            F_CMD: begin
                                field <= F_LEN;
                                state <= S_SEND;
                            end
                            F_LEN: begin
                                byte_idx <= 8'd0;
                                field <= (buf_len == 8'd0) ? F_CHKSUM : F_PAYLOAD;
                                state <= S_SEND;
                            end
                            F_PAYLOAD: begin
                                byte_idx <= byte_idx + 8'd1;
                                if (byte_idx + 8'd1 == buf_len) begin
                                    field <= F_CHKSUM;
                                end
                                state <= S_SEND;
                            end
                            F_CHKSUM: begin
                                state <= S_IDLE;
                            end
                            default: state <= S_IDLE;
                        endcase
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
