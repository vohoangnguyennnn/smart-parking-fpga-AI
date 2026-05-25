`timescale 1ns/1ps

//============================================================================
// Module : servo_pwm_controller
// Desc   : Generates 50 Hz PWM for two servos (entry and exit barriers).
//          Closed = 1.0 ms pulse, Open = 2.0 ms pulse.
//============================================================================

module servo_pwm_controller #(
    parameter CLK_FREQ       = 50_000_000,
    parameter PERIOD_CYCLES  = CLK_FREQ / 50,        // 1_000_000
    parameter CLOSED_CYCLES  = CLK_FREQ / 1_000,     // 50_000   (1.0 ms)
    parameter OPEN_CYCLES    = CLK_FREQ / 500         // 100_000  (2.0 ms)
) (
    input  wire clk,
    input  wire rst_n,

    // one-clock command pulses from parking_command_controller
    input  wire entry_gate_open,
    input  wire entry_gate_close,
    input  wire exit_gate_open,
    input  wire exit_gate_close,

    // continuous PWM outputs
    output reg  entry_servo_pwm,
    output reg  exit_servo_pwm
);

    // Width derived from PERIOD_CYCLES to support any CLK_FREQ
    localparam integer PWM_CNT_W = $clog2(PERIOD_CYCLES);

    // PWM period counter (shared)
    reg [PWM_CNT_W-1:0] pwm_cnt;

    // Target pulse widths
    reg [PWM_CNT_W-1:0] entry_pw;
    reg [PWM_CNT_W-1:0] exit_pw;

    // --- Latch target pulse width on command pulses ---
    always @(posedge clk) begin
        if (!rst_n) begin
            entry_pw <= CLOSED_CYCLES[PWM_CNT_W-1:0];
            exit_pw  <= CLOSED_CYCLES[PWM_CNT_W-1:0];
        end else begin
            // close wins over open when simultaneous
            if (entry_gate_close)
                entry_pw <= CLOSED_CYCLES[PWM_CNT_W-1:0];
            else if (entry_gate_open)
                entry_pw <= OPEN_CYCLES[PWM_CNT_W-1:0];

            if (exit_gate_close)
                exit_pw <= CLOSED_CYCLES[PWM_CNT_W-1:0];
            else if (exit_gate_open)
                exit_pw <= OPEN_CYCLES[PWM_CNT_W-1:0];
        end
    end

    // --- Free-running period counter ---
    always @(posedge clk) begin
        if (!rst_n) begin
            pwm_cnt <= {PWM_CNT_W{1'b0}};
        end else begin
            if (pwm_cnt >= PERIOD_CYCLES[PWM_CNT_W-1:0] - 1)
                pwm_cnt <= {PWM_CNT_W{1'b0}};
            else
                pwm_cnt <= pwm_cnt + 1;
        end
    end

    // --- PWM output generation ---
    always @(posedge clk) begin
        if (!rst_n) begin
            entry_servo_pwm <= 1'b0;
            exit_servo_pwm  <= 1'b0;
        end else begin
            entry_servo_pwm <= (pwm_cnt < entry_pw);
            exit_servo_pwm  <= (pwm_cnt < exit_pw);
        end
    end

endmodule
