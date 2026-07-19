// ============================================================================
// Module      : accel_ramp
// Description : Rate-limited ramp generator. current_limit_o ramps toward
//               target_limit_i at rate controlled by ramp_rate_i (measured
//               in clock cycles per +/-1 step).
// Author      : MHR
// Project     : FPGA Balance Bot — Level 2 Motion Coprocessor
// ============================================================================

module accel_ramp #(
    parameter LIMIT_WIDTH = 20,
    parameter RATE_WIDTH  = 21
) (
    input                          clk_i,
    input                          rst_i,           // active high
    input      [LIMIT_WIDTH-1:0]   target_limit_i,
    input      [RATE_WIDTH-1:0]    ramp_rate_i,     // clocks per step
    output reg [LIMIT_WIDTH-1:0]   current_limit_o
);

    // ------------------------------------------------------------------------
    // Internal state
    // ------------------------------------------------------------------------
    reg [RATE_WIDTH-1:0] ramp_counter_r;

    // ------------------------------------------------------------------------
    // Ramp logic
    // ------------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            current_limit_o <= {LIMIT_WIDTH{1'b0}};
            ramp_counter_r  <= {RATE_WIDTH{1'b0}};
        end
        else if (ramp_counter_r >= ramp_rate_i) begin
            ramp_counter_r <= {RATE_WIDTH{1'b0}};
            if (current_limit_o > target_limit_i)
                current_limit_o <= current_limit_o - 1'b1;
            else if (current_limit_o < target_limit_i)
                current_limit_o <= current_limit_o + 1'b1;
        end
        else begin
            ramp_counter_r <= ramp_counter_r + 1'b1;
        end
    end

endmodule
