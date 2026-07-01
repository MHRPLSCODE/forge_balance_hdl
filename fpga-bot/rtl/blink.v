// Rung 0: LED Blink — Toolchain Proof
// Platform: Vicharak Shrike Lite (Renesas SLG47910 ForgeFPGA)
// Clock: 50 MHz on-chip oscillator
// Blink rate: ~1.5 Hz (counter bit [24] toggles every 2^25 / 50MHz ≈ 0.67s)

(* top *) module blink(
    (* clkbuf_inhibit *) input clk,
    output led,
    output led_oe,
    output o_osc_ctrl_en
);

reg [24:0] counter = 25'd0;

always @(posedge clk)
    counter <= counter + 1;

assign led = counter[24];
assign led_oe = 1'b1;
assign o_osc_ctrl_en = 1'b1;

endmodule
