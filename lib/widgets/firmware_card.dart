import 'package:flutter/material.dart';

import '../models/firmware.dart';
import '../services/download_manager.dart';
import 'vink_chrome.dart';

class FirmwareCard extends StatelessWidget {
  const FirmwareCard({
    super.key,
    required this.firmwares,
    required this.onDownload,
    required this.onDelete,
    required this.onFlash,
    required this.onExport,
    required this.isDownloading,
    required this.isExporting,
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
  final void Function(Firmware firmware) onExport;
  final bool Function(Firmware firmware) isDownloading;
  final bool Function(Firmware firmware) isExporting;
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

    return VinkGlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VinkIconTile(icon: Icons.developer_board_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              latest.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.45,
                                height: 1.12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          VinkPill(
                            icon: Icons.cloud_done_rounded,
                            text: latest.sourceLabel,
                            color: VinkColors.cyan,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          VinkPill(
                            icon: Icons.new_releases_rounded,
                            text: latest.version,
                            color: VinkColors.blue,
                          ),
                          VinkPill(
                            icon: latest.flashOffset == 0
                                ? Icons.all_inclusive_rounded
                                : Icons.app_shortcut_rounded,
                            text: latest.flashOffset == 0 ? '完整镜像' : 'App 分区',
                            color: latest.flashOffset == 0
                                ? VinkColors.mint
                                : VinkColors.amber,
                          ),
                        ],
                      ),
                      if (latest.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          latest.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: VinkColors.muted,
                            height: 1.32,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FirmwareVersionPanel(
              firmware: latest,
              title: '最新版本',
              expanded: false,
              isDownloading: isDownloading(latest),
              isExporting: isExporting(latest),
              progress: downloadProgress(latest),
              status: localStatus(latest),
              partialBytes: partialBytes(latest),
              onDownload: onDownload,
              onDelete: showDeleteAction ? onDelete : null,
              onFlash: showFlashAction ? onFlash : null,
              onExport: onExport,
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
                      style: const TextStyle(
                          color: VinkColors.muted, fontSize: 11)),
                  children: [
                    for (final item in history) ...[
                      _FirmwareVersionPanel(
                        firmware: item,
                        title: item.version,
                        expanded: false,
                        dense: true,
                        isDownloading: isDownloading(item),
                        isExporting: isExporting(item),
                        progress: downloadProgress(item),
                        status: localStatus(item),
                        partialBytes: partialBytes(item),
                        onDownload: onDownload,
                        onDelete: showDeleteAction ? onDelete : null,
                        onFlash: showFlashAction ? onFlash : null,
                        onExport: onExport,
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
    required this.isExporting,
    required this.progress,
    required this.status,
    required this.partialBytes,
    required this.onDownload,
    required this.onDelete,
    required this.onFlash,
    required this.onExport,
    this.dense = false,
  });

  final Firmware firmware;
  final String title;
  final bool expanded;
  final bool dense;
  final bool isDownloading;
  final bool isExporting;
  final double? progress;
  final LocalFirmwareStatus status;
  final int? partialBytes;
  final void Function(Firmware firmware, {bool force}) onDownload;
  final void Function(Firmware firmware)? onDelete;
  final void Function(Firmware firmware)? onFlash;
  final void Function(Firmware firmware) onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloaded = status == LocalFirmwareStatus.complete;
    final partial = status == LocalFirmwareStatus.partial;

    final child = Container(
      padding: EdgeInsets.all(dense ? 7 : 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: downloaded
              ? const [Color(0xFF22211D), Color(0xFF141311)]
              : const [Color(0xFF151411), Color(0xFF0D0D0B)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: downloaded ? const Color(0x70F4EFE3) : VinkColors.lineSoft),
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
                    size: 18, color: VinkColors.mint)
              else if (partial)
                const Icon(Icons.downloading_rounded,
                    size: 18, color: VinkColors.cyan),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${firmware.sizeLabel} · ${firmware.flashOffset == 0 ? '完整镜像' : 'App分区'}',
            style: theme.textTheme.bodySmall?.copyWith(color: VinkColors.muted),
          ),
          const SizedBox(height: 5),
          _LocalStatusLine(
            status: status,
            partialBytes: partialBytes,
            totalBytes: firmware.sizeBytes,
          ),
          const SizedBox(height: 7),
          if (isDownloading)
            _Downloading(progress: progress)
          else
            _VersionActions(
              downloaded: downloaded,
              partial: partial,
              exporting: isExporting,
              onDownload: () => onDownload(firmware, force: downloaded),
              onExport: downloaded ? () => onExport(firmware) : null,
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
    required this.exporting,
    required this.onDownload,
    required this.onFlash,
    this.onExport,
    this.onDelete,
  });

  final bool downloaded;
  final bool partial;
  final bool exporting;
  final VoidCallback onDownload;
  final VoidCallback? onExport;
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
            icon: Icon(
                downloaded ? Icons.refresh_rounded : Icons.download_rounded),
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
        if (onExport != null) ...[
          const SizedBox(width: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: exporting ? null : onExport,
            icon: exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt_rounded),
            label: const Text('导出'),
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

class _Downloading extends StatelessWidget {
  const _Downloading({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x14F4EFE3),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: VinkColors.lineSoft),
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
          VinkColors.mint
        ),
      LocalFirmwareStatus.partial => (
          Icons.downloading_rounded,
          '已下载 ${_sizeLabel(partialBytes)}${totalBytes == null ? '' : ' / ${_sizeLabel(totalBytes)}'}，可继续下载或删除',
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

  String _sizeLabel(int? bytes) {
    final value = bytes;
    if (value == null || value <= 0) return '0 B';
    if (value >= 1024 * 1024)
      return '${(value / 1024 / 1024).toStringAsFixed(2)} MB';
    if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    return '$value B';
  }
}