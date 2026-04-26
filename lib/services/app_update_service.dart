import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    required this.apkName,
    required this.apkUrl,
    required this.releaseUrl,
    required this.releaseNotes,
    this.apkSize,
  });

  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String apkName;
  final String apkUrl;
  final String releaseUrl;
  final String releaseNotes;
  final int? apkSize;
}

class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const _latestReleaseApi =
      'https://api.github.com/repos/Vivitoto/Vink-Flasher/releases/tags/latest';

  final http.Client _client;

  Future<AppUpdateInfo> checkLatest() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final response = await _client.get(
      Uri.parse(_latestReleaseApi),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('检查更新失败: HTTP ${response.statusCode}');
    }

    final json = _asMap(jsonDecode(response.body));
    final assets = _asList(json['assets']).map(_asMap);
    final apk = assets.firstWhere(
      (asset) => _asString(asset['name']).toLowerCase().endsWith('.apk'),
      orElse: () => <String, dynamic>{},
    );
    if (apk.isEmpty) {
      throw Exception('latest Release 中没有 APK');
    }

    final apkName = _asString(apk['name']);
    final latestVersion = _versionFromApkName(apkName) ?? currentVersion;

    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      hasUpdate: _compareVersions(latestVersion, currentVersion) > 0,
      apkName: apkName,
      apkUrl: _asString(apk['browser_download_url']),
      releaseUrl: _asString(json['html_url']),
      releaseNotes: _asString(json['body']).trim(),
      apkSize: _asInt(apk['size']),
    );
  }

  Future<File> downloadApk(
    AppUpdateInfo update, {
    required void Function(int received, int? total) onProgress,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/${update.apkName}');
    final tempFile = File('${file.path}.part');

    var existing = await tempFile.exists() ? await tempFile.length() : 0;
    final request = http.Request('GET', Uri.parse(update.apkUrl));
    if (existing > 0) request.headers['Range'] = 'bytes=$existing-';

    final response = await _client.send(request);
    if (response.statusCode == 416) {
      final tempLength = await tempFile.exists() ? await tempFile.length() : 0;
      if (update.apkSize != null && update.apkSize! > 0 && tempLength == update.apkSize) {
        if (await file.exists()) await file.delete();
        await tempFile.rename(file.path);
        return file;
      }
      if (await tempFile.exists()) await tempFile.delete();
      throw Exception('下载更新失败: 断点续传文件不完整');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('下载更新失败: HTTP ${response.statusCode}');
    }

    final append = existing > 0 && response.statusCode == 206;
    if (!append && await tempFile.exists()) {
      await tempFile.delete();
      existing = 0;
    }

    final total = response.contentLength == null
        ? update.apkSize
        : response.statusCode == 206
            ? existing + response.contentLength!
            : response.contentLength;

    final sink = tempFile.openWrite(mode: append ? FileMode.append : FileMode.write);
    var received = existing;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    final finalLength = await tempFile.length();
    if (update.apkSize != null && update.apkSize! > 0 && finalLength != update.apkSize) {
      await tempFile.delete();
      throw Exception('下载更新失败: 文件大小不一致');
    }

    if (await file.exists()) await file.delete();
    await tempFile.rename(file.path);
    return file;
  }

  Future<void> installApk(File file) async {
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw Exception('无法打开安装器: ${result.message}');
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

  String _asString(Object? value) => value?.toString() ?? '';

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  String? _versionFromApkName(String name) {
    final match = RegExp(r'vink-flasher-v([0-9_]+)\.apk').firstMatch(name);
    if (match == null) return null;
    return match.group(1)!.replaceAll('_', '.');
  }

  int _compareVersions(String a, String b) {
    final left = a.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final right = b.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }
}
