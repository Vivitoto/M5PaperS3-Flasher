import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/firmware.dart';

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

  Stream<DownloadProgress> download(Firmware firmware) async* {
    final directory = await getTemporaryDirectory();
    final safeName = '${firmware.id.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_')}.bin';
    final file = File('${directory.path}/$safeName');
    final tempFile = File('${file.path}.part');

    final existing = await tempFile.exists() ? await tempFile.length() : 0;
    final request = http.Request('GET', Uri.parse(firmware.downloadUrl));
    if (existing > 0) request.headers['Range'] = 'bytes=$existing-';

    final response = await _client.send(request);
    if (response.statusCode == 416) {
      await tempFile.rename(file.path);
      final verified = await verify(file, firmware.hash);
      yield DownloadProgress(
        receivedBytes: await file.length(),
        totalBytes: await file.length(),
        filePath: file.path,
        verified: verified,
      );
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final total = _contentLength(response, existing);
    final sink = tempFile.openWrite(mode: FileMode.append);
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
