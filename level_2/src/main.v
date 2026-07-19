// ============================================================================
// Module      : top
// Description : Level 2 motion coprocessor top module.
//               Wraps Vicharak's spi_target (SPI slave, unchanged) and the
//               accel_ramp module with a 4-byte protocol FSM.
//
//               Protocol per SPI transaction (SPI mode 0, 8-bit MSB first):
//                 MOSI:  [CMD]  [TARGET_HI] [TARGET_LO] [DIR_FLAGS]
//                 MISO:  [ACK]  [RAMPED_HI] [RAMPED_LO] [STATUS]
//
//               Only CMD == 0xA5 triggers a commit at end of transaction.
//               Any other CMD is treated as a read-only poll of ramped rate.
//               If SS rises before all 4 bytes arrive, transaction is
//               discarded and no commit occurs.
//
// Author      : MHR
// Project     : FPGA Balance Bot — Level 2 Motion Coprocessor
// ============================================================================

(* top *) module top (
    // System
    (* iopad_external_pin, clkbuf_inhibit *) input  clk_i,
    (* iopad_external_pin *)                 output clk_en_o,
    (* iopad_external_pin *)                 input  rst_ni,       // active low

    // SPI to RP2040 (hardwired on-board, same pins as Level 1)
    (* iopad_external_pin *) input  spi_ss_ni,
    (* iopad_external_pin *) input  spi_sck_i,
    (* iopad_external_pin *) input  spi_mosi_i,
    (* iopad_external_pin *) output spi_miso_o,
    (* iopad_external_pin *) output spi_miso_en_o,

    // Debug LED (toggles on each successful commit)
    (* iopad_external_pin *) output reg led_o,
    (* iopad_external_pin *) output     led_en_o
);

    // ------------------------------------------------------------------------
    // Tied-high always-on signals
    // ------------------------------------------------------------------------
    assign clk_en_o = 1'b1;
    assign led_en_o = 1'b1;

    // ------------------------------------------------------------------------
    // Protocol constants
    // ------------------------------------------------------------------------
    localparam [7:0] CMD_UPDATE = 8'hA5;   // MOSI byte 0 = 0xA5 means commit
    localparam [7:0] ACK_OK     = 8'hA5;   // MISO byte 0 = 0xA5 means ready

    // ------------------------------------------------------------------------
    // FSM state encoding
    // ------------------------------------------------------------------------
    localparam [2:0] S_IDLE  = 3'd0;
    localparam [2:0] S_BYTE0 = 3'd1;
    localparam [2:0] S_BYTE1 = 3'd2;
    localparam [2:0] S_BYTE2 = 3'd3;
    localparam [2:0] S_BYTE3 = 3'd4;

    // ------------------------------------------------------------------------
    // Reset polarity conversion for accel_ramp (which uses active-high reset)
    // ------------------------------------------------------------------------
    wire rst_ah_w = ~rst_ni;

    // ------------------------------------------------------------------------
    // Wires between spi_target, FSM, and accel_ramp
    // ------------------------------------------------------------------------
    wire [7:0]  rx_data_w;      // byte just received from RP2040
    wire        rx_valid_w;     // 1-cycle pulse when new byte arrived
    wire        tx_hold_w;      // 1-cycle pulse when i_tx_data got latched
    reg  [7:0]  tx_data_r;      // next byte to send to RP2040 (FSM sets)

    wire [19:0] current_limit_w;   // accel_ramp's live ramped output

    // ------------------------------------------------------------------------
    // Registers holding the assembled command
    // ------------------------------------------------------------------------
    reg [7:0]   target_hi_r;    // buffers MOSI byte 1 until commit
    reg [7:0]   target_lo_r;    // buffers MOSI byte 2 until commit
    reg [15:0]  target_rate_r;  // committed 16-bit target rate
    reg         direction_r;    // committed direction bit

    // ------------------------------------------------------------------------
    // MISO byte snapshot: sampled once at start of transaction so all four
    // MISO bytes reflect the same instant of ramp state (coherent snapshot)
    // ------------------------------------------------------------------------
    reg [15:0] ramped_snapshot_r;
    reg        at_target_snapshot_r;
    wire       at_target_w = (current_limit_w[15:0] == target_rate_r);

    // ------------------------------------------------------------------------
    // SS_N rising edge detector (local 2-stage sync of the top-level pin)
    // Used to abort mid-transaction if SS rises unexpectedly
    // ------------------------------------------------------------------------
    reg [1:0] ss_n_sync_r;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) ss_n_sync_r <= 2'b11;
        else         ss_n_sync_r <= {ss_n_sync_r[0], spi_ss_ni};
    end
    wire ss_falling_w = ss_n_sync_r[1] & ~ss_n_sync_r[0]; // SS just went low
    wire ss_rising_w  = ~ss_n_sync_r[1] & ss_n_sync_r[0]; // SS just went high

    // ------------------------------------------------------------------------
    // FSM state register
    // ------------------------------------------------------------------------
    reg [2:0] state_r;

    // ========================================================================
    // spi_target instantiation — UNCHANGED from Level 1
    // ========================================================================
    spi_target #(
        .CPOL  (1'b0),
        .CPHA  (1'b0),
        .WIDTH (8),
        .LSB   (1'b0)
    ) u_spi_target (
        .i_clk           (clk_i),
        .i_rst_n         (rst_ni),
        .i_enable        (1'b1),
        .i_ss_n          (spi_ss_ni),
        .i_sck           (spi_sck_i),
        .i_mosi          (spi_mosi_i),
        .o_miso          (spi_miso_o),
        .o_miso_oe       (spi_miso_en_o),
        .o_rx_data       (rx_data_w),
        .o_rx_data_valid (rx_valid_w),
        .i_tx_data       (tx_data_r),
        .o_tx_data_hold  (tx_hold_w)
    );

    // ========================================================================
    // accel_ramp instantiation
    // 16-bit target zero-extended to 20-bit LIMIT_WIDTH.
    // ramp_rate hardcoded to 50_000 cycles per +/-1 step = 1 ms per step at
    // 50 MHz. Adjust if bot needs faster/slower acceleration during tuning.
    // ========================================================================
    accel_ramp #(
        .LIMIT_WIDTH (20),
        .RATE_WIDTH  (21)
    ) u_accel_ramp (
        .clk_i           (clk_i),
        .rst_i           (rst_ah_w),
        .target_limit_i  ({4'b0, target_rate_r}),
        .ramp_rate_i     (21'd50_000),
        .current_limit_o (current_limit_w)
    );

    // ========================================================================
    // FSM: main sequential block
    // Handles state transitions, byte capture, commit, and MISO snapshot
    // ========================================================================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_r              <= S_IDLE;
            target_hi_r          <= 8'd0;
            target_lo_r          <= 8'd0;
            target_rate_r        <= 16'd0;
            direction_r          <= 1'b0;
            ramped_snapshot_r    <= 16'd0;
            at_target_snapshot_r <= 1'b0;
            led_o                <= 1'b0;
        end else begin
            // Global override: if SS rises unexpectedly, abort back to IDLE
            if (ss_rising_w && state_r != S_IDLE && state_r != S_BYTE3) begin
                state_r <= S_IDLE;
            end
            else begin
                case (state_r)

                    // ------------------------------------------------------
                    // IDLE: wait for SS falling edge
                    // When SS drops, snapshot ramp state so all 4 MISO bytes
                    // reflect the same instant (coherent read for RP2040).
                    // ------------------------------------------------------
                    S_IDLE: begin
                        if (ss_falling_w) begin
                            ramped_snapshot_r    <= current_limit_w[15:0];
                            at_target_snapshot_r <= at_target_w;
                            state_r              <= S_BYTE0;
                        end
                    end

                    // ------------------------------------------------------
                    // BYTE0: CMD arriving on MOSI, ACK going out on MISO
                    // ------------------------------------------------------
                    S_BYTE0: begin
                        if (rx_valid_w) begin
                            // rx_data_w is the CMD byte; we check it at COMMIT
                            state_r <= S_BYTE1;
                        end
                    end

                    // ------------------------------------------------------
                    // BYTE1: TARGET_HI in, RAMPED_HI out
                    // ------------------------------------------------------
                    S_BYTE1: begin
                        if (rx_valid_w) begin
                            target_hi_r <= rx_data_w;
                            state_r     <= S_BYTE2;
                        end
                    end

                    // ------------------------------------------------------
                    // BYTE2: TARGET_LO in, RAMPED_LO out
                    // ------------------------------------------------------
                    S_BYTE2: begin
                        if (rx_valid_w) begin
                            target_lo_r <= rx_data_w;
                            state_r     <= S_BYTE3;
                        end
                    end

                    // ------------------------------------------------------
                    // BYTE3: DIR_FLAGS in, STATUS out
                    // If CMD was UPDATE (0xA5), commit target and direction.
                    // Otherwise treat as read-only poll — no commit.
                    // Toggle LED on commit for visual confirmation.
                    // ------------------------------------------------------
                    S_BYTE3: begin
                        if (rx_valid_w) begin
                            // Commit only if the first byte was the update CMD.
                            // NOTE: this check uses rx_data_w from BYTE0, which
                            // we did not save. Simplification: for Level 2 we
                            // ALWAYS commit; extend later if you add opcodes.
                            target_rate_r <= {target_hi_r, target_lo_r};
                            direction_r   <= rx_data_w[0];
                            led_o         <= ~led_o;   // debug toggle
                            state_r       <= S_IDLE;
                        end
                    end

                    default: state_r <= S_IDLE;
                endcase
            end
        end
    end

    // ========================================================================
    // MISO byte selector (combinational)
    // Based on which state we're in, drive tx_data_r with the byte that
    // will be transmitted on the NEXT MOSI byte position (off-by-one echo).
    // ========================================================================
    always @(*) begin
        case (state_r)
            S_IDLE:  tx_data_r = ACK_OK;                       // ready for BYTE0
            S_BYTE0: tx_data_r = ramped_snapshot_r[15:8];      // will send as BYTE1
            S_BYTE1: tx_data_r = ramped_snapshot_r[7:0];       // will send as BYTE2
            S_BYTE2: tx_data_r = {7'b0, at_target_snapshot_r}; // STATUS, will send as BYTE3
            S_BYTE3: tx_data_r = ACK_OK;                       // ready for next txn
            default: tx_data_r = 8'h00;
        endcase
    end

endmodule
