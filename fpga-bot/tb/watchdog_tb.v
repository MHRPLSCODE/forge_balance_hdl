`timescale 1ns/1ps
module watchdog_tb;
reg clk = 0;
reg reset = 0;
reg heartbeat = 0;
reg [23:0] timeout_limit = 24'd50;  
wire kill_motors;

watchdog uut (
    .clk(clk),
    .reset(reset),
    .heartbeat(heartbeat),
    .timeout_limit(timeout_limit),
    .kill_motors(kill_motors)
);
always #5 clk = ~clk;
task send_heartbeat;
    begin
        @(posedge clk);
        heartbeat = 1;
        @(posedge clk);
        heartbeat = 0;
    end
endtask
initial begin
    $dumpfile("watchdog_tb.vcd");
    $dumpvars(0, watchdog_tb);
    reset = 1;
    #30;
    reset = 0;
    #20;
    send_heartbeat; #200;
    send_heartbeat; #200;
    send_heartbeat; #200;
    #600;
    send_heartbeat;
    #200;
    #600;
    #200;
    $finish;
end
endmodule
