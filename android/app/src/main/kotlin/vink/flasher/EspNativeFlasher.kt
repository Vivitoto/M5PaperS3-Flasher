package vink.flasher

import android.content.Context
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max
import kotlin.math.min

/**
 * Native ESP32 flashing engine for any ESP32 chip family.
 * Replaces the PaperS3-specific flasher with a generic implementation.
 *
 * Protocol reference: ESP32 ROM Serial Communication Protocol
 * https://github.com/espressif/esptool/blob/master/docs/en/esptool/serial-protocol.md
 */
class EspNativeFlasher(
    private val context: Context,
    private val shouldCancel: () -> Boolean,
    private val emitLog: (String) -> Unit,
    private val emitProgress: (Map<String, Any>) -> Unit,
) {
    private companion object {
        // SLIP framing
        const val SLIP_FRAME = 0xC0.toByte()
        const val SLIP_ESC = 0xDB.toByte()
        const val SLIP_ESC_FRAME = 0xDC.toByte()
        const val SLIP_ESC_ESC = 0xDD.toByte()

        // ESP32 download mode commands
        const val CMD_SYNC = 0x08
        const val CMD_FLASH_BEGIN = 0x02
        const val CMD_FLASH_DATA = 0x03
        const val CMD_FLASH_END = 0x04
        const val CMD_SPI_SET_PARAMS = 0x0B
        const val CMD_SPI_ATTACH = 0x0D
        const val CMD_READ_FLASH_ID = 0x0F
        const val CMD_READ_MAC = 0x0F
        const val CMD_GET_CHIP_INFO = 0x0F
        const val CMD_CHECKSUM = 0x10
        const val CMD_FLASH_DEFL_BEGIN = 0x05
        const val CMD_FLASH_DEFL_DATA = 0x06
        const val CMD_FLASH_DEFL_END = 0x07

        // ESPRESSIF USB Vendor ID
        const val ESPRESSIF_VID = 0x303A

        // USB Serial JTAG PIDs that indicate ESP32 in download mode
        val ESP32S3_JTAG_PIDS = setOf(0x1001, 0x1002)
        val ESP32C6_USB_PIDS = setOf(0x1001, 0x1002, 0x1003)
        val ESP32H2_USB_PIDS = setOf(0x1001, 0x1002, 0x1003)

        // Block size: 0x400 (1024) is standard for ESP32; some chips use 0x800
        const val BLOCK_SIZE = 0x400
        const val READ_TIMEOUT_MS = 5000
        const val WRITE_TIMEOUT_MS = 5000
        const val PROGRESS_BLOCK_INTERVAL = 50
    }

    private var port: UsbSerialPort? = null
    private val rx = ArrayList<Byte>(8192)
    private var chipFamily = ChipFamily.UNKNOWN

    // ─── Public API ────────────────────────────────────────────────────────────

    /**
     * Flash a firmware file to the connected ESP32 device.
     *
     * @param deviceName   USB serial port device name (e.g. /dev/bus/usb/001/002)
     *                     Pass null for auto-detect.
     * @param profile      Device profile with chip family and flash offset defaults.
     * @param firmwarePath Path to the .bin file on local storage.
     * @param flashOffset  Flash address to write to (use profile.defaultFlashOffset.bytes as default).
     * @param baudRate     UART baud rate (use profile.defaultBaudRate as default).
     * @param reboot       Whether to reboot the device after flashing.
     */
    fun flash(
        deviceName: String?,
        profile: EspDeviceProfile,
        firmwarePath: String,
        flashOffset: Int = profile.defaultFlashOffset.bytes,
        baudRate: Int = profile.defaultBaudRate,
        reboot: Boolean = true,
    ) {
        val firmware = File(firmwarePath)
        require(firmware.exists()) { "固件文件不存在: $firmwarePath" }
        val bytes = firmware.readBytes()
        val started = System.currentTimeMillis()

        chipFamily = profile.chipFamily

        openPort(deviceName, baudRate)
        try {
            progress(0, bytes.size, 0.0, "连接芯片...")
            enterBootloader()
            sync()

            progress(0, bytes.size, 0.0, "读取芯片信息...")
            val chipInfo = getChipInfo()
            emitLog("芯片信息: $chipInfo")

            progress(0, bytes.size, 0.0, "初始化 SPI Flash")
            spiAttach()
            spiSetParams(chipInfo.flashSize)

            progress(0, bytes.size, 0.0, "开始写入固件")
            flashBegin(bytes.size, flashOffset)

            val block = ByteArray(BLOCK_SIZE)
            val blocks = (bytes.size + BLOCK_SIZE - 1) / BLOCK_SIZE
            var written = 0
            for (sequence in 0 until blocks) {
                if (shouldCancel()) throw InterruptedException("Flash cancelled by user")
                val chunkLength = min(BLOCK_SIZE, bytes.size - written)
                block.fill(0.toByte())
                System.arraycopy(bytes, written, block, 0, chunkLength)
                flashData(block, sequence)
                written += chunkLength

                if (sequence % PROGRESS_BLOCK_INTERVAL == 0 || sequence == blocks - 1) {
                    val elapsed = max(1L, System.currentTimeMillis() - started) / 1000.0
                    val label = if (flashOffset == 0) "正在刷写完整镜像" else "正在刷写固件"
                    progress(written, bytes.size, written / elapsed, label)
                }
            }

            flashEnd(reboot)
            if (reboot) {
                progress(bytes.size, bytes.size, 0.0, "正在重启设备")
                hardReset()
            }
            val doneMsg = if (reboot) "完成并重启" else "完成"
            progress(bytes.size, bytes.size, 0.0, "Done — $doneMsg")
            emitLog("Flashed ${bytes.size} bytes to offset 0x${Integer.toHexString(flashOffset)}")
        } finally {
            closePort()
        }
    }

    /**
     * Probe a connected device and return its chip info.
     * Call this before flash() to confirm the device is in download mode.
     */
    fun probeDevice(deviceName: String?, baudRate: Int = 921600): ProbedDeviceInfo {
        openPort(deviceName, baudRate)
        try {
            enterBootloader()
            sync()
            return getChipInfo()
        } finally {
            closePort()
        }
    }

    // ─── Port management ────────────────────────────────────────────────────────

    private fun openPort(deviceName: String?, baudRate: Int) {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
        require(drivers.isNotEmpty()) { "未发现 USB 串口设备" }

        val driver = drivers.firstOrNull { it.device.deviceName == deviceName }
            ?: drivers.firstOrNull { d ->
                // Prefer Espressif USB JTAG devices
                d.device.vendorId == ESPRESSIF_VID
            }
            ?: drivers.first()

        val device = driver.device
        require(usbManager.hasPermission(device)) {
            "没有 USB 权限，请先在系统弹窗中允许 Vink Flasher 访问设备"
        }
        val connection = usbManager.openDevice(device)
            ?: throw IllegalStateException("无法打开 USB 设备: ${device.deviceName}")

        val selectedPort = driver.ports.firstOrNull()
            ?: throw IllegalStateException("USB 设备没有可用串口: ${device.deviceName}")

        selectedPort.open(connection)
        selectedPort.setParameters(
            baudRate,
            UsbSerialPort.DATABITS_8,
            UsbSerialPort.STOPBITS_1,
            UsbSerialPort.PARITY_NONE,
        )
        selectedPort.setDTR(false)
        selectedPort.setRTS(false)
        port = selectedPort
        emitLog("USB serial opened at $baudRate baud: ${device.deviceName} (VID=${device.vendorId} PID=${device.productId})")
    }

    private fun closePort() {
        try {
            port?.close()
        } catch (_: Throwable) {
        } finally {
            port = null
            rx.clear()
        }
    }

    // ─── Bootloader reset ───────────────────────────────────────────────────────

    /**
     * Trigger download mode on ESP32.
     * Sequence: RTS↑ → DTR↑ → RTS↓ → DTR↓ (for CH340/CP210x auto-baud)
     */
    private fun enterBootloader() {
        val p = requirePort()
        p.setDTR(false)
        p.setRTS(true)
        Thread.sleep(100)
        p.setDTR(true)
        p.setRTS(false)
        Thread.sleep(500)
        p.setDTR(false)
        p.setRTS(false)
        Thread.sleep(100)
    }

    private fun hardReset() {
        val p = requirePort()
        p.setDTR(false)
        p.setRTS(false)
        Thread.sleep(100)
        p.setDTR(true)
        Thread.sleep(100)
        p.setDTR(false)
        Thread.sleep(500)
    }

    // ─── ESP32 protocol commands ───────────────────────────────────────────────

    private fun sync() {
        val payload = ByteArray(36)
        // The first 4 bytes are a "sync" magic; rest are 0x55
        payload[0] = 0x07
        payload[1] = 0x07
        payload[2] = 0x12
        payload[3] = 0x20
        for (i in 4 until payload.size) payload[i] = 0x55

        var lastError: Throwable? = null
        repeat(10) { attempt ->
            try {
                rx.clear()
                sendCommand(CMD_SYNC, payload)
                readCommandResponse(CMD_SYNC, 3000, checkStatus = false)
                rx.clear()
                emitLog("SYNC OK")
                return
            } catch (error: Throwable) {
                lastError = error
                Thread.sleep(100)
                emitLog("SYNC attempt ${attempt + 1} failed: ${error.message}")
            }
        }
        throw IllegalStateException("ESP32 下载模式同步失败: ${lastError?.message}", lastError)
    }

    private fun getChipInfo(): ProbedDeviceInfo {
        // Try the CHIP_INFO command (0x0F with different subcommand)
        val chipData = sendWithResponse(CMD_GET_CHIP_INFO, byteArrayOf(0x00), 3000)
        if (chipData.size >= 12) {
            val chipType = chipData[0].toInt() and 0xFF
            val chipRevision = chipData[1].toInt() and 0xFF
            val numCores = chipData[2].toInt() and 0xFF
            val cpuFreq = (chipData[3].toInt() and 0xFF) or
                ((chipData[4].toInt() and 0xFF) shl 8)
            val chipFamilyId = chipData[5].toInt() and 0xFF

            val family = when (chipFamilyId) {
                1 -> ChipFamily.ESP32
                2 -> ChipFamily.ESP32S2
                4 -> ChipFamily.ESP32S3
                5 -> ChipFamily.ESP32C2
                6 -> ChipFamily.ESP32C3
                7 -> ChipFamily.ESP32C6
                8 -> ChipFamily.ESP32H2
                9 -> ChipFamily.ESP32P4
                else -> ChipFamily.UNKNOWN
            }
            chipFamily = family

            // Read MAC address
            val macBytes = try {
                sendWithResponse(CMD_READ_MAC, byteArrayOf(0x04), 2000)
            } catch (_: Throwable) {
                byteArrayOf()
            }
            val mac = if (macBytes.size >= 6) {
                macBytes.take(6).joinToString(":") {
                    String.format("%02X", it.toInt() and 0xFF)
                }
            } else {
                "unknown"
            }

            // Read flash ID
            val flashSize = try {
                val flashIdData = sendWithResponse(CMD_READ_FLASH_ID, byteArrayOf(), 2000)
                if (flashIdData.size >= 4) {
                    // Flash size encoded in the response (JEDEC ID)
                    val flashId = (flashIdData[0].toInt() and 0xFF shl 16) or
                        (flashIdData[1].toInt() and 0xFF shl 8) or
                        (flashIdData[2].toInt() and 0xFF)
                    // Common flash sizes: 0x14=16MB, 0x13=8MB, 0x12=4MB, 0x11=2MB
                    when (flashIdData[2].toInt() and 0xFF) {
                        0x14 -> 16 * 1024L * 1024L
                        0x13 -> 8 * 1024L * 1024L
                        0x12 -> 4 * 1024L * 1024L
                        0x11 -> 2 * 1024L * 1024L
                        else -> family.defaultFlashSizeBytes
                    }
                } else {
                    family.defaultFlashSizeBytes
                }
            } catch (_: Throwable) {
                family.defaultFlashSizeBytes
            }

            val profile = EspDeviceProfile.fromVidPid(
                requirePort().let { port ->
                    port.javaClass.getDeclaredField("device")
                        .apply { isAccessible = true }
                        .let { field -> (field.get(port) as? com.hoho.android.usbserial.driver.UsbSerialDriver)?.device }
                        ?.vendorId ?: ESPRESSIF_VID
                },
                requirePort().let { port ->
                    port.javaClass.getDeclaredField("device")
                        .apply { isAccessible = true }
                        .let { field -> (field.get(port) as? com.hoho.android.usbserial.driver.UsbSerialDriver)?.device }
                        ?.productId ?: 0x1001
                }
            )

            return ProbedDeviceInfo(
                chipFamily = family,
                chipRevision = chipRevision,
                flashSize = flashSize,
                macAddress = mac,
                profile = profile,
                rawDescription = "ESP32 family=0x${Integer.toHexString(chipFamilyId)} " +
                    "revision=$chipRevision cores=$numCores freq=${cpuFreq}MHz",
            )
        }

        // Fallback: probe via MAC read
        chipFamily = ChipFamily.ESP32S3 // assume S3 if PaperS3 is common
        return ProbedDeviceInfo(
            chipFamily = chipFamily,
            chipRevision = 0,
            flashSize = chipFamily.defaultFlashSizeBytes,
            macAddress = "unknown",
            profile = EspDeviceProfile.PAPER_S3,
            rawDescription = "Probe fallback — assuming ESP32-S3",
        )
    }

    private fun spiAttach() {
        sendCommand(CMD_SPI_ATTACH, ByteArray(8))
        readCommandResponse(CMD_SPI_ATTACH, READ_TIMEOUT_MS, checkStatus = false)
    }

    private fun spiSetParams(flashSizeBytes: Long) {
        val out = ByteArrayOutputStream()
        // flash_size (4B), block_size (4B), sector_size (4B), page_size (4B), status_mask (4B)
        out.u32(0) // starting address
        out.u32((flashSizeBytes and 0xFFFFFFFF).toInt())
        out.u32(0x10000) // block size = 64KB
        out.u32(0x1000)  // sector size = 4KB
        out.u32(0x100)   // page size = 256B
        out.u32(0xFFFF)  // status mask
        sendCommand(CMD_SPI_SET_PARAMS, out.toByteArray())
        readCommandResponse(CMD_SPI_SET_PARAMS, READ_TIMEOUT_MS, checkStatus = false)
    }

    private fun flashBegin(size: Int, offset: Int) {
        val blocks = (size + BLOCK_SIZE - 1) / BLOCK_SIZE
        // Erase size: aligned to 4KB sectors
        val eraseSize = ((size + 0xFFF) / 0x1000) * 0x1000
        val out = ByteArrayOutputStream()
        out.u32(eraseSize)
        out.u32(blocks)
        out.u32(BLOCK_SIZE)
        out.u32(offset)
        out.u32(0) // encryption flag: false

        val timeoutMs = max(5000, ((eraseSize * 1000L) / 175000L).toInt() + 15000)
        var lastError: Throwable? = null
        repeat(3) { attempt ->
            try {
                rx.clear()
                sendCommand(CMD_FLASH_BEGIN, out.toByteArray())
                readCommandResponse(CMD_FLASH_BEGIN, timeoutMs)
                emitLog("FLASH_BEGIN OK — $blocks blocks to erase=$eraseSize")
                return
            } catch (error: Throwable) {
                lastError = error
                emitLog("FLASH_BEGIN attempt ${attempt + 1} failed: ${error.message}")
                if (attempt < 2) {
                    drainResponses(10_000)
                    rx.clear()
                }
            }
        }
        throw IllegalStateException("FLASH_BEGIN failed after 3 attempts: ${lastError?.message}", lastError)
    }

    private fun flashData(block: ByteArray, sequence: Int) {
        val out = ByteArrayOutputStream(BLOCK_SIZE + 16)
        out.u32(block.size)
        out.u32(sequence)
        out.u32(0) // zero (data_size in SPI attach mode)
        out.u32(0) // zero (block_size in SPI attach mode)
        out.write(block)
        sendCommand(CMD_FLASH_DATA, out.toByteArray(), checksum(block))
        readCommandResponse(CMD_FLASH_DATA, READ_TIMEOUT_MS)
    }

    private fun flashEnd(reboot: Boolean) {
        val out = ByteArrayOutputStream(4)
        out.u32(if (reboot) 0 else 1)
        sendCommand(CMD_FLASH_END, out.toByteArray())
        readCommandResponse(CMD_FLASH_END, READ_TIMEOUT_MS)
    }

    // ─── Low-level SLIP protocol ────────────────────────────────────────────────

    private fun sendCommand(command: Int, data: ByteArray, checksum: Int = 0) {
        val out = ByteArrayOutputStream(data.size + 8)
        out.write(0x00)             // direction: host→device
        out.write(command)
        out.u16(data.size)
        out.u32(checksum)
        out.write(data)
        val encoded = slipEncode(out.toByteArray())
        requirePort().write(encoded, WRITE_TIMEOUT_MS)
    }

    private fun sendWithResponse(command: Int, data: ByteArray, timeoutMs: Int): ByteArray {
        sendCommand(command, data)
        return readCommandResponse(command, timeoutMs)
    }

    private fun readCommandResponse(
        command: Int,
        timeoutMs: Int,
        checkStatus: Boolean = true,
    ): ByteArray {
        repeat(100) {
            val packet = readSlipPacket(timeoutMs)
            if (packet.size < 8) return@repeat
            val response = packet[0].toInt() and 0xFF
            val op = packet[1].toInt() and 0xFF
            if (response != 0x01 || op != command) return@repeat
            val dataLength = (packet[2].toInt() and 0xFF) or ((packet[3].toInt() and 0xFF) shl 8)
            val value = (packet[4].toInt() and 0xFF) or
                ((packet[5].toInt() and 0xFF) shl 8) or
                ((packet[6].toInt() and 0xFF) shl 16) or
                ((packet[7].toInt() and 0xFF) shl 24)
            if (packet.size < 8 + dataLength) {
                throw IllegalStateException(
                    "ESP32 响应长度异常: command=0x${command.toString(16)}"
                )
            }
            if (checkStatus && value != 0) {
                throw IllegalStateException(
                    "ESP32 拒绝命令: command=0x${command.toString(16)}, value=$value"
                )
            }
            return packet.copyOfRange(8, 8 + dataLength)
        }
        throw java.util.concurrent.TimeoutException(
            "ESP32 未响应命令: 0x${command.toString(16)}"
        )
    }

    private fun readSlipPacket(timeoutMs: Int): ByteArray {
        val deadline = System.currentTimeMillis() + timeoutMs
        val temp = ByteArray(4096)
        while (System.currentTimeMillis() < deadline) {
            val end = rx.indexOf(SLIP_FRAME)
            if (end >= 0) {
                val raw = rx.subList(0, end + 1).toByteArray()
                rx.subList(0, end + 1).clear()
                val decoded = slipDecode(raw)
                if (decoded.isNotEmpty()) return decoded
                continue
            }
            val read = requirePort().read(temp, 20)
            if (read > 0) {
                for (i in 0 until read) rx.add(temp[i])
            }
        }
        throw java.util.concurrent.TimeoutException("Timed out waiting for ESP32 response")
    }

    private fun drainResponses(durationMs: Long) {
        val until = System.currentTimeMillis() + durationMs
        while (System.currentTimeMillis() < until) {
            try {
                readSlipPacket(250)
            } catch (_: Throwable) {
                // keep draining
            }
        }
    }

    private fun slipEncode(packet: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(packet.size + 2)
        out.write(SLIP_FRAME.toInt())
        for (b in packet) {
            when (b.toInt() and 0xFF) {
                0xC0 -> {
                    out.write(SLIP_ESC.toInt())
                    out.write(SLIP_ESC_FRAME.toInt())
                }
                0xDB -> {
                    out.write(SLIP_ESC.toInt())
                    out.write(SLIP_ESC_ESC.toInt())
                }
                else -> out.write(b.toInt())
            }
        }
        out.write(SLIP_FRAME.toInt())
        return out.toByteArray()
    }

    private fun slipDecode(packet: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(packet.size)
        var i = 0
        while (i < packet.size) {
            val b = packet[i].toInt() and 0xFF
            when {
                b == 0xC0 -> Unit
                b == 0xDB && i + 1 < packet.size -> {
                    val next = packet[++i].toInt() and 0xFF
                    when (next) {
                        0xDC -> out.write(0xC0)
                        0xDD -> out.write(0xDB)
                        else -> out.write(next)
                    }
                }
                else -> out.write(b)
            }
            i++
        }
        return out.toByteArray()
    }

    /** ESP32 flasher checksum: starting from 0xEF, XOR each byte */
    private fun checksum(data: ByteArray): Int {
        var value = 0xEF
        for (b in data) value = value xor (b.toInt() and 0xFF)
        return value
    }

    // ─── Helpers ────────────────────────────────────────────────────────────────

    private fun progress(written: Int, total: Int, speed: Double, stage: String) {
        emitProgress(
            mapOf(
                "writtenBytes" to written,
                "totalBytes" to total,
                "speedBytesPerSecond" to speed,
                "stage" to stage,
            )
        )
    }

    private fun requirePort(): UsbSerialPort =
        port ?: throw IllegalStateException("USB serial port is not open")

    private fun ByteArrayOutputStream.u16(value: Int) {
        write(value and 0xFF)
        write((value ushr 8) and 0xFF)
    }

    private fun ByteArrayOutputStream.u32(value: Int) {
        write(value and 0xFF)
        write((value ushr 8) and 0xFF)
        write((value ushr 16) and 0xFF)
        write((value ushr 24) and 0xFF)
    }
}
