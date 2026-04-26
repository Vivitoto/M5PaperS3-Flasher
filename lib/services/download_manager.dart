import 'dart:async';
import 'dart:io';

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

  double? get fraction =>
      totalBytes == null || totalBytes == 0 ? null : receivedBytes / totalBytes!;
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

  Stream<DownloadProgress> download(Firmware firmware, {bool force = false}) async* {
    final file = await _targetFile(firmware);
    final tempFile = File('${file.path}.part');
    final expectedSize = firmware.sizeBytes;

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
    if (expectedSize != null && expectedSize > 0 && existing > expectedSize) {
      await tempFile.delete();
      existing = 0;
    }

    final request = http.Request('GET', Uri.parse(firmware.downloadUrl));
    if (existing > 0) request.headers['Range'] = 'bytes=$existing-';

    final response = await _client.send(request);
    if (response.statusCode == 416) {
      final tempLength = await tempFile.exists() ? await tempFile.length() : 0;
      if (expectedSize != null && expectedSize > 0 && tempLength == expectedSize) {
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
      throw Exception('Download resume failed: server rejected range and partial file is incomplete');
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
    final sink = tempFile.openWrite(mode: append ? FileMode.append : FileMode.write);
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
    if (expectedSize != null && expectedSize > 0 && finalLength != expectedSize) {
      await tempFile.delete();
      throw Exception('Download size mismatch: expected $expectedSize bytes, got $finalLength bytes');
    }

    if (await file.exists()) await file.delete();
    await tempFile.rename(file.path);
    final verified = await verify(file, firmware.hash);
    yield DownloadProgress(
      receivedBytes: await file.length(),
      totalBytes: await file.length(),
      filePath: file.path,
      verified: verified,
    );
  }

  Future<File> _targetFile(Firmware firmware) async {
    final directory = await getTemporaryDirectory();
    final safeName = '${firmware.id.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_')}.bin';
    return File('${directory.path}/$safeName');
  }

  int? _contentLength(http.StreamedResponse response, int offset) {
    final headerLength = response.contentLength;
    if (headerLength == null) return null;
    return response.statusCode == 206 ? offset + headerLength : headerLength;
  }

  Future<bool?> verify(File file, FirmwareHash? expected) async {
    if (expected == null) return null;
    final bytes = await file.readAsBytes();
    final digest = expected.type == HashType.md5 ? md5.convert(bytes) : sha256.convert(bytes);
    return digest.toString().toLowerCase() == expected.value.toLowerCase();
  }
}
