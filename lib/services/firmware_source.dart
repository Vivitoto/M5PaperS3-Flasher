import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/firmware.dart';

/// Vink 官方固件源。
///
/// GitHub Release 是仓库级的，无法放进设备子目录；因此每个设备目录维护
/// 自己的 releases.json，App 以设备清单作为接口入口。
class VinkSource {
  static const List<String> _manifestUrls = [
    'https://raw.githubusercontent.com/Vivitoto/Vink-Firmware/main/PaperS3/releases.json',
  ];

  final http.Client _client;

  VinkSource({http.Client? client}) : _client = client ?? http.Client();

  Future<List<Firmware>> fetchFirmwares() async {
    final results = <Firmware>[];

    for (final manifestUrl in _manifestUrls) {
      final response = await _client.get(
        Uri.parse(manifestUrl),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Vink 固件清单请求失败: ${response.statusCode}');
      }

      final manifest = jsonDecode(response.body) as Map<String, dynamic>;
      final device = (manifest['device'] ?? 'unknown').toString();
      final firmwareName = (manifest['firmwareName'] ?? 'Vink-$device').toString();
      final releases = (manifest['releases'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      for (final release in releases) {
        final version = (release['version'] ?? '').toString();
        if (version.isEmpty) continue;

        final assets = (release['assets'] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        final selectedAsset = _selectFlashAsset(assets);
        if (selectedAsset == null) continue;

        final asset = selectedAsset.cast<String, dynamic>();
        final assetName = (asset['name'] ?? '').toString();
        final downloadUrl = (asset['url'] ?? '').toString();
        if (downloadUrl.isEmpty) continue;

        final changelog = (release['changelog'] ?? '').toString().trim();
        final summary = (release['summary'] ?? '').toString().trim();
        final releaseName = (release['name'] ?? firmwareName).toString();

        results.add(Firmware(
          id: 'vink-$device-$version-${assetName.hashCode}',
          name: firmwareName,
          version: version,
          description: summary.isEmpty ? _summary(changelog, releaseName) : summary,
          changelog: changelog.isEmpty ? '暂无更新说明' : changelog,
          downloadUrl: downloadUrl,
          sizeBytes: asset['size'] as int?,
          releaseUrl: release['releaseUrl'] as String?,
          source: FirmwareSource.vink,
          flashOffset: asset['flashOffset'] as int? ?? 0,
        ));
      }
    }

    return results;
  }

  Map<String, dynamic>? _selectFlashAsset(Map<String, dynamic> assets) {
    // App 默认烧录完整包。旧历史版本如果没有 full，只作为历史说明兼容回退。
    final preferred = assets['full'] ?? assets['factory'] ?? assets['complete'] ?? assets['ota'];
    if (preferred is Map<String, dynamic>) return preferred;
    if (preferred is Map) return preferred.cast<String, dynamic>();
    for (final value in assets.values) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return value.cast<String, dynamic>();
    }
    return null;
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

/// 固件仓库：Vink 系列固件统一入口。
class FirmwareRepository {
  FirmwareRepository({VinkSource? vinkSource})
      : _vinkSource = vinkSource ?? VinkSource();

  final VinkSource _vinkSource;

  Future<List<Firmware>> fetchAllFirmwares() async {
    final results = await _vinkSource.fetchFirmwares();
    results.sort((a, b) => b.version.compareTo(a.version));
    return results;
  }
}
