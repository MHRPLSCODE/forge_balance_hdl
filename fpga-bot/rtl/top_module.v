(* top *) module top_module(
    (* clkbuf_inhibit *) input clk,
    output o_osc_ctrl_en,
    input sclk,
    input ss_n,
    input mosi,
    output miso,
    output miso_oe,
    output sclk_oe,
    output ss_n_oe,
    output mosi_oe,
    output step_out_1,
    output step_oe_1,
    output dir_out_1,
    output dir_oe_1,
    output enable_n_1,
    output enable_oe_1,
    output step_out_2,
    output step_oe_2,
    output dir_out_2,
    output dir_oe_2,
    output enable_n_2,
    output enable_oe_2,
    output uart_tx_out,
    output uart_tx_oe
);

    assign o_osc_ctrl_en = 1'b1;
    assign miso_oe   = 1'b1;
    assign sclk_oe   = 1'b0;
    assign ss_n_oe   = 1'b0;
    assign mosi_oe   = 1'b0;
    assign step_oe_1   = 1'b1;
    assign dir_oe_1    = 1'b1;
    assign enable_oe_1 = 1'b1;
    assign step_oe_2   = 1'b1;
    assign dir_oe_2    = 1'b1;
    assign enable_oe_2 = 1'b1;
    assign uart_tx_oe = 1'b1;

    wire reset = 1'b0;
    wire [23:0] spi_rx_data;
    wire [23:0] spi_tx_data;
    wire spi_rx_valid;
    wire [19:0] target_limit;
    wire direction;
    wire [19:0] current_limit_1;
    wire [19:0] current_limit_2;
    wire step_raw_1;
    wire step_raw_2;
    wire kill_motors;
    wire uart_busy;
    wire uart_done;

    assign target_limit = spi_rx_data[23:4];
    assign direction    = spi_rx_data[3];
    assign spi_tx_data  = {current_limit_1, kill_motors, 3'b000};
    assign enable_n_1   = kill_motors;
    assign enable_n_2   = kill_motors;
    assign step_out_1   = kill_motors ? 1'b0 : step_raw_1;
    assign step_out_2   = kill_motors ? 1'b0 : step_raw_2;
    assign dir_out_1    = direction;
    assign dir_out_2    = direction;

    spi_slave u_spi (
        .clk(clk), .reset(reset), .sclk(sclk), .ss_n(ss_n),
        .mosi(mosi), .miso(miso), .tx_data(spi_tx_data),
        .rx_data(spi_rx_data), .rx_valid(spi_rx_valid)
    );

    accel_ramp u_ramp_1 (
        .clk(clk), .reset(reset), .target_limit(target_limit),
        .ramp_rate(21'd50000), .current_limit(current_limit_1)
    );

    accel_ramp u_ramp_2 (
        .clk(clk), .reset(reset), .target_limit(target_limit),
        .ramp_rate(21'd50000), .current_limit(current_limit_2)
    );

    stepper_driver u_step_1 (
        .clk(clk), .reset(reset), .step_limit(current_limit_1),
        .direction(direction), .step_out(step_raw_1),
        .step_oe(), .dir_out(), .dir_oe(), .o_osc_ctrl_en()
    );

    stepper_driver u_step_2 (
        .clk(clk), .reset(reset), .step_limit(current_limit_2),
        .direction(direction), .step_out(step_raw_2),
        .step_oe(), .dir_out(), .dir_oe(), .o_osc_ctrl_en()
    );

    watchdog u_watchdog (
        .clk(clk), .reset(reset), .heartbeat(spi_rx_valid),
        .timeout_limit(24'd5_000_000), .kill_motors(kill_motors)
    );

    uart_tx u_uart (
        .clk(clk), .reset(reset), .tx_byte(current_limit_1[7:0]),
        .tx_start(spi_rx_valid), .tx_out(uart_tx_out),
        .tx_busy(uart_busy), .tx_done(uart_done)
    );

endmodule
