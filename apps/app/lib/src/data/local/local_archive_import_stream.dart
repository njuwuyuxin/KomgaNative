import 'dart:io';
import 'dart:typed_data';

import 'package:yomu/src/data/local/archive_password_store.dart';
import 'package:yomu/src/data/local/comic_reader_factory.dart';
import 'package:yomu/src/data/local/cover_thumbnail_generator.dart';
import 'package:yomu/src/data/local/local_comic_importer_models.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_import_cleanup.dart';
import 'package:yomu/src/data/local/native_archive_reader.dart';
import 'package:yomu/src/data/local/native_pdf_reader.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// 加密归档/PDF 导入时的交互式密码输入回调（LMB-13）。
typedef ArchivePasswordPromptCallback =
    Future<({String password, bool saveToDictionary})?> Function(
      String fileName, {
      bool wrongAttempt,
    });

/// 导入单个归档文件流；支持：
/// - 嵌套合集包自动拆包（LMB-06）；
/// - 原生 PDF（LMB-11）与 CBR/CB7（LMB-12）；
/// - 加密包自动尝试常用密码词典 + 交互弹窗 + 钥匙串按 `bookId` 记忆（LMB-13）。
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
  ArchivePasswordStore? passwordStore,
  ArchivePasswordPromptCallback? onPasswordPrompt,
  String? password,
  bool allowNestedUnpack = true,
  ImportCancellationToken? cancelToken,
}) async {
  cancelToken?.throwIfCancelled();
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

  ComicArchiveReader? reader;
  String? committedBookId;
  try {
    await destFile.parent.create(recursive: true);
    await writeStreamToFile(openStream(), destFile, cancelToken: cancelToken);
    cancelToken?.throwIfCancelled();
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

    Future<ComicArchiveReader> openWithPassword(String? pwd) async {
      if (isPdf) {
        return NativePdfComicReader.open(
          pdfBridge ?? ChannelNativePdfBridge(),
          destFile.path,
          password: pwd,
        );
      }
      if (isNativeArchive) {
        return NativeArchiveComicReader.open(
          archiveBridge ?? ChannelNativeArchiveBridge(),
          destFile.path,
          password: pwd,
        );
      }
      final source = await FileByteSource.open(destFile);
      return openComicArchive(source, password: pwd);
    }

    String? unlockedPassword = password;
    try {
      reader = await openWithPassword(password);
    } on ArchiveException catch (e) {
      if (e.kind == ArchiveErrorKind.encryptedArchive &&
          (password == null || password.isEmpty)) {
        final resolved = await _unlockEncryptedArchive(
          fileName: displayFileName,
          openWithPassword: openWithPassword,
          passwordStore: passwordStore,
          onPasswordPrompt: onPasswordPrompt,
        );
        reader = resolved.reader;
        unlockedPassword = resolved.password;
      } else if (allowNestedUnpack &&
          !isPdf &&
          !isNativeArchive &&
          e.kind == ArchiveErrorKind.noImages) {
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
          passwordStore: passwordStore,
          onPasswordPrompt: onPasswordPrompt,
          cancelToken: cancelToken,
        );
        if (unpacked != null) {
          // destFile 只是本次流式拷入沙盒的临时外层合集副本（用户原始源文件从未改动）；
          // 无论子书部分成功、全部失败还是取消，都必须清理临时副本，绝不在 books/ 下遗留无数据库索引的孤儿文件（N5）。
          await tryDeleteImportDir(destFile.parent);
          return unpacked;
        }
        rethrow;
      } else {
        rethrow;
      }
    }

    final storageKind = LocalStorageKind.forManagedReader(reader).wireValue;
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
    committedBookId = result.bookId;
    if (unlockedPassword != null && unlockedPassword.isNotEmpty) {
      await passwordStore?.saveBookPassword(bookId, unlockedPassword);
    }
    final closing = reader;
    reader = null;
    await closing.close();
    return LocalImportBatchResult(
      importedSeriesIds: <String>[result.seriesId],
      importedBookIds: <String>[result.bookId],
    );
  } on Object {
    await tryCloseArchiveReader(reader);
    if (committedBookId != null) {
      await rollbackCommittedLocalBook(
        db: db,
        storage: storage,
        bookId: committedBookId,
        passwordStore: passwordStore,
      );
    }
    await tryDeleteImportDir(destFile.parent);
    rethrow;
  }
}

Future<({ComicArchiveReader reader, String password})> _unlockEncryptedArchive({
  required String fileName,
  required Future<ComicArchiveReader> Function(String? pwd) openWithPassword,
  required ArchivePasswordStore? passwordStore,
  required ArchivePasswordPromptCallback? onPasswordPrompt,
}) async {
  // 1) 优先静音尝试常用解压密码词典
  final dict = await passwordStore?.loadCommonPasswords() ?? const <String>[];
  for (final candidate in dict) {
    try {
      final reader = await openWithPassword(candidate);
      return (reader: reader, password: candidate);
    } on ArchiveException catch (e) {
      if (e.kind != ArchiveErrorKind.encryptedArchive) rethrow;
    }
  }

  // 2) 词典未命中时弹出交互式密码输入框（最多重试 3 次）
  if (onPasswordPrompt != null) {
    for (var attempt = 0; attempt < 3; attempt++) {
      final submission = await onPasswordPrompt(
        fileName,
        wrongAttempt: attempt > 0,
      );
      if (submission == null || submission.password.isEmpty) {
        break;
      }
      try {
        final reader = await openWithPassword(submission.password);
        if (submission.saveToDictionary) {
          await passwordStore?.addCommonPassword(submission.password);
        }
        return (reader: reader, password: submission.password);
      } on ArchiveException catch (e) {
        if (e.kind != ArchiveErrorKind.encryptedArchive) rethrow;
      }
    }
  }

  throw ArchiveException(ArchiveErrorKind.encryptedArchive, fileName);
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
  ArchivePasswordStore? passwordStore,
  ArchivePasswordPromptCallback? onPasswordPrompt,
  ImportCancellationToken? cancelToken,
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
    var cancelled = false;

    for (final entry in nestedEntries) {
      if (cancelToken?.isCancelled ?? false) {
        cancelled = true;
        break;
      }
      final childName = importBaseName(entry.name);
      try {
        final childBytes = await ZipComicReader.extractEntry(
          outerSource,
          entry,
          maxUncompressedBytes: kMaxNestedZipEntryBytes,
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
          passwordStore: passwordStore,
          onPasswordPrompt: onPasswordPrompt,
          allowNestedUnpack: false,
          cancelToken: cancelToken,
        );
        seriesIds.addAll(sub.importedSeriesIds);
        bookIds.addAll(sub.importedBookIds);
        failures.addAll(sub.failures);
      } on ImportCancelledException {
        cancelled = true;
        break;
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
      cancelled: cancelled,
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
