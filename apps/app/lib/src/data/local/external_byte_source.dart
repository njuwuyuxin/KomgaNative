import 'dart:io';
import 'dart:typed_data';

import 'package:yomu/src/data/local/external_roots_dao.dart';
import 'package:yomu/src/data/local/native_pdf_reader.dart';
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

/// 打开外部原位挂载书对应的零拷贝读取器（LMB-08 / LMB-11）。
Future<ComicArchiveReader> openExternalComicReader({
  required ProgressDatabase db,
  required ExternalRootsBridge externalRoots,
  required NativePdfBridge pdfBridge,
  required LocalBooksRow row,
  required List<ArchivePageEntry> entries,
  String? password,
}) async {
  final rootRow = await db.mountedRootById(row.mountRootId!);
  final root = rootRow == null ? null : mountedRootFromRow(rootRow);

  if (row.isCloudPlaceholder) {
    await externalRoots.triggerCloudDownload(row.relativePath, root: root);
    throw const ArchiveException(
      ArchiveErrorKind.ioError,
      'Cloud placeholder is downloading; please retry shortly',
    );
  }

  if (row.storageKind == 'ext_folder') {
    final dir = Directory(row.relativePath);
    return entries.isNotEmpty
        ? FolderComicReader.fromIndexedPages(dir, entries)
        : FolderComicReader.open(dir);
  }

  if (row.storageKind == 'ext_pdf') {
    return entries.isNotEmpty
        ? NativePdfComicReader.fromIndexedPages(
            pdfBridge,
            row.relativePath,
            entries,
            password: password,
          )
        : NativePdfComicReader.open(
            pdfBridge,
            row.relativePath,
            password: password,
          );
  }

  final useBridge =
      row.storageKind.startsWith('saf_') ||
      root?.kind == ExternalRootKind.androidSaf ||
      root?.kind == ExternalRootKind.iosBookmark;
  final RandomAccessByteSource source = useBridge
      ? ExternalRangeByteSource(
          bridge: externalRoots,
          uri: row.relativePath,
          root: root,
          knownLength: row.sizeBytes > 0 ? row.sizeBytes : null,
        )
      : await FileByteSource.open(File(row.relativePath));

  if (row.storageKind.endsWith('_tar')) {
    return entries.isNotEmpty
        ? TarComicReader.fromIndexedPages(source, entries)
        : TarComicReader.open(source);
  }
  if (password != null && password.isNotEmpty) {
    return ZipComicReader.open(
      source,
      sniffDimensions: false,
      password: password,
    );
  }
  return entries.isNotEmpty
      ? ZipComicReader.fromIndexedPages(source, entries)
      : openComicArchive(source);
}
