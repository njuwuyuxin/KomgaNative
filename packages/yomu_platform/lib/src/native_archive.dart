import 'package:flutter/services.dart';

/// 平台原生归档解码器支持的格式类型（LMB-12）。
enum NativeArchiveFormat { rar4, rar5, sevenZip }

/// 平台原生归档解码错误类型（LMB-12 / LMB-13）。
enum NativeArchiveErrorKind { invalidPassword, corrupted, unsupported, ioError }

final class NativeArchiveException implements Exception {
  const NativeArchiveException(this.kind, [this.message]);

  final NativeArchiveErrorKind kind;
  final String? message;

  @override
  String toString() => message == null
      ? 'NativeArchiveException(${kind.name})'
      : 'NativeArchiveException(${kind.name}: $message)';
}

final class NativeArchiveEntry {
  const NativeArchiveEntry({
    required this.entryName,
    required this.uncompressedSize,
    this.isEncrypted = false,
    this.isDirectory = false,
  });

  final String entryName;
  final int uncompressedSize;
  final bool isEncrypted;
  final bool isDirectory;
}

final class NativeArchiveListing {
  const NativeArchiveListing({
    required this.format,
    required this.isSolid,
    required this.entries,
  });

  final NativeArchiveFormat format;
  final bool isSolid;
  final List<NativeArchiveEntry> entries;
}

/// 平台原生 CBR (RAR4/RAR5) 与 CB7 (7z/LZMA2) 解码通道抽象（LMB-12，ADR 0010）。
abstract interface class NativeArchiveBridge {
  /// 枚举归档条目列表并探测是否为固实压缩包；加密且密码不匹配时抛 [NativeArchiveErrorKind.invalidPassword]。
  Future<NativeArchiveListing> listEntries(String filePath, {String? password});

  /// 单条目按需解压（适用于非固实归档与 `ComicInfo.xml` 读取）。
  Future<Uint8List> extractEntry({
    required String filePath,
    required String entryName,
    String? password,
  });

  /// 固实包单趟批量窗口解压（一次顺序扫描抽出多页，避免 \(O(N^2)\) 重头解压）。
  Future<Map<String, Uint8List>> extractWindow({
    required String filePath,
    required List<String> entryNames,
    String? password,
  });

  /// 释放底层归档句柄缓存。
  Future<void> closeArchive(String filePath);
}

/// 基于 `yomu/native_archive` MethodChannel 的实现。
class ChannelNativeArchiveBridge implements NativeArchiveBridge {
  ChannelNativeArchiveBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('yomu/native_archive');

  final MethodChannel _channel;

  @override
  Future<NativeArchiveListing> listEntries(
    String filePath, {
    String? password,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'listEntries',
        <String, Object?>{'filePath': filePath, 'password': password},
      );
      if (raw == null) {
        throw const NativeArchiveException(
          NativeArchiveErrorKind.unsupported,
          'Native archive engine unavailable',
        );
      }
      final format = switch (raw['format']) {
        'rar4' => NativeArchiveFormat.rar4,
        'rar5' => NativeArchiveFormat.rar5,
        _ => NativeArchiveFormat.sevenZip,
      };
      final rawEntries = raw['entries'] as List<Object?>? ?? const <Object?>[];
      final entries = <NativeArchiveEntry>[];
      for (final item in rawEntries) {
        if (item is Map<Object?, Object?>) {
          final name = item['entryName'];
          if (name is! String || name.isEmpty) continue;
          entries.add(
            NativeArchiveEntry(
              entryName: name,
              uncompressedSize: (item['uncompressedSize'] as int?) ?? 0,
              isEncrypted: item['isEncrypted'] == true,
              isDirectory: item['isDirectory'] == true,
            ),
          );
        }
      }
      return NativeArchiveListing(
        format: format,
        isSolid: raw['isSolid'] == true,
        entries: List<NativeArchiveEntry>.unmodifiable(entries),
      );
    } on MissingPluginException {
      throw const NativeArchiveException(
        NativeArchiveErrorKind.unsupported,
        'Native archive channel not implemented',
      );
    } on PlatformException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<Uint8List> extractEntry({
    required String filePath,
    required String entryName,
    String? password,
  }) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'extractEntry',
        <String, Object?>{
          'filePath': filePath,
          'entryName': entryName,
          'password': password,
        },
      );
      if (bytes == null) {
        throw const NativeArchiveException(
          NativeArchiveErrorKind.corrupted,
          'Entry not found in archive',
        );
      }
      return bytes;
    } on MissingPluginException {
      throw const NativeArchiveException(
        NativeArchiveErrorKind.unsupported,
        'Native archive channel not implemented',
      );
    } on PlatformException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<Map<String, Uint8List>> extractWindow({
    required String filePath,
    required List<String> entryNames,
    String? password,
  }) async {
    if (entryNames.isEmpty) return const <String, Uint8List>{};
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'extractWindow',
        <String, Object?>{
          'filePath': filePath,
          'entryNames': entryNames,
          'password': password,
        },
      );
      if (raw == null) return const <String, Uint8List>{};
      final out = <String, Uint8List>{};
      raw.forEach((Object? key, Object? value) {
        if (key is String && value is Uint8List) {
          out[key] = value;
        }
      });
      return out;
    } on MissingPluginException {
      throw const NativeArchiveException(
        NativeArchiveErrorKind.unsupported,
        'Native archive channel not implemented',
      );
    } on PlatformException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> closeArchive(String filePath) async {
    try {
      await _channel.invokeMethod<void>('closeArchive', <String, Object?>{
        'filePath': filePath,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static NativeArchiveException _mapError(PlatformException e) {
    final kind = switch (e.code) {
      'INVALID_PASSWORD' => NativeArchiveErrorKind.invalidPassword,
      'CORRUPTED' => NativeArchiveErrorKind.corrupted,
      'UNSUPPORTED' => NativeArchiveErrorKind.unsupported,
      _ => NativeArchiveErrorKind.ioError,
    };
    return NativeArchiveException(kind, e.message);
  }
}
