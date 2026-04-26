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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    latest.name,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: Text(latest.sourceLabel, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('最新版本: ${latest.version}'),
            Text('大小: ${latest.sizeLabel}'),
            Text('烧录: ${latest.flashOffset == 0 ? '完整镜像' : 'App分区'}'),
            const SizedBox(height: 8),
            _LocalStatusLine(
              status: status,
              partialBytes: partialBytes(latest),
              totalBytes: latest.sizeBytes,
            ),
            const SizedBox(height: 10),
            _ChangelogTile(
              title: '最新更新内容',
              subtitle: latest.description,
              changelog: latest.changelog,
              initiallyExpanded: true,
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 6),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text('历史版本（${history.length}）'),
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
            const SizedBox(height: 16),
            Row(
              children: [
                if (downloading) ...[
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(value: progress),
                  ),
                  const SizedBox(width: 12),
                  Text(progress == null
                      ? '下载中...'
                      : '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%'),
                  const Spacer(),
                ] else ...[
                  FilledButton.icon(
                    onPressed: () => onDownload(latest, force: downloaded),
                    icon: Icon(downloaded ? Icons.refresh : Icons.download),
                    label: Text(downloaded
                        ? '重新下载'
                        : partial
                            ? '继续下载'
                            : '下载最新版'),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: () => onFlash(latest),
                  icon: const Icon(Icons.flash_on),
                  label: Text(downloaded ? '刷写已下载' : '下载并刷写'),
                ),
              ],
            ),
          ],
        ),
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
      LocalFirmwareStatus.complete => (Icons.check_circle, '本地: 已下载，可直接刷写', Colors.lightGreenAccent),
      LocalFirmwareStatus.partial => (
          Icons.downloading,
          '本地: 已下载 ${_sizeLabel(partialBytes)}${totalBytes == null ? '' : ' / ${_sizeLabel(totalBytes)}'}，可继续下载',
          Colors.amberAccent,
        ),
      LocalFirmwareStatus.none => (Icons.cloud_download_outlined, '本地: 未下载', Colors.white54),
    };

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13))),
      ],
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
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
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
