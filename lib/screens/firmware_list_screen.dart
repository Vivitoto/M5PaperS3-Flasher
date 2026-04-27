import 'package:flutter/material.dart';

import '../models/firmware.dart';
import '../services/download_manager.dart';
import '../services/firmware_source.dart';
import '../widgets/firmware_card.dart';
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
  String _selectedDevice = 'papers3';

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
        '${firmware.id} ${firmware.name} ${firmware.description}'.toLowerCase();
    if (text.contains('papers3') || text.contains('paper s3')) return 'papers3';
    return 'other';
  }

  List<_DeviceFilter> _deviceFilters(List<Firmware> firmwares) {
    final ids = firmwares.map(_deviceIdOf).toSet();
    return [
      if (ids.contains('papers3'))
        const _DeviceFilter(id: 'papers3', label: 'M5Stack Paper S3'),
      if (ids.contains('other'))
        const _DeviceFilter(id: 'other', label: '其他设备'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('固件'),
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
          final filters = _deviceFilters(firmwares);
          if (filters.isNotEmpty &&
              !filters.any((item) => item.id == _selectedDevice)) {
            _selectedDevice = filters.first.id;
          }
          final filtered = firmwares
              .where((firmware) => _deviceIdOf(firmware) == _selectedDevice)
              .toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 22),
              children: [
                if (filters.isNotEmpty) ...[
                  _DeviceFilterBar(
                    filters: filters,
                    selected: _selectedDevice,
                    onSelected: (id) => setState(() => _selectedDevice = id),
                  ),
                  const SizedBox(height: 10),
                ],
                if (firmwares.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('暂无可用 Vink 固件，请稍后刷新')),
                  )
                else if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('当前设备暂无固件')),
                  )
                else
                  FirmwareCard(
                    firmwares: filtered,
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
                      if (mounted && _localPaths[firmware.id] != null)
                        _openFlash(firmware);
                    },
                  ),
              ],
            ),
          );
        },
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF151516),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2B2B2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择设备',
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white54,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
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
        ],
      ),
    );
  }
}
