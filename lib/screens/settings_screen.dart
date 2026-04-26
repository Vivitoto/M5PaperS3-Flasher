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
  String _burnMode = 'fast';
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
      _burnMode = _normalizeBurnMode(prefs.getString('eraseOption'));
    });
  }

  String _normalizeBurnMode(String? value) {
    return switch (value) {
      'clean' || 'all' => 'clean',
      _ => 'fast',
    };
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('githubToken', _githubTokenController.text.trim());
    await prefs.setString('customFirmwareUrl', _customUrlController.text.trim());
    await prefs.setInt('baudRate', _baudRate);
    await prefs.setString('eraseOption', _burnMode);
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

  String _baudRateLabel(int rate) {
    return switch (rate) {
      115200 => '115200 · 最稳',
      230400 => '230400 · 稳定',
      460800 => '460800 · 较快',
      921600 => '921600 · 最快',
      _ => '$rate',
    };
  }

  String get _burnModeSummary => _burnMode == 'clean'
      ? '先清空设备闪存，再写入完整固件；适合异常修复或换固件。'
      : '直接写入完整固件，不额外清空整颗闪存；适合日常升级。';

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
            title: '烧录设置',
            subtitle: '控制烧录速度，以及烧录前是否清空设备闪存',
            children: [
              DropdownButtonFormField<int>(
                value: _baudRate,
                decoration: const InputDecoration(
                  labelText: '烧录速度',
                  helperText: '也叫波特率。数值越高传输越快；如果烧录失败或中断，调低会更稳。',
                ),
                items: const [115200, 230400, 460800, 921600]
                    .map((rate) => DropdownMenuItem(value: rate, child: Text(_baudRateLabel(rate))))
                    .toList(),
                onChanged: (value) => setState(() => _baudRate = value ?? 115200),
              ),
              const SizedBox(height: 18),
              Text(
                '烧录模式',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              _BurnModeCard(
                selected: _burnMode == 'fast',
                title: '快速烧录',
                badge: '推荐',
                bullets: const [
                  '直接写入完整固件，不额外清空整颗闪存。',
                  '速度更快，适合正常升级、重复烧录同一个 Vink 固件。',
                  '大多数情况下选这个就够了。',
                ],
                onTap: () => setState(() => _burnMode = 'fast'),
              ),
              const SizedBox(height: 10),
              _BurnModeCard(
                selected: _burnMode == 'clean',
                title: '彻底烧录',
                badge: '修复用',
                bullets: const [
                  '先清空设备闪存，再写入完整固件。',
                  '更干净，但耗时更长。',
                  '适合从其他固件切换、设备异常、资源/配置残留导致问题时使用。',
                ],
                onTap: () => setState(() => _burnMode = 'clean'),
              ),
              const SizedBox(height: 12),
              Text(
                '当前选择：$_burnModeSummary',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54, height: 1.35),
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

class _BurnModeCard extends StatelessWidget {
  const _BurnModeCard({
    required this.selected,
    required this.title,
    required this.badge,
    required this.bullets,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String badge;
  final List<String> bullets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = selected ? Colors.white : Colors.white12;
    final backgroundColor = selected ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.03);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: selected ? 1.3 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? Colors.white : Colors.white38,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : Colors.white10,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: selected ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...bullets.map((text) => _Bullet(text: text)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.white54, height: 1.35)),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
