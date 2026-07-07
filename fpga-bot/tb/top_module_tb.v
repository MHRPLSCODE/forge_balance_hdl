`timescale 1ns/1ps

module top_module_tb;

reg clk = 0;
reg sclk = 0;
reg ss_n = 1;
reg mosi = 0;

wire miso;
wire step_out_1, step_out_2;
wire dir_out_1, dir_out_2;
wire enable_n_1, enable_n_2;
wire uart_tx_out;
wire o_osc_ctrl_en;

wire miso_oe, sclk_oe, ss_n_oe, mosi_oe;
wire step_oe_1, dir_oe_1, enable_oe_1;
wire step_oe_2, dir_oe_2, enable_oe_2;
wire uart_tx_oe;

top_module uut (
    .clk(clk),
    .o_osc_ctrl_en(o_osc_ctrl_en),
    .sclk(sclk),
    .ss_n(ss_n),
    .mosi(mosi),
    .miso(miso),
    .miso_oe(miso_oe),
    .sclk_oe(sclk_oe),
    .ss_n_oe(ss_n_oe),
    .mosi_oe(mosi_oe),
    .step_out_1(step_out_1),
    .step_oe_1(step_oe_1),
    .dir_out_1(dir_out_1),
    .dir_oe_1(dir_oe_1),
    .enable_n_1(enable_n_1),
    .enable_oe_1(enable_oe_1),
    .step_out_2(step_out_2),
    .step_oe_2(step_oe_2),
    .dir_out_2(dir_out_2),
    .dir_oe_2(dir_oe_2),
    .enable_n_2(enable_n_2),
    .enable_oe_2(enable_oe_2),
    .uart_tx_out(uart_tx_out),
    .uart_tx_oe(uart_tx_oe)
);

always #5 clk = ~clk;

task spi_send_bit(input bit_val);
    begin
        mosi = bit_val;
        #250;
        sclk = 1;
        #250;
        sclk = 0;
    end
endtask

task spi_send_24(input [23:0] data);
    integer i;
    begin
        ss_n = 0;
        #100;

        for (i = 23; i >= 0; i = i - 1)
            spi_send_bit(data[i]);

        #100;
        ss_n = 1;
        #500;
    end
endtask

initial begin
    $dumpfile("top_module_tb.vcd");
    $dumpvars(0, top_module_tb);

    #100;

    $display("=== TX1: target=1000, dir=1 ===");
    spi_send_24(24'h03E88);
    #2000;

    $display("=== TX2: repeat ===");
    spi_send_24(24'h03E88);
    #2000;

    $display("=== TX3: target=500, dir=0 ===");
    spi_send_24(24'h01F40);
    #2000;

    $display("=== TX4: stop ===");
    spi_send_24(24'h186A00);
    #2000;

    $display("=== Waiting for watchdog (won't trigger in short sim) ===");
    #5000;

    $finish;
end

endmodule
