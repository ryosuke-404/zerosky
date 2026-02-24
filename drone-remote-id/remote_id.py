import subprocess
import time

def start_ibeacon():
    uuid = "11223344556677889900AABBCCDDEEFF"
    major = "0001"
    minor = "0001"
    tx_power = "C5"
    prefix = "1A FF 4C 00 02 15"
    payload = prefix + " " + " ".join(uuid[i:i+2] for i in range(0, len(uuid), 2))
    payload += f" {major[:2]} {major[2:]} {minor[:2]} {minor[2:]} {tx_power}"
    subprocess.run(f"sudo hcitool -i hci0 cmd 0x08 0x0008 {payload}", shell=True)
    subprocess.run("sudo hciconfig hci0 leadv 3", shell=True)
    print(" iBeacon advertising started.")

def start_eddystone():
    namespace = "11223344556677889900"
    instance  = "AABBCCDDEEFF"
    tx_power = "C5"
    payload = "02 01 06 03 03 AA FE 17 16 AA FE 00 " + tx_power + " "
    payload += " ".join(namespace[i:i+2] for i in range(0, len(namespace), 2)) + " "
    payload += " ".join(instance[i:i+2] for i in range(0, len(instance), 2)) + " 00 00"
    subprocess.run(f"sudo hcitool -i hci0 cmd 0x08 0x0008 {payload}", shell=True)
    subprocess.run("sudo hciconfig hci0 leadv 3", shell=True)
    print(" Eddystone UID advertising started.")

def start_custom_service():
    service_uuid = "1234"  # 16-bit custom UUID
    data = "DE AD BE EF 01 02 03 04"
    payload = f"02 01 06 03 03 {service_uuid} {data}"
    subprocess.run(f"sudo hcitool -i hci0 cmd 0x08 0x0008 {payload}", shell=True)
    subprocess.run("sudo hciconfig hci0 leadv 3", shell=True)
    print(" Custom Service advertising started.")

# -----------------------------
# Start all three
# -----------------------------
start_ibeacon()
start_eddystone()
start_custom_service()

try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    subprocess.run("sudo hciconfig hci0 noleadv", shell=True)
    print(" Advertising stopped.")
