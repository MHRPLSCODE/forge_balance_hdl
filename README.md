# FPGA-Based Self-Balancing Robot — Motor Control & Sensor Interface

FPGA motor controller and sensor interface for a two-wheeled self-balancing robot, built on the **Vicharak Shrike Lite** (Renesas SLG47910 ForgeFPGA, 1120 LUTs + RP2040).



## Architecture

The FPGA handles all time-critical motor I/O (stepper pulse generation, acceleration ramping, encoder decoding, safety watchdog), while the RP2040 runs the PID balance algorithm and reads the IMU. This hardware/software co-design mirrors industrial motor drive architectures where deterministic parallel logic handles actuation and a processor handles control.

```
MPU-6050 IMU ──I²C──▶ RP2040 (PID) ──SPI──▶ ForgeFPGA ──step/dir──▶ A4988 ──▶ NEMA 17
                          ▲                      │                              │
                          └──── count/dir ◀──────┘◀──── encoder A/B ◀───────────┘
```

## Build Ladder

Each rung is simulated in Icarus Verilog / GTKWave before synthesis in GCSH.

| Rung | Module | Status |
|------|--------|--------|
| 0 | Blink — toolchain proof (clock divider → LED) | ✅ Done + hardware verified |
| 1 | Button → LED with debouncer | ⏭ Skipped (input pads tested in Rung 3) |
| 2 | Stepper motor controller (step pulse gen + direction) | ✅ Simulated |
| 2.5 | Acceleration ramp engine | ✅ Simulated |
| 3a | Quadrature decoder (A/B edge counting + direction) | ✅ Written |
| 3b | Stall detector (expected vs actual step count) | ✅ Written |
| 3c | Hardware watchdog (timeout safety shutdown) | ✅ Written |
| 4a | SPI slave interface (RP2040 ↔ FPGA comms) | ✅ Written |
| 4b | Debug UART TX (115200 baud serial debug output) | ✅ Written |
| 5 | Top module (wires all modules, pin mapping) | 🔲 Next |
| 6 | System integration — closed-loop balancing | 🔲 Hardware pending (arrives ~July 8-9) |

## FPGA Module Map

Target LUT budget: 1120 LUTs total

| Module | Function | Est. LUTs | Status |
|--------|----------|-----------|--------|
| Step pulse generator (2 ch) | Variable-frequency pulse output for A4988 step/dir | ~100 | ✅ Simulated |
| Acceleration ramp engine | Gradual speed change via timed increment/decrement | ~150 | ✅ Simulated |
| Quadrature decoder (2 ch) | Encoder A/B edge counting + direction detection | ~120 | ✅ Written |
| Stall detector | Expected vs actual encoder count, flags motor stall | ~60 | ✅ Written |
| Hardware watchdog | Auto-shutdown if RP2040 stops communicating | ~30 | ✅ Written |
| SPI slave interface | 24-bit bidirectional RP2040 ↔ FPGA data transfer | ~150 | ✅ Written |
| Debug UART TX | 115200 baud serial output of internal state | ~80 | ✅ Written |
| **Total** | | **~690 / 1120 (~62%)** | **8/8 modules written** |

## Design Decisions

- **No division operator anywhere** — step frequency controlled via programmable-limit counter, not clock/target division. Conserves LUT budget on a chip with no DSP blocks.
- **Inverse speed encoding** — `step_limit` is a counter ceiling: large value = slow motor, small value = fast motor. The acceleration ramp walks this value toward the target one tick at a time.
- **Reset to max `step_limit` (0xFFFFF)** — on reset, motor starts at slowest possible speed and ramps from there, preventing stall on startup.
- **1x quadrature decoding** — only counts rising edges of channel A. Simpler than 4x (all edges of both channels), sufficient for 400PPR encoders, conserves LUTs.
- **Edge detection pattern** — `(~signal_prev & signal)` used across quad_decoder, stall_detector, and watchdog for single-cycle rising edge detection. One universal pattern, three applications.
- **SPI slave, not master** — FPGA is the slave; RP2040 master generates SCLK and initiates transactions. FPGA only responds. 24-bit transfers (3 bytes) for clean byte-alignment with MicroPython SPI library.
- **UART TX is debug-only** — not part of the control loop. Allows real-time hardware state inspection via USB-serial adapter without involving the RP2040.
- **Microstepping controller deprioritized** — A4988 MS1/MS2/MS3 pins can be hardwired or controlled directly by RP2040 GPIO. Not worth FPGA LUTs.

## SPI Data Format

| Direction | Bits | Content |
|-----------|------|---------|
| MOSI (RP2040 → FPGA) | [23:4] | target_limit (20 bits) |
| | [3] | direction (1 bit) |
| | [2:0] | reserved (3 bits) |
| MISO (FPGA → RP2040) | [23:8] | encoder_count (16 bits) |
| | [7] | encoder_dir (1 bit) |
| | [6] | stall_flag (1 bit) |
| | [5:0] | reserved (6 bits) |

## Key Patterns Used

| Pattern | Where Used | Description |
|---------|-----------|-------------|
| Programmable-limit counter | blink, stepper_driver, accel_ramp, watchdog | Count to N, pulse, reset. Change N = change frequency |
| Rising edge detector | quad_decoder, stall_detector, watchdog | `(~prev & current)` — true for exactly 1 clock cycle on 0→1 transition |
| Synchronous reset | Every module | `if (reset) begin ... end else begin ... end` inside `always @(posedge clk)` |
| Shift register | spi_slave | `{shift_reg[22:0], mosi}` — shift left, new bit enters at LSB |
| Finite state machine | uart_tx | IDLE → START → DATA → STOP states with baud counter |
| Output enable | blink, stepper_driver (top-level only) | ForgeFPGA-specific: every output pin needs `_oe = 1'b1` |

## Platform

| Component | Spec |
|-----------|------|
| FPGA | Renesas SLG47910 ForgeFPGA — 1120 LUTs, 50 MHz on-chip oscillator |
| MCU | Raspberry Pi RP2040 (on same board) |
| Board | Vicharak Shrike Lite |
| Motors | NEMA 17 JK42HS34-0406 (1.5 kg-cm, 0.31A, 6-wire bipolar) × 2 + 1 spare |
| Drivers | A4988 (Good Quality, with heatsink) × 2 + 1 spare |
| Encoders | 400PPR 2-phase incremental optical rotary encoder × 2 |
| IMU | MPU-6050 GY-521 (I²C to RP2040) × 2 (1 spare) |
| Battery | Orange 11.1V 600mAh 25C 3S LiPo |
| Synthesis | Go Configure Software Hub (GCSH) |
| Simulation | Icarus Verilog + GTKWave |
| Flash tool | mpremote → shrike.flash() |

## Repo Structure

```
forge_balance_hdl/
├── fpga-bot/
│   ├── rtl/
│   │   ├── blink.v              # Rung 0 — clock divider LED blink
│   │   ├── stepper_driver.v     # Rung 2 — variable-frequency step pulse generator
│   │   ├── accel_ramp.v         # Rung 2.5 — gradual speed ramp
│   │   ├── quad_decoder.v       # Rung 3a — quadrature encoder decoder
│   │   ├── stall_detector.v     # Rung 3b — motor stall detection
│   │   ├── watchdog.v           # Rung 3c — hardware safety watchdog
│   │   ├── spi_slave.v          # Rung 4a — SPI slave for RP2040 comms
│   │   └── uart_tx.v            # Rung 4b — debug UART transmitter
│   ├── tb/
│   │   ├── blink_tb.v
│   │   ├── stepper_driver_tb.v
│   │   ├── accel_ramp_tb.v
│   │   ├── quad_decoder_tb.v
│   │   ├── stall_detector_tb.v
│   │   ├── watchdog_tb.v
│   │   ├── spi_slave_tb.v
│   │   └── uart_tx_tb.v
│   └── docs/
├── .gitignore
└── README.md
```

## ForgeFPGA Quirks

```verilog
(* top *) module my_module(
    (* clkbuf_inhibit *) input clk,
    output led,
    output led_oe,                      // OE = 1 → output, OE = 0 → input
    output o_osc_ctrl_en                // = 1'b1 to enable 50 MHz oscillator
);
```

- `(* top *)` — marks top-level module for synthesis
- `(* clkbuf_inhibit *)` — prevents double clock buffering
- Every output pin needs explicit `_oe` signal set to `1'b1`
- `o_osc_ctrl_en = 1'b1` enables the on-chip 50 MHz oscillator
- Internal modules (accel_ramp, quad_decoder, etc.) don't need these attributes
- Only the final top module that connects to physical pins needs them

## Simulation

```bash
# Blink
iverilog -o tb/blink_tb rtl/blink.v tb/blink_tb.v && vvp tb/blink_tb && gtkwave tb/blink_tb.vcd

# Stepper driver
iverilog -o tb/stepper_driver_tb rtl/stepper_driver.v tb/stepper_driver_tb.v && vvp tb/stepper_driver_tb && gtkwave tb/stepper_driver_tb.vcd

# Acceleration ramp
iverilog -o tb/accel_ramp_tb rtl/accel_ramp.v tb/accel_ramp_tb.v && vvp tb/accel_ramp_tb && gtkwave tb/accel_ramp_tb.vcd

# Quadrature decoder
iverilog -o tb/quad_decoder_tb rtl/quad_decoder.v tb/quad_decoder_tb.v && vvp tb/quad_decoder_tb && gtkwave tb/quad_decoder_tb.vcd

# Stall detector
iverilog -o tb/stall_detector_tb rtl/stall_detector.v tb/stall_detector_tb.v && vvp tb/stall_detector_tb && gtkwave tb/stall_detector_tb.vcd

# Watchdog
iverilog -o tb/watchdog_tb rtl/watchdog.v tb/watchdog_tb.v && vvp tb/watchdog_tb && gtkwave tb/watchdog_tb.vcd

# SPI slave
iverilog -o tb/spi_slave_tb rtl/spi_slave.v tb/spi_slave_tb.v && vvp tb/spi_slave_tb && gtkwave tb/spi_slave_tb.vcd

# UART TX
iverilog -o tb/uart_tx_tb rtl/uart_tx.v tb/uart_tx_tb.v && vvp tb/uart_tx_tb && gtkwave tb/uart_tx_tb.vcd
```

## Flash Workflow

```bash
mpremote cp FPGA_bitstream_FLASH_MEM.bin :
mpremote exec "import shrike; shrike.flash('FPGA_bitstream_FLASH_MEM.bin')"
```

## Pin Mapping

### Rung 0 — Blink (verified on hardware)

| Signal | GCSH Pin | Board Label | Function |
|--------|----------|-------------|----------|
| clk | OSC_CLK | (internal) | 50 MHz on-chip oscillator |
| o_osc_ctrl_en | OSC_EN | (internal) | Oscillator enable |
| led | GPIO16_OUT [PIN 7] | FPGA_IO16 | Onboard FPGA LED |
| led_oe | GPIO16_OE [PIN 7] | FPGA_IO16 | Output enable for LED |

### Full System (pin mapping TBD during hardware integration)

| Signal | A4988/Encoder Pin | Count | Function |
|--------|-------------------|-------|----------|
| step_out × 2 | A4988 STEP | 2 | Rising edge triggers one motor step |
| dir_out × 2 | A4988 DIR | 2 | Rotation direction |
| enable_n × 2 | A4988 ENABLE | 2 | Motor enable (active low, watchdog controls) |
| enc_a × 2 | Encoder Ch A | 2 | Quadrature channel A |
| enc_b × 2 | Encoder Ch B | 2 | Quadrature channel B |
| sclk | RP2040 SPI SCK | 1 | SPI clock |
| mosi | RP2040 SPI TX | 1 | SPI data in |
| miso | RP2040 SPI RX | 1 | SPI data out |
| ss_n | RP2040 SPI CSn | 1 | SPI slave select |
| uart_tx | Debug header | 1 | UART serial debug output |
| **Total FPGA pins** | | **15** | **of 19 available** |

## Timeline

| Date | Milestone |
|------|-----------|
| July 1 | ✅ Blink verified on hardware |
| July 1 | ✅ Stepper driver simulated |
| July 2 | ✅ Acceleration ramp simulated |
| July 3 | ✅ Quad decoder, stall detector, watchdog written |
| July 3 | ✅ SPI slave and UART TX written |
| July 4 | Top module + full sim verification |
| July 5 | MicroPython (SPI master, IMU driver, PID loop) |


## Author
Mohammed Hasan Rizvi — B.Tech ECE, 4th Year, USICT, GGSIPU
