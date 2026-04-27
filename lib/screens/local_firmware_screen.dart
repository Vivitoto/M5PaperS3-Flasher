import 'package:flutter/material.dart';

import '../models/firmware.dart';
import '../services/download_manager.dart';
import '../services/firmware_source.dart';
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

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Firmware>> _load() async {
    final firmwares = await _repository.fetchAllFirmwares();
    await _hydrate(firmwares);
    return firmwares;
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
      appBar: AppBar(
        title: const Text('本地 / 烧录'),
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
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 22),
              children: [
                _IntroCard(localCount: localFirmwares.length),
                const SizedBox(height: 10),
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
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.localCount});

  final int localCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF202022),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.folder_copy_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('本地固件与烧录入口',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    localCount == 0
                        ? '先到“固件”页下载需要的版本，然后在这里统一管理和烧录。'
                        : '已缓存 $localCount 个固件版本，可删除或指定版本烧录。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white54, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLocalFirmware extends StatelessWidget {
  const _EmptyLocalFirmware();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 42, color: Colors.white38),
            const SizedBox(height: 10),
            Text('暂无本地固件', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              '从“固件”页下载最新版或历史版本后，会出现在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(firmware.name,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(firmware.version,
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                Chip(
                  label: Text(complete ? '可烧录' : '未完成',
                      style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _MetaPill(
                    icon: Icons.sd_storage_outlined, text: firmware.sizeLabel),
                _MetaPill(
                    icon: Icons.memory_rounded,
                    text: firmware.flashOffset == 0
                        ? '完整镜像'
                        : 'Offset 0x${firmware.flashOffset.toRadixString(16)}'),
                _MetaPill(
                    icon: Icons.cloud_outlined, text: firmware.sourceLabel),
              ],
            ),
            const SizedBox(height: 10),
            _StatusLine(info: info),
            if (info.filePath != null) ...[
              const SizedBox(height: 8),
              Text(
                info.filePath!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.white38, fontFamily: 'monospace'),
              ),
            ],
            const SizedBox(height: 12),
            if (isDownloading) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                  progress == null
                      ? '下载中...'
                      : '下载中 ${(progress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white70)),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: complete ? onFlash : onDownload,
                      icon: Icon(complete
                          ? Icons.bolt_rounded
                          : Icons.download_rounded),
                      label: Text(complete
                          ? '刷写此版本'
                          : partial
                              ? '继续下载'
                              : '下载'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDownload,
                      icon: Icon(complete
                          ? Icons.refresh_rounded
                          : Icons.download_rounded),
                      label: Text(complete ? '重新下载' : '下载'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('删除本地固件'),
                ),
              ),
            ],
          ],
        ),
      ),
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
          '已下载 ${_sizeLabel(info.receivedBytes)}，可直接烧录',
          Colors.white,
        ),
      LocalFirmwareStatus.partial => (
          Icons.downloading_rounded,
          '已下载 ${_sizeLabel(info.receivedBytes)}${info.totalBytes == null ? '' : ' / ${_sizeLabel(info.totalBytes!)}'}，可继续下载或删除',
          Colors.white70,
        ),
      LocalFirmwareStatus.none => (
          Icons.cloud_download_outlined,
          '未下载',
          Colors.white54
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF101011),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2B2B2E)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  String _sizeLabel(int bytes) {
    if (bytes >= 1024 * 1024)
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF202022),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF303033)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
