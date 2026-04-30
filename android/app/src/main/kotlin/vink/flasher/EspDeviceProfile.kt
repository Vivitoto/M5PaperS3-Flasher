package vink.flasher

import com.hoho.android.usbserial.driver.UsbSerialProber
import android.hardware.usb.UsbManager
import android.content.Context

/**
 * Known ESP32 chip families and their flash capacity defaults.
 * flashSizeBytes = 0 means "read from chip", any other value is a default hint.
 */
enum class ChipFamily(
    val label: String,
    val defaultFlashSizeBytes: Long,
    val supportsEncryption: Boolean,
) {
    ESP32("ESP32", 4 * 1024 * 1024, false),
    ESP32S2("ESP32-S2", 4 * 1024 * 1024, false),
    ESP32S3("ESP32-S3", 16 * 1024 * 1024, true),
    ESP32C2("ESP32-C2", 4 * 1024 * 1024, false),
    ESP32C3("ESP32-C3", 4 * 1024 * 1024, false),
    ESP32C6("ESP32-C6", 4 * 1024 * 1024, false),
    ESP32H2("ESP32-H2", 4 * 1024 * 1024, false),
    ESP32P4("ESP32-P4", 16 * 1024 * 1024, false),
    UNKNOWN("Unknown ESP32", 0, false),
    ;

    companion object {
        fun fromString(name: String?): ChipFamily {
            if (name == null) return UNKNOWN
            return entries.find {
                name.equals(it.label, ignoreCase = true) ||
                name.equals(it.name, ignoreCase = true)
            } ?: UNKNOWN
        }
    }
}

/**
 * Flash address presets per device type.
 */
enum class FlashOffset(val bytes: Int, val description: String) {
    /** Full image (bootloader + partition + app), flash from 0x0 */
    FULL_IMAGE(0x0, "完整镜像 (含 bootloader)"),
    /** App-only offset for PaperS3 (Vink app partition) */
    APP_ONLY(0x200000, "仅应用分区 (0x200000)"),
    /** SPIFFS / data partition */
    SPIFFS(0x500000, "数据分区 (0x500000)"),
    ;

    companion object {
        fun fromBytes(bytes: Int): FlashOffset {
            return entries.find { it.bytes == bytes } ?: FULL_IMAGE
        }
    }
}

/**
 * USB device filter for known ESP32 boards.
 */
enum class EspDeviceProfile(
    val displayName: String,
    val chipFamily: ChipFamily,
    val vid: Int,
    val pid: Int,
    val defaultBaudRate: Int,
    val defaultFlashOffset: FlashOffset,
    val description: String,
) {
    PAPER_S3(
        displayName = "M5Stack PaperS3",
        chipFamily = ChipFamily.ESP32S3,
        vid = 0x303A,
        pid = 0x1001, // ESP32-S3 USB Serial JTAG
        defaultBaudRate = 921600,
        defaultFlashOffset = FlashOffset.APP_ONLY,
        description = "M5Stack PaperS3 / M5Paper",
    ),
    LILYGO_T5_47(
        displayName = "LilyGO T5 4.7\" E-Paper",
        chipFamily = ChipFamily.ESP32S3,
        vid = 0x303A,
        pid = 0x1001,
        defaultBaudRate = 921600,
        defaultFlashOffset = FlashOffset.FULL_IMAGE,
        description = "LilyGO T5 4.7\" E-Paper V2.3",
    ),
    GENERIC_ESP32S3(
        displayName = "Generic ESP32-S3",
        chipFamily = ChipFamily.ESP32S3,
        vid = 0x303A,
        pid = 0x1001,
        defaultBaudRate = 921600,
        defaultFlashOffset = FlashOffset.FULL_IMAGE,
        description = "Any ESP32-S3 board in USB download mode",
    ),
    GENERIC_ESP32(
        displayName = "Generic ESP32",
        chipFamily = ChipFamily.ESP32,
        vid = 0x10C4, // Common CP210x VID
        pid = 0xEA60,
        defaultBaudRate = 921600,
        defaultFlashOffset = FlashOffset.FULL_IMAGE,
        description = "Generic ESP32 board in USB download mode",
    ),
    ;

    companion object {
        /**
         * Auto-detect profile from VID/PID.
         * Falls back to GENERIC_ESP32S3 if Espressif VID, otherwise GENERIC_ESP32.
         */
        fun fromVidPid(vid: Int, pid: Int): EspDeviceProfile {
            return entries.find { it.vid == vid && it.pid == pid }
                ?: if (vid == 0x303A) GENERIC_ESP32S3 else GENERIC_ESP32
        }

        /**
         * Find all profiles matching a chip family.
         */
        fun forChipFamily(family: ChipFamily): List<EspDeviceProfile> {
            return entries.filter { it.chipFamily == family }
        }

        /**
         * Get a display-friendly list of all profiles for the device picker.
         */
        fun all(): List<EspDeviceProfile> = entries.toList()
    }
}

/**
 * Probed device info returned after reading the chip.
 */
data class ProbedDeviceInfo(
    val chipFamily: ChipFamily,
    val chipRevision: Int,
    val flashSize: Long,
    val macAddress: String,
    val profile: EspDeviceProfile,
    val rawDescription: String,
)
