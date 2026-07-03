module stall_detector(
    input clk,
    input reset,
    input step_pulse,               
    input [15:0] encoder_count,     
    input [15:0] stall_threshold,   
    output reg stall_flag
);

    reg [15:0] expected_count = 16'd0;
    reg step_prev = 1'b0;

    wire step_rising;
    wire [15:0] diff;
    wire stalled;
    assign step_rising = (~step_prev & step_pulse);

    assign diff = (expected_count > encoder_count) ?
                  (expected_count - encoder_count) :
                  (encoder_count - expected_count);
    assign stalled = (diff > stall_threshold);

    always @(posedge clk) begin
        if (reset) begin
            expected_count <= 16'd0;
            stall_flag <= 1'b0;
            step_prev <= 1'b0;
        end else begin
            step_prev <= step_pulse;
            if (step_rising)
                expected_count <= expected_count + 1;
            stall_flag <= stalled;
        end
    end

endmodule
