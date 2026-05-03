import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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



/// M5Burner 云端固件源。
///
/// 过滤规则来自 ink-box APK 内置 assets/config/firmware_filter.json：只展示
/// Paper 类目下确认面向 PaperS3 的阅读器固件，避免把无关 demo/工具固件塞进列表。
class M5BurnerSource {
  static const String _apiUrl =
      'http://m5burner-api-fc-hk-cdn.m5stack.com/api/firmware';
  static const String _downloadBase = 'https://m5burner-cdn.m5stack.com/firmware';
  static const List<String> _allowedNames = [
    '墨阅书匣 | MoYue',
    '阅读卡片 | EDC Book',
    'ReadPaper',
    'XReader for paperS3',
    '梅花小民',
    'Booklet · 片读',
  ];

  final http.Client _client;

  M5BurnerSource({http.Client? client}) : _client = client ?? http.Client();

  Future<List<Firmware>> fetchFirmwares() async {
    final response = await _client
        .get(Uri.parse(_apiUrl), headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('M5Burner 固件清单请求失败: ${response.statusCode}');
    }

    final items = _asList(jsonDecode(response.body)).map(_asMap);
    final results = <Firmware>[];
    for (final item in items) {
      final category = _asString(item['category']).toLowerCase();
      final name = _asString(item['name']);
      if (category != 'paper' || !_allowedNames.contains(name)) continue;

      final versions = _asList(item['versions']).map(_asMap).where((version) {
        final file = _asString(version['file']).toLowerCase();
        return version['published'] == true && file.endsWith('.bin');
      }).toList();
      if (versions.isEmpty) continue;
      versions.sort((a, b) =>
          _asString(b['published_at']).compareTo(_asString(a['published_at'])));
      final description = _asString(item['description']).trim();
      final github = _asString(item['github']).trim();

      for (final versionItem in versions) {
        final file = _asString(versionItem['file']);
        final version = _asString(versionItem['version'], fallback: 'latest');
        final changeLog = _asString(versionItem['change_log']).trim();
        final publishedAt = _asString(versionItem['published_at']).trim();
        results.add(Firmware(
          id: 'm5burner-${_asString(item['fid']).hashCode}-${version.hashCode}-${file.hashCode}',
          name: name,
          version: version,
          description: _summary(
            changeLog.isEmpty ? description : changeLog,
            publishedAt.isEmpty ? 'M5Burner PaperS3 固件' : '发布于 $publishedAt',
          ),
          changelog: changeLog.isEmpty ? description : changeLog,
          downloadUrl: '$_downloadBase/$file',
          releaseUrl: github.isEmpty ? null : github,
          source: FirmwareSource.m5stackCommunity,
          flashOffset: 0,
        ));
      }
    }
    return results;
  }
}

/// LilyGo 固件清单源。
///
/// 过滤规则同样来自 ink-box APK：只接入 T5 4.7 v2.3 的墨阅书匣固件。
/// LilyGo manifest 提供的是 zip 包；DownloadManager 会下载后解出里面的 .bin。
class LilyGoSource {
  static const String _manifestUrl =
      'https://lilygo.oss-accelerate.aliyuncs.com/firmware_manifest.json';
  static const String _productId = 't5-4-7-inch-e-paper-v2-3';
  static const String _firmwareName = '墨阅书匣 | MoYue';

  final http.Client _client;

  LilyGoSource({http.Client? client}) : _client = client ?? http.Client();

  Future<List<Firmware>> fetchFirmwares() async {
    final response = await _client
        .get(Uri.parse(_manifestUrl), headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('LilyGo 固件清单请求失败: ${response.statusCode}');
    }

    final manifest = _asMap(jsonDecode(response.body));
    final firmwares = _asList(manifest['firmware_list']).map(_asMap).where((item) {
      final productIds = _asList(item['supported_product_ids']).map(_asString).toSet();
      final name = _asString(item['name']);
      final type = _asString(item['type']);
      final url = _asString(item['download_url']).isNotEmpty
          ? _asString(item['download_url'])
          : _asString(item['oss_url']);
      return productIds.contains(_productId) &&
          name == _firmwareName &&
          type == 'community' &&
          url.isNotEmpty;
    }).toList();
    if (firmwares.isEmpty) return const <Firmware>[];
    firmwares.sort((a, b) =>
        _asString(b['published_at']).compareTo(_asString(a['published_at'])));

    return firmwares.map((item) {
      final url = _asString(item['download_url']).isNotEmpty
          ? _asString(item['download_url'])
          : _asString(item['oss_url']);
      final sha256 = _asString(item['sha256']);
      final sourceCode = _asString(item['source_code_url']);
      final description = _asString(item['description']).trim();
      final publishedAt = _asString(item['published_at']).trim();
      return Firmware(
        id: 'lilygo-$_productId-${_asString(item['version']).hashCode}-${url.hashCode}',
        name: 'LilyGo T5 · $_firmwareName',
        version: _asString(item['version'], fallback: 'latest'),
        description: description.isEmpty
            ? 'LilyGo T5 4.7 v2.3 社区固件，完整镜像从 0x0 烧录。'
            : _summary(description, publishedAt.isEmpty ? 'LilyGo T5 4.7 v2.3 固件' : '发布于 $publishedAt'),
        changelog: description.isEmpty
            ? '暂无逐版本更新说明${publishedAt.isEmpty ? '' : ' · 发布于 $publishedAt'}'
            : description,
        downloadUrl: url,
        sizeBytes: _asInt(item['size']),
        hash: sha256.isEmpty
            ? null
            : FirmwareHash(type: HashType.sha256, value: sha256),
        releaseUrl: sourceCode.isEmpty ? null : sourceCode,
        source: FirmwareSource.lilyGo,
        flashOffset: 0,
      );
    }).toList();
  }
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

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
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

/// 用户在设置页配置的自定义固件 URL。
///
/// 这个入口只做下载源接入；实际能否烧录取决于用户选择的设备模式和固件本身。
/// 默认按完整镜像从 0x0 写入，因此设置页应填写 full/factory/complete 这类完整包。
class CustomUrlSource {
  const CustomUrlSource();

  Future<List<Firmware>> fetchFirmwares() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('customFirmwareUrl')?.trim() ?? '';
    if (url.isEmpty) return const <Firmware>[];

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return const <Firmware>[];
    }

    final fileName = uri.pathSegments.isEmpty ? 'firmware.bin' : uri.pathSegments.last;
    final lower = fileName.toLowerCase();
    final versionMatch = RegExp(r'v\d+(?:[._-]\d+)*(?:[-_][a-z0-9]+)*', caseSensitive: false)
        .firstMatch(fileName);
    final isLikelyFull = lower.contains('full') ||
        lower.contains('factory') ||
        lower.contains('complete') ||
        lower.contains('16mb');

    return [
      Firmware(
        id: 'custom-${url.hashCode}',
        name: '自定义固件',
        version: versionMatch?.group(0)?.replaceAll('_', '.') ?? 'custom',
        description: isLikelyFull
            ? '设置页配置的自定义完整镜像，默认从 0x0 烧录。'
            : '设置页配置的自定义固件。请确认这是完整镜像；App 默认从 0x0 烧录。',
        changelog: '自定义 URL：$url',
        downloadUrl: url,
        releaseUrl: url,
        source: FirmwareSource.custom,
        flashOffset: 0,
      ),
    ];
  }
}

/// 固件仓库：Vink 系列固件统一入口。
class FirmwareRepository {
  FirmwareRepository({
    VinkSource? vinkSource,
    M5BurnerSource? m5BurnerSource,
    LilyGoSource? lilyGoSource,
    CustomUrlSource? customSource,
  })  : _vinkSource = vinkSource ?? VinkSource(),
        _m5BurnerSource = m5BurnerSource ?? M5BurnerSource(),
        _lilyGoSource = lilyGoSource ?? LilyGoSource(),
        _customSource = customSource ?? const CustomUrlSource();

  final VinkSource _vinkSource;
  final M5BurnerSource _m5BurnerSource;
  final LilyGoSource _lilyGoSource;
  final CustomUrlSource _customSource;

  Future<List<Firmware>> fetchAllFirmwares() async {
    // 所有源并行请求，任意源返回空不影响其他源。
    // Vink 官方源结果排在最前，其余按版本号排序。
    final results = <Firmware>[];

    final vinkFuture = _vinkSource.fetchFirmwares();
    final m5Future = () async {
      try { return await _m5BurnerSource.fetchFirmwares(); }
      catch (_) { return const <Firmware>[]; }
    }();
    final lilyFuture = () async {
      try { return await _lilyGoSource.fetchFirmwares(); }
      catch (_) { return const <Firmware>[]; }
    }();
    final customFuture = () async {
      try { return await _customSource.fetchFirmwares(); }
      catch (_) { return const <Firmware>[]; }
    }();

    final allResults = await Future.wait< List<Firmware>>(
        [vinkFuture, m5Future(), lilyFuture(), customFuture()]);
    for (final batch in allResults) {
      results.addAll(batch);
    }

    results.sort((a, b) {
      if (a.source == FirmwareSource.vink && b.source != FirmwareSource.vink) return -1;
      if (a.source != FirmwareSource.vink && b.source == FirmwareSource.vink) return 1;
      return _compareVersions(b.version, a.version);
    });
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
