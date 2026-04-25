import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/firmware.dart';
import '../services/esp_flasher.dart';

class FlashScreen extends StatefulWidget {
  const FlashScreen({super.key, required this.firmware});

  final Firmware firmware;

  @override
  State<FlashScreen> createState() => _FlashScreenState();
}

class _FlashScreenState extends State<FlashScreen> {
  final _flasher = EspFlasher();
  List<String> _devices = const [];
  String? _selectedDevice;
  FlashProgress? _progress;
  bool _busy = false;
  String? _status;
  int _baudRate = 115200;

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
    setState(() => _baudRate = prefs.getInt('baudRate') ?? 115200);
  }

  void _scanDevices() {
    try {
      final devices = EspFlasher.listDevices();
      setState(() {
        _devices = devices;
        _selectedDevice ??= devices.isNotEmpty ? devices.first : null;
      });
    } catch (error) {
      setState(() => _status = 'USB 扫描失败: $error');
    }
  }

  Future<void> _flash() async {
    final device = _selectedDevice;
    final path = widget.firmware.localPath;
    if (device == null || device.isEmpty) {
      setState(() => _status = '未选择 USB 串口设备');
      return;
    }
    if (path == null || !await File(path).exists()) {
      setState(() => _status = '固件尚未下载');
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在打开串口 ($_baudRate 波特率)';
    });

    try {
      await _flasher.connect(device, baudRate: _baudRate);
      await for (final progress in _flasher.flashFile(File(path), flashOffset: widget.firmware.flashOffset)) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
          _status = progress.stage;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('刷写完成')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '刷写失败: $error');
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
                  Text("烧录模式: ${widget.firmware.flashOffset == 0 ? '完整镜像(0x0)' : 'App分区(0x${widget.firmware.flashOffset.toRadixString(16)})'}"),
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
                      IconButton(onPressed: _scanDevices, icon: const Icon(Icons.refresh)),
                    ],
                  ),
                  if (_devices.isEmpty)
                    const Text('无设备', style: TextStyle(color: Colors.white54))
                  else
                    ..._devices.map((device) => ListTile(
                      dense: true,
                      title: Text(device),
                      leading: Radio<String>(
                        value: device,
                        groupValue: _selectedDevice,
                        onChanged: _busy ? null : (v) => setState(() => _selectedDevice = v),
                      ),
                    )),
                  Text('波特率: $_baudRate'),
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
          FilledButton.icon(
            onPressed: _busy ? null : _flash,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.flash_on),
            label: const Text('开始刷写'),
          ),
          const SizedBox(height: 8),
          const Text(
            '提示: 通过 USB-C OTG 连接 M5PaperS3，点击开始刷写后自动进入下载模式。默认写入完整镜像，包含分区表、固件和资源。',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
