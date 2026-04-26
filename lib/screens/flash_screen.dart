import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/firmware.dart';
import '../services/esp_flasher.dart';
import '../services/esptool_service.dart';

class FlashScreen extends StatefulWidget {
  const FlashScreen({super.key, required this.firmware});

  final Firmware firmware;

  @override
  State<FlashScreen> createState() => _FlashScreenState();
}

class _FlashScreenState extends State<FlashScreen> {
  final _flasher = EspFlasher();
  List<SerialDeviceInfo> _devices = const [];
  SerialDeviceInfo? _selectedDevice;
  FlashProgress? _progress;
  bool _busy = false;
  bool _scanning = false;
  String? _status;
  final List<String> _logs = [];
  int _baudRate = 115200;
  String _burnMode = 'fast';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _scanDevices();
  }

  @override
  void dispose() {
    _flasher.close();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _baudRate = prefs.getInt('baudRate') ?? 115200;
      _burnMode = _normalizeBurnMode(prefs.getString('eraseOption'));
    });
  }

  String _normalizeBurnMode(String? value) {
    return switch (value) {
      'clean' || 'all' => 'clean',
      _ => 'fast',
    };
  }

  String get _burnModeLabel => _burnMode == 'clean' ? '彻底烧录' : '快速烧录';

  String _baudRateLabel(int rate) {
    return switch (rate) {
      115200 => '115200（稳定）',
      230400 => '230400（均衡）',
      460800 => '460800（快速）',
      921600 => '921600（高速）',
      _ => '$rate',
    };
  }

  void _addLog(String message) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.add('[$time] $message');
      if (_logs.length > 160) _logs.removeRange(0, _logs.length - 160);
    });
  }

  void _handleEsptoolLog(String raw) {
    if (!mounted) return;
    final lines = raw
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    for (final line in lines) {
      _addLog(line.length > 300 ? '${line.substring(0, 300)}…' : line);
      _updateProgressFromEsptoolLine(line);
    }
  }

  void _updateProgressFromEsptoolLine(String line) {
    final percentMatch = RegExp(r'\((\d+)\s*%\)').firstMatch(line);
    if (percentMatch != null) {
      final percent = int.tryParse(percentMatch.group(1) ?? '0') ?? 0;
      setState(() {
        _status = '正在写入固件 $percent%';
        _progress = FlashProgress(
          writtenBytes: percent,
          totalBytes: 100,
          speedBytesPerSecond: 0,
          stage: '官方 esptool 正在写入固件',
        );
      });
      return;
    }

    String? stage;
    if (line.contains('Connecting')) {
      stage = '正在连接 ESP32 下载模式';
    } else if (line.contains('Chip is')) {
      stage = '已识别芯片';
    } else if (line.contains('Uploading stub') || line.contains('Running stub')) {
      stage = '正在启动 esptool 写入助手';
    } else if (line.contains('Erasing flash') || line.contains('Erase size')) {
      stage = '正在擦除目标区域';
    } else if (line.contains('Writing at')) {
      stage = '正在写入固件';
    } else if (line.contains('Hash of data verified')) {
      stage = '写入校验通过';
    } else if (line.contains('Hard resetting')) {
      stage = '正在重启设备';
    }

    if (stage != null) {
      setState(() {
        _status = stage;
        _progress = FlashProgress(
          writtenBytes: _progress?.writtenBytes ?? 0,
          totalBytes: 100,
          speedBytesPerSecond: 0,
          stage: stage!,
        );
      });
    }
  }

  Future<void> _scanDevices() async {
    setState(() => _scanning = true);
    try {
      final devices = await EspFlasher.listDevices();
      if (!mounted) return;
      String? logMessage;
      setState(() {
        _devices = devices;
        if (devices.isEmpty) {
          _selectedDevice = null;
          _status = '未发现 USB 设备，请确认手机支持 OTG，并重新插拔设备后刷新';
          logMessage = '未发现 USB 设备';
        } else {
          final current = _selectedDevice;
          _selectedDevice = current == null
              ? devices.first
              : devices.firstWhere(
                  (device) => device.id == current.id,
                  orElse: () => devices.first,
                );
          _status = '发现 ${devices.length} 个 USB 设备，首次连接时系统可能会询问权限';
          logMessage = '发现 ${devices.length} 个 USB 设备: ${_selectedDevice?.label ?? ''}';
        }
      });
      if (logMessage != null) _addLog(logMessage!);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'USB 扫描失败: $error');
      _addLog('USB 扫描失败: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _flash() async {
    final device = _selectedDevice;
    final path = widget.firmware.localPath;
    if (device == null) {
      setState(() => _status = '未选择 USB 串口设备');
      return;
    }
    if (path == null || !await File(path).exists()) {
      setState(() => _status = '固件尚未下载');
      return;
    }

    setState(() {
      _busy = true;
      _progress = null;
      _logs.clear();
      _status = '正在打开 USB 串口（如系统询问权限请选择允许）';
    });
    _addLog('准备烧录: ${widget.firmware.name} ${widget.firmware.version}');
    _addLog('本地文件: $path');
    _addLog('固件大小: ${await File(path).length()} bytes');
    _addLog('烧录模式: $_burnModeLabel, offset=0x${widget.firmware.flashOffset.toRadixString(16)}');
    _addLog('打开 USB 串口: ${device.label}');

    try {
      // 先用 Flutter USB 层打开一次设备，触发/确认 Android USB 授权；
      // 真正烧录交给 Android 内置 Python esptool，避免 Dart 手写 ROM 协议不稳定。
      await _flasher.connect(device, baudRate: _baudRate);
      await _flasher.close();
      _addLog('USB 授权已确认，切换到官方 esptool 烧录引擎');

      setState(() {
        _status = '正在启动官方 esptool 烧录引擎';
        _progress = FlashProgress(
          writtenBytes: 0,
          totalBytes: 100,
          speedBytesPerSecond: 0,
          stage: '启动 esptool',
        );
      });

      final logSubscription = EsptoolService.instance.logs.listen(_handleEsptoolLog);
      try {
        final result = await EsptoolService.instance.flashFullImage(
          port: device.id,
          firmware: File(path),
          flashOffset: widget.firmware.flashOffset,
          baudRate: _baudRate,
        );
        if (!mounted) return;
        if (!result.success) {
          throw Exception(result.output.isEmpty ? 'esptool 烧录失败' : result.output.split('\n').last);
        }
        setState(() {
          _status = '刷写完成，设备正在重启';
          _progress = const FlashProgress(
            writtenBytes: 100,
            totalBytes: 100,
            speedBytesPerSecond: 0,
            stage: 'Done, rebooting / 完成并重启',
          );
        });
        _addLog('刷写完成，设备正在重启');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('刷写完成')),
        );
      } finally {
        await logSubscription.cancel();
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _status = '未连接到 ESP32 下载模式。请按住设备 BOOT/下载键，再短按 RESET 或重新插入 USB，然后重试。';
      });
      _addLog('失败: ESP32 下载模式连接超时');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '刷写失败: $error');
      _addLog('失败: $error');
    } finally {
      await _flasher.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('刷写固件')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.firmware.name, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('版本: ${widget.firmware.version}'),
                  Text('来源: ${widget.firmware.sourceLabel}'),
                  Text('本地文件: ${widget.firmware.localPath ?? '未下载'}'),
                  Text('固件类型: ${widget.firmware.flashOffset == 0 ? '完整镜像 (0x0)' : 'App 分区 (0x${widget.firmware.flashOffset.toRadixString(16)})'}'),
                  Text('烧录模式: $_burnModeLabel'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('USB 设备', style: Theme.of(context).textTheme.titleMedium),
                      ),
                      IconButton(
                        onPressed: _busy || _scanning ? null : _scanDevices,
                        icon: _scanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (_devices.isEmpty)
                    const Text('无设备', style: TextStyle(color: Colors.white54))
                  else
                    ..._devices.map((device) => ListTile(
                          dense: true,
                          title: Text(device.label),
                          leading: Radio<String>(
                            value: device.id,
                            groupValue: _selectedDevice?.id,
                            onChanged: _busy ? null : (_) => setState(() => _selectedDevice = device),
                          ),
                        )),
                  Text('烧录速度: ${_baudRateLabel(_baudRate)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (progress != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(progress.stage),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: progress.percent / 100),
                    const SizedBox(height: 8),
                    Text('${progress.percent.toStringAsFixed(1)}% · ${(progress.speedBytesPerSecond / 1024).toStringAsFixed(1)} KB/s'),
                  ],
                ),
              ),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_status!, style: const TextStyle(color: Colors.white70)),
            ),
          if (_logs.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('烧录日志', style: Theme.of(context).textTheme.titleMedium)),
                        TextButton(
                          onPressed: _busy ? null : () => setState(_logs.clear),
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF101011),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF2B2B2E)),
                      ),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: SelectableText(
                          _logs.join('\n'),
                          style: const TextStyle(fontSize: 11, height: 1.35, color: Colors.white70, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : _flash,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.flash_on),
            label: const Text('开始刷写'),
          ),
          const SizedBox(height: 8),
          const Text(
            '提示: 通过 USB-C OTG 连接目标设备。首次连接时系统可能会询问 USB 权限，请选择允许；如果没有弹窗但能看到设备，通常表示已授权。若一直卡在连接引导模式，请按住 BOOT/下载键后重置或重新插入 USB。',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
