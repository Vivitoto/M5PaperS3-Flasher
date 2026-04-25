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
          name: 'M5PaperS3 Factory',
          version: 'v2.0.9',
          description:
              'M5Stack official factory firmware. / M5Stack 官方出厂固件。',
          downloadUrl: 'https://m5stack.oss-cn-shenzhen.aliyuncs.com/resource/docs/products/core/M5PaperS3/bin/M5PaperS3_FactoryTest.bin',
          source: FirmwareSource.m5stackOfficial,
        ),
        Firmware(
          id: 'm5stack-m5papers3-uiflow2',
          name: 'M5PaperS3 UIFlow2.0',
          version: 'v2.0.9',
          description:
              'M5Stack official UIFlow2.0 launcher. / M5Stack 官方 UIFlow2.0 启动器。',
          downloadUrl: 'https://m5stack.oss-cn-shenzhen.aliyuncs.com/resource/docs/products/core/M5PaperS3/bin/M5PaperS3_UIFlow2.0.bin',
          source: FirmwareSource.m5stackOfficial,
        ),
        Firmware(
          id: 'm5stack-m5papers3-arduino',
          name: 'M5PaperS3 Arduino',
          version: 'v2.0.9',
          description:
              'M5Stack official Arduino firmware. / M5Stack 官方 Arduino 固件。',
          downloadUrl: 'https://m5stack.oss-cn-shenzhen.aliyuncs.com/resource/docs/products/core/M5PaperS3/bin/M5PaperS3_Arduino.bin',
          source: FirmwareSource.m5stackOfficial,
        ),
      ];

  List<Firmware> _edcBookFirmwares() => const [
        Firmware(
          id: 'edcbook-m5papers3-release',
          name: 'EDC Book（梦西游）',
          version: 'v3.x',
          description:
              'EDC Book e-reader firmware for M5PaperS3. / 梦西游电子书固件，适配 M5PaperS3。',
          downloadUrl: 'https://github.com/dreamxiyou/edcbook/releases/download/latest/edcbook_m5papers3.bin',
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
