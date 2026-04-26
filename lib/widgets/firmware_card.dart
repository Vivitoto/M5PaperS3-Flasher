import 'package:flutter/material.dart';

import '../models/firmware.dart';

class FirmwareCard extends StatefulWidget {
  const FirmwareCard({
    super.key,
    required this.firmwares,
    required this.onDownload,
    required this.onFlash,
    required this.isDownloading,
    required this.downloadProgress,
  });

  final List<Firmware> firmwares;
  final void Function(Firmware firmware) onDownload;
  final void Function(Firmware firmware) onFlash;
  final bool Function(Firmware firmware) isDownloading;
  final double? Function(Firmware firmware) downloadProgress;

  @override
  State<FirmwareCard> createState() => _FirmwareCardState();
}

class _FirmwareCardState extends State<FirmwareCard> {
  Firmware? _selectedHistory;

  Firmware get latest => widget.firmwares.first;
  List<Firmware> get history => widget.firmwares.length <= 1 ? const [] : widget.firmwares.skip(1).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedHistory;
    final downloading = widget.isDownloading(latest);
    final progress = widget.downloadProgress(latest);

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
            const SizedBox(height: 12),
            Text('最新更新内容', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              latest.changelog.trim().isEmpty ? latest.description : latest.changelog,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 8),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text('历史版本（${history.length}）'),
                  children: [
                    for (final item in history)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.version),
                        subtitle: Text(item.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => setState(() => _selectedHistory = item),
                      ),
                  ],
                ),
              ),
            ],
            if (selected != null) ...[
              const Divider(height: 24),
              Text('历史版本 ${selected.version}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                selected.changelog.trim().isEmpty ? selected.description : selected.changelog,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
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
                    onPressed: () => widget.onDownload(latest),
                    icon: const Icon(Icons.download),
                    label: const Text('下载最新版'),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: () => widget.onFlash(latest),
                  icon: const Icon(Icons.flash_on),
                  label: const Text('刷写最新版'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
