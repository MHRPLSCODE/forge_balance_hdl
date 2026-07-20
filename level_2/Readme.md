# Level 2 — Motion Coprocessor

**Status:** Working end-to-end (July 20, 2026)

RP2040 sends target step-rate + direction over SPI, FPGA runs `accel_ramp` in hardware at 50 MHz, returns current ramped rate back on the same SPI cycle. Verified on Shrike Lite hardware with target=5000 climbing cleanly 0→5000 over 5 seconds (1 ms per step).

## SPI protocol

4 single-byte SPI transactions per command cycle, SPI mode 0, 1 MHz, MSB first. Each byte is a separate CS toggle. FPGA maintains protocol state across transactions.

**MOSI (RP2040 → FPGA):**
| Byte | Contents |
|---|---|
| 0 | CMD (`0xA5` = start-of-command) |
| 1 | TARGET_HI (upper 8 bits of 16-bit target step-rate) |
| 2 | TARGET_LO (lower 8 bits) |
| 3 | DIR_FLAGS (bit 0 = direction) |

**MISO (FPGA → RP2040), reply to byte N shows up in byte N+1's transaction:**
| Byte | Contents |
|---|---|
| 0 | ACK (`0xA5`) from previous transaction |
| 1 | RAMPED_HI (current ramp output, upper 8 bits) |
| 2 | RAMPED_LO (current ramp output, lower 8 bits) |
| 3 | STATUS (bit 0 = at_target) |

## FSM states

- `S_IDLE` — waiting for CMD byte
- `S_WAIT_HI` — expecting TARGET_HI, replies RAMPED_HI
- `S_WAIT_LO` — expecting TARGET_LO, replies RAMPED_LO
- `S_WAIT_DIR` — expecting DIR_FLAGS, replies STATUS, commits target on arrival

## Pin assignments (GCSH I/O Planner)

Same physical pins as Level 1, port names updated to industry style (`_i` / `_o` / `_ni`).

| Port | FPGA pin | RP2040 pin |
|---|---|---|
| clk_i | OSC_CLK (internal 50 MHz) | — |
| clk_en_o | OSC_EN | — |
| rst_ni | GPIO18 (Pin 9) | GPIO14 |
| spi_sck_i | GPIO3 (Pin 16) | GPIO2 |
| spi_ss_ni | GPIO4 (Pin 17) | GPIO1 |
| spi_mosi_i | GPIO5 (Pin 18) | GPIO3 |
| spi_miso_o | GPIO6 (Pin 19) OUT | GPIO0 |
| spi_miso_en_o | GPIO6 (Pin 19) OE | — |
| led_o | GPIO16 (Pin 7) OUT | — |
| led_en_o | GPIO16 (Pin 7) OE | — |

## Flash procedure

1. Open PIO project in VS Code.
2. Place `level2.bin` (renamed from GCSH's `FPGA_bitstream_MCU.bin`) in `data/`.
3. Board → BOOTSEL mode (hold BOOT, plug USB, release BOOT). Board mounts as `E:`.
4. PlatformIO → General → **Full Clean**.
5. PlatformIO → Platform → **Build unified FW+FS UF2 image**.
6. Copy `firmware_with_fs.uf2` from `.pio/build/pico/` into `E:`.
7. Open Monitor on the new COM port.

## Expected serial output (target = 5000)

```
=== Level 2: Motion Coprocessor ===
[ShrikeFlash] FPGA programming done.
SPI ready. Starting ramp tests.
>>> New target: 5000
  replies: 0xA5 0x00 0x00 0x00
  ramped=0  status=0x00  at_target=no
  replies: 0xA5 0x00 0xC9 0x00
  ramped=201  status=0x00  at_target=no
  ...
  replies: 0xA5 0x13 0x88 0x01
  ramped=5000  status=0x01  at_target=YES
```

Ramp climbs 0 → 5000 in ~25 polls × 200 ms = 5 s, matching `ramp_rate_i = 50_000` cycles per step = 1 ms per step at 50 MHz. LED toggles on each commit.

## Design story

Five RTL iterations. Each attempt exposed a different real bug:

1. **v1** — race condition between FSM state transitions and `spi_target`'s `o_tx_data_hold` latching. Byte 0 correct, byte 1+ wrong.
2. **v2** — metastability from 2-stage SS synchronizer that was shallower than `spi_target`'s 3-stage sync.
3. **v3** — global "if received byte == 0xA5, reset to WAIT_HI" override corrupted state progression during real command bytes.
4. **v4** — state cycled 25× per received byte because `rx_valid_w` from `spi_target` stays HIGH for a full SCK half-period (~25 FPGA clocks at 1 MHz SPI on 50 MHz FPGA), not one clock as assumed.
5. **v5** — added rising-edge detector on `rx_valid_w`. State now advances exactly once per received byte. **Working.**

The v4 bug was found by writing `tb_top.v`, running iverilog + gtkwave, and looking at the trace. The waveform showed `rx_valid_w` staying HIGH across many clocks while `state_r` cycled rapidly. Without the simulator this bug would have taken far longer to isolate — RTL debug on hardware alone is a bad time.

## What is NOT yet integrated

- Two-motor variant (currently one target, one direction — bot needs left + right)
- Wiring FPGA ramped output into the actual STEP-pulse generator on RP2040
- Bot balance control loop (currently the ramp is verified in isolation)
