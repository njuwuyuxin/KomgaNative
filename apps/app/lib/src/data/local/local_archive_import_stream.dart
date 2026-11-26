import 'dart:io';
import 'dart:typed_data';

import 'package:yomu/src/data/local/cover_thumbnail_generator.dart';
import 'package:yomu/src/data/local/local_comic_importer_models.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/native_archive_reader.dart';
import 'package:yomu/src/data/local/native_pdf_reader.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// 导入单个归档文件流；若检测到为「嵌套合集包」（内部无直接图片但含多个子归档），
/// 自动拆包入库并归入同一系列，同时清理外层临时文件（LMB-06 / LMB-11 / LMB-12）。
Future<LocalImportBatchResult> importArchiveOrCollectionStream({
  required ProgressDatabase db,
  required LocalComicsStorage storage,
  required CoverThumbnailEncoder coverEncoder,
  required Stream<List<int>> Function() openStream,
  required String displayFileName,
  required String? parentFolderName,
  required String Function(String prefix) nextId,
  NativePdfBridge? pdfBridge,
  NativeArchiveBridge? archiveBridge,
  String? password,
  bool allowNestedUnpack = true,
}) async {
  final bookId = nextId('b');
  final safeFolder = bookId.replaceAll(':', '_');
  final lower = displayFileName.toLowerCase();
  final archiveExt = lower.endsWith('.pdf')
      ? 'pdf'
      : lower.endsWith('.epub')
      ? 'epub'
      : (lower.endsWith('.cbt') || lower.endsWith('.tar'))
      ? 'cbt'
      : (lower.endsWith('.cb7') || lower.endsWith('.7z'))
      ? 'cb7'
      : (lower.endsWith('.cbr') || lower.endsWith('.rar'))
      ? 'cbr'
      : 'cbz';
  final archiveRelPath = 'books/$safeFolder/archive.$archiveExt';
  final destFile = await storage.resolveFile(archiveRelPath);

  FileByteSource? fileSource;
  ComicArchiveReader? reader;
  try {
    await destFile.parent.create(recursive: true);
    await writeStreamToFile(openStream(), destFile);
    final sizeBytes = await destFile.length();
    if (sizeBytes <= 0) {
      throw const ArchiveException(ArchiveErrorKind.emptyFile);
    }

    final head = await _peekFileHead(destFile, 16);
    final magic = sniffContainerMagic(head);
    final isPdf = magic == ContainerMagic.pdf || lower.endsWith('.pdf');
    final isNativeArchive =
        magic == ContainerMagic.rar4 ||
        magic == ContainerMagic.rar5 ||
        magic == ContainerMagic.sevenZip;

    if (isPdf) {
      reader = await NativePdfComicReader.open(
        pdfBridge ?? ChannelNativePdfBridge(),
        destFile.path,
        password: password,
      );
    } else if (isNativeArchive) {
      reader = await NativeArchiveComicReader.open(
        archiveBridge ?? ChannelNativeArchiveBridge(),
        destFile.path,
        password: password,
      );
    } else {
      fileSource = await FileByteSource.open(destFile);
      try {
        reader = await openComicArchive(fileSource);
      } on ArchiveException catch (e) {
        fileSource = null; // openComicArchive 失败时已关闭句柄
        if (allowNestedUnpack && e.kind == ArchiveErrorKind.noImages) {
          final unpacked = await _tryUnpackNestedCollection(
            db: db,
            storage: storage,
            coverEncoder: coverEncoder,
            outerFile: destFile,
            outerFileName: displayFileName,
            parentFolderName: parentFolderName,
            nextId: nextId,
            pdfBridge: pdfBridge,
            archiveBridge: archiveBridge,
          );
          if (unpacked != null) {
            await tryDeleteImportDir(destFile.parent);
            return unpacked;
          }
        }
        rethrow;
      }
    }

    final storageKind = switch (reader) {
      NativePdfComicReader() => 'pdf',
      NativeArchiveComicReader(:final format) =>
        format == NativeArchiveFormat.sevenZip ? 'cb7' : 'cbr',
      EpubComicReader() => 'epub',
      TarComicReader() => 'tar',
      _ => 'zip',
    };
    final result = await commitComicReaderToDatabase(
      db: db,
      storage: storage,
      coverEncoder: coverEncoder,
      bookId: bookId,
      safeFolder: safeFolder,
      storageKind: storageKind,
      relativePath: archiveRelPath,
      sizeBytes: sizeBytes,
      displayName: displayFileName,
      parentFolderName: parentFolderName,
      reader: reader,
      generateSeriesId: () => nextId('s'),
    );
    await reader.close();
    reader = null;
    fileSource = null;
    return LocalImportBatchResult(
      importedSeriesIds: <String>[result.seriesId],
      importedBookIds: <String>[result.bookId],
    );
  } on Object {
    await reader?.close();
    await fileSource?.close();
    await tryDeleteImportDir(destFile.parent);
    rethrow;
  }
}

Future<LocalImportBatchResult?> _tryUnpackNestedCollection({
  required ProgressDatabase db,
  required LocalComicsStorage storage,
  required CoverThumbnailEncoder coverEncoder,
  required File outerFile,
  required String outerFileName,
  required String? parentFolderName,
  required String Function(String prefix) nextId,
  NativePdfBridge? pdfBridge,
  NativeArchiveBridge? archiveBridge,
}) async {
  final outerSource = await FileByteSource.open(outerFile);
  try {
    final nestedEntries = await inspectNestedZipArchives(outerSource);
    if (nestedEntries.isEmpty) return null;

    final collectionSeries =
        (parentFolderName != null && parentFolderName.trim().isNotEmpty)
        ? parentFolderName.trim()
        : inferTitlesFromFileName(outerFileName).seriesTitle;

    final seriesIds = <String>{};
    final bookIds = <String>[];
    final failures = <ImportFailureItem>[];

    for (final entry in nestedEntries) {
      final childName = importBaseName(entry.name);
      try {
        final childBytes = await ZipComicReader.extractEntry(
          outerSource,
          entry,
        );
        final sub = await importArchiveOrCollectionStream(
          db: db,
          storage: storage,
          coverEncoder: coverEncoder,
          openStream: () => Stream<Uint8List>.value(childBytes),
          displayFileName: childName,
          parentFolderName: collectionSeries,
          nextId: nextId,
          pdfBridge: pdfBridge,
          archiveBridge: archiveBridge,
          allowNestedUnpack: false,
        );
        seriesIds.addAll(sub.importedSeriesIds);
        bookIds.addAll(sub.importedBookIds);
        failures.addAll(sub.failures);
      } on ArchiveException catch (e) {
        failures.add(
          ImportFailureItem(
            fileName: childName,
            reason: mapArchiveImportFailure(e.kind),
          ),
        );
      } on FileSystemException {
        failures.add(
          ImportFailureItem(
            fileName: childName,
            reason: ImportFailureReason.ioError,
          ),
        );
      }
    }

    return LocalImportBatchResult(
      importedSeriesIds: seriesIds.toList(growable: false),
      importedBookIds: bookIds,
      failures: failures,
    );
  } finally {
    await outerSource.close();
  }
}

Future<Uint8List> _peekFileHead(File file, int maxBytes) async {
  final raf = await file.open();
  try {
    final len = await raf.length();
    final toRead = len < maxBytes ? len : maxBytes;
    if (toRead <= 0) return Uint8List(0);
    return await raf.read(toRead);
  } finally {
    await raf.close();
  }
}
