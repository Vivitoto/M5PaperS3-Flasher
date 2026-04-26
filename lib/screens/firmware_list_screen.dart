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
      await for (final progress in _downloadManager.download(firmware, force: force)) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('固件'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
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
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                _Header(count: firmwares.length),
                const SizedBox(height: 16),
                if (firmwares.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('暂无可用 Vink 固件，请稍后刷新')),
                  )
                else
                  FirmwareCard(
                    firmwares: firmwares,
                    isDownloading: (firmware) => _downloadProgress.containsKey(firmware.id),
                    downloadProgress: (firmware) => _downloadProgress[firmware.id],
                    localStatus: (firmware) => _localStatus[firmware.id] ?? LocalFirmwareStatus.none,
                    partialBytes: (firmware) => _partialBytes[firmware.id],
                    onDownload: _download,
                    onFlash: (firmware) async {
                      if (_localPaths[firmware.id] == null && firmware.localPath == null) {
                        await _download(firmware);
                      }
                      if (mounted && _localPaths[firmware.id] != null) _openFlash(firmware);
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

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF151516),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF2B2B2E)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset('assets/images/vink_flasher_logo.png', width: 72, height: 72),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vink Flasher',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Vink 系列烧录器',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(text: 'PaperS3'),
                    _Pill(text: '${count <= 1 ? 0 : count - 1} 个历史版本'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF222224),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF333336)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
    );
  }
}
