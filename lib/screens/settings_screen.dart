import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_update_service.dart';
import '../widgets/vink_chrome.dart';

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
      'lilygo_t5_47' || 'lilygo' || 't5_47' => 'lilygo_t5_47',
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
        'generic_esptool' => '通用 ESP32',
        'lilygo_t5_47' => 'LilyGo T5 4.7',
        _ => 'PaperS3 推荐',
      };

  String get _burnModeSummary => _burnMode == 'clean' ? '彻底烧录' : '快速烧录';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updateInfo = _updateInfo;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(toolbarHeight: 48, title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
        children: [
          const VinkHeroHeader(
            eyebrow: 'control center',
            title: '控制中心',
            subtitle: '烧录参数、固件源和应用更新，保持克制清楚。',
            icon: Icons.tune_rounded,
            trailing: VinkPill(
              icon: Icons.verified_rounded,
              text: '推荐',
              color: VinkColors.text,
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: '烧录设置',
            subtitle: '当前：$_flashProfileSummary · $_burnModeSummary',
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
              const SizedBox(height: 12),
              Text('烧录模式',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              _BurnModeCard(
                selected: _flashProfile == 'papers3',
                title: 'Paper S3',
                badge: '推荐',
                description: 'M5Stack PaperS3 / Vink-PaperS3',
                onTap: () => setState(() => _flashProfile = 'papers3'),
              ),
              const SizedBox(height: 6),
              _BurnModeCard(
                selected: _flashProfile == 'lilygo_t5_47',
                title: 'LilyGo T5',
                description: 'T5 4.7 英寸设备',
                onTap: () => setState(() => _flashProfile = 'lilygo_t5_47'),
              ),
              const SizedBox(height: 6),
              _BurnModeCard(
                selected: _flashProfile == 'generic_esptool',
                title: '通用模式',
                description: '已进入下载模式的 ESP32 设备',
                onTap: () => setState(() => _flashProfile = 'generic_esptool'),
              ),
              const SizedBox(height: 12),
              Text('写入方式',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              _BurnModeCard(
                selected: _burnMode == 'fast',
                title: '快速烧录',
                badge: '推荐',
                description: '日常推荐',
                onTap: () => setState(() => _burnMode = 'fast'),
              ),
              const SizedBox(height: 6),
              _BurnModeCard(
                selected: _burnMode == 'clean',
                title: '彻底烧录',
                description: '换固件或异常修复',
                onTap: () => setState(() => _burnMode = 'clean'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Section(
            title: '固件源',
            subtitle: '高级选项',
            children: [
              TextField(
                controller: _customUrlController,
                decoration: const InputDecoration(
                  labelText: '自定义固件 URL',
                  hintText: 'https://example.com/firmware.bin',
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _githubTokenController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'GitHub 令牌（可选）',
                  helperText: '可选',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Section(
            title: '应用更新',
            subtitle: updateInfo == null
                ? '检查 Vink Flasher 新版本'
                : '当前 ${updateInfo.currentVersion} · 最新 ${updateInfo.latestVersion}',
            children: [
              if (_updateStatus != null) ...[
                Text(_updateStatus!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: VinkColors.muted)),
                const SizedBox(height: 6),
              ],
              if (_downloadingUpdate) ...[
                LinearProgressIndicator(value: _updateProgress),
                const SizedBox(height: 6),
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
            ],
          ),
          const SizedBox(height: 12),
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
    return VinkGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900, letterSpacing: -0.25)),
          const SizedBox(height: 4),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: VinkColors.muted, height: 1.25)),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
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
    final borderColor = selected ? VinkColors.cyan : VinkColors.lineSoft;
    final backgroundColor = selected
        ? VinkColors.cyan.withOpacity(0.1)
        : Colors.white.withOpacity(0.035);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                color: selected ? VinkColors.cyan : VinkColors.muted,
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
                            color: selected ? VinkColors.cyan : Colors.white10,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: selected ? Colors.black : VinkColors.muted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: VinkColors.muted, height: 1.2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
