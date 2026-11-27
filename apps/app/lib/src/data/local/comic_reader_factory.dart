import 'dart:io';

import 'package:yomu/src/data/local/archive_password_store.dart';
import 'package:yomu/src/data/local/external_byte_source.dart';
import 'package:yomu/src/data/local/external_roots_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_storage_kind.dart';
import 'package:yomu/src/data/local/native_archive_reader.dart';
import 'package:yomu/src/data/local/native_pdf_reader.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

export 'package:yomu/src/data/local/local_storage_kind.dart';

/// 统一的本机与外部原位漫画读取器工厂（P1-6）。
///
/// 阅读器打开整书与书架封面提取共用同一套分派逻辑，杜绝「能读不能出封面」或格式遗漏。
final class ComicReaderFactory {
  ComicReaderFactory({
    required ProgressDatabase db,
    required LocalComicsStorage storage,
    ExternalRootsBridge? externalRoots,
    NativePdfBridge? pdfBridge,
    NativeArchiveBridge? archiveBridge,
    ArchivePasswordStore? passwordStore,
  }) : _db = db,
       _storage = storage,
       _externalRoots = externalRoots ?? ChannelExternalRootsBridge(),
       _pdfBridge = pdfBridge ?? ChannelNativePdfBridge(),
       _archiveBridge = archiveBridge ?? ChannelNativeArchiveBridge(),
       _passwordStore = passwordStore;

  final ProgressDatabase _db;
  final LocalComicsStorage _storage;
  final ExternalRootsBridge _externalRoots;
  final NativePdfBridge _pdfBridge;
  final NativeArchiveBridge _archiveBridge;
  final ArchivePasswordStore? _passwordStore;

  /// 按 `row` 的存储格式与挂载位置打开对应 [ComicArchiveReader]。
  Future<ComicArchiveReader> open(
    LocalBooksRow row, {
    List<ArchivePageEntry> entries = const <ArchivePageEntry>[],
    bool sniffDimensions = true,
  }) async {
    final password = await _readSavedPassword(row.id);
    if (row.mountRootId != null) {
      return _openExternal(
        row,
        entries: entries,
        password: password,
        sniffDimensions: sniffDimensions,
      );
    }
    return _openManaged(
      row,
      entries: entries,
      password: password,
      sniffDimensions: sniffDimensions,
    );
  }

  Future<String?> _readSavedPassword(String bookId) async {
    final store = _passwordStore;
    if (store == null) return null;
    try {
      return await store.getBookPassword(bookId);
    } on Object {
      return null;
    }
  }

  Future<ComicArchiveReader> _openManaged(
    LocalBooksRow row, {
    required List<ArchivePageEntry> entries,
    required String? password,
    required bool sniffDimensions,
  }) async {
    final kind = LocalStorageKind.parse(row.storageKind);
    switch (kind) {
      case LocalStorageKind.folder:
      case LocalStorageKind.extFolder:
        final dir = await _storage.resolveDirectory(row.relativePath);
        if (!await dir.exists()) {
          throw const ArchiveException(
            ArchiveErrorKind.ioError,
            'Missing folder',
          );
        }
        return entries.isNotEmpty
            ? FolderComicReader.fromIndexedPages(dir, entries)
            : FolderComicReader.open(dir, sniffDimensions: sniffDimensions);

      case LocalStorageKind.pdf:
      case LocalStorageKind.extPdf:
      case LocalStorageKind.safPdf:
        final file = await _storage.resolveFile(row.relativePath);
        return _openPdf(file.path, entries: entries, password: password);

      case LocalStorageKind.cb7:
      case LocalStorageKind.cbr:
      case LocalStorageKind.extCb7:
      case LocalStorageKind.extCbr:
        final file = await _storage.resolveFile(row.relativePath);
        final format =
            (kind == LocalStorageKind.cb7 || kind == LocalStorageKind.extCb7)
            ? NativeArchiveFormat.sevenZip
            : NativeArchiveFormat.rar4;
        return _openNativeArchive(
          file.path,
          format: format,
          entries: entries,
          password: password,
          sniffFirstCoverDimensions: sniffDimensions,
        );

      case LocalStorageKind.tar:
      case LocalStorageKind.extTar:
      case LocalStorageKind.safTar:
        final source = await FileByteSource.open(
          await _storage.resolveFile(row.relativePath),
        );
        return entries.isNotEmpty
            ? TarComicReader.fromIndexedPages(source, entries)
            : TarComicReader.open(source, sniffDimensions: sniffDimensions);

      case LocalStorageKind.zip:
      case LocalStorageKind.epub:
      case LocalStorageKind.extZip:
      case LocalStorageKind.extEpub:
      case LocalStorageKind.safZip:
      case LocalStorageKind.safEpub:
        final source = await FileByteSource.open(
          await _storage.resolveFile(row.relativePath),
        );
        return _openZipOrArchive(
          source,
          entries: entries,
          password: password,
          sniffDimensions: sniffDimensions,
        );
    }
  }

  Future<ComicArchiveReader> _openExternal(
    LocalBooksRow row, {
    required List<ArchivePageEntry> entries,
    required String? password,
    required bool sniffDimensions,
  }) async {
    final rootRow = await _db.mountedRootById(row.mountRootId!);
    final root = rootRow == null ? null : mountedRootFromRow(rootRow);

    if (row.isCloudPlaceholder) {
      await _externalRoots.triggerCloudDownload(row.relativePath, root: root);
      throw const ArchiveException(
        ArchiveErrorKind.ioError,
        'Cloud placeholder is downloading; please retry shortly',
      );
    }

    final kind = LocalStorageKind.parse(row.storageKind);
    switch (kind) {
      case LocalStorageKind.folder:
      case LocalStorageKind.extFolder:
        final dir = Directory(row.relativePath);
        return entries.isNotEmpty
            ? FolderComicReader.fromIndexedPages(dir, entries)
            : FolderComicReader.open(dir, sniffDimensions: sniffDimensions);

      case LocalStorageKind.pdf:
      case LocalStorageKind.extPdf:
      case LocalStorageKind.safPdf:
        return _openPdf(row.relativePath, entries: entries, password: password);

      case LocalStorageKind.cb7:
      case LocalStorageKind.cbr:
      case LocalStorageKind.extCb7:
      case LocalStorageKind.extCbr:
        final format =
            (kind == LocalStorageKind.cb7 || kind == LocalStorageKind.extCb7)
            ? NativeArchiveFormat.sevenZip
            : NativeArchiveFormat.rar4;
        return _openNativeArchive(
          row.relativePath,
          format: format,
          entries: entries,
          password: password,
          sniffFirstCoverDimensions: sniffDimensions,
        );

      case LocalStorageKind.tar:
      case LocalStorageKind.extTar:
      case LocalStorageKind.safTar:
        final source = await _openExternalByteSource(
          row,
          kind: kind,
          root: root,
        );
        return entries.isNotEmpty
            ? TarComicReader.fromIndexedPages(source, entries)
            : TarComicReader.open(source, sniffDimensions: sniffDimensions);

      case LocalStorageKind.zip:
      case LocalStorageKind.epub:
      case LocalStorageKind.extZip:
      case LocalStorageKind.extEpub:
      case LocalStorageKind.safZip:
      case LocalStorageKind.safEpub:
        final source = await _openExternalByteSource(
          row,
          kind: kind,
          root: root,
        );
        return _openZipOrArchive(
          source,
          entries: entries,
          password: password,
          sniffDimensions: sniffDimensions,
        );
    }
  }

  Future<RandomAccessByteSource> _openExternalByteSource(
    LocalBooksRow row, {
    required LocalStorageKind kind,
    required MountedExternalRoot? root,
  }) async {
    final useBridge =
        kind.isSaf ||
        root?.kind == ExternalRootKind.androidSaf ||
        root?.kind == ExternalRootKind.iosBookmark;
    if (useBridge) {
      return ExternalRangeByteSource(
        bridge: _externalRoots,
        uri: row.relativePath,
        root: root,
        knownLength: row.sizeBytes > 0 ? row.sizeBytes : null,
      );
    }
    return FileByteSource.open(File(row.relativePath));
  }

  Future<ComicArchiveReader> _openPdf(
    String path, {
    required List<ArchivePageEntry> entries,
    required String? password,
  }) async {
    if (entries.isNotEmpty) {
      return NativePdfComicReader.fromIndexedPages(
        _pdfBridge,
        path,
        entries,
        password: password,
      );
    }
    return NativePdfComicReader.open(_pdfBridge, path, password: password);
  }

  Future<ComicArchiveReader> _openNativeArchive(
    String path, {
    required NativeArchiveFormat format,
    required List<ArchivePageEntry> entries,
    required String? password,
    required bool sniffFirstCoverDimensions,
  }) async {
    if (entries.isNotEmpty) {
      return NativeArchiveComicReader.fromIndexedPages(
        _archiveBridge,
        path,
        entries,
        format: format,
        isSolid: true,
        password: password,
      );
    }
    return NativeArchiveComicReader.open(
      _archiveBridge,
      path,
      password: password,
      sniffFirstCoverDimensions: sniffFirstCoverDimensions,
    );
  }

  Future<ComicArchiveReader> _openZipOrArchive(
    RandomAccessByteSource source, {
    required List<ArchivePageEntry> entries,
    required String? password,
    required bool sniffDimensions,
  }) async {
    if (password != null && password.isNotEmpty) {
      return ZipComicReader.open(
        source,
        sniffDimensions: false,
        password: password,
      );
    }
    if (entries.isNotEmpty) {
      return ZipComicReader.fromIndexedPages(source, entries);
    }
    return openComicArchive(source, sniffDimensions: sniffDimensions);
  }
}
