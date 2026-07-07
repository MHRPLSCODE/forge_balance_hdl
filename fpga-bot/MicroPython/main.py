import time
import shrike
import config
from spi_master import FPGALink
from imu import MPU6050
from pid import PIDController

def pid_to_motor(pid_output):
    magnitude = abs(pid_output)
    if magnitude < config.MOTOR_DEAD_ZONE:
        return config.STEP_LIMIT_MAX, 0
    direction = 1 if pid_output > 0 else 0
    magnitude = min(magnitude, config.PID_OUTPUT_MAX)
    range_in = config.PID_OUTPUT_MAX - config.MOTOR_DEAD_ZONE
    range_out = config.STEP_LIMIT_MAX - config.STEP_LIMIT_MIN
    if range_in > 0:
        step_limit = config.STEP_LIMIT_MAX - int(
            (magnitude - config.MOTOR_DEAD_ZONE) * range_out / range_in
        )
    else:
        step_limit = config.STEP_LIMIT_MAX
    step_limit = max(config.STEP_LIMIT_MIN, min(step_limit, config.STEP_LIMIT_MAX))
    return step_limit, direction

def main():
    print("FPGA Balance Bot — Starting Up")
    print("Flashing FPGA...")
    shrike.reset()
    shrike.flash(config.BITSTREAM_FILE)
    time.sleep_ms(200)

    fpga = FPGALink()
    imu = MPU6050()
    pid = PIDController()

    print("Calibrating IMU — hold robot still and upright!")
    time.sleep(2)
    imu.calibrate()

    print("Starting balance loop...")
    fpga.stop_motors()
    loop_count = 0
    loop_start = time.ticks_ms()

    try:
        while True:
            iter_start = time.ticks_us()
            tilt_angle = imu.get_tilt_angle()
            pid_output = pid.compute(tilt_angle)
            step_limit, direction = pid_to_motor(pid_output)
            current_limit, kill_status = fpga.transfer(step_limit, direction)

            loop_count += 1
            if config.DEBUG_PRINT and (loop_count % config.DEBUG_INTERVAL == 0):
                elapsed = time.ticks_diff(time.ticks_ms(), loop_start)
                actual_freq = (loop_count * 1000) / elapsed if elapsed > 0 else 0
                print(
                    f"angle={tilt_angle:+6.1f} "
                    f"pid={pid_output:+7.0f} "
                    f"step={step_limit:6d} "
                    f"dir={direction} "
                    f"cur={current_limit:6d} "
                    f"kill={kill_status} "
                    f"freq={actual_freq:.0f}Hz"
                )

            iter_time_us = time.ticks_diff(time.ticks_us(), iter_start)
            sleep_us = (config.LOOP_PERIOD_MS * 1000) - iter_time_us
            if sleep_us > 0:
                time.sleep_us(sleep_us)

    except KeyboardInterrupt:
        fpga.emergency_stop()
        print("Motors safe.")

def test_spi():
    print("SPI test mode")
    shrike.reset()
    shrike.flash(config.BITSTREAM_FILE)
    time.sleep_ms(200)
    fpga = FPGALink()
    for i in range(100):
        cur, kill = fpga.transfer(10000, 1)
        if i % 10 == 0:
            print(f"  cur={cur}, kill={kill}")
        time.sleep_ms(50)
    fpga.stop_motors()
    print("SPI test done.")

def test_imu():
    print("IMU test mode")
    imu = MPU6050()
    imu.calibrate()
    try:
        while True:
            angle = imu.get_tilt_angle()
            print(f"angle={angle:+6.1f}")
            time.sleep_ms(50)
    except KeyboardInterrupt:
        print("IMU test done.")

def test_motor_sweep():
    print("Motor sweep test")
    shrike.reset()
    shrike.flash(config.BITSTREAM_FILE)
    time.sleep_ms(200)
    fpga = FPGALink()
    print("Speeding up...")
    for step in range(50000, 1000, -500):
        fpga.transfer(step, 1)
        time.sleep_ms(50)
    time.sleep(1)
    print("Slowing down...")
    for step in range(1000, 50000, 500):
        fpga.transfer(step, 1)
        time.sleep_ms(50)
    fpga.stop_motors()
    print("Motor sweep done.")

if __name__ == "__main__":
    main()
