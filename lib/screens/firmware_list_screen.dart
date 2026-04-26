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

  @override
  void initState() {
    super.initState();
    _future = _repository.fetchAllFirmwares();
  }

  Future<void> _refresh() async {
    setState(() => _future = _repository.fetchAllFirmwares());
    await _future;
  }

  Future<void> _download(Firmware firmware) async {
    setState(() => _downloadProgress[firmware.id] = null);
    try {
      await for (final progress in _downloadManager.download(firmware)) {
        if (!mounted) return;
        setState(() {
          _downloadProgress[firmware.id] = progress.fraction;
          if (progress.filePath != null) {
            _localPaths[firmware.id] = progress.filePath!;
            _downloadProgress.remove(firmware.id);
          }
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载完成')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _downloadProgress.remove(firmware.id));
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
        title: const Text('固件列表'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
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
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: firmwares.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _Header(count: firmwares.length);
                if (firmwares.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('暂无可用自制固件，请稍后刷新')),
                  );
                }
                final firmware = firmwares[index - 1];
                return FirmwareCard(
                  firmware: firmware,
                  isDownloading: _downloadProgress.containsKey(firmware.id),
                  downloadProgress: _downloadProgress[firmware.id],
                  onDownload: () => _download(firmware),
                  onFlash: () async {
                    if (_localPaths[firmware.id] == null && firmware.localPath == null) {
                      await _download(firmware);
                    }
                    if (mounted) _openFlash(firmware);
                  },
                );
              },
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Image.asset('assets/images/ink_flasher_logo.png', width: 72, height: 72),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ink Flasher',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '自制固件源 · 共 $count 个版本，下拉刷新',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
