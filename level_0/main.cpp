#include <Arduino.h>
#include <EEPROM.h>
#include <Shrike.h>

ShrikeFlash fpga;

void setup() {
  delay(2000);
  Serial.begin(115200);
  while (!Serial) {
    delay(10);
  }

  Serial.println("Shrike Flash Example");

  if (!fpga.begin()) {
    Serial.println("Initialization failed!");
    while (1) {
      Serial.println("FPGA is not running!");
    }
  }

  Serial.print("Flashing FPGA..");
  fpga.flash("/FPGA_bitstream_MCU.bin");
  Serial.println(" Done.");
}

void loop() {
  Serial.println("FPGA is running!");
  delay(1000);
}
