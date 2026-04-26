import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/firmware.dart';

/// Vivitoto 自制固件源：只展示自己的 M5PaperS3-Firmware Release。
class VivitotoSource {
  static const String _releasesUrl =
      'https://api.github.com/repos/Vivitoto/M5PaperS3-Firmware/releases';

  final http.Client _client;

  VivitotoSource({http.Client? client}) : _client = client ?? http.Client();

  Future<List<Firmware>> fetchFirmwares() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('githubToken')?.trim();

    final response = await _client.get(
      Uri.parse(_releasesUrl),
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
      final tagName = (release['tag_name'] ?? 'latest').toString();
      final releaseName = (release['name'] ?? 'M5PaperS3 Ebook').toString();
      final body = (release['body'] ?? '').toString().trim();
      final htmlUrl = release['html_url'] as String?;
      final assets = (release['assets'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      final binAssets = assets
          .where((a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.bin'))
          .toList();
      if (binAssets.isEmpty) continue;

      // 优先显示最完整镜像：bootloader + partition + app + SPIFFS。
      // 旧 Release 如果还没有 full/factory/16mb 包，则暂时回退到第一个 bin，
      // 但自制源仍只保留 Vivitoto 自己的固件。
      final fullAssets = binAssets.where((a) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        return name.contains('full') ||
            name.contains('complete') ||
            name.contains('factory') ||
            name.contains('16mb');
      }).toList();
      final binAsset = fullAssets.isNotEmpty ? fullAssets.first : binAssets.first;
      final assetName = (binAsset['name'] ?? '').toString();
      final isFullImage = fullAssets.isNotEmpty;

      results.add(Firmware(
        id: 'vivitoto-$tagName-${assetName.hashCode}',
        name: 'M5PaperS3 Ebook',
        version: tagName,
        description: _summary(body, releaseName),
        changelog: body.isEmpty ? '暂无更新说明' : body,
        downloadUrl: binAsset['browser_download_url'] as String,
        sizeBytes: binAsset['size'] as int?,
        releaseUrl: htmlUrl,
        source: FirmwareSource.vivitoto,
        flashOffset: isFullImage ? 0x0 : 0x10000,
      ));
    }

    return results;
  }

  String _summary(String body, String fallback) {
    if (body.isEmpty) return fallback;
    final lines = body
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'^#+\s*'), '').trim())
        .where((line) => line.isNotEmpty && !line.startsWith('-'));
    return lines.isEmpty ? fallback : lines.first;
  }
}

/// 固件仓库：只保留自制固件源。
class FirmwareRepository {
  FirmwareRepository({VivitotoSource? vivitotoSource})
      : _vivitotoSource = vivitotoSource ?? VivitotoSource();

  final VivitotoSource _vivitotoSource;

  Future<List<Firmware>> fetchAllFirmwares() async {
    final results = await _vivitotoSource.fetchFirmwares();
    results.sort((a, b) => b.version.compareTo(a.version));
    return results;
  }
}
