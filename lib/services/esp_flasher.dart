import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:usb_serial/usb_serial.dart';

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
  static const int blockSize = 0x400;
  static const int defaultFlashOffset = 0x10000;

  UsbPort? _port;
  StreamSubscription<Uint8List>? _inputSubscription;
  final List<int> _rxBuffer = [];

  static Future<List<UsbDevice>> listDevices() => UsbSerial.listDevices();

  Future<void> connect(UsbDevice device, {int baudRate = 115200}) async {
    final port = await device.create();
    if (port == null) throw Exception('Unable to create USB serial port.');
    final opened = await port.open();
    if (opened != true) throw Exception('Unable to open USB serial port.');

    await port.setPortParameters(
      baudRate,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    _port = port;
    _inputSubscription = port.inputStream?.listen((data) => _rxBuffer.addAll(data));
  }

  Future<void> close() async {
    await _inputSubscription?.cancel();
    await _port?.close();
    _inputSubscription = null;
    _port = null;
    _rxBuffer.clear();
  }

  Future<void> enterBootloader() async {
    final port = _requirePort();
    await port.setDTR(false);
    await port.setRTS(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await port.setDTR(true);
    await port.setRTS(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await port.setDTR(false);
    await port.setRTS(false);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Stream<FlashProgress> flashFile(
    File firmware, {
    int flashOffset = defaultFlashOffset,
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
      stage: 'Begin flash / 开始写入',
    );
    await flashBegin(bytes.length, flashOffset);

    var sequence = 0;
    var written = 0;
    while (written < bytes.length) {
      final chunkLength = min(blockSize, bytes.length - written);
      final chunk = Uint8List(blockSize)..setRange(0, chunkLength, bytes, written);
      await flashData(chunk, sequence);
      written += chunkLength;
      sequence++;
      final elapsed = DateTime.now().difference(started).inMilliseconds / 1000.0;
      yield FlashProgress(
        writtenBytes: written,
        totalBytes: bytes.length,
        speedBytesPerSecond: elapsed <= 0 ? 0 : written / elapsed,
        stage: 'Writing firmware / 正在刷写',
      );
    }

    await flashEnd(reboot: reboot);
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
    await _sendCommand(syncCommand, Uint8List.fromList(payload));
    await _readSlipPacket(timeout: const Duration(seconds: 2));
  }

  Future<void> flashBegin(int size, int offset) async {
    final blocks = (size + blockSize - 1) ~/ blockSize;
    final data = BytesBuilder();
    data.add(_u32(size));
    data.add(_u32(blocks));
    data.add(_u32(blockSize));
    data.add(_u32(offset));
    await _sendCommand(flashBeginCommand, data.toBytes());
    await _readSlipPacket();
  }

  Future<void> flashData(Uint8List block, int sequence) async {
    final data = BytesBuilder();
    data.add(_u32(block.length));
    data.add(_u32(sequence));
    data.add(_u32(0));
    data.add(_u32(0));
    data.add(block);
    await _sendCommand(flashDataCommand, data.toBytes(), checksum: _checksum(block));
    await _readSlipPacket();
  }

  Future<void> flashEnd({bool reboot = true}) async {
    await _sendCommand(flashEndCommand, _u32(reboot ? 0 : 1));
    await _readSlipPacket();
  }

  Future<void> _sendCommand(int command, Uint8List data, {int checksum = 0}) async {
    final packet = BytesBuilder();
    packet.addByte(0x00); // host to ESP
    packet.addByte(command);
    packet.add(_u16(data.length));
    packet.add(_u32(checksum));
    packet.add(data);
    await _requirePort().write(_slipEncode(packet.toBytes()));
  }

  Future<Uint8List> _readSlipPacket({Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final end = _rxBuffer.indexOf(0xC0);
      if (end >= 0) {
        final raw = _rxBuffer.sublist(0, end + 1);
        _rxBuffer.removeRange(0, end + 1);
        final decoded = _slipDecode(raw);
        if (decoded.isNotEmpty) return decoded;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
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
        out.add(escaped == 0xDC ? 0xC0 : escaped == 0xDD ? 0xDB : escaped);
      } else {
        out.add(byte);
      }
    }
    return Uint8List.fromList(out);
  }

  Uint8List _u16(int value) => Uint8List(2)
    ..buffer.asByteData().setUint16(0, value, Endian.little);

  Uint8List _u32(int value) => Uint8List(4)
    ..buffer.asByteData().setUint32(0, value, Endian.little);

  int _checksum(List<int> data) {
    var checksum = 0xEF;
    for (final byte in data) {
      checksum ^= byte;
    }
    return checksum;
  }

  UsbPort _requirePort() {
    final port = _port;
    if (port == null) throw StateError('USB port is not connected.');
    return port;
  }
}
