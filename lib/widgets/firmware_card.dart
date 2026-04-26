import 'package:flutter/material.dart';

import '../models/firmware.dart';

class FirmwareCard extends StatelessWidget {
  const FirmwareCard({
    super.key,
    required this.firmware,
    required this.onDownload,
    required this.onFlash,
    this.downloadProgress,
    this.isDownloading = false,
  });

  final Firmware firmware;
  final VoidCallback onDownload;
  final VoidCallback onFlash;
  final double? downloadProgress;
  final bool isDownloading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    firmware.name,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: Text(firmware.sourceLabel, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('版本: ${firmware.version}'),
            Text('大小: ${firmware.sizeLabel}'),
            Text('烧录: ${firmware.flashOffset == 0 ? '完整镜像' : 'App分区'}'),
            const SizedBox(height: 10),
            Text(
              firmware.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            if (firmware.changelog.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('更新内容'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        firmware.changelog,
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (isDownloading) ...[
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(value: downloadProgress),
                  ),
                  const SizedBox(width: 12),
                  Text(downloadProgress == null
                      ? '下载中...'
                      : '${(downloadProgress! * 100).clamp(0, 100).toStringAsFixed(0)}%'),
                  const Spacer(),
                ] else ...[
                  FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download),
                    label: const Text('下载'),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: onFlash,
                  icon: const Icon(Icons.flash_on),
                  label: const Text('刷写'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
