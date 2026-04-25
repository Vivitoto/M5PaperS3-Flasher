import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// TODO: Replace with actual USB serial implementation
// Current stub: flashing is not yet implemented on this CI build
// For now the app supports: firmware list, download, and settings

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

  // Stub: USB serial not available in this build
  static Future<List<dynamic>> listDevices() async {
    return [];
  }

  Future<void> connect(dynamic device, {int baudRate = 115200}) async {
    throw UnsupportedError('USB serial flashing is not yet implemented in this build.');
  }

  Future<void> close() async {}

  Future<void> enterBootloader() async {}

  Stream<FlashProgress> flashFile(
    File firmware, {
    int flashOffset = defaultFlashOffset,
    bool reboot = true,
  }) async* {
    yield FlashProgress(
      writtenBytes: 0,
      totalBytes: await firmware.length(),
      speedBytesPerSecond: 0,
      stage: 'USB serial not implemented in this build / 本版本暂不支持 USB 烧录',
    );
    throw UnsupportedError('USB serial flashing is not yet implemented.');
  }

  Future<void> sync() async {}
  Future<void> flashBegin(int size, int offset) async {}
  Future<void> flashData(Uint8List block, int sequence) async {}
  Future<void> flashEnd({bool reboot = true}) async {}
  Future<void> _sendCommand(int command, Uint8List data, {int checksum = 0}) async {}
  Future<Uint8List> _readSlipPacket({Duration timeout = const Duration(seconds: 5)}) async => Uint8List(0);
  Uint8List _slipEncode(List<int> packet) => Uint8List(0);
  Uint8List _slipDecode(List<int> packet) => Uint8List(0);
  Uint8List _u16(int value) => Uint8List(2);
  Uint8List _u32(int value) => Uint8List(4);
  int _checksum(List<int> data) => 0;
}
