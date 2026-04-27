import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

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

  Stream<String> get logs => _logs.stream;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'esptoolLog') {
      final text = call.arguments?.toString() ?? '';
      if (text.isNotEmpty) _logs.add(text);
    }
  }

  Future<EsptoolResult> flashFullImage({
    required String port,
    required File firmware,
    required int flashOffset,
    int baudRate = 115200,
    String flashSize = '16MB',
  }) async {
    final args = <String>[
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
      flashOffset == 0 ? '0x0' : '0x${flashOffset.toRadixString(16)}',
      firmware.path,
    ];

    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('runEsptool', {'args': args});
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
