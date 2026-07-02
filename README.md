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
| 0 | Blink — toolchain proof (clock divider → LED) | ✅ Done |
| 1 | Button → LED with debouncer | ⏭ Skipped (input pads tested in Rung 3) |
| 2 | Stepper motor controller (step pulse gen + direction) | ✅ Done |
| 2.5 | Acceleration ramp engine | ✅ Done |
| 3 | Quadrature decoder (A/B edge counting + direction) | 🔲 |
| 4 | RP2040 ↔ FPGA communication interface (SPI/parallel) | 🔲 |
| 5 | System integration — closed-loop balancing | 🔲 |

## FPGA Module Map

Target LUT budget: 1120 LUTs total

| Module | Function | Est. LUTs | Status |
|--------|----------|-----------|--------|
| Step pulse generator (2 ch) | Variable-frequency pulse output for A4988 step/dir | ~100 | ✅ Simulated |
| Acceleration ramp engine | Gradual speed change via timed increment/decrement to prevent stepper stalling | ~150 | ✅ Simulated |
| Microstep config controller | MS1/MS2/MS3 pin control for A4988 | ~30 | 🔲 Deprioritized |
| Quadrature decoder (2 ch) | Encoder A/B edge counting + direction | ~120 | 🔲 |
| Stall detector | Expected vs. actual encoder count comparison | ~60 | 🔲 |
| Hardware watchdog | Auto-shutdown if RP2040 stops communicating | ~30 | 🔲 |
| SPI/parallel comms interface | Bidirectional RP2040 ↔ FPGA data transfer | ~150 | 🔲 |
| Debug UART TX | 115200 baud serial output for hardware debug | ~80 | 🔲 |
| **Total** | | **~720 / 1120 (~64%)** | |

## Design Decisions

- **No division operator anywhere** — step frequency is controlled via a programmable-limit counter, not clock/target division. Conserves LUT budget on a chip with no DSP blocks.
- **Inverse speed encoding** — `step_limit` is a counter ceiling: large value = slow motor, small value = fast motor. The acceleration ramp module walks this value toward the target one tick at a time on a configurable timer.
- **Reset to max `step_limit` (0xFFFFF)** — on reset, the motor starts at its slowest possible speed and ramps from there, preventing stall on startup.

## Platform

| Component | Spec |
|-----------|------|
| FPGA | Renesas SLG47910 ForgeFPGA — 1120 LUTs, 50 MHz on-chip oscillator |
| MCU | Raspberry Pi RP2040 (on same board) |
| Board | Vicharak Shrike Lite |
| Motors | NEMA 17 (17HS2408) × 2 |
| Drivers | A4988 × 2 (step/dir interface) |
| Encoders | 400PPR incremental quadrature × 2 |
| IMU | MPU-6050 (I²C to RP2040) |
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
│   │   └── accel_ramp.v         # Rung 2.5 — gradual speed ramp to prevent stalling
│   ├── tb/
│   │   ├── blink_tb.v
│   │   ├── stepper_driver_tb.v
│   │   └── accel_ramp_tb.v
│   └── docs/
├── .gitignore
└── README.md
```

## ForgeFPGA Quirks

Every module targeting this chip needs these or it won't drive pins:

```verilog
(* top *) module my_module(
    (* clkbuf_inhibit *) input clk,    // suppress extra clock buffer
    output led,
    output led_oe,                      // OE = 1 → output, OE = 0 → input
    output o_osc_ctrl_en                // = 1'b1 to enable 50 MHz oscillator
);
```

- `(* top *)` — marks the top-level module for synthesis
- `(* clkbuf_inhibit *)` — prevents double-buffering on the clock input
- Every output pin needs an explicit `_oe` signal set to `1'b1`
- `o_osc_ctrl_en = 1'b1` enables the on-chip 50 MHz oscillator
- Internal-only modules (like `accel_ramp`) don't need these attributes

## Simulation

```bash
# Blink (Rung 0)
iverilog -o tb/blink_tb rtl/blink.v tb/blink_tb.v
vvp tb/blink_tb && gtkwave tb/blink_tb.vcd

# Stepper driver (Rung 2)
iverilog -o tb/stepper_driver_tb rtl/stepper_driver.v tb/stepper_driver_tb.v
vvp tb/stepper_driver_tb && gtkwave tb/stepper_driver_tb.vcd

# Acceleration ramp (Rung 2.5)
iverilog -o tb/accel_ramp_tb rtl/accel_ramp.v tb/accel_ramp_tb.v
vvp tb/accel_ramp_tb && gtkwave tb/accel_ramp_tb.vcd
```

## Flash Workflow

```bash
mpremote cp FPGA_bitstream_FLASH_MEM.bin :
mpremote exec "import shrike; shrike.flash('FPGA_bitstream_FLASH_MEM.bin')"
```

## Pin Mapping

### Rung 0 — Blink

| Signal | GCSH Pin | Board Label | Function |
|--------|----------|-------------|----------|
| clk | OSC_CLK | (internal) | 50 MHz on-chip oscillator |
| o_osc_ctrl_en | OSC_EN | (internal) | Oscillator enable |
| led | GPIO16_OUT [PIN 7] | FPGA_IO16 | Onboard FPGA LED |
| led_oe | GPIO16_OE [PIN 7] | FPGA_IO16 | Output enable for LED |

### Rung 2 — Stepper Driver (pin mapping TBD on hardware test)

| Signal | A4988 Pin | Function |
|--------|-----------|----------|
| step_out | STEP | Rising edge triggers one motor step |
| dir_out | DIR | High/low sets rotation direction |

## Author

Mohammed Hasan Rizvi — B.Tech ECE, 4th Year, USICT, GGSIPU

