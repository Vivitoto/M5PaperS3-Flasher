import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  int _baudRate = 921600;
  String _burnMode = 'fast';
  String _flashProfile = 'papers3';
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
      _baudRate = prefs.getInt('baudRate') ?? 921600;
      _burnMode = _normalizeBurnMode(prefs.getString('eraseOption'));
      _flashProfile = _normalizeFlashProfile(prefs.getString('flashProfile'));
    });
  }

  String _normalizeBurnMode(String? value) {
    return switch (value) {
      'clean' || 'all' => 'clean',
      _ => 'fast',
    };
  }

  String _normalizeFlashProfile(String? value) {
    return switch (value) {
      'papers3' || 'manual' || 'official' || 'no_reset' => 'papers3',
      'generic_esptool' || 'generic' || 'esptool' => 'generic_esptool',
      'auto_reset' || 'usb_reset' => 'auto_reset',
      'ink_box' || 'inkBox' => 'ink_box',
      // v0.3.6/v0.3.7 stored legacy profiles which still relied on
      // automatic reset. Keep them on the PaperS3-specific path.
      'stable' || 'compatible' => 'papers3',
      _ => 'papers3',
    };
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('githubToken', _githubTokenController.text.trim());
    await prefs.setString(
        'customFirmwareUrl', _customUrlController.text.trim());
    await prefs.setInt('baudRate', _baudRate);
    await prefs.setString('eraseOption', _burnMode);
    await prefs.setString('flashProfile', _flashProfile);
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
            _updateProgress =
                total == null || total <= 0 ? null : received / total;
            _updateStatus = total == null
                ? '正在下载 ${_sizeLabel(received)}'
                : '正在下载 ${_sizeLabel(received)} / ${_sizeLabel(total)}';
          });
        },
      );
      if (!mounted) return;
      setState(() => _updateStatus = '已保存到系统 Downloads，正在打开安装器');
      await _updateService.installApk(apk);
    } catch (error) {
      if (!mounted) return;
      setState(() => _updateStatus = '更新失败: $error');
    } finally {
      if (mounted) setState(() => _downloadingUpdate = false);
    }
  }

  String _sizeLabel(int bytes) {
    if (bytes >= 1024 * 1024)
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  String _baudRateLabel(int rate) {
    return switch (rate) {
      115200 => '115200 · 稳定',
      230400 => '230400 · 均衡',
      460800 => '460800 · 快速',
      921600 => '921600 · 高速',
      _ => '$rate',
    };
  }

  String get _flashProfileSummary => switch (_flashProfile) {
        'generic_esptool' => '通用模式：esptool chip auto，预留给 LilyGo/其他 ESP32',
        'ink_box' => '兼容模式：按 Ink Box 参数验证烧录',
        'auto_reset' => '自动模式：尝试 USB-JTAG DTR/RTS 复位',
        _ => 'PaperS3 专用模式：0xFlash 兼容烧录链路',
      };

  String get _burnModeSummary =>
      _burnMode == 'clean' ? '彻底烧录：按写入范围覆盖完整镜像' : '快速烧录：直接写入完整固件';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updateInfo = _updateInfo;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 22),
        children: [
          _Section(
            title: '烧录设置',
            subtitle: '$_flashProfileSummary · $_burnModeSummary',
            children: [
              DropdownButtonFormField<int>(
                value: _baudRate,
                decoration: const InputDecoration(labelText: '烧录速度'),
                items: const [115200, 230400, 460800, 921600]
                    .map((rate) => DropdownMenuItem(
                        value: rate, child: Text(_baudRateLabel(rate))))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _baudRate = value ?? 115200),
              ),
              const SizedBox(height: 14),
              Text('烧录逻辑',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _BurnModeCard(
                selected: _flashProfile == 'papers3',
                title: 'PaperS3 专用模式',
                badge: '推荐',
                description:
                    '面向 Vink-PaperS3：按 M5Stack 官方方式进入下载模式，并使用 0xFlash 兼容的 ESP ROM 烧录链路。不要用于其他 ESP32 设备。',
                onTap: () => setState(() => _flashProfile = 'papers3'),
              ),
              const SizedBox(height: 8),
              _BurnModeCard(
                selected: _flashProfile == 'generic_esptool',
                title: '通用 esptool 模式',
                badge: '预留',
                description:
                    '面向 LilyGo/其他 ESP32 设备扩展：chip auto、default_reset、hard_reset，由设备配置决定固件和 offset。当前仍需对应设备 profile 后再推荐使用。',
                onTap: () => setState(() => _flashProfile = 'generic_esptool'),
              ),
              const SizedBox(height: 8),
              _BurnModeCard(
                selected: _flashProfile == 'auto_reset',
                title: 'PaperS3 自动复位备用',
                description:
                    '尝试通过 USB-JTAG DTR/RTS 自动进入下载模式。作为 PaperS3 备用，不推荐给其他设备。',
                onTap: () => setState(() => _flashProfile = 'auto_reset'),
              ),
              const SizedBox(height: 8),
              _BurnModeCard(
                selected: _flashProfile == 'ink_box',
                title: 'Ink Box 对照模式',
                description:
                    '按 Ink Box 参数验证：chip auto、default_reset、no-stub、固定 460800。仅用于对照测试。',
                onTap: () => setState(() => _flashProfile = 'ink_box'),
              ),
              const SizedBox(height: 14),
              Text('写入方式',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _BurnModeCard(
                selected: _burnMode == 'fast',
                title: '快速烧录',
                badge: '推荐',
                description: '不额外清空整颗闪存，直接写入完整固件。适合日常升级、重复烧录 Vink 固件。',
                onTap: () => setState(() => _burnMode = 'fast'),
              ),
              const SizedBox(height: 8),
              _BurnModeCard(
                selected: _burnMode == 'clean',
                title: '彻底烧录',
                description: '写入完整镜像并覆盖目标写入范围。适合换固件、设备异常或残留数据导致问题。',
                onTap: () => setState(() => _burnMode = 'clean'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Section(
            title: '固件源',
            subtitle: '自定义下载地址和 GitHub 访问',
            children: [
              TextField(
                controller: _customUrlController,
                decoration: const InputDecoration(
                  labelText: '自定义固件 URL',
                  hintText: 'https://example.com/firmware.bin',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _githubTokenController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'GitHub 令牌（可选）',
                  helperText: '私有仓库或 API 限额不足时使用',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Section(
            title: '应用更新',
            subtitle: updateInfo == null
                ? '检查 Vink Flasher 新版本'
                : '当前 ${updateInfo.currentVersion} · 最新 ${updateInfo.latestVersion}',
            children: [
              if (_updateStatus != null) ...[
                Text(_updateStatus!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white70)),
                const SizedBox(height: 10),
              ],
              if (_downloadingUpdate) ...[
                LinearProgressIndicator(value: _updateProgress),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _checkingUpdate || _downloadingUpdate
                          ? null
                          : _checkUpdate,
                      icon: _checkingUpdate
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.system_update_alt_rounded),
                      label: const Text('检查更新'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: updateInfo?.hasUpdate == true &&
                              !_checkingUpdate &&
                              !_downloadingUpdate
                          ? _downloadAndInstallUpdate
                          : null,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('下载安装'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'APK 会保存到系统 Downloads，不再占用应用临时缓存。下载完成后会打开系统安装器；如被拦截，请允许 Vink Flasher 安装未知来源应用。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.white38, height: 1.35),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('保存设置'),
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800, letterSpacing: -0.2)),
            const SizedBox(height: 3),
            Text(subtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.white38, height: 1.25)),
            const SizedBox(height: 12),
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
    this.badge,
    required this.description,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String? badge;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = selected ? Colors.white : Colors.white12;
    final backgroundColor = selected
        ? Colors.white.withOpacity(0.08)
        : Colors.white.withOpacity(0.03);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: selected ? 1.2 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? Colors.white : Colors.white38,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: selected ? Colors.white : Colors.white10,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: selected ? Colors.black : Colors.white60,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(description,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white54, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
