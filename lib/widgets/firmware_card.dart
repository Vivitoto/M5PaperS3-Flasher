import 'package:flutter/material.dart';

import '../models/firmware.dart';
import '../services/download_manager.dart';

class FirmwareCard extends StatelessWidget {
  const FirmwareCard({
    super.key,
    required this.firmwares,
    required this.onDownload,
    required this.onFlash,
    required this.isDownloading,
    required this.downloadProgress,
    required this.localStatus,
    required this.partialBytes,
  });

  final List<Firmware> firmwares;
  final void Function(Firmware firmware, {bool force}) onDownload;
  final void Function(Firmware firmware) onFlash;
  final bool Function(Firmware firmware) isDownloading;
  final double? Function(Firmware firmware) downloadProgress;
  final LocalFirmwareStatus Function(Firmware firmware) localStatus;
  final int? Function(Firmware firmware) partialBytes;

  Firmware get latest => firmwares.first;
  List<Firmware> get history => firmwares.length <= 1 ? const [] : firmwares.skip(1).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloading = isDownloading(latest);
    final progress = downloadProgress(latest);
    final status = localStatus(latest);
    final downloaded = status == LocalFirmwareStatus.complete;
    final partial = status == LocalFirmwareStatus.partial;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                      Text(
                        latest.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        latest.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Chip(
                  label: Text(latest.sourceLabel, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaPill(icon: Icons.tag_rounded, text: latest.version),
                _MetaPill(icon: Icons.sd_storage_outlined, text: latest.sizeLabel),
                _MetaPill(icon: Icons.memory_rounded, text: latest.flashOffset == 0 ? '完整镜像' : 'App分区'),
              ],
            ),
            const SizedBox(height: 12),
            _LocalStatusLine(
              status: status,
              partialBytes: partialBytes(latest),
              totalBytes: latest.sizeBytes,
            ),
            const SizedBox(height: 12),
            _ChangelogTile(
              title: '最新更新内容',
              subtitle: latest.description,
              changelog: latest.changelog,
              initiallyExpanded: false,
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 4),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text('历史版本', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text('${history.length} 个版本', style: const TextStyle(color: Colors.white54)),
                  children: [
                    for (final item in history)
                      _ChangelogTile(
                        title: item.version,
                        subtitle: item.description,
                        changelog: item.changelog,
                        initiallyExpanded: false,
                        dense: true,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (downloading)
              _Downloading(progress: progress)
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => onDownload(latest, force: downloaded),
                      icon: Icon(downloaded ? Icons.refresh_rounded : Icons.download_rounded),
                      label: Text(downloaded
                          ? '重新下载'
                          : partial
                              ? '继续下载'
                              : '下载'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onFlash(latest),
                      icon: const Icon(Icons.bolt_rounded),
                      label: Text(downloaded ? '刷写' : '下载并刷写'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF202022),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF303033)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF202022),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF303033)),
      ),
      child: Row(
        children: [
          SizedBox(width: 26, height: 26, child: CircularProgressIndicator(value: progress, strokeWidth: 3)),
          const SizedBox(width: 12),
          Text(progress == null ? '下载中...' : '${(progress! * 100).clamp(0, 100).toStringAsFixed(0)}%'),
        ],
      ),
    );
  }
}

class _LocalStatusLine extends StatelessWidget {
  const _LocalStatusLine({
    required this.status,
    required this.partialBytes,
    required this.totalBytes,
  });

  final LocalFirmwareStatus status;
  final int? partialBytes;
  final int? totalBytes;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (status) {
      LocalFirmwareStatus.complete => (Icons.check_circle_rounded, '已下载，可直接刷写', Colors.white),
      LocalFirmwareStatus.partial => (
          Icons.downloading_rounded,
          '已下载 ${_sizeLabel(partialBytes)}${totalBytes == null ? '' : ' / ${_sizeLabel(totalBytes)}'}，可继续下载',
          Colors.white70,
        ),
      LocalFirmwareStatus.none => (Icons.cloud_download_outlined, '未下载', Colors.white54),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF101011),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2B2B2E)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  String _sizeLabel(int? bytes) {
    final value = bytes;
    if (value == null || value <= 0) return '0 B';
    if (value >= 1024 * 1024) return '${(value / 1024 / 1024).toStringAsFixed(2)} MB';
    if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    return '$value B';
  }
}

class _ChangelogTile extends StatelessWidget {
  const _ChangelogTile({
    required this.title,
    required this.subtitle,
    required this.changelog,
    required this.initiallyExpanded,
    this.dense = false,
  });

  final String title;
  final String subtitle;
  final String changelog;
  final bool initiallyExpanded;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _plainChangelog(changelog.trim().isEmpty ? subtitle : changelog.trim());

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.only(left: dense ? 16 : 0, right: 0, bottom: 10),
        initiallyExpanded: initiallyExpanded,
        title: Text(
          title,
          style: dense ? theme.textTheme.titleSmall : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: dense && subtitle.trim().isNotEmpty
            ? Text(_plainChangelog(subtitle), maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white60, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  String _plainChangelog(String value) {
    return value
        .split('\n')
        .map((line) => line
            .replaceAll(RegExp(r'^#{1,6}\s*'), '')
            .replaceAll(RegExp(r'^[-*]\s+'), '• ')
            .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
            .replaceAll('**', '')
            .trimRight())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
