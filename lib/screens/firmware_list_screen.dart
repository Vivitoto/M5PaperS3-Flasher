import 'package:flutter/material.dart';

import '../models/firmware.dart';
import '../services/download_manager.dart';
import '../services/firmware_source.dart';
import '../widgets/firmware_card.dart';
import '../widgets/vink_chrome.dart';
import 'flash_screen.dart';

class FirmwareListScreen extends StatefulWidget {
  const FirmwareListScreen({super.key});

  @override
  State<FirmwareListScreen> createState() => _FirmwareListScreenState();
}

class _FirmwareListScreenState extends State<FirmwareListScreen> {
  final _repository = FirmwareRepository();
  final _downloadManager = DownloadManager();
  late Future<List<Firmware>> _future;
  final Map<String, double?> _downloadProgress = {};
  final Map<String, String> _localPaths = {};
  final Map<String, LocalFirmwareStatus> _localStatus = {};
  final Map<String, int> _partialBytes = {};
  String _selectedDevice = 'm5stack';

  @override
  void initState() {
    super.initState();
    _future = _loadFirmwares();
  }

  Future<List<Firmware>> _loadFirmwares() async {
    final firmwares = await _repository.fetchAllFirmwares();
    await _hydrateLocalState(firmwares);
    return firmwares;
  }

  Future<void> _hydrateLocalState(List<Firmware> firmwares) async {
    // 每次刷新时清空旧数据，避免 Map 持续膨胀。
    _localStatus.clear();
    _localPaths.clear();
    _partialBytes.clear();
    for (final firmware in firmwares) {
      final info = await _downloadManager.localInfo(firmware);
      _localStatus[firmware.id] = info.status;
      if (info.filePath != null) {
        _localPaths[firmware.id] = info.filePath!;
      } else {
        _localPaths.remove(firmware.id);
      }
      if (info.status == LocalFirmwareStatus.partial) {
        _partialBytes[firmware.id] = info.receivedBytes;
      } else {
        _partialBytes.remove(firmware.id);
      }
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadFirmwares());
    await _future;
  }

  Future<void> _download(Firmware firmware, {bool force = false}) async {
    setState(() {
      _downloadProgress[firmware.id] = null;
      if (force) {
        _localStatus[firmware.id] = LocalFirmwareStatus.none;
        _localPaths.remove(firmware.id);
        _partialBytes.remove(firmware.id);
      }
    });
    try {
      await for (final progress
          in _downloadManager.download(firmware, force: force)) {
        if (!mounted) return;
        setState(() {
          _downloadProgress[firmware.id] = progress.fraction;
          if (progress.filePath != null) {
            _localPaths[firmware.id] = progress.filePath!;
            _localStatus[firmware.id] = LocalFirmwareStatus.complete;
            _partialBytes.remove(firmware.id);
            _downloadProgress.remove(firmware.id);
          } else {
            _localStatus[firmware.id] = LocalFirmwareStatus.partial;
            _partialBytes[firmware.id] = progress.receivedBytes;
          }
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载完成')),
      );
    } catch (error) {
      if (!mounted) return;
      final info = await _downloadManager.localInfo(firmware);
      setState(() {
        _downloadProgress.remove(firmware.id);
        _localStatus[firmware.id] = info.status;
        if (info.filePath != null) _localPaths[firmware.id] = info.filePath!;
        if (info.status == LocalFirmwareStatus.partial) {
          _partialBytes[firmware.id] = info.receivedBytes;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败: $error')),
      );
    }
  }

  Future<void> _deleteLocal(Firmware firmware) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本地固件？'),
        content:
            Text('将删除 ${firmware.name} ${firmware.version} 的本地文件，之后可重新下载。'),
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
      _localPaths.remove(firmware.id);
      _partialBytes.remove(firmware.id);
      _localStatus[firmware.id] = info.status;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('本地固件已删除')),
    );
  }

  void _openFlash(Firmware firmware) {
    final localPath = _localPaths[firmware.id];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FlashScreen(
          firmware: firmware.copyWith(localPath: localPath),
        ),
      ),
    );
  }

  String _deviceIdOf(Firmware firmware) {
    final text =
        '${firmware.id} ${firmware.name} ${firmware.description} ${firmware.downloadUrl}'
            .toLowerCase();
    if (firmware.source == FirmwareSource.lilyGo ||
        text.contains('lilygo') ||
        text.contains('t5-4-7') ||
        text.contains('t5 4.7')) {
      return 'lilygo';
    }
    return 'm5stack';
  }

  List<_DeviceFilter> _deviceFilters(List<Firmware> firmwares) {
    final ids = firmwares.map(_deviceIdOf).toSet();
    return [
      if (ids.contains('m5stack'))
        const _DeviceFilter(id: 'm5stack', label: 'M5Stack'),
      if (ids.contains('lilygo'))
        const _DeviceFilter(id: 'lilygo', label: 'LilyGo'),
    ];
  }

  List<List<Firmware>> _groupFirmwares(List<Firmware> firmwares) {
    final groups = <String, List<Firmware>>{};
    for (final firmware in firmwares) {
      final key = '${firmware.source.name}:${firmware.name}';
      groups.putIfAbsent(key, () => <Firmware>[]).add(firmware);
    }
    return groups.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: 48,
        title: const Text('固件库'),
        actions: [
          IconButton(
              onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: FutureBuilder<List<Firmware>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _LoadingFirmwareList(onRefresh: _refresh);
          }
          if (snapshot.hasError) {
            return _FirmwareLoadFailed(
              message: '固件列表暂时不可用',
              onRefresh: _refresh,
            );
          }
          final firmwares = snapshot.data ?? const <Firmware>[];
          final filters = _deviceFilters(firmwares);
          if (filters.isNotEmpty &&
              !filters.any((item) => item.id == _selectedDevice)) {
            _selectedDevice = filters.first.id;
          }
          final filtered = firmwares
              .where((firmware) => _deviceIdOf(firmware) == _selectedDevice)
              .toList();
          final grouped = _groupFirmwares(filtered);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
              children: [
                if (filters.isNotEmpty) ...[
                  _DeviceFilterBar(
                    filters: filters,
                    selected: _selectedDevice,
                    onSelected: (id) => setState(() => _selectedDevice = id),
                  ),
                  const SizedBox(height: 8),
                ],
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 8),
                  child: Text(
                    '${filtered.length} 个版本',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: VinkColors.muted),
                  ),
                ),
                if (firmwares.isEmpty)
                  _FirmwareLoadFailed(
                    message: '没有加载到固件',
                    onRefresh: _refresh,
                  )
                else if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('当前设备暂无固件')),
                  )
                else
                  for (final group in grouped) ...[
                    FirmwareCard(
                      firmwares: group,
                      isDownloading: (firmware) =>
                          _downloadProgress.containsKey(firmware.id),
                      downloadProgress: (firmware) =>
                          _downloadProgress[firmware.id],
                      localStatus: (firmware) =>
                          _localStatus[firmware.id] ?? LocalFirmwareStatus.none,
                      partialBytes: (firmware) => _partialBytes[firmware.id],
                      showDeleteAction: false,
                      showFlashAction: false,
                      onDownload: _download,
                      onDelete: _deleteLocal,
                      onFlash: (firmware) async {
                        if (_localPaths[firmware.id] == null &&
                            firmware.localPath == null) {
                          await _download(firmware);
                        }
                        if (mounted && _localPaths[firmware.id] != null) {
                          _openFlash(firmware);
                        }
                      },
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

class _LoadingFirmwareList extends StatelessWidget {
  const _LoadingFirmwareList({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 96),
        children: const [
          VinkGlassCard(
            padding: EdgeInsets.all(18),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '正在加载固件列表...',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 10),
          Text(
            '如果一直停在这里，下拉或点右上角刷新。',
            style: TextStyle(color: VinkColors.muted),
          ),
        ],
      ),
    );
  }
}

class _FirmwareLoadFailed extends StatelessWidget {
  const _FirmwareLoadFailed({required this.message, required this.onRefresh});

  final String message;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return VinkGlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded, color: VinkColors.amber, size: 30),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            '检查网络后刷新，已下载固件可在“烧录”页使用。',
            textAlign: TextAlign.center,
            style: TextStyle(color: VinkColors.muted),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('刷新'),
          ),
        ],
      ),
    );
  }
}

class _DeviceFilter {
  const _DeviceFilter({required this.id, required this.label});

  final String id;
  final String label;
}

class _DeviceFilterBar extends StatelessWidget {
  const _DeviceFilterBar({
    required this.filters,
    required this.selected,
    required this.onSelected,
  });

  final List<_DeviceFilter> filters;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x99101722),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: VinkColors.lineSoft),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final filter in filters) ...[
              ChoiceChip(
                label: Text(filter.label),
                selected: selected == filter.id,
                onSelected: (_) => onSelected(filter.id),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}
