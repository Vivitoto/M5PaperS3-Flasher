import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/firmware.dart';

/// M5Stack 社区固件源（通过 GitHub API）
class M5StackCommunitySource {
  static const String _repo = 'm5stack/M5PaperS3';
  static const String _apiUrl = 'https://api.github.com/repos/$_repo/releases';

  final http.Client _client;

  M5StackCommunitySource({http.Client? client}) : _client = client ?? http.Client();

  /// Ink Box 支持的 M5PaperS3 固件名称列表
  static const List<String> _supportedFirmwares = [
    '墨阅书匣',
    'EDC Book',
    '阅读卡片',
    'ReadPaper',
    'XReader for paperS3',
    'XReader',
    '梅花小民',
    'Booklet',
    '片读',
  ];

  Future<List<Firmware>> fetchFirmwares() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('githubToken')?.trim();

    final response = await _client.get(
      Uri.parse(_apiUrl),
      headers: {
        'Accept': 'application/vnd.github+json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GitHub API 请求失败: ${response.statusCode}');
    }

    final releases = jsonDecode(response.body) as List<dynamic>;
    final results = <Firmware>[];

    for (final release in releases.cast<Map<String, dynamic>>()) {
      final tagName = release['tag_name'] as String? ?? '';
      final releaseName = release['name'] as String? ?? '';
      final body = release['body'] as String? ?? '';
      final htmlUrl = release['html_url'] as String? ?? '';

      final assets = (release['assets'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      for (final asset in assets) {
        final assetName = asset['name'] as String? ?? '';
        if (!assetName.toLowerCase().endsWith('.bin')) continue;

        final firmwareName = _extractFirmwareName(releaseName, assetName);
        if (!_isSupported(firmwareName, releaseName, body)) continue;

        results.add(Firmware(
          id: 'm5stack-${tagName.hashCode}-${assetName.hashCode}',
          name: firmwareName,
          version: tagName,
          description: _extractDescription(body, releaseName),
          downloadUrl: asset['browser_download_url'] as String,
          sizeBytes: asset['size'] as int?,
          releaseUrl: htmlUrl,
          source: FirmwareSource.m5stackCommunity,
        ));
      }
    }

    return results;
  }

  String _extractFirmwareName(String releaseName, String assetName) {
    for (final name in _supportedFirmwares) {
      if (releaseName.contains(name) || assetName.contains(name)) {
        return name;
      }
    }
    // 清理文件名
    return assetName.replaceAll('.bin', '').replaceAll('_', ' ');
  }

  bool _isSupported(String firmwareName, String releaseName, String body) {
    final text = '${releaseName.toLowerCase()} ${body.toLowerCase()} ${firmwareName.toLowerCase()}';
    for (final name in _supportedFirmwares) {
      if (text.contains(name.toLowerCase())) return true;
    }
    return false;
  }

  String _extractDescription(String body, String releaseName) {
    if (body.trim().isEmpty) return 'M5Stack 社区固件';
    final lines = body.trim().split('\n');
    final desc = lines.firstWhere(
      (l) => l.trim().isNotEmpty && l.length < 200,
      orElse: () => body.substring(0, body.length.clamp(0, 200)),
    );
    return desc.trim();
  }
}

/// Vivitoto 自制固件源
class VivitotoSource {
  static const String _latestUrl =
      'https://api.github.com/repos/Vivitoto/M5PaperS3-Firmware/releases/latest';

  final http.Client _client;

  VivitotoSource({http.Client? client}) : _client = client ?? http.Client();

  Future<Firmware?> fetchLatest() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('githubToken')?.trim();

    try {
      final response = await _client.get(
        Uri.parse(_latestUrl),
        headers: {
          'Accept': 'application/vnd.github+json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final assets = (data['assets'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final binAssets = assets
          .where((a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.bin'))
          .toList();
      if (binAssets.isEmpty) return null;

      // 统一烧录最完整镜像：包含 bootloader / partition / app / SPIFFS。
      // 如果 Release 里没有完整镜像，就先不展示，避免把 app-only firmware.bin 错写到 0x0。
      final fullAssets = binAssets.where((a) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        return name.contains('full') || name.contains('complete') || name.contains('factory') || name.contains('16mb');
      }).toList();
      if (fullAssets.isEmpty) return null;
      final binAsset = fullAssets.first;

      return Firmware(
        id: 'vivitoto-${data['tag_name'] ?? 'latest'}',
        name: 'M5PaperS3 Ebook（自制）',
        version: (data['tag_name'] ?? 'latest').toString(),
        description: 'Vivitoto 自制完整镜像，包含分区表、固件和字库/Web资源',
        downloadUrl: binAsset['browser_download_url'] as String,
        sizeBytes: binAsset['size'] as int?,
        releaseUrl: data['html_url'] as String?,
        source: FirmwareSource.vivitoto,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 固件仓库（聚合所有源）
class FirmwareRepository {
  FirmwareRepository({
    M5StackCommunitySource? m5stackSource,
    VivitotoSource? vivitotoSource,
  })  : _m5stackSource = m5stackSource ?? M5StackCommunitySource(),
        _vivitotoSource = vivitotoSource ?? VivitotoSource();

  final M5StackCommunitySource _m5stackSource;
  final VivitotoSource _vivitotoSource;

  Future<List<Firmware>> fetchAllFirmwares() async {
    final results = <Firmware>[];

    // 1. Vivitoto 自制固件
    try {
      final vivitoto = await _vivitotoSource.fetchLatest();
      if (vivitoto != null) results.add(vivitoto);
    } catch (_) {}

    // 2. M5Stack 社区固件
    try {
      final community = await _m5stackSource.fetchFirmwares();
      results.addAll(community);
    } catch (_) {}

    // 3. 如果网络不可用，使用内置 fallback
    if (results.isEmpty) {
      results.addAll(_fallbackFirmwares());
    }

    return results;
  }

  List<Firmware> _fallbackFirmwares() => const [
        Firmware(
          id: 'vivitoto-m5papers3-ebook-latest',
          name: 'M5PaperS3 Ebook（自制）',
          version: 'latest',
          description: '网络不可用，请刷新重试',
          downloadUrl:
              'https://github.com/Vivitoto/M5PaperS3-Firmware/releases/latest',
          source: FirmwareSource.vivitoto,
        ),
        Firmware(
          id: 'm5stack-m5papers3-factory',
          name: 'M5PaperS3 出厂固件',
          version: 'v2.0.9',
          description: 'M5Stack 官方出厂测试固件',
          downloadUrl:
              'https://m5stack.oss-cn-shenzhen.aliyuncs.com/resource/docs/products/core/M5PaperS3/bin/M5PaperS3_FactoryTest.bin',
          source: FirmwareSource.m5stackOfficial,
        ),
        Firmware(
          id: 'm5stack-m5papers3-uiflow2',
          name: 'M5PaperS3 UIFlow2.0',
          version: 'v2.0.9',
          description: 'M5Stack 官方 UIFlow2.0 启动器',
          downloadUrl:
              'https://m5stack.oss-cn-shenzhen.aliyuncs.com/resource/docs/products/core/M5PaperS3/bin/M5PaperS3_UIFlow2.0.bin',
          source: FirmwareSource.m5stackOfficial,
        ),
        Firmware(
          id: 'm5stack-m5papers3-arduino',
          name: 'M5PaperS3 Arduino',
          version: 'v2.0.9',
          description: 'M5Stack 官方 Arduino 固件',
          downloadUrl:
              'https://m5stack.oss-cn-shenzhen.aliyuncs.com/resource/docs/products/core/M5PaperS3/bin/M5PaperS3_Arduino.bin',
          source: FirmwareSource.m5stackOfficial,
        ),
        Firmware(
          id: 'edcbook-m5papers3-release',
          name: 'EDC Book（梦西游）',
          version: 'v3.x',
          description: '梦西游电子书固件，适配 M5PaperS3',
          downloadUrl:
              'https://github.com/dreamxiyou/edcbook/releases/download/latest/edcbook_m5papers3.bin',
          source: FirmwareSource.edcBook,
        ),
      ];
}
