import 'dart:typed_data';

import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// 基于 [ExternalRootsBridge] 的外部挂载文件随机访问字节源（LMB-08）。
///
/// 通过 Android SAF `ParcelFileDescriptor` 或 iOS Security-Scoped Bookmark
/// 直接原位区间读，实现外部 SD 卡 / 文件夹零全量拷贝直开 CBZ / EPUB / CBT。
final class ExternalRangeByteSource implements RandomAccessByteSource {
  ExternalRangeByteSource({
    required ExternalRootsBridge bridge,
    required String uri,
    MountedExternalRoot? root,
    int? knownLength,
  }) : _bridge = bridge,
       _uri = uri,
       _root = root,
       _cachedLength = knownLength;

  final ExternalRootsBridge _bridge;
  final String _uri;
  final MountedExternalRoot? _root;
  int? _cachedLength;

  @override
  Future<int> length() async {
    final cached = _cachedLength;
    if (cached != null) return cached;
    final len = await _bridge.fileLength(_uri, root: _root);
    if (len == null) {
      throw ArchiveException(
        ArchiveErrorKind.ioError,
        'Unable to query external file length: $_uri',
      );
    }
    _cachedLength = len;
    return len;
  }

  @override
  Future<Uint8List> readRange(int offset, int length) async {
    if (length <= 0) return Uint8List(0);
    final bytes = await _bridge.readFileRange(
      _uri,
      offset,
      length,
      root: _root,
    );
    if (bytes == null) {
      throw ArchiveException(
        ArchiveErrorKind.ioError,
        'Unable to read external range [$offset, +$length): $_uri',
      );
    }
    return bytes;
  }

  @override
  Future<void> close() async {}
}
