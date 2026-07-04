module uart_tx(
    input clk,
    input reset,
    input [7:0] tx_byte,
    input tx_start,
    output reg tx_out,
    output reg tx_busy,
    output reg tx_done
);

    localparam CLKS_PER_BIT = 434;

    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;

    reg [2:0] state = IDLE;
    reg [8:0] baud_counter = 9'd0;
    reg [2:0] bit_index = 3'd0;
    reg [7:0] shift_reg = 8'd0;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            tx_out <= 1'b1;
            tx_busy <= 1'b0;
            tx_done <= 1'b0;
            baud_counter <= 9'd0;
            bit_index <= 3'd0;
            shift_reg <= 8'd0;
        end else begin
            tx_done <= 1'b0;

            case (state)

                IDLE: begin
                    tx_out <= 1'b1;
                    tx_busy <= 1'b0;
                    baud_counter <= 9'd0;
                    bit_index <= 3'd0;

                    if (tx_start) begin
                        shift_reg <= tx_byte;
                        tx_busy <= 1'b1;
                        state <= START;
                    end
                end

                START: begin
                    tx_out <= 1'b0;

                    if (baud_counter >= CLKS_PER_BIT - 1) begin
                        baud_counter <= 9'd0;
                        state <= DATA;
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end

                DATA: begin
                    tx_out <= shift_reg[0];

                    if (baud_counter >= CLKS_PER_BIT - 1) begin
                        baud_counter <= 9'd0;
                        shift_reg <= {1'b0, shift_reg[7:1]};

                        if (bit_index >= 3'd7) begin
                            bit_index <= 3'd0;
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end

                STOP: begin
                    tx_out <= 1'b1;

                    if (baud_counter >= CLKS_PER_BIT - 1) begin
                        baud_counter <= 9'd0;
                        tx_done <= 1'b1;
                        tx_busy <= 1'b0;
                        state <= IDLE;
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
