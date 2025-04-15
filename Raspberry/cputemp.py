#!/usr/bin/python3

import dbus
import time
from threading import Thread

from advertisement import Advertisement
from service import Application, Service, Characteristic, Descriptor
from gpiozero import CPUTemperature, MotionSensor

from funcs import load_config , update_config
inactivity_timeout = load_config().get("inactivity_timeout", 10)
GATT_CHRC_IFACE = "org.bluez.GattCharacteristic1"
NOTIFY_TIMEOUT = 5000

class ThermometerAdvertisement(Advertisement):
    def __init__(self, index):
        Advertisement.__init__(self, index, "peripheral")
        self.add_local_name("MotionSensor")
        self.include_tx_power = True

class ThermometerService(Service):
    THERMOMETER_SVC_UUID = "00000001-710e-4a5b-8d75-3e5b444bc3cf"

    def __init__(self, index):
        super().__init__(index, self.THERMOMETER_SVC_UUID, True)
        self.farenheit = False
        self.temp_char = TempCharacteristic(self)
        self.motion_char = MotionCharacteristic(self)
        self.time_char = TimeCharacteristic(self)
        self.add_characteristic(self.temp_char)
        self.add_characteristic(UnitCharacteristic(self))
        self.add_characteristic(self.motion_char)
        self.add_characteristic(self.time_char)


    def is_farenheit(self):
        return self.farenheit

    def set_farenheit(self, farenheit):
        self.farenheit = farenheit

class TempCharacteristic(Characteristic):
    UUID = "4b05770d-da92-4599-bacf-1332697f3bd7"

    def __init__(self, service):
        super().__init__(self.UUID, ["notify", "read"], service)
        self.notifying = False
        self.add_descriptor(TempDescriptor(self))

    def get_temperature(self):
        value = []
        unit = "C"
        cpu = CPUTemperature()
        temp = cpu.temperature
        if self.service.is_farenheit():
            temp = (temp * 1.8) + 32
            unit = "F"
        strtemp = str(round(temp, 1)) + " " + unit
        for c in strtemp:
            value.append(dbus.Byte(c.encode()))
        return value

    def notify_temp(self):
        if self.notifying:
            value = self.get_temperature()
            self.PropertiesChanged(GATT_CHRC_IFACE, {"Value": value}, [])
        return self.notifying

    def StartNotify(self):
        if self.notifying:
            return
        self.notifying = True
        self.add_timeout(NOTIFY_TIMEOUT, self.notify_temp)

    def StopNotify(self):
        self.notifying = False

    def ReadValue(self, options):
        return self.get_temperature()

class TempDescriptor(Descriptor):
    def __init__(self, characteristic):
        super().__init__("2901", ["read"], characteristic)
    def ReadValue(self, options):
        return [dbus.Byte(c.encode()) for c in "CPU Temperature"]

class MotionCharacteristic(Characteristic):
    UUID = "e95d9250-251d-470a-a062-fa1922dfa9a8"

    def __init__(self, service):
        super().__init__(self.UUID, ["notify"], service)
        self.notifying = False
        self.motion_state = ""
        self.add_descriptor(MotionDescriptor(self))

    def update_motion(self, text):
        self.motion_state = text
        if self.notifying:
            self.notify()

    def notify(self):
        value = [dbus.Byte(b) for b in self.motion_state.encode()]
        self.PropertiesChanged(GATT_CHRC_IFACE, {"Value": value}, [])

    def StartNotify(self):
        self.notifying = True

    def StopNotify(self):
        self.notifying = False

class MotionDescriptor(Descriptor):
    def __init__(self, characteristic):
        super().__init__("2901", ["read"], characteristic)
    def ReadValue(self, options):
        return [dbus.Byte(c.encode()) for c in "Motion status"]

class UnitCharacteristic(Characteristic):
    UUID = "00000003-710e-4a5b-8d75-3e5b444bc3cf"

    def __init__(self, service):
        super().__init__(self.UUID, ["read", "write"], service)
        self.add_descriptor(UnitDescriptor(self))

    def WriteValue(self, value, options):
        val = str(value[0]).upper()
        if val == "C":
            self.service.set_farenheit(False)
        elif val == "F":
            self.service.set_farenheit(True)

    def ReadValue(self, options):
        val = "F" if self.service.is_farenheit() else "C"
        return [dbus.Byte(val.encode())]

class UnitDescriptor(Descriptor):
    def __init__(self, characteristic):
        super().__init__("2901", ["read"], characteristic)
    def ReadValue(self, options):
        return [dbus.Byte(c.encode()) for c in "Temperature Units (F or C)"]

class TimeCharacteristic(Characteristic):
    UUID = "00000005-710e-4a5b-8d75-3e5b444bc3cf"

    def __init__(self, service):
        super().__init__(self.UUID, ["write", "write-without-response"], service)
        self.add_descriptor(TimeDescriptor(self))

    def WriteValue(self, value, options):
        global inactivity_timeout
        try:
            text = ''.join([chr(byte) for byte in value])
            seconds = round(float(text))
            inactivity_timeout = seconds
            update_config("inactivity_timeout", seconds)
            print(f"⏱ Noul timp de inactiune: {inactivity_timeout} secunde")

        except Exception as e:
            print(f"❌ Erroare cand sa primit timpul: {e}")
    

class TimeDescriptor(Descriptor):
    def __init__(self, characteristic):
        super().__init__("2901", ["read"], characteristic)

    def ReadValue(self, options):
        return [dbus.Byte(c.encode()) for c in "Inactivity Time (sec)"]


def motion_loop(motion_char):
    pir = MotionSensor(4)
    no_motion_start = None

    while True:
        if pir.motion_detected:
            print("👀 actiune")
            motion_char.update_motion("👀 actiune")
            no_motion_start = None
        else:
            if no_motion_start is None:
                no_motion_start = time.time()
            elif time.time() - no_motion_start >= inactivity_timeout:
                print("🔔 nu sunt miscari")
                motion_char.update_motion("🔔 Nu sunt miscari")
                no_motion_start = None
        time.sleep(1)

app = Application()
svc = ThermometerService(0)
app.add_service(svc)
app.register()

adv = ThermometerAdvertisement(0)
adv.register()

motion_thread = Thread(target=motion_loop, args=(svc.motion_char,), daemon=True)
motion_thread.start()

try:
    app.run()
except KeyboardInterrupt:
    app.quit()
