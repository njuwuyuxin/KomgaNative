import 'dart:io';
import 'dart:typed_data';

import 'package:yomu/src/data/local/cover_thumbnail_generator.dart';
import 'package:yomu/src/data/local/local_catalog_edit_dao.dart';
import 'package:yomu/src/data/local/local_comic_importer_models.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
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

const int _maxExternalSidecarCoverBytes = 20 * 1024 * 1024;

/// 将外部挂载目录中的同级侧车封面（`cover.*` / `folder.*` / `poster.*`）绑定到对应单一本地系列。
Future<void> applyExternalSidecarCovers({
  required ProgressDatabase db,
  required LocalComicsStorage storage,
  required ExternalRootsBridge bridge,
  required CoverThumbnailEncoder coverEncoder,
  required MountedExternalRoot root,
  required List<ExternalTreeEntry> allEntries,
  required Map<String, Set<String>> dirToSeriesIds,
}) async {
  final sidecars = <String, ({ExternalTreeEntry entry, int prio})>{};
  for (final e in allEntries) {
    if (e.isDirectory || e.isCloudPlaceholder) continue;
    final prio = sidecarCoverPriority(e.name);
    if (prio == null) continue;
    final dirKey = externalParentDirKey(e.relativePath);
    if (dirKey.isEmpty) continue;
    final prev = sidecars[dirKey];
    if (prev == null || prio < prev.prio) {
      sidecars[dirKey] = (entry: e, prio: prio);
    }
  }
  for (final pair in sidecars.entries) {
    final seriesIds = dirToSeriesIds[pair.key];
    if (seriesIds == null || seriesIds.length != 1) continue;
    final seriesId = seriesIds.single;
    final target = await db.findLocalSeriesForSidecarCover(seriesId: seriesId);
    if (target == null) continue;
    final bytes = await _readExternalSmallFile(bridge, root, pair.value.entry);
    if (bytes == null || bytes.isEmpty) continue;
    await applySidecarSeriesCover(
      db: db,
      storage: storage,
      coverEncoder: coverEncoder,
      imageBytes: bytes,
      seriesId: seriesId,
    );
  }
}

String externalParentDirKey(String relPath) {
  final norm = relPath.replaceAll(r'\', '/');
  final parts = norm.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.length < 2) return '';
  return parts.sublist(0, parts.length - 1).join('/');
}

Future<Uint8List?> _readExternalSmallFile(
  ExternalRootsBridge bridge,
  MountedExternalRoot root,
  ExternalTreeEntry entry,
) async {
  try {
    if (root.kind == ExternalRootKind.localDirectory) {
      final file = File(entry.uri);
      final len = await file.length();
      if (len <= 0 || len > _maxExternalSidecarCoverBytes) return null;
      return await file.readAsBytes();
    }
    final len = entry.sizeBytes > 0
        ? entry.sizeBytes
        : await bridge.fileLength(entry.uri, root: root);
    if (len == null || len <= 0 || len > _maxExternalSidecarCoverBytes) {
      return null;
    }
    return await bridge.readFileRange(entry.uri, 0, len, root: root);
  } on FileSystemException {
    return null;
  }
}
