import 'dart:async';

import 'package:flutter/material.dart';

import '../models/firmware.dart';
import '../services/download_manager.dart';
import '../services/firmware_source.dart';
import '../widgets/vink_chrome.dart';
import 'flash_screen.dart';

class LocalFirmwareScreen extends StatefulWidget {
  const LocalFirmwareScreen({super.key});

  @override
  State<LocalFirmwareScreen> createState() => _LocalFirmwareScreenState();
}

class _LocalFirmwareScreenState extends State<LocalFirmwareScreen> {
  final _repository = FirmwareRepository();
  final _downloadManager = DownloadManager();
  late Future<List<Firmware>> _future;
  final Map<String, LocalFirmwareInfo> _localInfo = {};
  final Map<String, double?> _downloadProgress = {};
  Object? _loadWarning;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Firmware>> _load() async {
    final generation = ++_loadGeneration;
    _loadWarning = null;

    final localFirmwares = await _downloadManager.scanLocalFirmwares();
    _hydrateScannedLocal(localFirmwares);

    // 本地/烧录页必须离线优先：进入页面和点击烧录都不能等待远端 manifest。
    // 远端只用于补全版本说明/Release 链接，放后台做，失败或超时只显示提示。
    if (localFirmwares.isNotEmpty) {
      unawaited(_mergeRemoteMetadataInBackground(generation, localFirmwares));
    }

    return localFirmwares;
  }

  Future<void> _mergeRemoteMetadataInBackground(
    int generation,
    List<Firmware> localFirmwares,
  ) async {
    try {
      final remoteFirmwares = await _repository
          .fetchAllFirmwares()
          .timeout(const Duration(seconds: 4));
      await _hydrate(remoteFirmwares);
      final merged = _mergeRemoteMetadata(localFirmwares, remoteFirmwares);
      if (!mounted || generation != _loadGeneration || merged.isEmpty) return;
      setState(() {
        _loadWarning = null;
        _future = Future.value(merged);
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadWarning = error);
    }
  }

  void _hydrateScannedLocal(List<Firmware> firmwares) {
    _localInfo.clear();
    for (final firmware in firmwares) {
      final path = firmware.localPath;
      final size = firmware.sizeBytes ?? 0;
      _localInfo[firmware.id] = LocalFirmwareInfo(
        status: LocalFirmwareStatus.complete,
        filePath: path,
        receivedBytes: size,
        totalBytes: size,
      );
    }
  }

  List<Firmware> _mergeRemoteMetadata(
    List<Firmware> localFirmwares,
    List<Firmware> remoteFirmwares,
  ) {
    if (localFirmwares.isEmpty) return const <Firmware>[];

    final remoteByAsset = <String, Firmware>{};
    for (final firmware in remoteFirmwares) {
      final asset = Uri.tryParse(firmware.downloadUrl)?.pathSegments.last;
      if (asset != null && asset.isNotEmpty) remoteByAsset[asset] = firmware;
    }

    return localFirmwares.map((local) {
      final asset = Uri.tryParse(local.downloadUrl)?.pathSegments.last;
      final remote = asset == null ? null : remoteByAsset[asset];
      if (remote == null) return local;

      final info = _localInfo.remove(local.id);
      if (info != null) _localInfo[remote.id] = info;
      return remote.copyWith(localPath: local.localPath);
    }).toList();
  }

  Future<void> _hydrate(List<Firmware> firmwares) async {
    for (final firmware in firmwares) {
      _localInfo[firmware.id] = await _downloadManager.localInfo(firmware);
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _download(Firmware firmware, {bool force = false}) async {
    setState(() => _downloadProgress[firmware.id] = null);
    try {
      await for (final progress
          in _downloadManager.download(firmware, force: force)) {
        if (!mounted) return;
        setState(() {
          _downloadProgress[firmware.id] = progress.fraction;
          _localInfo[firmware.id] = LocalFirmwareInfo(
            status: progress.filePath == null
                ? LocalFirmwareStatus.partial
                : LocalFirmwareStatus.complete,
            filePath: progress.filePath,
            receivedBytes: progress.receivedBytes,
            totalBytes: progress.totalBytes,
          );
          if (progress.filePath != null) _downloadProgress.remove(firmware.id);
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${firmware.version} 下载完成')),
      );
    } catch (error) {
      final info = await _downloadManager.localInfo(firmware);
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(firmware.id);
        _localInfo[firmware.id] = info;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败: $error')),
      );
    }
  }

  Future<void> _delete(Firmware firmware) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本地固件？'),
        content: Text('将删除 ${firmware.name} ${firmware.version} 的本地文件和未完成下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _downloadManager.delete(firmware);
    final info = await _downloadManager.localInfo(firmware);
    if (!mounted) return;
    setState(() {
      _downloadProgress.remove(firmware.id);
      _localInfo[firmware.id] = info;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('本地固件已删除')),
    );
  }

  Future<void> _openFlash(Firmware firmware) async {
    var info =
        _localInfo[firmware.id] ?? await _downloadManager.localInfo(firmware);
    if (info.status != LocalFirmwareStatus.complete || info.filePath == null) {
      await _download(firmware);
      info =
          _localInfo[firmware.id] ?? await _downloadManager.localInfo(firmware);
    }
    if (!mounted || info.filePath == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            FlashScreen(firmware: firmware.copyWith(localPath: info.filePath)),
      ),
    );
  }

  List<Firmware> _localFirmwares(List<Firmware> firmwares) {
    return firmwares.where((firmware) {
      final info = _localInfo[firmware.id];
      return info != null && info.status != LocalFirmwareStatus.none;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: 48,
        title: const Text('本地烧录'),
        actions: [
          IconButton(
              onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: FutureBuilder<List<Firmware>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }

          final firmwares = snapshot.data ?? const <Firmware>[];
          final localFirmwares = _localFirmwares(firmwares);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
              children: [
                VinkHeroHeader(
                  title: '本地烧录台',
                  icon: Icons.auto_stories_rounded,
                  trailing: VinkPill(
                    icon: localFirmwares.isEmpty
                        ? Icons.inventory_2_outlined
                        : Icons.check_circle_rounded,
                    text: '${localFirmwares.length} 个',
                    color: localFirmwares.isEmpty
                        ? VinkColors.muted
                        : VinkColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                if (_loadWarning != null) ...[
                  _OfflineLocalNotice(error: _loadWarning!),
                  const SizedBox(height: 10),
                ],
                if (localFirmwares.isEmpty)
                  const _EmptyLocalFirmware()
                else
                  for (final firmware in localFirmwares) ...[
                    _LocalFirmwareCard(
                      firmware: firmware,
                      info: _localInfo[firmware.id]!,
                      progress: _downloadProgress[firmware.id],
                      isDownloading: _downloadProgress.containsKey(firmware.id),
                      onDownload: () => _download(
                        firmware,
                        force: _localInfo[firmware.id]?.status ==
                            LocalFirmwareStatus.complete,
                      ),
                      onDelete: () => _delete(firmware),
                      onFlash: () => _openFlash(firmware),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OfflineLocalNotice extends StatelessWidget {
  const _OfflineLocalNotice({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: VinkColors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VinkColors.amber.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: VinkColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '远端信息暂不可用，已显示本地固件',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: VinkColors.muted, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLocalFirmware extends StatelessWidget {
  const _EmptyLocalFirmware();

  @override
  Widget build(BuildContext context) {
    return VinkGlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined,
              size: 34, color: VinkColors.muted),
          const SizedBox(height: 6),
          Text('暂无本地固件', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            '先到“固件库”下载。',
            textAlign: TextAlign.center,
            style: TextStyle(color: VinkColors.muted),
          ),
        ],
      ),
    );
  }
}

class _LocalFirmwareCard extends StatelessWidget {
  const _LocalFirmwareCard({
    required this.firmware,
    required this.info,
    required this.progress,
    required this.isDownloading,
    required this.onDownload,
    required this.onDelete,
    required this.onFlash,
  });

  final Firmware firmware;
  final LocalFirmwareInfo info;
  final double? progress;
  final bool isDownloading;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onFlash;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = info.status == LocalFirmwareStatus.complete;
    final partial = info.status == LocalFirmwareStatus.partial;

    return VinkGlassCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VinkIconTile(
                icon: complete
                    ? Icons.flash_on_rounded
                    : Icons.downloading_rounded,
                color: complete ? VinkColors.mint : VinkColors.amber,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(firmware.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.35)),
                        ),
                        const SizedBox(width: 8),
                        VinkPill(
                          icon: complete
                              ? Icons.check_circle_rounded
                              : Icons.downloading_rounded,
                          text: complete ? '可烧录' : '未完成',
                          color: complete ? VinkColors.mint : VinkColors.amber,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        VinkPill(
                          icon: Icons.new_releases_rounded,
                          text: firmware.version,
                          color: VinkColors.blue,
                        ),
                        VinkPill(
                          icon: firmware.flashOffset == 0
                              ? Icons.all_inclusive_rounded
                              : Icons.app_shortcut_rounded,
                          text: firmware.flashOffset == 0 ? '完整镜像' : 'App 分区',
                          color: firmware.flashOffset == 0
                              ? VinkColors.mint
                              : VinkColors.amber,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            firmware.sizeLabel,
            style: theme.textTheme.bodySmall?.copyWith(color: VinkColors.muted),
          ),
          const SizedBox(height: 6),
          _StatusLine(info: info),
          const SizedBox(height: 8),
          if (isDownloading)
            _Downloading(progress: progress)
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: complete ? onFlash : onDownload,
                    icon: Icon(
                        complete ? Icons.bolt_rounded : Icons.download_rounded),
                    label: Text(complete
                        ? '刷写'
                        : partial
                            ? '继续下载'
                            : '下载'),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: complete ? '重新下载' : '下载',
                  onPressed: onDownload,
                  icon: Icon(complete
                      ? Icons.refresh_rounded
                      : Icons.download_rounded),
                ),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '删除本地固件',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Downloading extends StatelessWidget {
  const _Downloading({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: LinearProgressIndicator(value: progress)),
        const SizedBox(width: 8),
        Text(
          progress == null
              ? '下载中'
              : '${(progress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
          style: const TextStyle(color: VinkColors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.info});

  final LocalFirmwareInfo info;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (info.status) {
      LocalFirmwareStatus.complete => (
          Icons.check_circle_rounded,
          '可烧录',
          VinkColors.mint,
        ),
      LocalFirmwareStatus.partial => (
          Icons.downloading_rounded,
          '未完成，可继续下载',
          VinkColors.cyan,
        ),
      LocalFirmwareStatus.none => (
          Icons.cloud_download_outlined,
          '未下载',
          VinkColors.muted
        ),
    };

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
