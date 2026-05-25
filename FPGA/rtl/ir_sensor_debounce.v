`timescale 1ns/1ps

//============================================================================
// Module : ir_sensor_debounce
// Desc   : Synchronizes and debounces active-low IR parking slot sensors.
//============================================================================

module ir_sensor_debounce #(
    parameter NUM_SLOTS     = 4,
    parameter DEBOUNCE_CLKS = 500_000
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [NUM_SLOTS-1:0]  ir_sensors_raw,
    output reg  [NUM_SLOTS-1:0]  slot_occupied
);

    localparam integer CNT_W = (DEBOUNCE_CLKS <= 1) ? 1 : $clog2(DEBOUNCE_CLKS);
    localparam [CNT_W-1:0] CNT_LIMIT = (DEBOUNCE_CLKS <= 1) ? {CNT_W{1'b0}} : (DEBOUNCE_CLKS - 1);

    reg [NUM_SLOTS-1:0] sync_0;
    reg [NUM_SLOTS-1:0] sync_1;
    reg [NUM_SLOTS-1:0] candidate;
    reg [CNT_W-1:0] cnt [0:NUM_SLOTS-1];

    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            sync_0        <= {NUM_SLOTS{1'b1}};
            sync_1        <= {NUM_SLOTS{1'b1}};
            candidate     <= {NUM_SLOTS{1'b0}};
            slot_occupied <= {NUM_SLOTS{1'b0}};
            for (i = 0; i < NUM_SLOTS; i = i + 1) begin
                cnt[i] <= {CNT_W{1'b0}};
            end
        end else begin
            sync_0 <= ir_sensors_raw;
            sync_1 <= sync_0;

            for (i = 0; i < NUM_SLOTS; i = i + 1) begin
                if (~sync_1[i] == slot_occupied[i]) begin
                    candidate[i] <= ~sync_1[i];
                    cnt[i]       <= {CNT_W{1'b0}};
                end else if (~sync_1[i] != candidate[i]) begin
                    candidate[i] <= ~sync_1[i];
                    cnt[i]       <= {CNT_W{1'b0}};
                end else if (cnt[i] == CNT_LIMIT) begin
                    slot_occupied[i] <= candidate[i];
                    cnt[i]           <= {CNT_W{1'b0}};
                end else begin
                    cnt[i] <= cnt[i] + 1'b1;
                end
            end
        end
    end

endmodule
