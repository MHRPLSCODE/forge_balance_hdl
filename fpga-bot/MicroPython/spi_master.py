# spi_master.py — SPI Master for RP2040 ↔ FPGA communication
#
# Sends 24-bit commands to the FPGA SPI slave and receives
# 24 bits of sensor data back simultaneously (full-duplex).
#
# MOSI format (RP2040 → FPGA):
#   [23:4]  = target_limit (20 bits)
#   [3]     = direction (1 bit)
#   [2:0]   = reserved (3 bits)
#
# MISO format (FPGA → RP2040):
#   [23:8]  = encoder_count (16 bits)
#   [7]     = encoder_dir (1 bit)
#   [6]     = stall_flag (1 bit)
#   [5:0]   = reserved (6 bits)

from machine import Pin, SPI
import config


class FPGALink:
    def __init__(self):
        # Initialize SPI master
        self.spi = SPI(
            config.SPI_ID,
            baudrate=config.SPI_BAUDRATE,
            polarity=config.SPI_POLARITY,
            phase=config.SPI_PHASE,
            bits=8,
            firstbit=SPI.MSB,
            sck=Pin(config.SPI_SCK_PIN),
            mosi=Pin(config.SPI_MOSI_PIN),
            miso=Pin(config.SPI_MISO_PIN)
        )

        # Chip select — active low, manually controlled
        self.cs = Pin(config.SPI_CS_PIN, Pin.OUT, value=1)

        # Buffers for 3-byte (24-bit) transfers
        self.tx_buf = bytearray(3)
        self.rx_buf = bytearray(3)

    def transfer(self, target_limit, direction):
        """
        Send a speed command to the FPGA and read back sensor data.

        Args:
            target_limit: 20-bit unsigned int (0-1048575)
                         Larger = slower motor, smaller = faster
            direction:   0 or 1 (motor spin direction)

        Returns:
            tuple: (encoder_count, encoder_dir, stall_flag)
                   encoder_count: 16-bit unsigned position count
                   encoder_dir:   0 or 1
                   stall_flag:    0 or 1
        """
        # Clamp target_limit to 20 bits
        target_limit = max(0, min(target_limit, 0xFFFFF))

        # Pack MOSI: [23:4] = target_limit, [3] = direction, [2:0] = 0
        packed = (target_limit << 4) | ((direction & 1) << 3)

        self.tx_buf[0] = (packed >> 16) & 0xFF  # bits [23:16]
        self.tx_buf[1] = (packed >> 8) & 0xFF   # bits [15:8]
        self.tx_buf[2] = packed & 0xFF           # bits [7:0]

        # Perform SPI transaction
        self.cs.value(0)                         # select FPGA
        self.spi.write_readinto(self.tx_buf, self.rx_buf)
        self.cs.value(1)                         # deselect FPGA

        # Unpack MISO: [23:8] = encoder_count, [7] = dir, [6] = stall
        raw = (self.rx_buf[0] << 16) | (self.rx_buf[1] << 8) | self.rx_buf[2]

        encoder_count = (raw >> 8) & 0xFFFF      # bits [23:8]
        encoder_dir = (raw >> 7) & 1              # bit [7]
        stall_flag = (raw >> 6) & 1               # bit [6]

        return encoder_count, encoder_dir, stall_flag

    def stop_motors(self):
        """Send maximum step_limit (slowest speed = effectively stopped)."""
        self.transfer(config.STEP_LIMIT_MAX, 0)

    def emergency_stop(self):
        """Send stop command multiple times to ensure delivery."""
        for _ in range(5):
            self.stop_motors()
