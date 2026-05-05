import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/firmware.dart';

enum LocalFirmwareStatus { none, partial, complete }

class LocalFirmwareInfo {
  const LocalFirmwareInfo({
    required this.status,
    this.filePath,
    this.receivedBytes = 0,
    this.totalBytes,
  });

  final LocalFirmwareStatus status;
  final String? filePath;
  final int receivedBytes;
  final int? totalBytes;
}

class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    this.totalBytes,
    this.filePath,
    this.verified,
  });

  final int receivedBytes;
  final int? totalBytes;
  final String? filePath;
  final bool? verified;

  double? get fraction => totalBytes == null || totalBytes == 0
      ? null
      : receivedBytes / totalBytes!;
}

class DownloadManager {
  DownloadManager({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<LocalFirmwareInfo> localInfo(Firmware firmware) async {
    final file = await _targetFile(firmware);
    final tempFile = File('${file.path}.part');
    final expectedSize = firmware.sizeBytes;

    if (await file.exists()) {
      final length = await file.length();
      if (expectedSize == null || expectedSize <= 0 || length == expectedSize) {
        return LocalFirmwareInfo(
          status: LocalFirmwareStatus.complete,
          filePath: file.path,
          receivedBytes: length,
          totalBytes: expectedSize ?? length,
        );
      }
    }

    if (await tempFile.exists()) {
      final length = await tempFile.length();
      if (length > 0) {
        return LocalFirmwareInfo(
          status: LocalFirmwareStatus.partial,
          receivedBytes: length,
          totalBytes: expectedSize,
        );
      }
    }

    return LocalFirmwareInfo(
      status: LocalFirmwareStatus.none,
      totalBytes: expectedSize,
    );
  }

  Stream<DownloadProgress> download(Firmware firmware,
      {bool force = false}) async* {
    final file = await _targetFile(firmware);
    final tempFile = File('${file.path}.part');
    final expectedSize = firmware.sizeBytes;
    final archiveDownload = _isArchiveDownload(firmware);

    if (force) {
      if (await file.exists()) await file.delete();
      if (await tempFile.exists()) await tempFile.delete();
    } else if (await file.exists()) {
      final length = await file.length();
      if (expectedSize == null || expectedSize <= 0 || length == expectedSize) {
        final verified = await verify(file, firmware.hash);
        yield DownloadProgress(
          receivedBytes: length,
          totalBytes: expectedSize ?? length,
          filePath: file.path,
          verified: verified,
        );
        return;
      }
      await file.delete();
    }

    var existing = await tempFile.exists() ? await tempFile.length() : 0;
    if (!archiveDownload &&
        expectedSize != null &&
        expectedSize > 0 &&
        existing > expectedSize) {
      await tempFile.delete();
      existing = 0;
    }

    final downloadUrls = _downloadUrls(firmware);
    http.StreamedResponse? response;
    Object? lastError;
    for (final url in downloadUrls) {
      try {
        final request = http.Request('GET', Uri.parse(url));
        if (existing > 0) request.headers['Range'] = 'bytes=$existing-';
        final candidate =
            await _client.send(request).timeout(const Duration(seconds: 12));
        if ((candidate.statusCode >= 200 && candidate.statusCode < 300) ||
            candidate.statusCode == 416) {
          response = candidate;
          break;
        }
        lastError = 'HTTP ${candidate.statusCode}';
      } catch (error) {
        lastError = error;
      }
    }
    if (response == null) {
      throw Exception('Download failed: $lastError');
    }
    if (response.statusCode == 416) {
      final tempLength = await tempFile.exists() ? await tempFile.length() : 0;
      if (expectedSize != null &&
          expectedSize > 0 &&
          tempLength == expectedSize) {
        if (await file.exists()) await file.delete();
        await tempFile.rename(file.path);
        final verified = await verify(file, firmware.hash);
        yield DownloadProgress(
          receivedBytes: await file.length(),
          totalBytes: expectedSize,
          filePath: file.path,
          verified: verified,
        );
        return;
      }
      if (await tempFile.exists()) await tempFile.delete();
      throw Exception(
          'Download resume failed: server rejected range and partial file is incomplete');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    // 服务器不支持 Range 时会返回 200。此时必须重下，避免把完整文件追加到半截文件后面。
    final append = existing > 0 && response.statusCode == 206;
    if (!append && await tempFile.exists()) {
      await tempFile.delete();
      existing = 0;
    }

    final total = _contentLength(response, existing);
    final sink =
        tempFile.openWrite(mode: append ? FileMode.append : FileMode.write);
    var received = existing;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        yield DownloadProgress(receivedBytes: received, totalBytes: total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    final finalLength = await tempFile.length();
    if (!archiveDownload &&
        expectedSize != null &&
        expectedSize > 0 &&
        finalLength != expectedSize) {
      await tempFile.delete();
      throw Exception(
          'Download size mismatch: expected $expectedSize bytes, got $finalLength bytes');
    }

    if (await file.exists()) await file.delete();
    if (archiveDownload) {
      await _extractBinFromArchive(tempFile, file);
      await tempFile.delete();
      final extractedLength = await file.length();
      if (expectedSize != null &&
          expectedSize > 0 &&
          extractedLength != expectedSize) {
        await file.delete();
        throw Exception(
            'Archive size mismatch: expected $expectedSize bytes, got $extractedLength bytes');
      }
    } else {
      await tempFile.rename(file.path);
    }
    final verified = await verify(file, firmware.hash);
    yield DownloadProgress(
      receivedBytes: await file.length(),
      totalBytes: await file.length(),
      filePath: file.path,
      verified: verified,
    );
  }

  Future<void> delete(Firmware firmware) async {
    final file = await _targetFile(firmware);
    final tempFile = File('${file.path}.part');
    if (await file.exists()) await file.delete();
    if (await tempFile.exists()) await tempFile.delete();
  }

  Future<List<Firmware>> scanLocalFirmwares() async {
    final directory = await _firmwareDirectory();
    if (!await directory.exists()) return const <Firmware>[];

    final entries = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.bin'))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    final firmwares = <Firmware>[];
    for (final file in entries) {
      final name = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : file.path.split(Platform.pathSeparator).last;
      if (name.endsWith('.part')) continue;
      final version = RegExp(r'v\d+(?:_\d+|\.\d+)*')
              .firstMatch(name)
              ?.group(0)
              ?.replaceAll('_', '.') ??
          'local';
      final size = await file.length();
      firmwares.add(Firmware(
        id: 'local-${name.hashCode}-$size',
        name: name.contains('Vink-PaperS3')
            ? 'Vink-PaperS3'
            : name.replaceAll('.bin', ''),
        version: version,
        description: '本地缓存固件 · 网络不可用时仍可烧录',
        changelog: '从本地 firmwares 目录识别。网络恢复后可刷新固件列表获取完整更新说明。',
        downloadUrl: file.uri.toString(),
        source: FirmwareSource.vink,
        sizeBytes: size,
        localPath: file.path,
        flashOffset: name.contains('full') || name.contains('16MB') ? 0 : 65536,
      ));
    }
    return firmwares;
  }

  Future<Directory> _firmwareDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/firmwares');
  }

  List<String> _downloadUrls(Firmware firmware) {
    return <String>[
      ...firmware.mirrorUrls,
      firmware.downloadUrl,
    ].where((url) => url.isNotEmpty).toSet().toList();
  }

  Future<File> _targetFile(Firmware firmware) async {
    // 固件不要放临时目录：系统可能清理，用户也无法明确管理。
    // 统一放到 app 文档目录下的 firmwares/，并在固件页提供删除入口。
    final directory = await _firmwareDirectory();
    if (!await directory.exists()) await directory.create(recursive: true);
    final assetName = Uri.tryParse(firmware.downloadUrl)?.pathSegments.last;
    final fallback =
        '${firmware.id.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_')}.bin';
    var safeName =
        (assetName == null || assetName.isEmpty ? fallback : assetName)
            .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    if (safeName.toLowerCase().endsWith('.zip')) {
      safeName = safeName.substring(0, safeName.length - 4);
    }
    if (!safeName.toLowerCase().endsWith('.bin')) {
      safeName = '$safeName.bin';
    }
    return File('${directory.path}/$safeName');
  }

  bool _isArchiveDownload(Firmware firmware) {
    final path = Uri.tryParse(firmware.downloadUrl)?.path.toLowerCase() ?? '';
    return path.endsWith('.zip');
  }

  Future<void> _extractBinFromArchive(File archiveFile, File targetFile) async {
    Archive? archive;
    try {
      archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
    } catch (error) {
      throw Exception('无法解析 ZIP 压缩包（可能已损坏）: $error');
    }
    ArchiveFile? bin;
    ArchiveFile? bestBin;
    for (final file in archive.files) {
      if (file.isFile && file.name.toLowerCase().endsWith('.bin')) {
        bestBin = file;
        // Prefer a file whose name suggests it's the main firmware
        final lower = file.name.toLowerCase();
        if (lower.contains('full') ||
            lower.contains('firmware') ||
            lower.contains('app')) {
          bin = file;
          break;
        }
      }
    }
    bin ??= bestBin;
    if (bin == null) {
      throw Exception('ZIP 包内未找到 .bin 固件文件');
    }
    final content = bin.content;
    final bytes =
        content is List<int> ? content : List<int>.from(content as Iterable);
    await targetFile.writeAsBytes(bytes, flush: true);
  }

  int? _contentLength(http.StreamedResponse response, int offset) {
    final headerLength = response.contentLength;
    if (headerLength == null) return null;
    return response.statusCode == 206 ? offset + headerLength : headerLength;
  }

  Future<bool?> verify(File file, FirmwareHash? expected) async {
    if (expected == null) return null;
    final bytes = await file.readAsBytes();
    final digest = expected.type == HashType.md5
        ? md5.convert(bytes)
        : sha256.convert(bytes);
    return digest.toString().toLowerCase() == expected.value.toLowerCase();
  }
}
