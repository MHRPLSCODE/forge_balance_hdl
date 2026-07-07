# FPGA-Based Self-Balancing Robot — Motor Control & Sensor Interface

FPGA motor controller for a two-wheeled self-balancing robot, built on the **Vicharak Shrike Lite** (Renesas SLG47910 ForgeFPGA, 1120 LUTs + RP2040).

**AICTE IDEA Lab Summer Internship 2026** — USICT, GGSIPU, New Delhi

## Architecture

FPGA handles deterministic motor I/O (step pulse generation, acceleration ramping, hardware safety). RP2040 handles IMU reading, sensor fusion, and PID balance control. Hardware/software co-design mirroring industrial motor drive architectures.

## Build Status

| Rung | Module | Status |
|------|--------|--------|
| 0 | Blink — toolchain proof | ✅ Hardware verified |
| 2 | Stepper driver (step pulse gen + direction) | ✅ Simulated |
| 2.5 | Acceleration ramp engine | ✅ Simulated |
| 3 | Hardware watchdog (timeout safety shutdown) | ✅ Written |
| 4a | SPI slave interface (RP2040 ↔ FPGA comms) | ✅ Written |
| 4b | Debug UART TX (115200 baud serial debug) | ✅ Written |
| 5 | Top module (wires all sub-modules) | ✅ Written |
| 6 | System integration | 🔲 Hardware integration in progress |

**All 6 Verilog modules + top module written. MicroPython stack generated.**

## FPGA Module Map (1120 LUT Budget)

| Module | Function | Est. LUTs | Status |
|--------|----------|-----------|--------|
| Step pulse generator (×2) | Variable-frequency pulse for TMC2209 step/dir | ~200 | ✅ |
| Acceleration ramp (×2) | Timed increment/decrement to prevent stalling | ~300 | ✅ |
| Hardware watchdog | Auto-shutdown if RP2040 stops communicating | ~30 | ✅ |
| SPI slave | 24-bit bidirectional RP2040 ↔ FPGA transfer | ~150 | ✅ |
| Debug UART TX | 115200 baud serial debug output | ~80 | ✅ |
| Top-level glue | Wiring, muxing, enable logic | ~20 | ✅ |
| **Total** | | **~780 / 1120 (~70%)** | **All done** |

## Design Decisions

- **No division operator** — step frequency via programmable-limit counter (NCO pattern), not clock division. Conserves LUTs on a chip with no DSP blocks.
- **Inverse speed encoding** — large step_limit = slow motor, small = fast. Ramp module walks value toward target ±1 per tick.
- **Reset to max step_limit (0xFFFFF)** — motors start stopped, ramp up. Prevents stall on startup.
- **Edge detection pattern** — (~prev & current) used in watchdog for heartbeat detection.
- **SPI slave (not master)** — RP2040 generates SCLK and initiates. FPGA responds. 24-bit transfers for MicroPython byte alignment.
- **Watchdog gates step output** — when kill_motors fires, step pulses forced to zero AND TMC2209 ENABLE pulled high (disabled). Dual safety path.
- **IMU-only feedback** — no encoders. PID uses tilt angle from MPU-6050 complementary filter. Simpler, sufficient for stepper-based balancing.
- **TMC2209 over A4988** — better current regulation, StealthChop for quiet operation, same STEP/DIR/EN interface.

## SPI Data Format

| Direction | Bits | Content |
|-----------|------|---------|
| MOSI (RP2040 → FPGA) | [23:4] | target_limit (20 bits) |
| | [3] | direction (1 bit) |
| | [2:0] | padding |
| MISO (FPGA → RP2040) | [23:4] | current_limit (20 bits) |
| | [3] | kill_motors status (1 bit) |
| | [2:0] | padding |

## Key Patterns

| Pattern | Modules | Description |
|---------|---------|-------------|
| Programmable-limit counter | stepper_driver, accel_ramp, watchdog | Count to N, pulse, reset |
| Rising edge detector | watchdog | (~prev & current) — 1 cycle pulse on 0→1 |
| Synchronous reset | All | if (reset) inside always @(posedge clk) |
| Shift register | spi_slave | {reg[22:0], mosi} — serial to parallel |
| FSM | uart_tx | IDLE → START → DATA → STOP with baud counter |
| Output enable | top_module only | ForgeFPGA _oe = 1'b1 for every output pin |
| Kill gating | top_module | step_out = kill_motors ? 0 : step_raw |

## Hardware

| Component | Spec | Qty |
|-----------|------|-----|
| Vicharak Shrike Lite | ForgeFPGA 1120 LUTs + RP2040, 50 MHz | 1 |
| NEMA 17 JK42HS34-0406 | 1.5 kg-cm, 0.31A, 6-wire, round shaft | 3 (1 spare) |
| TMC2209 driver module | STEP/DIR/EN, up to 2A, UART config | 2 |
| MPU-6050 GY-521 | 6-axis IMU, I²C | 2 (1 spare) |
| 2S LiPo battery | 7.4V 2600mAh | 1 |
| B3 LiPo charger | Balance charger for 2S/3S | 1 |
| XL4015 buck converter | Step-down for logic power | 1 |
| Clamps/couplers | Motor shaft coupling | 2 |
| 9x15 PCB | Prototype carrier board | 1 |

## Repo Structure

```
FPGA-Balance-Bot/
├── rtl/
│   ├── blink.v
│   ├── stepper_driver.v
│   ├── accel_ramp.v
│   ├── watchdog.v
│   ├── spi_slave.v
│   ├── uart_tx.v
│   └── top_module.v
├── tb/
│   ├── blink_tb.v
│   ├── stepper_driver_tb.v
│   ├── accel_ramp_tb.v
│   ├── watchdog_tb.v
│   ├── spi_slave_tb.v
│   └── uart_tx_tb.v
├── micropython/
│   ├── config.py
│   ├── main.py
│   ├── spi_master.py
│   ├── imu.py
│   └── pid.py
├── docs/
├── .gitignore
└── README.md
```

## Simulation

```bash
iverilog -o tb/stepper_driver_tb rtl/stepper_driver.v tb/stepper_driver_tb.v && vvp tb/stepper_driver_tb && gtkwave tb/stepper_driver_tb.vcd
iverilog -o tb/accel_ramp_tb rtl/accel_ramp.v tb/accel_ramp_tb.v && vvp tb/accel_ramp_tb && gtkwave tb/accel_ramp_tb.vcd
iverilog -o tb/watchdog_tb rtl/watchdog.v tb/watchdog_tb.v && vvp tb/watchdog_tb && gtkwave tb/watchdog_tb.vcd
iverilog -o tb/spi_slave_tb rtl/spi_slave.v tb/spi_slave_tb.v && vvp tb/spi_slave_tb && gtkwave tb/spi_slave_tb.vcd
iverilog -o tb/uart_tx_tb rtl/uart_tx.v tb/uart_tx_tb.v && vvp tb/uart_tx_tb && gtkwave tb/uart_tx_tb.vcd
```

## Flash

```bash
mpremote cp FPGA_bitstream_FLASH_MEM.bin :
mpremote exec "import shrike; shrike.flash('FPGA_bitstream_FLASH_MEM.bin')"
```

## Timeline

| Date | Milestone |
|------|-----------|
| July 1 | ✅ Blink hardware verified |
| July 1 | ✅ Stepper driver simulated |
| July 2 | ✅ Acceleration ramp simulated |
| July 3 | ✅ Watchdog, SPI slave, UART TX written |
| July 4 | ✅ MicroPython package generated |
| July 6 | ✅ Top module written, hardware purchased |
| July 7 | Compile and simulate all remaining modules |
| July 8-9 | Hardware arrives (Robu order), flash + wire + test |
| July 10-12 | Integration, PID tuning, demo polish |
| July 13-17 | Presentation window |

## Author

Mohammed Hasan Rizvi — B.Tech ECE, 4th Year, USICT, GGSIPU
Supervisor: Dr. Mansi Jhamb | Mentor: Dr. Ankita Sarkar
