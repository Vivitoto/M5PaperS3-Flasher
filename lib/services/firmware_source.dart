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

      final manifest = _asMap(jsonDecode(response.body));
      final device = _asString(manifest['device'], fallback: 'unknown');
      final firmwareName = _asString(manifest['firmwareName'], fallback: 'Vink-$device');
      final releases = _asList(manifest['releases']).map(_asMap);

      for (final release in releases) {
        final version = _asString(release['version']);
        if (version.isEmpty) continue;

        final assets = _asMap(release['assets']);
        final selectedAsset = _selectFlashAsset(assets);
        if (selectedAsset == null) continue;

        final asset = _asMap(selectedAsset);
        final assetName = _asString(asset['name']);
        final downloadUrl = _asString(asset['url']);
        if (downloadUrl.isEmpty) continue;

        final changelog = _asString(release['changelog']).trim();
        final summary = _asString(release['summary']).trim();
        final releaseName = _asString(release['name'], fallback: firmwareName);

        results.add(Firmware(
          id: 'vink-$device-$version-${assetName.hashCode}',
          name: firmwareName,
          version: version,
          description: summary.isEmpty ? _summary(changelog, releaseName) : summary,
          changelog: changelog.isEmpty ? '暂无更新说明' : changelog,
          downloadUrl: downloadUrl,
          sizeBytes: _asInt(asset['size']),
          releaseUrl: _asNullableString(release['releaseUrl']),
          source: FirmwareSource.vink,
          flashOffset: _asInt(asset['flashOffset']) ?? 0,
        ));
      }
    }

    return results;
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, value) => MapEntry(key.toString(), value));
    return <String, dynamic>{};
  }

  List<dynamic> _asList(Object? value) {
    if (value is List) return value;
    return const <dynamic>[];
  }

  String _asString(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString();
    return text.isEmpty ? fallback : text;
  }

  String? _asNullableString(Object? value) {
    final text = _asString(value);
    return text.isEmpty ? null : text;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  Map<String, dynamic>? _selectFlashAsset(Map<String, dynamic> assets) {
    // App 默认烧录完整包。旧历史版本如果没有 full，只作为历史说明兼容回退。
    final preferred = assets['full'] ?? assets['factory'] ?? assets['complete'] ?? assets['ota'];
    if (preferred is Map) return _asMap(preferred);
    for (final value in assets.values) {
      if (value is Map) return _asMap(value);
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
    results.sort((a, b) => _compareVersions(b.version, a.version));
    return results;
  }

  int _compareVersions(String a, String b) {
    final left = _versionParts(a);
    final right = _versionParts(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return a.compareTo(b);
  }

  List<int> _versionParts(String version) {
    return RegExp(r'\d+').allMatches(version).map((match) => int.parse(match.group(0)!)).toList();
  }
}
