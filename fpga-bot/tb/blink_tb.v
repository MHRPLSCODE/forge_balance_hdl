// Testbench for Rung 0: LED Blink
// Simulates 1000ns (~100 clock cycles at 50 MHz equivalent timing)
// Verify: counter increments every posedge clk, led_oe = 1, o_osc_ctrl_en = 1
// Note: led (counter[24]) won't toggle in 1000ns — verify via low counter bits

`timescale 1ns/1ps

module blink_tb;

reg clk = 0;
wire led;
wire led_oe;
wire o_osc_ctrl_en;

blink uut (
    .clk(clk),
    .led(led),
    .led_oe(led_oe),
    .o_osc_ctrl_en(o_osc_ctrl_en)
);

always #5 clk = ~clk;

initial begin
    $dumpfile("blink_tb.vcd");
    $dumpvars(0, blink_tb);
    #1000;
    $finish;
end

endmodule
