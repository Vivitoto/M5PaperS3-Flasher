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
  List<dynamic> _devices = const [];
  dynamic _selectedDevice;
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

  Future<void> _scanDevices() async {
    try {
      final devices = await EspFlasher.listDevices();
      setState(() {
        _devices = devices;
        _selectedDevice ??= devices.isNotEmpty ? devices.first : null;
      });
    } catch (error) {
      setState(() => _status = 'USB scan failed / USB 扫描失败: $error');
    }
  }

  Future<void> _flash() async {
    final device = _selectedDevice;
    final path = widget.firmware.localPath;
    if (device == null) {
      setState(() => _status = 'No USB serial device selected / 未选择 USB 串口设备');
      return;
    }
    if (path == null || !await File(path).exists()) {
      setState(() => _status = 'Firmware not downloaded / 固件尚未下载');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Opening USB serial at $_baudRate baud / 正在打开串口';
    });

    try {
      await _flasher.connect(device, baudRate: _baudRate);
      await for (final progress in _flasher.flashFile(File(path))) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
          _status = progress.stage;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flash complete / 刷写完成')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Flash failed / 刷写失败: $error');
    } finally {
      await _flasher.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('Flash Firmware / 刷写固件')),
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
                  Text('Version / 版本: ${widget.firmware.version}'),
                  Text('Source / 来源: ${widget.firmware.sourceLabel}'),
                  Text('Local file / 本地文件: ${widget.firmware.localPath ?? 'Not downloaded / 未下载'}'),
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
                        child: Text('USB Devices / USB 设备', style: Theme.of(context).textTheme.titleMedium),
                      ),
                      IconButton(onPressed: _scanDevices, icon: const Icon(Icons.usb)),
                    ],
                  ),
                  if (_devices.isEmpty)
                    const Text('No devices / 无设备', style: TextStyle(color: Colors.white54))
                  else
                    ..._devices.map((device) => ListTile(
                      dense: true,
                      title: Text(device.toString()),
                      leading: Radio<dynamic>(
                        value: device,
                        groupValue: _selectedDevice,
                        onChanged: _busy ? null : (v) => setState(() => _selectedDevice = v),
                      ),
                    )),
                  Text('Baud rate / 波特率: $_baudRate'),
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
            label: const Text('Start Flash / 开始刷写'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tip / 提示: connect M5PaperS3 over USB-C. The app toggles DTR/RTS to enter ESP32 download mode, then sends SYNC, FLASH_BEGIN, FLASH_DATA, FLASH_END packets using SLIP framing.',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}