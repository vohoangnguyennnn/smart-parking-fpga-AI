`timescale 1ns/1ps

//============================================================================
// Module : lcd_content_mux
// Desc   : Selects idle parking text or temporary ESP32-provided LCD message.
//============================================================================

module lcd_content_mux #(
    parameter CLK_FREQ       = 50_000_000,
    parameter NUM_SLOTS      = 4,
    parameter MSG_HOLD_CLKS  = CLK_FREQ * 3
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire [NUM_SLOTS-1:0]     slot_occupied,
    input  wire                     writer_busy,

    input  wire                     msg_valid,
    input  wire [127:0]             msg_line0,
    input  wire [127:0]             msg_line1,

    output reg                      lcd_update,
    output reg  [127:0]             lcd_line0,
    output reg  [127:0]             lcd_line1
);

    localparam integer HOLD_W = (MSG_HOLD_CLKS <= 1) ? 1 : $clog2(MSG_HOLD_CLKS + 1);

    reg [NUM_SLOTS-1:0] slot_prev;
    reg [HOLD_W-1:0] hold_cnt;
    reg message_active;
    reg pending_update;
    reg [127:0] active_line0;
    reg [127:0] active_line1;

    function [7:0] count_occupied;
        input [NUM_SLOTS-1:0] slots;
        integer i;
        begin
            count_occupied = 8'd0;
            for (i = 0; i < NUM_SLOTS; i = i + 1) begin
                if (slots[i])
                    count_occupied = count_occupied + 1'b1;
            end
        end
    endfunction

    // "WELCOME" (7) + 9 spaces = 16 bytes
    localparam [127:0] IDLE_LINE0 = {"WELCOME", {9{" "}}};

    function [127:0] make_idle_line1;
        input [NUM_SLOTS-1:0] slots;
        reg [7:0] occ;
        reg [7:0] fre;
        begin
            occ = count_occupied(slots);
            fre = NUM_SLOTS[7:0] - occ;
            // "Occ:X Free:Y    " = 4+1+6+1+4 pad = 16 bytes
            make_idle_line1 = {"Occ:", (8'h30 + occ), " Free:", (8'h30 + fre), {4{" "}}};
        end
    endfunction

    always @(*) begin
        if (message_active) begin
            active_line0 = msg_line0;
            active_line1 = msg_line1;
        end else begin
            active_line0 = IDLE_LINE0;
            active_line1 = make_idle_line1(slot_occupied);
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            slot_prev      <= {NUM_SLOTS{1'b0}};
            hold_cnt       <= {HOLD_W{1'b0}};
            message_active <= 1'b0;
            pending_update <= 1'b1;
            lcd_update     <= 1'b0;
            lcd_line0      <= IDLE_LINE0;
            lcd_line1      <= make_idle_line1({NUM_SLOTS{1'b0}});
        end else begin
            lcd_update <= 1'b0;

            if (msg_valid) begin
                message_active <= 1'b1;
                hold_cnt       <= MSG_HOLD_CLKS[HOLD_W-1:0];
                pending_update <= 1'b1;
            end else if (message_active) begin
                if (hold_cnt == 0) begin
                    message_active <= 1'b0;
                    pending_update <= 1'b1;
                end else begin
                    hold_cnt <= hold_cnt - 1;
                end
            end else if (slot_occupied != slot_prev) begin
                pending_update <= 1'b1;
            end

            slot_prev <= slot_occupied;

            if (pending_update && !writer_busy) begin
                lcd_line0      <= active_line0;
                lcd_line1      <= active_line1;
                lcd_update     <= 1'b1;
                pending_update <= 1'b0;
            end
        end
    end

endmodule
