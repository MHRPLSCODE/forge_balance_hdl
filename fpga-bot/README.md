# FPGA-Based Self-Balancing Robot — Motor Control & Sensor Interface

FPGA motor controller and sensor interface for a two-wheeled self-balancing robot, built on the **Vicharak Shrike Lite** (Renesas SLG47910 ForgeFPGA, 1120 LUTs + RP2040).

**AICTE IDEA Lab Summer Internship 2026** — USICT, GGSIPU, New Delhi

## Architecture

The FPGA handles all time-critical motor I/O (stepper pulse generation, encoder decoding, safety watchdog), while the RP2040 runs the PID balance algorithm and reads the IMU. This hardware/software co-design mirrors industrial motor drive architectures where deterministic parallel logic handles actuation and a processor handles control.

```
MPU-6050 IMU ──I²C──▶ RP2040 (PID) ──SPI──▶ ForgeFPGA ──step/dir──▶ A4988 ──▶ NEMA 17
                          ▲                      │                              │
                          └──── count/dir ◀──────┘◀──── encoder A/B ◀───────────┘
```

## Build Ladder (Incremental Milestones)

Each rung is simulated in Icarus Verilog / GTKWave before synthesis in GCSH.

| Rung | Module | Status |
|------|--------|--------|
| 0 | Blink — toolchain proof (clock divider → LED) | ✅ Done |
| 1 | Button → LED with debouncer | 🔲 |
| 2 | Stepper motor controller (step pulse gen + accel ramp) | 🔲 |
| 3 | Quadrature decoder (A/B edge counting + direction) | 🔲 |
| 4 | RP2040 ↔ FPGA communication interface (SPI/parallel) | 🔲 |
| 5 | System integration — closed-loop balancing | 🔲 |

## Platform

| Component | Spec |
|-----------|------|
| FPGA | Renesas SLG47910 ForgeFPGA — 1120 LUTs, 50 MHz on-chip oscillator |
| MCU | Raspberry Pi RP2040 (on same board) |
| Board | Vicharak Shrike Lite |
| Motors | NEMA 17 (17HS2408) × 2 |
| Drivers | A4988 × 2 |
| Encoders | 400PPR incremental quadrature × 2 |
| IMU | MPU-6050 (I²C to RP2040) |
| Synthesis | Go Configure Software Hub (GCSH) |
| Simulation | Icarus Verilog + GTKWave |
| Flash tool | mpremote → shrike.flash() |

## Repo Structure

```
fpga-bot/
├── rtl/              # Synthesizable Verilog (ForgeFPGA attributes included)
│   └── blink.v
├── tb/               # Simulation testbenches
│   └── blink_tb.v
├── docs/             # Datasheets, pinout refs, notes
├── bitstreams/       # Generated .bin files (gitignored, kept locally)
├── .gitignore
└── README.md
```

## ForgeFPGA Quirks (Reference)

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
- Without any of these, synthesis succeeds but the pin stays tristated

## Simulation Workflow

```bash
# From repo root
iverilog -o tb/blink_tb rtl/blink.v tb/blink_tb.v
vvp tb/blink_tb
gtkwave tb/blink_tb.vcd
```

## Flash Workflow

```bash
# Upload bitstream to RP2040 filesystem
mpremote cp bitstreams/FPGA_bitstream_FLASH_MEM.bin :

# Flash to FPGA
mpremote exec "import shrike; shrike.flash('FPGA_bitstream_FLASH_MEM.bin')"
```

## Pin Mapping (Rung 0)

| Signal | GCSH Pin | Board Label | Function |
|--------|----------|-------------|----------|
| clk | OSC_CLK | (internal) | 50 MHz on-chip oscillator |
| o_osc_ctrl_en | OSC_EN | (internal) | Oscillator enable |
| led | GPIO16_OUT [PIN 7] | FPGA_IO16 | Onboard FPGA LED |
| led_oe | GPIO16_OE [PIN 7] | FPGA_IO16 | Output enable for LED |

## Author

Mohammed Hasan Rizvi — B.Tech ECE, 4th Year, USICT, GGSIPU  
Supervisor: Dr. Mansi Jhamb | Mentor: Dr. Ankita Sarkar
