package vink.flasher

import android.content.Context
import android.hardware.usb.UsbManager
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max
import kotlin.math.min

class PaperS3NativeFlasher(
    private val context: Context,
    private val shouldCancel: () -> Boolean,
    private val emitLog: (String) -> Unit,
    private val emitProgress: (Map<String, Any>) -> Unit,
) {
    private companion object {
        const val ESPRESSIF_VID = 0x303A
        const val ESPRESSIF_USB_SERIAL_JTAG_PID = 0x1001

        const val SYNC = 0x08
        const val FLASH_BEGIN = 0x02
        const val FLASH_DATA = 0x03
        const val FLASH_END = 0x04
        const val SPI_SET_PARAMS = 0x0B
        const val SPI_ATTACH = 0x0D

        const val BLOCK_SIZE = 0x400
        const val SECTOR_SIZE = 0x1000
        const val READ_TIMEOUT_MS = 5000
        const val WRITE_TIMEOUT_MS = 5000
        const val PROGRESS_BLOCK_INTERVAL = 50 // match 0xFlash log cadence, about 50KB
    }

    private data class FlashRange(val start: Int, val endExclusive: Int) {
        val size: Int get() = endExclusive - start
    }

    private var port: UsbSerialPort? = null
    private val rx = ArrayList<Byte>(8192)

    fun flash(
        deviceName: String?,
        firmwarePath: String,
        flashOffset: Int,
        baudRate: Int,
        reboot: Boolean,
        cleanWrite: Boolean = false,
    ) {
        val firmware = File(firmwarePath)
        require(firmware.exists()) { "固件文件不存在: $firmwarePath" }
        val bytes = firmware.readBytes()

        openPort(deviceName, baudRate)
        try {
            progress(0, bytes.size, 0.0, "Connecting bootloader / 连接引导模式")
            enterBootloader()
            sync()

            progress(0, bytes.size, 0.0, "初始化 SPI Flash 参数")
            spiAttach()
            spiSetParams()

            progress(0, bytes.size, 0.0, "开始写入固件")
            // Reset the speed window once the real flash phase begins; everything
            // above (bootloader handshake, sync, SPI attach, SPI params, erase
            // setup) is fixed overhead and should not deflate the displayed rate.
            val flashPhaseStart = System.currentTimeMillis()
            val speedWindow = SpeedWindow()
            if (cleanWrite) {
                emitLog("Clean write: writing the whole ${bytes.size} byte image")
                writeRange(bytes, 0, bytes.size, flashOffset, flashPhaseStart, speedWindow, bytes.size, "正在彻底刷写完整镜像")
            } else {
                val ranges = findNonBlankSectorRanges(bytes)
                val bytesToWrite = ranges.sumOf { it.size }
                emitLog("Fast write: ${ranges.size} non-blank ranges, $bytesToWrite/${bytes.size} bytes to transfer")
                for (range in ranges) {
                    if (shouldCancel()) throw InterruptedException("Flash cancelled by user")
                    emitLog("Fast write range: 0x${(flashOffset + range.start).toString(16)} + ${range.size} bytes")
                    writeRange(bytes, range.start, range.endExclusive, flashOffset + range.start, flashPhaseStart, speedWindow, bytes.size, "正在快速刷写完整镜像")
                }
            }

            flashEnd(reboot)
            if (reboot) {
                progress(bytes.size, bytes.size, 0.0, "正在重启设备")
                hardReset()
            }
            progress(bytes.size, bytes.size, 0.0, if (reboot) "Done, rebooting / 完成并重启" else "Done / 完成")
        } finally {
            closePort()
        }
    }

    private fun openPort(deviceName: String?, baudRate: Int) {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
        require(drivers.isNotEmpty()) { "未发现 USB 串口设备" }

        val driver = drivers.firstOrNull { it.device.deviceName == deviceName }
            ?: drivers.firstOrNull {
                it.device.vendorId == ESPRESSIF_VID && it.device.productId == ESPRESSIF_USB_SERIAL_JTAG_PID
            }
            ?: drivers.first()

        val device = driver.device
        require(usbManager.hasPermission(device)) { "没有 USB 权限，请先在系统弹窗中允许 Vink Flasher 访问设备" }
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
        emitLog("Native PaperS3 backend connected at $baudRate baud: ${device.deviceName}")
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

    private fun sync() {
        val payload = ByteArray(36)
        payload[0] = 0x07
        payload[1] = 0x07
        payload[2] = 0x12
        payload[3] = 0x20
        for (i in 4 until payload.size) payload[i] = 0x55
        var lastError: Throwable? = null
        repeat(10) { attempt ->
            if (shouldCancel()) throw InterruptedException("Flash cancelled by user")
            try {
                rx.clear()
                sendCommand(SYNC, payload)
                readCommandResponse(SYNC, 3000, checkStatus = false)
                rx.clear()
                emitLog("Native PaperS3 backend synced with bootloader")
                return
            } catch (error: Throwable) {
                lastError = error
                Thread.sleep(100)
                emitLog("SYNC attempt ${attempt + 1} failed: ${error.message}")
            }
        }
        throw IllegalStateException("ESP32 下载模式同步失败: ${lastError?.message}", lastError)
    }

    private fun spiAttach() {
        sendCommand(SPI_ATTACH, ByteArray(8))
        readCommandResponse(SPI_ATTACH, READ_TIMEOUT_MS, checkStatus = false)
    }

    private fun spiSetParams() {
        val out = ByteArrayOutputStream()
        out.u32(0)
        out.u32(0x1000000)
        out.u32(0x10000)
        out.u32(0x1000)
        out.u32(0x100)
        out.u32(0xFFFF)
        sendCommand(SPI_SET_PARAMS, out.toByteArray())
        readCommandResponse(SPI_SET_PARAMS, READ_TIMEOUT_MS, checkStatus = false)
    }

    private fun findNonBlankSectorRanges(bytes: ByteArray): List<FlashRange> {
        val ranges = ArrayList<FlashRange>()
        var rangeStart = -1
        var sectorStart = 0
        while (sectorStart < bytes.size) {
            val sectorEnd = min(bytes.size, sectorStart + SECTOR_SIZE)
            var blank = true
            for (i in sectorStart until sectorEnd) {
                if ((bytes[i].toInt() and 0xFF) != 0xFF) {
                    blank = false
                    break
                }
            }
            if (!blank && rangeStart < 0) {
                rangeStart = sectorStart
            } else if (blank && rangeStart >= 0) {
                ranges.add(FlashRange(rangeStart, sectorStart))
                rangeStart = -1
            }
            sectorStart += SECTOR_SIZE
        }
        if (rangeStart >= 0) ranges.add(FlashRange(rangeStart, bytes.size))
        return ranges
    }

    private fun writeRange(
        bytes: ByteArray,
        start: Int,
        endExclusive: Int,
        flashOffset: Int,
        flashPhaseStart: Long,
        speedWindow: SpeedWindow,
        progressTotal: Int,
        stage: String,
    ) {
        val size = endExclusive - start
        if (size <= 0) return
        flashBegin(size, flashOffset)

        val block = ByteArray(BLOCK_SIZE)
        val blocks = (size + BLOCK_SIZE - 1) / BLOCK_SIZE
        var writtenInRange = 0
        for (sequence in 0 until blocks) {
            if (shouldCancel()) throw InterruptedException("Flash cancelled by user")
            val chunkLength = min(BLOCK_SIZE, size - writtenInRange)
            block.fill(0.toByte())
            System.arraycopy(bytes, start + writtenInRange, block, 0, chunkLength)
            flashData(block, sequence)
            writtenInRange += chunkLength

            if (sequence % PROGRESS_BLOCK_INTERVAL == 0 || sequence == blocks - 1) {
                val now = System.currentTimeMillis()
                val logicalWritten = min(progressTotal, start + writtenInRange)
                val sample = speedWindow.sample(logicalWritten, now)
                val speed = sample ?: run {
                    val elapsedFlashSec = max(1L, now - flashPhaseStart) / 1000.0
                    logicalWritten / elapsedFlashSec
                }
                progress(logicalWritten, progressTotal, speed, stage)
            }
        }
    }

    private fun flashBegin(size: Int, offset: Int) {
        val blocks = (size + BLOCK_SIZE - 1) / BLOCK_SIZE
        val eraseSize = ((size + 0xFFF) / 0x1000) * 0x1000
        val out = ByteArrayOutputStream()
        out.u32(eraseSize)
        out.u32(blocks)
        out.u32(BLOCK_SIZE)
        out.u32(offset)
        out.u32(0) // ESP32-S3 ROM encrypted-write flag, false
        val timeoutMs = max(5000, ((eraseSize * 1000L) / 175000L).toInt() + 15000)
        var lastError: Throwable? = null
        repeat(3) { attempt ->
            if (shouldCancel()) throw InterruptedException("Flash cancelled by user")
            try {
                rx.clear()
                sendCommand(FLASH_BEGIN, out.toByteArray())
                readCommandResponse(FLASH_BEGIN, timeoutMs)
                emitLog("FLASH_BEGIN accepted, writing $blocks blocks")
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
        out.u32(0)
        out.u32(0)
        out.write(block)
        sendCommand(FLASH_DATA, out.toByteArray(), checksum(block))
        readCommandResponse(FLASH_DATA, READ_TIMEOUT_MS)
    }

    private fun flashEnd(reboot: Boolean) {
        val out = ByteArrayOutputStream(4)
        out.u32(if (reboot) 0 else 1)
        sendCommand(FLASH_END, out.toByteArray())
        readCommandResponse(FLASH_END, READ_TIMEOUT_MS)
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

    private fun sendCommand(command: Int, data: ByteArray, checksum: Int = 0) {
        val out = ByteArrayOutputStream(data.size + 8)
        out.write(0x00)
        out.write(command)
        out.u16(data.size)
        out.u32(checksum)
        out.write(data)
        val encoded = slipEncode(out.toByteArray())
        requirePort().write(encoded, WRITE_TIMEOUT_MS)
    }

    private fun readCommandResponse(command: Int, timeoutMs: Int, checkStatus: Boolean = true): ByteArray {
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
                throw IllegalStateException("ESP32 响应长度异常: command=0x${command.toString(16)}")
            }
            if (checkStatus && value != 0) {
                throw IllegalStateException("ESP32 拒绝烧录命令: command=0x${command.toString(16)}, value=$value")
            }
            return packet.copyOfRange(8, 8 + dataLength)
        }
        throw java.util.concurrent.TimeoutException("ESP32 未确认烧录命令: 0x${command.toString(16)}")
    }

    private fun readSlipPacket(timeoutMs: Int): ByteArray {
        val deadline = System.currentTimeMillis() + timeoutMs
        val temp = ByteArray(4096)
        while (System.currentTimeMillis() < deadline) {
            val end = rx.indexOf(0xC0.toByte())
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
                // keep draining until deadline
            }
        }
    }

    private fun slipEncode(packet: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(packet.size + 2)
        out.write(0xC0)
        for (b in packet) {
            when (b.toInt() and 0xFF) {
                0xC0 -> {
                    out.write(0xDB)
                    out.write(0xDC)
                }
                0xDB -> {
                    out.write(0xDB)
                    out.write(0xDD)
                }
                else -> out.write(b.toInt())
            }
        }
        out.write(0xC0)
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

    private fun checksum(data: ByteArray): Int {
        var value = 0xEF
        for (b in data) value = value xor (b.toInt() and 0xFF)
        return value
    }

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

    private fun requirePort(): UsbSerialPort = port ?: throw IllegalStateException("USB serial port is not open")

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
