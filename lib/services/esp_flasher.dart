import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

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
  // Ink Flasher 统一烧录完整镜像：bootloader + partition + app + resources。
  // 完整镜像必须从 0x0 开始写入。
  static const int defaultFlashOffset = 0x0;

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _subscription;
  final List<int> _rxBuffer = [];
  final _rxCompleter = Completer<void>.sync();

  static List<String> listDevices() => SerialPort.availablePorts;

  Future<void> connect(String portName, {int baudRate = 115200}) async {
    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      throw Exception('Unable to open serial port: ${port.name}');
    }

    port.config.baudRate = baudRate;
    port.config.bits = 8;
    port.config.stopBits = 1;
    port.config.parity = SerialPortParity.none;
    port.config.setFlowControl(SerialPortFlowControl.none);
    port.config.dtr = SerialPortDtr.off;
    port.config.rts = SerialPortRts.off;

    _port = port;
    _reader = SerialPortReader(port);
    _subscription = _reader!.stream.listen((data) {
      _rxBuffer.addAll(data);
      if (!_rxCompleter.isCompleted) {
        _rxCompleter.complete();
      }
    });
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _reader?.close();
    _port?.close();
    _subscription = null;
    _reader = null;
    _port = null;
    _rxBuffer.clear();
  }

  Future<void> enterBootloader() async {
    final port = _requirePort();
    
    // ESP32 bootloader sequence:
    // DTR=false, RTS=true → wait 100ms
    // DTR=true, RTS=false → wait 50ms
    // DTR=false, RTS=false → wait 250ms
    port.config.dtr = SerialPortDtr.off;
    port.config.rts = SerialPortRts.on;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    port.config.dtr = SerialPortDtr.on;
    port.config.rts = SerialPortRts.off;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    port.config.dtr = SerialPortDtr.off;
    port.config.rts = SerialPortRts.off;
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
        stage: flashOffset == 0 ? '正在刷写完整镜像' : '正在刷写固件',
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
    packet.addByte(0x00); // direction: host to ESP
    packet.addByte(command);
    packet.add(_u16(data.length));
    packet.add(_u32(checksum));
    packet.add(data);
    _requirePort().write(_slipEncode(packet.toBytes()));
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

  SerialPort _requirePort() {
    final port = _port;
    if (port == null) throw StateError('Serial port is not connected.');
    return port;
  }
}
