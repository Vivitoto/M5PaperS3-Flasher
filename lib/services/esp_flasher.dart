import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:usb_serial/usb_serial.dart';

class SerialDeviceInfo {
  const SerialDeviceInfo({
    required this.id,
    required this.label,
    required this.device,
  });

  final String id;
  final String label;
  final UsbDevice device;
}

class FlashProgress {
  const FlashProgress({
    required this.writtenBytes,
    required this.totalBytes,
    required this.speedBytesPerSecond,
    required this.stage,
  });

  final int writtenBytes;
  final int totalBytes;
  final double speedBytesPerSecond;
  final String stage;

  double get percent => totalBytes == 0 ? 0 : writtenBytes * 100 / totalBytes;
}

class EspFlasher {
  static const int syncCommand = 0x08;
  static const int flashBeginCommand = 0x02;
  static const int flashDataCommand = 0x03;
  static const int flashEndCommand = 0x04;
  static const int spiSetParamsCommand = 0x0B;
  static const int spiAttachCommand = 0x0D;
  static const int eraseFlashCommand = 0xD0;
  static const int blockSize = 0x400;
  // Vink Flasher 优先烧录完整镜像：bootloader + partition + app + resources。
  // 完整镜像必须从 0x0 开始写入。
  static const int defaultFlashOffset = 0x0;

  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  final List<int> _rxBuffer = [];
  Completer<void>? _rxCompleter;

  static Future<List<SerialDeviceInfo>> listDevices() async {
    final devices = await UsbSerial.listDevices();
    return [
      for (final device in devices)
        SerialDeviceInfo(
          id: device.deviceName,
          label: _deviceLabel(device),
          device: device,
        ),
    ];
  }

  static String _deviceLabel(UsbDevice device) {
    final parts = <String>[
      if ((device.productName ?? '').isNotEmpty) device.productName!,
      if ((device.manufacturerName ?? '').isNotEmpty) device.manufacturerName!,
      if (device.deviceName.isNotEmpty) device.deviceName,
      'VID:${device.vid?.toRadixString(16) ?? 'unknown'} PID:${device.pid?.toRadixString(16) ?? 'unknown'}',
    ];
    return parts.join(' · ');
  }

  Future<void> connect(SerialDeviceInfo deviceInfo,
      {int baudRate = 115200}) async {
    final port = await deviceInfo.device.create();
    if (port == null) {
      throw Exception('无法创建 USB 串口: ${deviceInfo.label}');
    }

    final opened = await port.open();
    if (!opened) {
      throw Exception('无法打开 USB 串口，请在系统弹窗中允许 Vink Flasher 访问 USB 设备');
    }

    await port.setPortParameters(
      baudRate,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    await port.setDTR(false);
    await port.setRTS(false);

    _port = port;
    _subscription = port.inputStream?.listen((data) {
      _rxBuffer.addAll(data);
      final completer = _rxCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    });
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _port?.close();
    _subscription = null;
    _port = null;
    _rxBuffer.clear();
    _rxCompleter = null;
  }

  Future<void> enterBootloader() async {
    final port = _requirePort();

    // 0xFlash-compatible ESP32-S3 USB Serial/JTAG bootloader sequence:
    // DTR=false, RTS=true → wait 100ms
    // DTR=true, RTS=false → wait 500ms
    // DTR=false, RTS=false → wait 100ms
    await port.setDTR(false);
    await port.setRTS(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await port.setDTR(true);
    await port.setRTS(false);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await port.setDTR(false);
    await port.setRTS(false);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  Stream<FlashProgress> flashFile(
    File firmware, {
    int flashOffset = defaultFlashOffset,
    bool eraseBeforeWrite = false,
    bool reboot = true,
  }) async* {
    final bytes = await firmware.readAsBytes();
    final started = DateTime.now();

    yield FlashProgress(
      writtenBytes: 0,
      totalBytes: bytes.length,
      speedBytesPerSecond: 0,
      stage: 'Connecting bootloader / 连接引导模式',
    );
    await enterBootloader();
    await sync();

    yield FlashProgress(
      writtenBytes: 0,
      totalBytes: bytes.length,
      speedBytesPerSecond: 0,
      stage: '初始化 SPI Flash 参数',
    );
    await spiAttach();
    await spiSetParams();

    if (eraseBeforeWrite) {
      yield FlashProgress(
        writtenBytes: 0,
        totalBytes: bytes.length,
        speedBytesPerSecond: 0,
        stage: flashOffset == 0 ? '完整镜像将按写入范围自动擦除' : '即将擦除并写入固件区域',
      );
      // Do not send ERASE_FLASH before writing a full PaperS3 image. 0xFlash
      // relies on FLASH_BEGIN/FLASH_DATA to erase the target range, while the
      // ROM chip-erase command can block for a long time on Android with no
      // useful progress feedback.
    }

    yield FlashProgress(
      writtenBytes: 0,
      totalBytes: bytes.length,
      speedBytesPerSecond: 0,
      stage: '开始写入固件',
    );
    await flashBegin(bytes.length, flashOffset);

    var sequence = 0;
    var written = 0;
    while (written < bytes.length) {
      final chunkLength = min(blockSize, bytes.length - written);
      final chunk = Uint8List(blockSize)
        ..setRange(0, chunkLength, bytes, written);
      await flashData(chunk, sequence);
      written += chunkLength;
      sequence++;
      final elapsed =
          DateTime.now().difference(started).inMilliseconds / 1000.0;
      yield FlashProgress(
        writtenBytes: written,
        totalBytes: bytes.length,
        speedBytesPerSecond: elapsed <= 0 ? 0 : written / elapsed,
        stage: flashOffset == 0 ? '正在刷写完整镜像' : '正在刷写固件',
      );
    }

    await flashEnd(reboot: reboot);
    if (reboot) {
      yield FlashProgress(
        writtenBytes: bytes.length,
        totalBytes: bytes.length,
        speedBytesPerSecond: 0,
        stage: '正在重启设备',
      );
      await hardReset();
    }
    yield FlashProgress(
      writtenBytes: bytes.length,
      totalBytes: bytes.length,
      speedBytesPerSecond: 0,
      stage: reboot ? 'Done, rebooting / 完成并重启' : 'Done / 完成',
    );
  }

  Future<void> sync() async {
    final payload = <int>[0x07, 0x07, 0x12, 0x20];
    for (var i = 0; i < 32; i++) {
      payload.add(0x55);
    }

    Object? lastError;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        _clearReadBuffer();
        await _sendCommand(syncCommand, Uint8List.fromList(payload));
        await _readCommandResponse(
          syncCommand,
          timeout: const Duration(seconds: 3),
          checkStatus: false,
        );
        _clearReadBuffer();
        return;
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw TimeoutException('ESP32 下载模式同步失败: $lastError');
  }

  Future<void> spiAttach() async {
    await _sendCommand(spiAttachCommand, Uint8List(8));
    await _readCommandResponse(
      spiAttachCommand,
      timeout: const Duration(seconds: 5),
      checkStatus: false,
    );
  }

  Future<void> spiSetParams() async {
    final data = BytesBuilder();
    data.add(_u32(0)); // SPI flash id, 0 means autodetect/default.
    data.add(_u32(0x1000000)); // PaperS3 16MB flash size.
    data.add(_u32(0x10000)); // block size.
    data.add(_u32(0x1000)); // sector size.
    data.add(_u32(0x100)); // page size.
    data.add(_u32(0xFFFF)); // status mask.
    await _sendCommand(spiSetParamsCommand, data.toBytes());
    await _readCommandResponse(
      spiSetParamsCommand,
      timeout: const Duration(seconds: 5),
      checkStatus: false,
    );
  }

  Future<void> flashBegin(int size, int offset) async {
    final blocks = (size + blockSize - 1) ~/ blockSize;
    final eraseSize = ((size + 0xFFF) ~/ 0x1000) * 0x1000;
    final data = BytesBuilder();
    data.add(_u32(eraseSize));
    data.add(_u32(blocks));
    data.add(_u32(blockSize));
    data.add(_u32(offset));
    // ESP32-S3 ROM supports encrypted flash writes and expects a fifth
    // FLASH_BEGIN argument even when encryption is not requested. 0xFlash sends
    // false/0 here and uses 1024-byte ROM flash blocks.
    data.add(_u32(0));
    final packet = data.toBytes();
    final timeoutMs = max(5000, ((eraseSize * 1000) / 175000).round() + 15000);
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        _clearReadBuffer();
        await _sendCommand(flashBeginCommand, packet);
        await _readCommandResponse(
          flashBeginCommand,
          timeout: Duration(milliseconds: timeoutMs),
        );
        return;
      } catch (error) {
        lastError = error;
        if (attempt == 3) break;
        await _drainResponses(const Duration(seconds: 10));
        _clearReadBuffer();
      }
    }
    throw StateError('FLASH_BEGIN failed after 3 attempts: $lastError');
  }

  Future<void> flashData(Uint8List block, int sequence) async {
    final data = BytesBuilder();
    data.add(_u32(block.length));
    data.add(_u32(sequence));
    data.add(_u32(0));
    data.add(_u32(0));
    data.add(block);
    await _sendCommand(flashDataCommand, data.toBytes(),
        checksum: _checksum(block));
    await _readCommandResponse(flashDataCommand);
  }

  Future<void> flashEnd({bool reboot = true}) async {
    await _sendCommand(flashEndCommand, _u32(reboot ? 0 : 1));
    await _readCommandResponse(flashEndCommand);
  }

  Future<void> hardReset() async {
    final port = _requirePort();
    await port.setDTR(false);
    await port.setRTS(false);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await port.setDTR(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await port.setDTR(false);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  Future<void> eraseFlash() async {
    await _sendCommand(eraseFlashCommand, Uint8List(0));
    await _readCommandResponse(eraseFlashCommand,
        timeout: const Duration(seconds: 180));
  }

  Future<Uint8List> _readCommandResponse(
    int command, {
    Duration timeout = const Duration(seconds: 5),
    bool checkStatus = true,
  }) async {
    for (var retry = 0; retry < 100; retry++) {
      final packet = await _readSlipPacket(timeout: timeout);
      if (packet.length < 8) continue;
      final response = packet[0];
      final op = packet[1];
      if (response != 0x01 || op != command) continue;

      final dataLength = packet[2] | (packet[3] << 8);
      final value =
          packet[4] | (packet[5] << 8) | (packet[6] << 16) | (packet[7] << 24);
      final data = packet.sublist(8);
      if (data.length < dataLength) {
        throw StateError(
            'ESP32 响应长度异常: command=0x${command.toRadixString(16)}');
      }
      if (checkStatus && value != 0) {
        throw StateError(
          'ESP32 拒绝烧录命令: command=0x${command.toRadixString(16)}, value=$value, data=${_hex(data.take(dataLength).toList())}',
        );
      }
      return Uint8List.fromList(data.take(dataLength).toList());
    }
    throw TimeoutException('ESP32 未确认烧录命令: 0x${command.toRadixString(16)}');
  }

  Future<void> _sendCommand(int command, Uint8List data,
      {int checksum = 0}) async {
    final packet = BytesBuilder();
    packet.addByte(0x00); // direction: host to ESP
    packet.addByte(command);
    packet.add(_u16(data.length));
    packet.add(_u32(checksum));
    packet.add(data);
    await _requirePort().write(_slipEncode(packet.toBytes()));
  }

  Future<Uint8List> _readSlipPacket(
      {Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final end = _rxBuffer.indexOf(0xC0);
      if (end >= 0) {
        final raw = _rxBuffer.sublist(0, end + 1);
        _rxBuffer.removeRange(0, end + 1);
        final decoded = _slipDecode(raw);
        if (decoded.isNotEmpty) return decoded;
      }
      _rxCompleter = Completer<void>();
      await _rxCompleter!.future.timeout(
        const Duration(milliseconds: 20),
        onTimeout: () {},
      );
    }
    throw TimeoutException('Timed out waiting for ESP32 response.');
  }

  Uint8List _slipEncode(List<int> packet) {
    final out = <int>[0xC0];
    for (final byte in packet) {
      if (byte == 0xC0) {
        out.addAll([0xDB, 0xDC]);
      } else if (byte == 0xDB) {
        out.addAll([0xDB, 0xDD]);
      } else {
        out.add(byte);
      }
    }
    out.add(0xC0);
    return Uint8List.fromList(out);
  }

  Uint8List _slipDecode(List<int> packet) {
    final out = <int>[];
    for (var i = 0; i < packet.length; i++) {
      final byte = packet[i];
      if (byte == 0xC0) continue;
      if (byte == 0xDB && i + 1 < packet.length) {
        final escaped = packet[++i];
        out.add(escaped == 0xDC
            ? 0xC0
            : escaped == 0xDD
                ? 0xDB
                : escaped);
      } else {
        out.add(byte);
      }
    }
    return Uint8List.fromList(out);
  }

  Future<void> _drainResponses(Duration duration) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      try {
        await _readSlipPacket(timeout: const Duration(milliseconds: 250));
      } catch (_) {
        // Keep draining until the deadline, mirroring 0xFlash's retry pause.
      }
    }
  }

  void _clearReadBuffer() {
    _rxBuffer.clear();
  }

  String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');

  Uint8List _u16(int value) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);

  Uint8List _u32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

  int _checksum(List<int> data) {
    var checksum = 0xEF;
    for (final byte in data) {
      checksum ^= byte;
    }
    return checksum;
  }

  UsbPort _requirePort() {
    final port = _port;
    if (port == null) throw StateError('Serial port is not connected.');
    return port;
  }
}
