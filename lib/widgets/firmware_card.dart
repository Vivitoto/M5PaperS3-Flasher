import 'package:flutter/material.dart';

import '../models/firmware.dart';
import '../services/download_manager.dart';

class FirmwareCard extends StatelessWidget {
  const FirmwareCard({
    super.key,
    required this.firmwares,
    required this.onDownload,
    required this.onDelete,
    required this.onFlash,
    required this.isDownloading,
    required this.downloadProgress,
    required this.localStatus,
    required this.partialBytes,
    this.showDeleteAction = true,
    this.showFlashAction = true,
  });

  final List<Firmware> firmwares;
  final void Function(Firmware firmware, {bool force}) onDownload;
  final void Function(Firmware firmware) onDelete;
  final void Function(Firmware firmware) onFlash;
  final bool Function(Firmware firmware) isDownloading;
  final double? Function(Firmware firmware) downloadProgress;
  final LocalFirmwareStatus Function(Firmware firmware) localStatus;
  final int? Function(Firmware firmware) partialBytes;
  final bool showDeleteAction;
  final bool showFlashAction;

  Firmware get latest => firmwares.first;
  List<Firmware> get history =>
      firmwares.length <= 1 ? const [] : firmwares.skip(1).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        latest.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Chip(
                  label: Text(latest.sourceLabel,
                      style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _FirmwareVersionPanel(
              firmware: latest,
              title: '最新版本',
              expanded: false,
              isDownloading: isDownloading(latest),
              progress: downloadProgress(latest),
              status: localStatus(latest),
              partialBytes: partialBytes(latest),
              onDownload: onDownload,
              onDelete: showDeleteAction ? onDelete : null,
              onFlash: showFlashAction ? onFlash : null,
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 4),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text('历史版本',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  subtitle: Text('${history.length} 个历史版本',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
                  children: [
                    for (final item in history) ...[
                      _FirmwareVersionPanel(
                        firmware: item,
                        title: item.version,
                        expanded: false,
                        dense: true,
                        isDownloading: isDownloading(item),
                        progress: downloadProgress(item),
                        status: localStatus(item),
                        partialBytes: partialBytes(item),
                        onDownload: onDownload,
                        onDelete: showDeleteAction ? onDelete : null,
                        onFlash: showFlashAction ? onFlash : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FirmwareVersionPanel extends StatelessWidget {
  const _FirmwareVersionPanel({
    required this.firmware,
    required this.title,
    required this.expanded,
    required this.isDownloading,
    required this.progress,
    required this.status,
    required this.partialBytes,
    required this.onDownload,
    required this.onDelete,
    required this.onFlash,
    this.dense = false,
  });

  final Firmware firmware;
  final String title;
  final bool expanded;
  final bool dense;
  final bool isDownloading;
  final double? progress;
  final LocalFirmwareStatus status;
  final int? partialBytes;
  final void Function(Firmware firmware, {bool force}) onDownload;
  final void Function(Firmware firmware)? onDelete;
  final void Function(Firmware firmware)? onFlash;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloaded = status == LocalFirmwareStatus.complete;
    final partial = status == LocalFirmwareStatus.partial;

    final child = Container(
      padding: EdgeInsets.all(dense ? 7 : 8),
      decoration: BoxDecoration(
        color: const Color(0xFF101011),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: downloaded ? Colors.white30 : const Color(0xFF2B2B2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title == firmware.version
                      ? firmware.version
                      : '$title · ${firmware.version}',
                  style: (dense
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleMedium)
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (downloaded)
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: Colors.white)
              else if (partial)
                const Icon(Icons.downloading_rounded,
                    size: 18, color: Colors.white70),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: [
              _MetaPill(icon: Icons.tag_rounded, text: firmware.version),
              _MetaPill(
                  icon: Icons.sd_storage_outlined, text: firmware.sizeLabel),
              _MetaPill(
                  icon: Icons.memory_rounded,
                  text: firmware.flashOffset == 0 ? '完整镜像' : 'App分区'),
              if (firmware.hash != null)
                _MetaPill(
                  icon: Icons.verified_rounded,
                  text: firmware.hash!.type == HashType.sha256 ? 'SHA-256' : 'MD5',
                ),
            ],
          ),
          const SizedBox(height: 6),
          _LocalStatusLine(
            status: status,
            partialBytes: partialBytes,
            totalBytes: firmware.sizeBytes,
          ),
          const SizedBox(height: 4),
          _ChangelogTile(
            title: '说明 / 更新',
            subtitle: firmware.description,
            changelog: firmware.changelog,
            initiallyExpanded: expanded,
            dense: true,
          ),
          const SizedBox(height: 6),
          if (isDownloading)
            _Downloading(progress: progress)
          else
            _VersionActions(
              downloaded: downloaded,
              partial: partial,
              onDownload: () => onDownload(firmware, force: downloaded),
              onDelete:
                  downloaded || partial ? () => onDelete?.call(firmware) : null,
              onFlash: onFlash == null ? null : () => onFlash!.call(firmware),
            ),
        ],
      ),
    );

    return dense
        ? Padding(padding: const EdgeInsets.only(bottom: 0), child: child)
        : child;
  }
}

class _VersionActions extends StatelessWidget {
  const _VersionActions({
    required this.downloaded,
    required this.partial,
    required this.onDownload,
    required this.onFlash,
    this.onDelete,
  });

  final bool downloaded;
  final bool partial;
  final VoidCallback onDownload;
  final VoidCallback? onDelete;
  final VoidCallback? onFlash;

  @override
  Widget build(BuildContext context) {
    final downloadLabel = downloaded
        ? '重新下载'
        : partial
            ? '继续下载'
            : '下载';
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: onDownload,
            icon: Icon(downloaded ? Icons.refresh_rounded : Icons.download_rounded),
            label: Text(downloadLabel),
          ),
        ),
        if (onFlash != null) ...[
          const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: onFlash,
              icon: const Icon(Icons.bolt_rounded),
              label: Text(downloaded ? '刷写' : '下载刷写'),
            ),
          ),
        ],
        if (onDelete != null) ...[
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '删除本地固件',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF202022),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF303033)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white70),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600)),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF202022),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF303033)),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 20,
              height: 20,
              child:
                  CircularProgressIndicator(value: progress, strokeWidth: 2.5)),
          const SizedBox(width: 8),
          Text(progress == null
              ? '下载中...'
              : '${(progress! * 100).clamp(0, 100).toStringAsFixed(0)}%'),
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
      LocalFirmwareStatus.complete => (
          Icons.check_circle_rounded,
          '已下载，可直接刷写',
          Colors.white
        ),
      LocalFirmwareStatus.partial => (
          Icons.downloading_rounded,
          '已下载 ${_sizeLabel(partialBytes)}${totalBytes == null ? '' : ' / ${_sizeLabel(totalBytes)}'}，可继续下载或删除',
          Colors.white70,
        ),
      LocalFirmwareStatus.none => (
          Icons.cloud_download_outlined,
          '未下载',
          Colors.white54
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

  String _sizeLabel(int? bytes) {
    final value = bytes;
    if (value == null || value <= 0) return '0 B';
    if (value >= 1024 * 1024)
      return '${(value / 1024 / 1024).toStringAsFixed(2)} MB';
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
    final text =
        _plainChangelog(changelog.trim().isEmpty ? subtitle : changelog.trim());

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding:
            EdgeInsets.only(left: dense ? 6 : 0, right: 0, bottom: 4),
        initiallyExpanded: initiallyExpanded,
        title: Text(
          title,
          style: dense
              ? theme.textTheme.labelLarge
              : theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: subtitle.trim().isNotEmpty
            ? Text(_plainChangelog(subtitle),
                maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white60, height: 1.32),
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
