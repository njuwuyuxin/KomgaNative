import 'dart:io';

import 'package:yomu/src/data/local/cover_thumbnail_generator.dart';
import 'package:yomu/src/data/local/external_byte_source.dart';
import 'package:yomu/src/data/local/external_roots_dao.dart';
import 'package:yomu/src/data/local/local_catalog_delete_dao.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_comic_importer_models.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// iOS `Files.app`（App Documents 目录）自发现挂载根的固定 ID（LMB-09）。
const String kIosFilesRootId = 'root_ios_files_documents';

/// 单次增量扫描进度快照。
final class ExternalScanProgress {
  const ExternalScanProgress({
    required this.rootId,
    required this.scanned,
    required this.total,
    required this.currentName,
  });

  final String rootId;
  final int scanned;
  final int total;
  final String currentName;
}

/// 单次增量扫描统计结果。
final class ExternalScanSummary {
  const ExternalScanSummary({
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.removed = 0,
    this.failed = 0,
    this.cloudPlaceholders = 0,
  });

  final int added;
  final int updated;
  final int skipped;
  final int removed;
  final int failed;
  final int cloudPlaceholders;

  ExternalScanSummary operator +(ExternalScanSummary other) =>
      ExternalScanSummary(
        added: added + other.added,
        updated: updated + other.updated,
        skipped: skipped + other.skipped,
        removed: removed + other.removed,
        failed: failed + other.failed,
        cloudPlaceholders: cloudPlaceholders + other.cloudPlaceholders,
      );
}

/// 外部挂载目录增量扫描器（LMB-09）。
///
/// 按 `(mountRootId, sourceRelativePath, sizeBytes, sourceModifiedMs)` 做差量比对：
/// - 未变更文件直接跳过（零解包、零磁盘 I/O）；
/// - 新增/修改文件原位索引（保留已有 `bookId` 不丢阅读进度与书签）；
/// - 外部已删除文件仅清理数据库索引与缩略图缓存；
/// - iCloud 未下载占位文件记录为 `isCloudPlaceholder = true`，绝不强制全量拉取流量。
final class ExternalDirectoryScanner {
  ExternalDirectoryScanner({
    required ProgressDatabase db,
    required LocalComicsStorage storage,
    required ExternalRootsBridge bridge,
    CoverThumbnailEncoder coverEncoder = encodeDefaultCoverThumbnail,
  }) : _db = db,
       _storage = storage,
       _bridge = bridge,
       _coverEncoder = coverEncoder;

  final ProgressDatabase _db;
  final LocalComicsStorage _storage;
  final ExternalRootsBridge _bridge;
  final CoverThumbnailEncoder _coverEncoder;
  int _idSeq = 0;

  String _nextId(String prefix) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    _idSeq = (_idSeq + 1) & 0xFFFF;
    return 'local:${prefix}_${micros}_$_idSeq';
  }

  /// 对单个已挂载外部目录执行增量扫描。
  Future<ExternalScanSummary> scanRoot(
    MountedExternalRoot root, {
    void Function(ExternalScanProgress progress)? onProgress,
    DateTime? nowOverride,
  }) async {
    final entries = await _bridge.listTree(root);
    final archiveCandidates = <ExternalTreeEntry>[
      for (final e in entries)
        if (!e.isDirectory && isNestedComicArchivePath(e.name)) e,
    ];
    archiveCandidates.sort(
      (a, b) => naturalCompare(a.relativePath, b.relativePath),
    );

    final existingRows = await _db.booksForMountedRoot(root.id);
    final existingByRel = <String, LocalBooksRow>{
      for (final row in existingRows)
        if (row.sourceRelativePath != null) row.sourceRelativePath!: row,
    };

    final seenRelPaths = <String>{};
    final dirToSeriesIds = <String, Set<String>>{};
    var added = 0;
    var updated = 0;
    var skipped = 0;
    var removed = 0;
    var failed = 0;
    var cloudPlaceholders = 0;

    for (var i = 0; i < archiveCandidates.length; i++) {
      final entry = archiveCandidates[i];
      seenRelPaths.add(entry.relativePath);
      final dirKey = externalParentDirKey(entry.relativePath);
      onProgress?.call(
        ExternalScanProgress(
          rootId: root.id,
          scanned: i,
          total: archiveCandidates.length,
          currentName: entry.name,
        ),
      );

      final existing = existingByRel[entry.relativePath];
      final unchanged =
          existing != null &&
          existing.sizeBytes == entry.sizeBytes &&
          existing.sourceModifiedMs == entry.lastModifiedMs &&
          existing.isCloudPlaceholder == entry.isCloudPlaceholder &&
          existing.relativePath == entry.uri;

      if (unchanged) {
        skipped++;
        if (entry.isCloudPlaceholder) cloudPlaceholders++;
        dirToSeriesIds
            .putIfAbsent(dirKey, () => <String>{})
            .add(existing.seriesId);
        continue;
      }

      try {
        final seriesId = await _indexArchiveEntry(
          root: root,
          entry: entry,
          existing: existing,
          nowOverride: nowOverride,
        );
        dirToSeriesIds.putIfAbsent(dirKey, () => <String>{}).add(seriesId);
        if (entry.isCloudPlaceholder) cloudPlaceholders++;
        if (existing == null) {
          added++;
        } else {
          updated++;
        }
      } on ArchiveException {
        failed++;
      } on FileSystemException {
        failed++;
      }
    }

    await applyExternalSidecarCovers(
      db: _db,
      storage: _storage,
      bridge: _bridge,
      coverEncoder: _coverEncoder,
      root: root,
      allEntries: entries,
      dirToSeriesIds: dirToSeriesIds,
    );

    // 清理外部已删除文件的索引行与缩略图缓存（绝不删外部源文件）。
    for (final row in existingRows) {
      final rel = row.sourceRelativePath;
      if (rel != null && !seenRelPaths.contains(rel)) {
        final deleted = await _db.deleteLocalBookFromDb(row.id);
        if (deleted != null) {
          for (final cover in deleted.coverRelativePaths) {
            await _tryDeleteCover(cover);
          }
        }
        removed++;
      }
    }

    final activeBooks = (await _db.booksForMountedRoot(root.id)).length;
    await _db.updateMountedRootScanStats(
      rootId: root.id,
      booksCount: activeBooks,
      scannedAt: nowOverride ?? DateTime.now(),
    );

    onProgress?.call(
      ExternalScanProgress(
        rootId: root.id,
        scanned: archiveCandidates.length,
        total: archiveCandidates.length,
        currentName: '',
      ),
    );

    return ExternalScanSummary(
      added: added,
      updated: updated,
      skipped: skipped,
      removed: removed,
      failed: failed,
      cloudPlaceholders: cloudPlaceholders,
    );
  }

  /// iOS `Files.app` 目录自发现：确保应用 `Documents` 目录存在挂载根并增量扫描。
  Future<ExternalScanSummary> discoverAndScanDocumentsDirectory(
    Directory documentsDir, {
    String displayName = 'Files · Yomu',
    DateTime? nowOverride,
  }) async {
    if (!await documentsDir.exists()) {
      return const ExternalScanSummary();
    }
    final root = MountedExternalRoot(
      id: kIosFilesRootId,
      displayName: displayName,
      uriOrBookmark: documentsDir.path,
      kind: ExternalRootKind.localDirectory,
      hasNomedia: true,
    );
    await _db.upsertMountedRoot(root, nowOverride: nowOverride);
    return scanRoot(root, nowOverride: nowOverride);
  }

  Future<String> _indexArchiveEntry({
    required MountedExternalRoot root,
    required ExternalTreeEntry entry,
    required LocalBooksRow? existing,
    required DateTime? nowOverride,
  }) async {
    final bookId = existing?.id ?? _nextId('b');
    final safeFolder = bookId.replaceAll(':', '_');
    final parentFolder = _parentFolderFromRelPath(entry.relativePath);
    final inferred = inferTitlesFromFileName(
      entry.name,
      parentFolderName: parentFolder,
    );

    if (entry.isCloudPlaceholder) {
      final inserted = await _db.insertImportedLocalBook(
        LocalBookImportDraft(
          bookId: bookId,
          seriesIdOverride: existing?.seriesId,
          seriesTitle: inferred.seriesTitle,
          bookName: inferred.bookTitle,
          number: inferred.number,
          numberSort: inferred.numberSort,
          storageKind: root.kind == ExternalRootKind.localDirectory
              ? 'ext_zip'
              : 'saf_zip',
          relativePath: entry.uri,
          sizeBytes: entry.sizeBytes,
          pages: const <ArchivePageEntry>[],
          mountRootId: root.id,
          sourceRelativePath: entry.relativePath,
          sourceModifiedMs: entry.lastModifiedMs,
          isCloudPlaceholder: true,
        ),
        generateSeriesId: () => _nextId('s'),
        nowOverride: nowOverride,
      );
      return inserted.seriesId;
    }

    final useBridge = root.kind != ExternalRootKind.localDirectory;
    final RandomAccessByteSource source = useBridge
        ? ExternalRangeByteSource(
            bridge: _bridge,
            uri: entry.uri,
            root: root,
            knownLength: entry.sizeBytes > 0 ? entry.sizeBytes : null,
          )
        : await FileByteSource.open(File(entry.uri));

    final reader = await openComicArchive(source);
    try {
      final prefix = useBridge ? 'saf' : 'ext';
      final kindSuffix = switch (reader) {
        EpubComicReader() => 'epub',
        TarComicReader() => 'tar',
        _ => 'zip',
      };
      final committed = await commitComicReaderToDatabase(
        db: _db,
        storage: _storage,
        coverEncoder: _coverEncoder,
        bookId: bookId,
        safeFolder: safeFolder,
        storageKind: '${prefix}_$kindSuffix',
        relativePath: entry.uri,
        sizeBytes: entry.sizeBytes,
        displayName: entry.name,
        parentFolderName: parentFolder,
        reader: reader,
        generateSeriesId: () => _nextId('s'),
        seriesIdOverride: existing?.seriesId,
        mountRootId: root.id,
        sourceRelativePath: entry.relativePath,
        sourceModifiedMs: entry.lastModifiedMs,
        nowOverride: nowOverride,
      );
      return committed.seriesId;
    } finally {
      await reader.close();
    }
  }

  Future<void> _tryDeleteCover(String relPath) async {
    try {
      final f = await _storage.resolveFile(relPath);
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // 忽略缩略图清理失败。
    }
  }
}

String? _parentFolderFromRelPath(String relPath) {
  final norm = relPath.replaceAll(r'\', '/');
  final parts = norm.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.length < 2) return null;
  return parts[parts.length - 2];
}
