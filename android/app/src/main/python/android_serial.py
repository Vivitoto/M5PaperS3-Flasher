import time

from java import jclass
from serial.serialutil import PortNotOpenError, SerialBase, SerialException
from serial.tools import list_ports_common


UsbSerialPort = None
UsbSerialProber = None
UnsupportedOperationException = None


def _load_java_classes():
    global UsbSerialPort, UsbSerialProber, UnsupportedOperationException
    if UsbSerialPort is None:
        UsbSerialPort = jclass("com.hoho.android.usbserial.driver.UsbSerialPort")
    if UsbSerialProber is None:
        UsbSerialProber = jclass("com.hoho.android.usbserial.driver.UsbSerialProber")
    if UnsupportedOperationException is None:
        UnsupportedOperationException = jclass("java.lang.UnsupportedOperationException")


_android_context = None
_ESPRESSIF_VENDOR_ID = 0x303A
_ESPRESSIF_USB_SERIAL_JTAG_PID = 0x1001


def install_android_pyserial(context):
    global _android_context
    _android_context = context
    _load_java_classes()

    import serial
    from serial.tools import list_ports

    serial.Serial = AndroidSerial
    list_ports.comports = comports


def _get_android_context():
    if _android_context is None:
        raise SerialException("Android context is not initialized.")
    return _android_context


def _to_python_list(java_collection):
    if java_collection is None:
        return []
    if isinstance(java_collection, (list, tuple)):
        return list(java_collection)

    size = getattr(java_collection, "size", None)
    getter = getattr(java_collection, "get", None)
    if callable(size) and callable(getter):
        return [getter(index) for index in range(size())]

    iterator_factory = getattr(java_collection, "iterator", None)
    if callable(iterator_factory):
        iterator = iterator_factory()
        values = []
        while iterator.hasNext():
            values.append(iterator.next())
        return values

    to_array = getattr(java_collection, "toArray", None)
    if callable(to_array):
        java_array = to_array()
        try:
            return [java_array[index] for index in range(len(java_array))]
        except TypeError:
            pass

    try:
        return list(java_collection)
    except TypeError:
        return [java_collection]


def comports(include_links=False):
    del include_links
    context = _get_android_context()
    usb_manager = context.getSystemService(context.USB_SERVICE)
    device_list = usb_manager.getDeviceList()
    devices = []
    for device_key in _to_python_list(device_list.keySet()):
        usb_device = device_list.get(device_key)
        info = list_ports_common.ListPortInfo(usb_device.getDeviceName(), True)
        info.vid = usb_device.getVendorId()
        info.pid = usb_device.getProductId()
        info.manufacturer = usb_device.getManufacturerName()
        info.product = usb_device.getProductName()
        info.interface = usb_device.getInterface(0) if usb_device.getInterfaceCount() > 0 else None
        info.hwid = str(usb_device.getDeviceId())
        info.name = usb_device.getDeviceName()
        if info.product or info.manufacturer:
            info.apply_usb_info()
        devices.append(info)
    return devices


def _is_preferred_usb_device(usb_device):
    product_name = usb_device.getProductName() or ""
    normalized_product_name = product_name.lower()
    return (
        (
            usb_device.getVendorId() == _ESPRESSIF_VENDOR_ID
            and usb_device.getProductId() == _ESPRESSIF_USB_SERIAL_JTAG_PID
        )
        or "usb jtag" in normalized_product_name
        or "serial/jtag" in normalized_product_name
    )


class AndroidSerial(SerialBase):
    def __init__(self, *args, **kwargs):
        self.driver = None
        self.connection = None
        self.fd = None
        self._port_handle = None
        self._read_buffer = bytearray()
        super().__init__(*args, **kwargs)

    def open(self):
        if self._port is None:
            raise SerialException("Port must be configured before it can be used.")
        if self.is_open:
            raise SerialException("Port is already open.")

        _load_java_classes()
        context = _get_android_context()
        usb_manager = context.getSystemService(context.USB_SERVICE)
        drivers = _to_python_list(
            UsbSerialProber.getDefaultProber().findAllDrivers(usb_manager)
        )
        if not drivers:
            raise SerialException("No USB serial device found.")

        self.driver = None
        preferred_driver = None
        for candidate in drivers:
            candidate_device = candidate.getDevice()
            if candidate_device.getDeviceName() == self._port:
                self.driver = candidate
                break
            if preferred_driver is None and _is_preferred_usb_device(candidate_device):
                preferred_driver = candidate
        if self.driver is None:
            available_ports = ", ".join(
                str(candidate.getDevice().getDeviceName()) for candidate in drivers
            )
            raise SerialException(
                "Selected USB device was not found: %s. Available devices: %s"
                % (self._port, available_ports or "none")
            )

        if not usb_manager.hasPermission(self.driver.getDevice()):
            raise SerialException(
                "USB permission is not granted for device %s. Please reconnect the device and allow Vink Flasher access."
                % self.driver.getDevice().getDeviceName()
            )

        self.connection = usb_manager.openDevice(self.driver.getDevice())
        if self.connection is None:
            raise SerialException("Could not open connection to device. USB permission may not be granted.")

        self.fd = self.connection.getFileDescriptor()
        self._port_handle = self.driver.getPorts().get(0)
        self._port_handle.open(self.connection)
        self._reconfigure_port()
        self.is_open = True

    def _reconfigure_port(self):
        if not self._port_handle:
            raise SerialException("Can only operate on a valid port handle")

        if self._bytesize == 5:
            data_bits = UsbSerialPort.DATABITS_5
        elif self._bytesize == 6:
            data_bits = UsbSerialPort.DATABITS_6
        elif self._bytesize == 7:
            data_bits = UsbSerialPort.DATABITS_7
        elif self._bytesize == 8:
            data_bits = UsbSerialPort.DATABITS_8
        else:
            raise ValueError("unsupported bytesize: %r" % self._bytesize)

        if self._stopbits == 1:
            stop_bits = UsbSerialPort.STOPBITS_1
        elif self._stopbits == 1.5:
            stop_bits = UsbSerialPort.STOPBITS_1_5
        elif self._stopbits == 2:
            stop_bits = UsbSerialPort.STOPBITS_2
        else:
            raise ValueError("unsupported number of stopbits: %r" % self._stopbits)

        if self._parity == 'N':
            parity = UsbSerialPort.PARITY_NONE
        elif self._parity == 'E':
            parity = UsbSerialPort.PARITY_EVEN
        elif self._parity == 'O':
            parity = UsbSerialPort.PARITY_ODD
        elif self._parity == 'M':
            parity = UsbSerialPort.PARITY_MARK
        elif self._parity == 'S':
            parity = UsbSerialPort.PARITY_SPACE
        else:
            raise ValueError("unsupported parity type: %r" % self._parity)

        self._port_handle.setParameters(self._baudrate, data_bits, stop_bits, parity)
        # ESP32-S3 USB Serial/JTAG idle state is DTR=False, RTS=False.
        # Starting with both asserted can leave the chip held in/near reset on
        # some Android USB stacks before esptool gets to run its reset sequence.
        self._port_handle.setDTR(False)
        self._port_handle.setRTS(False)

    def _update_rts_state(self):
        if not self._port_handle:
            raise SerialException("Port not open")
        self._port_handle.setRTS(bool(self._rts_state))

    def _update_dtr_state(self):
        if not self._port_handle:
            raise SerialException("Port not open")
        self._port_handle.setDTR(bool(self._dtr_state))

    def close(self):
        if self._port_handle:
            try:
                self._port_handle.setDTR(False)
                self._port_handle.setRTS(False)
            except Exception:
                pass
            self._port_handle.close()
        if self.connection:
            self.connection.close()
        self.driver = None
        self.connection = None
        self.fd = None
        self._port_handle = None
        self._read_buffer.clear()
        self.is_open = False

    def read(self, size=16 * 1024):
        if not self._port_handle:
            raise SerialException("Port not open")
        if size is None or size < 0:
            size = 16 * 1024
        if size == 0:
            return b""

        if len(self._read_buffer) >= size:
            result = bytes(self._read_buffer[:size])
            del self._read_buffer[:size]
            return result

        # usb-serial-for-android may throw "Read buffer too small" for tiny
        # reads. esptool often reads one byte while syncing, so always read into
        # a reasonably large native buffer and then return exactly the requested
        # amount via this pySerial-compatible staging buffer.
        native_buffer_size = max(size, 16 * 1024)
        data = bytearray(native_buffer_size)
        timeout = int(self._timeout * 1000) if self._timeout is not None else 0
        num_bytes_read = self._port_handle.read(data, timeout)
        if num_bytes_read <= 0:
            return b""

        self._read_buffer.extend(data[:num_bytes_read])
        result = bytes(self._read_buffer[:size])
        del self._read_buffer[:size]
        return result

    def write(self, data):
        if not self._port_handle:
            raise SerialException("Port not open")
        if not isinstance(data, (bytes, bytearray)):
            raise TypeError("expected bytes or bytearray, got %s" % type(data))
        timeout = int(self._write_timeout * 1000) if self._write_timeout is not None else 0
        self._port_handle.write(data, timeout)
        return len(data)

    def reset_input_buffer(self):
        if not self._port_handle:
            raise SerialException("Port not open")
        self._read_buffer.clear()
        try:
            self._port_handle.purgeHwBuffers(True, False)
        except UnsupportedOperationException:
            pass

    def reset_output_buffer(self):
        if not self._port_handle:
            raise SerialException("Port not open")
        try:
            self._port_handle.purgeHwBuffers(False, True)
        except UnsupportedOperationException:
            pass

    def send_break(self, duration=0.25):
        if not self._port_handle:
            raise SerialException("Port not open")
        self._port_handle.setBreak(True)
        time.sleep(duration)
        self._port_handle.setBreak(False)

    def fileno(self):
        if not self.is_open:
            raise PortNotOpenError()
        return self.fd

    @property
    def in_waiting(self):
        return 0

    @property
    def cts(self):
        if not self._port_handle:
            raise SerialException("Port not open")
        return self._port_handle.getCTS()

    @property
    def dsr(self):
        if not self._port_handle:
            raise SerialException("Port not open")
        return self._port_handle.getDSR()

    @property
    def ri(self):
        if not self._port_handle:
            raise SerialException("Port not open")
        return self._port_handle.getRI()

    @property
    def cd(self):
        if not self._port_handle:
            raise SerialException("Port not open")
        return self._port_handle.getCD()
