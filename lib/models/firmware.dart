enum FirmwareSource { vink, m5stackOfficial, m5stackCommunity, edcBook, custom }

enum HashType { md5, sha256 }

class FirmwareHash {
  const FirmwareHash({required this.type, required this.value});

  final HashType type;
  final String value;
}

class Firmware {
  const Firmware({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.downloadUrl,
    required this.source,
    this.changelog = '',
    this.sizeBytes,
    this.hash,
    this.releaseUrl,
    this.localPath,
    this.flashOffset = 0,
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final String downloadUrl;
  final FirmwareSource source;
  final String changelog;
  final int? sizeBytes;
  final FirmwareHash? hash;
  final String? releaseUrl;
  final String? localPath;
  /// ESP32 flash offset. Full 16MB images are written at 0x0.
  final int flashOffset;

  Firmware copyWith({
    String? id,
    String? name,
    String? version,
    String? description,
    String? downloadUrl,
    FirmwareSource? source,
    String? changelog,
    int? sizeBytes,
    FirmwareHash? hash,
    String? releaseUrl,
    String? localPath,
    int? flashOffset,
  }) {
    return Firmware(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      description: description ?? this.description,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      source: source ?? this.source,
      changelog: changelog ?? this.changelog,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      hash: hash ?? this.hash,
      releaseUrl: releaseUrl ?? this.releaseUrl,
      localPath: localPath ?? this.localPath,
      flashOffset: flashOffset ?? this.flashOffset,
    );
  }

  String get sourceLabel {
    switch (source) {
      case FirmwareSource.vink:
        return 'Vink';
      case FirmwareSource.m5stackOfficial:
        return 'M5Stack 官方';
      case FirmwareSource.m5stackCommunity:
        return 'M5Stack 社区';
      case FirmwareSource.edcBook:
        return 'EDC Book';
      case FirmwareSource.custom:
        return '自定义';
    }
  }

  String get sizeLabel {
    final size = sizeBytes;
    if (size == null || size <= 0) return 'Unknown / 未知';
    if (size >= 1024 * 1024) return '${(size / 1024 / 1024).toStringAsFixed(2)} MB';
    if (size >= 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '$size B';
  }
}
