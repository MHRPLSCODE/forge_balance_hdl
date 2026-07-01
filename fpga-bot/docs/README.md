# Documentation

Reference materials for the FPGA-Based Self-Balancing Robot project.

## Key Resources

- [Vicharak Shrike Lite Docs](https://vicharak-in.github.io/shrike/)
- [Shrike Pinout Reference](https://vicharak-in.github.io/shrike/shrike_pinouts.html)
- [Shrike CLI Guide (mpremote)](https://vicharak-in.github.io/shrike/shrike_cli_guide.html)
- [Renesas SLG47910 Datasheet](https://www.renesas.com/en/products/programmable-mixed-signal-asic-ip-products/forgefpga-702-series/slg47910-forgefpga)
- [Vicharak GitHub Examples](https://github.com/vicharak-in/shrike)

## Pin Mapping Notes

- FPGA user LED: GPIO16 (PIN 7 in GCSH)
- RP2040 user LED: GPIO4 (not accessible from FPGA)
- FPGA PINs 17, 18 are shared with RP2040 GPIO14/15 via 0Ω resistors — avoid using as standalone FPGA IO unless resistors are desoldered
- SPI config pins (3, 4, 5, 6) are dual-purpose: programming + IO bus
