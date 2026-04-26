import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _githubTokenController = TextEditingController();
  final _customUrlController = TextEditingController();
  final _updateService = AppUpdateService();
  int _baudRate = 115200;
  String _eraseOption = 'none';
  AppUpdateInfo? _updateInfo;
  bool _checkingUpdate = false;
  bool _downloadingUpdate = false;
  double? _updateProgress;
  String? _updateStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _githubTokenController.dispose();
    _customUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _githubTokenController.text = prefs.getString('githubToken') ?? '';
      _customUrlController.text = prefs.getString('customFirmwareUrl') ?? '';
      _baudRate = prefs.getInt('baudRate') ?? 115200;
      _eraseOption = prefs.getString('eraseOption') ?? 'none';
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('githubToken', _githubTokenController.text.trim());
    await prefs.setString('customFirmwareUrl', _customUrlController.text.trim());
    await prefs.setInt('baudRate', _baudRate);
    await prefs.setString('eraseOption', _eraseOption);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设置已保存')),
    );
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _updateStatus = '正在检查更新...';
      _updateProgress = null;
    });
    try {
      final info = await _updateService.checkLatest();
      if (!mounted) return;
      setState(() {
        _updateInfo = info;
        _updateStatus = info.hasUpdate
            ? '发现新版本 ${info.latestVersion}'
            : '当前已是最新版本 ${info.currentVersion}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _updateStatus = '检查更新失败: $error');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _downloadAndInstallUpdate() async {
    final info = _updateInfo;
    if (info == null) return;
    setState(() {
      _downloadingUpdate = true;
      _updateStatus = '正在下载 ${info.apkName}';
      _updateProgress = null;
    });
    try {
      final apk = await _updateService.downloadApk(
        info,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _updateProgress = total == null || total <= 0 ? null : received / total;
            _updateStatus = total == null
                ? '正在下载 ${_sizeLabel(received)}'
                : '正在下载 ${_sizeLabel(received)} / ${_sizeLabel(total)}';
          });
        },
      );
      if (!mounted) return;
      setState(() => _updateStatus = '下载完成，正在打开安装器');
      await _updateService.installApk(apk);
    } catch (error) {
      if (!mounted) return;
      setState(() => _updateStatus = '更新失败: $error');
    } finally {
      if (mounted) setState(() => _downloadingUpdate = false);
    }
  }

  Future<void> _openM5StackFlashMode() async {
    final uri = Uri.parse('https://api.m5stack.com/flash_mode/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _sizeLabel(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updateInfo = _updateInfo;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _Section(
            title: '应用更新',
            subtitle: updateInfo == null
                ? '检查 Vink Flasher 新版本'
                : '当前 ${updateInfo.currentVersion} · 最新 ${updateInfo.latestVersion}',
            children: [
              if (_updateStatus != null) ...[
                Text(_updateStatus!, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                const SizedBox(height: 12),
              ],
              if (_downloadingUpdate) ...[
                LinearProgressIndicator(value: _updateProgress),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _checkingUpdate || _downloadingUpdate ? null : _checkUpdate,
                      icon: _checkingUpdate
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.system_update_alt_rounded),
                      label: const Text('检查更新'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: updateInfo?.hasUpdate == true && !_checkingUpdate && !_downloadingUpdate
                          ? _downloadAndInstallUpdate
                          : null,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('下载并安装'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '下载完成后会打开系统安装器。若系统提示禁止安装未知来源应用，请允许 Vink Flasher 安装更新。',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: '固件源',
            subtitle: '仓库访问和自定义固件地址',
            children: [
              TextField(
                controller: _githubTokenController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'GitHub 令牌（可选）',
                  helperText: '用于私有仓库或更高 API 限额',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _customUrlController,
                decoration: const InputDecoration(
                  labelText: '自定义固件 URL',
                  hintText: 'https://example.com/firmware.bin',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: '刷写',
            subtitle: '串口速度与擦除策略',
            children: [
              DropdownButtonFormField<int>(
                value: _baudRate,
                decoration: const InputDecoration(labelText: '波特率'),
                items: const [115200, 230400, 460800, 921600]
                    .map((rate) => DropdownMenuItem(value: rate, child: Text('$rate')))
                    .toList(),
                onChanged: (value) => setState(() => _baudRate = value ?? 115200),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _eraseOption,
                decoration: const InputDecoration(labelText: '擦除选项'),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('不擦除')),
                  DropdownMenuItem(value: 'all', child: Text('全部擦除')),
                  DropdownMenuItem(value: 'sectors', child: Text('擦除扇区')),
                ],
                onChanged: (value) => setState(() => _eraseOption = value ?? 'none'),
              ),
              const SizedBox(height: 10),
              Text(
                '擦除选项已保存，后续可接入完整 esptool 擦除命令。',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('保存设置'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _openM5StackFlashMode,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('打开 M5Stack 官方刷机目录'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white54)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
