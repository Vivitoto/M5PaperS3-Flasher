import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'esp_flasher.dart';

class EsptoolResult {
  const EsptoolResult({
    required this.success,
    required this.output,
    required this.cancelled,
  });

  final bool success;
  final String output;
  final bool cancelled;
}

class EsptoolService {
  EsptoolService._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final EsptoolService instance = EsptoolService._();
  static const MethodChannel _channel = MethodChannel('vink.flasher/esptool');

  final StreamController<String> _logs = StreamController<String>.broadcast();
  final StreamController<FlashProgress> _paperS3Progress =
      StreamController<FlashProgress>.broadcast();

  Stream<String> get logs => _logs.stream;
  Stream<FlashProgress> get paperS3Progress => _paperS3Progress.stream;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'esptoolLog') {
      final text = call.arguments?.toString() ?? '';
      if (text.isNotEmpty) _logs.add(text);
    } else if (call.method == 'paperS3Progress') {
      final args = call.arguments;
      if (args is Map) {
        _paperS3Progress.add(FlashProgress(
          writtenBytes: (args['writtenBytes'] as num?)?.toInt() ?? 0,
          totalBytes: (args['totalBytes'] as num?)?.toInt() ?? 0,
          speedBytesPerSecond:
              (args['speedBytesPerSecond'] as num?)?.toDouble() ?? 0,
          stage: args['stage']?.toString() ?? '',
        ));
      }
    }
  }

  Future<EsptoolResult> flashFullImage({
    required String port,
    required File firmware,
    required int flashOffset,
    int baudRate = 115200,
    String flashSize = '16MB',
    String flashProfile = 'papers3',
  }) async {
    final offset =
        flashOffset == 0 ? '0x0' : '0x${flashOffset.toRadixString(16)}';
    final args = switch (flashProfile) {
      'generic_esptool' || 'generic' || 'esptool' => <String>[
          // Generic expansion profile for LilyGo/other ESP32 devices: leave
          // chip detection and reset handling to esptool. Device-specific
          // manifests should provide the correct firmware and offset.
          '--chip',
          'auto',
          '--port',
          port,
          '--baud',
          baudRate.toString(),
          '--before',
          'default_reset',
          '--after',
          'hard_reset',
          '--no-stub',
          'write_flash',
          '-z',
          offset,
          firmware.path,
        ],
      'ink_box' || 'compatible' => <String>[
          // Ink Box compatibility profile: keep the official esptool flow,
          // default reset, no stub, compressed write and 460800 baud for A/B
          // verification against Ink Box behavior.
          '--chip',
          'auto',
          '--port',
          port,
          '--baud',
          '460800',
          '--before',
          'default_reset',
          '--after',
          'hard_reset',
          '--no-stub',
          'write_flash',
          '-z',
          offset,
          firmware.path,
        ],
      'auto_reset' || 'stable' => <String>[
          // Experimental auto-reset profile: official esptool write path with
          // the patched Android/PaperS3 USB-JTAG reset sequence. Kept as a
          // fallback, but not the default because M5Stack documents PaperS3
          // download mode as a manual long-press flow.
          '--chip',
          'esp32s3',
          '--port',
          port,
          '--baud',
          baudRate.toString(),
          '--before',
          'usb_reset',
          '--after',
          'hard_reset',
          'write_flash',
          '--flash_size',
          flashSize,
          '--flash_mode',
          'dio',
          '--flash_freq',
          '80m',
          offset,
          firmware.path,
        ],
      _ => <String>[
          // Legacy PaperS3 manual esptool fallback. The default PaperS3 path in
          // FlashScreen uses the in-app 0xFlash-compatible backend instead.
          '--chip',
          'esp32s3',
          '--port',
          port,
          '--baud',
          baudRate.toString(),
          '--before',
          'no_reset',
          '--after',
          'hard_reset',
          'write_flash',
          '--flash_size',
          flashSize,
          '--flash_mode',
          'dio',
          '--flash_freq',
          '80m',
          offset,
          firmware.path,
        ],
    };

    final raw = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('runEsptool', {'args': args});
    final result = raw ?? const <dynamic, dynamic>{};
    return EsptoolResult(
      success: result['success'] == true,
      output: result['output']?.toString() ?? '',
      cancelled: result['cancelled'] == true,
    );
  }

  Future<EsptoolResult> flashPaperS3Native({
    required String deviceName,
    required File firmware,
    required int flashOffset,
    int baudRate = 921600,
    bool reboot = true,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'flashPaperS3Native',
      {
        'deviceName': deviceName,
        'firmwarePath': firmware.path,
        'flashOffset': flashOffset,
        'baudRate': baudRate,
        'reboot': reboot,
      },
    );
    final result = raw ?? const <dynamic, dynamic>{};
    return EsptoolResult(
      success: result['success'] == true,
      output: result['output']?.toString() ?? '',
      cancelled: result['cancelled'] == true,
    );
  }

  Future<void> cancel() async {
    await _channel.invokeMethod<void>('cancelEsptool');
  }
}
