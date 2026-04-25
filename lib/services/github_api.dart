import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/firmware.dart';

class GithubApi {
  GithubApi({http.Client? client}) : _client = client ?? http.Client();

  static const latestReleaseUrl =
      'https://api.github.com/repos/Vivitoto/M5PaperS3-Firmware/releases/latest';

  final http.Client _client;

  Future<Firmware> fetchLatestM5PaperS3Ebook() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('githubToken')?.trim();
    final response = await _client.get(
      Uri.parse(latestReleaseUrl),
      headers: {
        'Accept': 'application/vnd.github+json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GitHub release request failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final assets = (data['assets'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final binAsset = assets.cast<Map<String, dynamic>?>().firstWhere(
          (asset) =>
              asset != null &&
              (asset['name'] as String? ?? '').toLowerCase().endsWith('.bin'),
          orElse: () => assets.isNotEmpty ? assets.first : null,
        );

    if (binAsset == null) {
      throw Exception('No firmware asset found in latest GitHub release.');
    }

    return Firmware(
      id: 'vivitoto-m5papers3-ebook-${data['tag_name'] ?? data['id']}',
      name: 'M5PaperS3 Ebook',
      version: (data['tag_name'] ?? data['name'] ?? 'latest').toString(),
      description: (data['body'] as String?)?.trim().isNotEmpty == true
          ? (data['body'] as String).trim()
          : 'Latest Vivitoto M5PaperS3 Ebook firmware / 最新自制固件',
      downloadUrl: binAsset['browser_download_url'] as String,
      sizeBytes: binAsset['size'] as int?,
      releaseUrl: data['html_url'] as String?,
      source: FirmwareSource.vivitoto,
    );
  }
}

class FirmwareRepository {
  FirmwareRepository({GithubApi? githubApi}) : _githubApi = githubApi ?? GithubApi();

  final GithubApi _githubApi;

  Future<List<Firmware>> fetchAllFirmwares() async {
    final results = <Firmware>[];

    try {
      results.add(await _githubApi.fetchLatestM5PaperS3Ebook());
    } catch (_) {
      results.add(_fallbackVivitotoFirmware());
    }

    results.addAll(_m5StackOfficialFirmwares());
    results.addAll(_edcBookFirmwares());
    results.addAll(await _customFirmwares());
    return results;
  }

  Firmware _fallbackVivitotoFirmware() => const Firmware(
        id: 'vivitoto-m5papers3-ebook-latest',
        name: 'M5PaperS3 Ebook',
        version: 'latest',
        description:
            'Fetches latest release from Vivitoto/M5PaperS3-Firmware when network is available / 网络可用时获取最新 Release',
        downloadUrl:
            'https://github.com/Vivitoto/M5PaperS3-Firmware/releases/latest',
        source: FirmwareSource.vivitoto,
      );

  List<Firmware> _m5StackOfficialFirmwares() => const [
        Firmware(
          id: 'm5stack-m5papers3-factory',
          name: 'M5PaperS3 Factory Demo',
          version: 'official/latest',
          description:
              'M5Stack official factory/demo firmware placeholder. Update URL from api.m5stack.com flash_mode app.js if needed. / 官方演示固件占位，可替换为 M5Stack Flash Mode 中的真实地址。',
          downloadUrl: 'https://static-cdn.m5stack.com/resource/docs/products/core/M5PaperS3/fw/M5PaperS3_Factory.bin',
          source: FirmwareSource.m5stackOfficial,
        ),
        Firmware(
          id: 'm5stack-m5papers3-core2paper',
          name: 'M5PaperS3 Official UIFlow',
          version: 'official/latest',
          description:
              'Official M5Stack UIFlow/launcher firmware entry. / M5Stack 官方 UIFlow/启动器固件条目。',
          downloadUrl: 'https://static-cdn.m5stack.com/resource/firmware/M5PaperS3/latest.bin',
          source: FirmwareSource.m5stackOfficial,
        ),
      ];

  List<Firmware> _edcBookFirmwares() => const [
        Firmware(
          id: 'edcbook-m5papers3-release',
          name: 'EDC Book for M5PaperS3',
          version: 'latest',
          description:
              'EDC Book firmware entry from M5Stack Flash Mode catalogue / 来自 M5Stack Flash Mode 目录的 EDC Book 固件条目。',
          downloadUrl: 'https://static-cdn.m5stack.com/resource/firmware/EDCBook/latest.bin',
          source: FirmwareSource.edcBook,
        ),
      ];

  Future<List<Firmware>> _customFirmwares() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('customFirmwareUrl')?.trim();
    if (url == null || url.isEmpty) return const [];
    return [
      Firmware(
        id: 'custom-${url.hashCode}',
        name: 'Custom Firmware / 自定义固件',
        version: 'custom',
        description: 'User-defined firmware URL / 用户自定义固件地址',
        downloadUrl: url,
        source: FirmwareSource.custom,
      ),
    ];
  }
}
