    (* top *) module stepper_driver(
        (* clkbuf_inhibit *) input clk,
        input reset,
        input [19:0] step_limit,
        input direction,
        output step_out,
        output step_oe,
        output dir_out,
        output dir_oe,
        output o_osc_ctrl_en
    );

    reg [19:0] counter = 20'd0;
    always @(posedge clk) 
    begin
    if (reset)
        counter <= 20'd0;
    else if (counter >= step_limit)
        counter <= 20'd0;
    else
        counter <= counter + 1;
    end
        
    assign step_out = (counter >= step_limit);
    assign step_oe = 1'b1;     
    assign dir_out = direction;
    assign dir_oe = 1'b1;      
    assign o_osc_ctrl_en = 1'b1;  

    endmodule
