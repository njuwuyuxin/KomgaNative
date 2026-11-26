import 'dart:io';
import 'dart:typed_data';

import 'package:yomu/src/data/local/comic_file_picker.dart';
import 'package:yomu/src/data/local/cover_thumbnail_generator.dart';
import 'package:yomu/src/data/local/local_archive_import_stream.dart';
import 'package:yomu/src/data/local/local_comic_importer.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

const int _externalCopyChunkBytes = 256 * 1024;
const int _maxExternalSidecarBytes = 20 * 1024 * 1024;

/// 判断文件名是否属于受本地导入器支持的漫画归档/文档格式。
bool isSupportedLocalArchiveName(String name) {
  final lower = name.toLowerCase();
  return isNestedComicArchivePath(name) ||
      lower.endsWith('.pdf') ||
      lower.endsWith('.cbr') ||
      lower.endsWith('.rar') ||
      lower.endsWith('.cb7') ||
      lower.endsWith('.7z');
}

/// 扫描普通文件系统目录中的归档文件与同级侧车封面。
Future<({List<PickedComicFile> archives, File? sidecarCover})>
scanLocalDirectoryForArchivesAndCover(Directory sourceDir) async {
  final archives = <PickedComicFile>[];
  File? sidecarCover;
  int? sidecarPrio;
  await for (final entity in sourceDir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = importBaseName(entity.path);
    if (isSupportedLocalArchiveName(name)) {
      archives.add(PickedComicFile.fromFile(entity, name: name));
      continue;
    }
    final prio = sidecarCoverPriority(name);
    if (prio != null && (sidecarPrio == null || prio < sidecarPrio)) {
      sidecarCover = entity;
      sidecarPrio = prio;
    }
  }
  archives.sort((a, b) => naturalCompare(a.name, b.name));
  return (archives: archives, sidecarCover: sidecarCover);
}

/// 通过 Android SAF / iOS Security-Scoped Bookmark 导入外部文件夹到受管沙盒。
///
/// 与 [LocalComicImporter.importDirectory] 语义一致：
/// - 若目录内含漫画压缩包/PDF（含多卷与同级侧车封面），按归档流式入库并绑定封面；
/// - 否则按图片页文件夹保留子目录层级（支持子目录章节与 `ComicInfo.xml`）拷贝并索引入库；
/// - 全程流式分块拷贝，不依赖系统相册选择器，无数量上限也无需额外存储权限。
Future<LocalImportBatchResult> importExternalDirectoryToSandbox({
  required ProgressDatabase db,
  required LocalComicsStorage storage,
  required CoverThumbnailEncoder coverEncoder,
  required ExternalRootsBridge bridge,
  required MountedExternalRoot root,
  required LocalComicImporter importer,
  required String Function(String prefix) nextId,
  ImportProgressCallback? onProgress,
  ArchivePasswordPromptCallback? onPasswordPrompt,
}) async {
  final folderName = root.displayName.trim().isEmpty
      ? 'Imported Comic'
      : root.displayName.trim();

  final List<ExternalTreeEntry> entries;
  try {
    entries = await bridge.listTree(root);
  } on Object {
    return LocalImportBatchResult(
      failures: <ImportFailureItem>[
        ImportFailureItem(
          fileName: folderName,
          reason: ImportFailureReason.ioError,
        ),
      ],
    );
  }

  final archiveEntries = <ExternalTreeEntry>[];
  ExternalTreeEntry? sidecarCover;
  int? sidecarPrio;
  final imageEntries = <ExternalTreeEntry>[];
  ExternalTreeEntry? comicInfoEntry;

  for (final entry in entries) {
    if (entry.isDirectory || entry.isCloudPlaceholder) continue;
    final rel = _sanitizeRelativeEntryPath(entry.relativePath);
    if (rel.isEmpty) continue;
    final isTopLevel = !rel.contains('/');
    final lowerBase = entry.name.toLowerCase();

    if (isTopLevel && isSupportedLocalArchiveName(entry.name)) {
      archiveEntries.add(entry);
      continue;
    }
    if (isTopLevel) {
      final prio = sidecarCoverPriority(entry.name);
      if (prio != null && (sidecarPrio == null || prio < sidecarPrio)) {
        sidecarCover = entry;
        sidecarPrio = prio;
      }
    }
    if (lowerBase == 'comicinfo.xml' && comicInfoEntry == null) {
      comicInfoEntry = entry;
      continue;
    }
    if (isSupportedComicImagePath(rel)) {
      imageEntries.add(entry);
    }
  }

  if (archiveEntries.isNotEmpty) {
    archiveEntries.sort(
      (a, b) => naturalCompare(a.relativePath, b.relativePath),
    );
    final picked = <PickedComicFile>[
      for (final item in archiveEntries)
        PickedComicFile(
          name: item.name,
          sizeBytes: item.sizeBytes,
          openRead: () =>
              _openExternalFileStream(bridge: bridge, root: root, entry: item),
        ),
    ];
    final result = await importer.importArchiveFiles(
      picked,
      parentFolderName: folderName,
      onProgress: onProgress,
      onPasswordPrompt: onPasswordPrompt,
    );
    if (sidecarCover != null && result.importedSeriesIds.length == 1) {
      final coverBytes = await _readSmallExternalBytes(
        bridge: bridge,
        root: root,
        entry: sidecarCover,
      );
      if (coverBytes != null && coverBytes.isNotEmpty) {
        await importer.applySeriesCoverImage(
          coverBytes,
          seriesId: result.importedSeriesIds.single,
        );
      }
    }
    return result;
  }

  if (imageEntries.isEmpty) {
    return LocalImportBatchResult(
      failures: <ImportFailureItem>[
        ImportFailureItem(
          fileName: folderName,
          reason: ImportFailureReason.noImages,
        ),
      ],
    );
  }

  imageEntries.sort((a, b) => naturalCompare(a.relativePath, b.relativePath));

  final bookId = nextId('b');
  final safeFolder = bookId.replaceAll(':', '_');
  final folderRelPath = 'books/$safeFolder/pages';
  final destDir = await storage.resolveDirectory(folderRelPath);
  FolderComicReader? managedReader;

  try {
    await destDir.create(recursive: true);
    var totalBytes = 0;
    for (var i = 0; i < imageEntries.length; i++) {
      final item = imageEntries[i];
      onProgress?.call(i, imageEntries.length, item.name);
      final safeRel = _sanitizeRelativeEntryPath(item.relativePath);
      final outFile = File('${destDir.path}/$safeRel');
      await outFile.parent.create(recursive: true);
      await writeStreamToFile(
        _openExternalFileStream(bridge: bridge, root: root, entry: item),
        outFile,
      );
      totalBytes += await outFile.length();
    }

    if (comicInfoEntry != null) {
      final xmlBytes = await _readSmallExternalBytes(
        bridge: bridge,
        root: root,
        entry: comicInfoEntry,
      );
      if (xmlBytes != null && xmlBytes.isNotEmpty) {
        await File('${destDir.path}/ComicInfo.xml').writeAsBytes(xmlBytes);
      }
    }

    managedReader = await FolderComicReader.open(destDir);
    final imported = await commitComicReaderToDatabase(
      db: db,
      storage: storage,
      coverEncoder: coverEncoder,
      bookId: bookId,
      safeFolder: safeFolder,
      storageKind: 'folder',
      relativePath: folderRelPath,
      sizeBytes: totalBytes,
      displayName: folderName,
      parentFolderName: null,
      reader: managedReader,
      generateSeriesId: () => nextId('s'),
    );
    await managedReader.close();
    managedReader = null;
    onProgress?.call(imageEntries.length, imageEntries.length, '');
    return LocalImportBatchResult(
      importedSeriesIds: <String>[imported.seriesId],
      importedBookIds: <String>[imported.bookId],
    );
  } on ArchiveException catch (e) {
    await managedReader?.close();
    await tryDeleteImportDir(destDir.parent);
    return LocalImportBatchResult(
      failures: <ImportFailureItem>[
        ImportFailureItem(
          fileName: folderName,
          reason: mapArchiveImportFailure(e.kind),
        ),
      ],
    );
  } on FileSystemException {
    await managedReader?.close();
    await tryDeleteImportDir(destDir.parent);
    return LocalImportBatchResult(
      failures: <ImportFailureItem>[
        ImportFailureItem(
          fileName: folderName,
          reason: ImportFailureReason.ioError,
        ),
      ],
    );
  }
}

Stream<List<int>> _openExternalFileStream({
  required ExternalRootsBridge bridge,
  required MountedExternalRoot root,
  required ExternalTreeEntry entry,
}) async* {
  final knownLen = entry.sizeBytes > 0
      ? entry.sizeBytes
      : await bridge.fileLength(entry.uri, root: root);
  var offset = 0;
  while (true) {
    final remaining = knownLen != null
        ? knownLen - offset
        : _externalCopyChunkBytes;
    if (knownLen != null && remaining <= 0) break;
    final toRead = remaining < _externalCopyChunkBytes
        ? remaining
        : _externalCopyChunkBytes;
    final chunk = await bridge.readFileRange(
      entry.uri,
      offset,
      toRead,
      root: root,
    );
    if (chunk == null) {
      throw FileSystemException(
        'Failed to read external file range',
        entry.uri,
      );
    }
    if (chunk.isEmpty) break;
    yield chunk;
    offset += chunk.length;
    if (knownLen == null && chunk.length < toRead) break;
  }
}

Future<Uint8List?> _readSmallExternalBytes({
  required ExternalRootsBridge bridge,
  required MountedExternalRoot root,
  required ExternalTreeEntry entry,
}) async {
  try {
    final len = entry.sizeBytes > 0
        ? entry.sizeBytes
        : await bridge.fileLength(entry.uri, root: root);
    if (len == null || len <= 0 || len > _maxExternalSidecarBytes) {
      return null;
    }
    return await bridge.readFileRange(entry.uri, 0, len, root: root);
  } on Object {
    return null;
  }
}

String _sanitizeRelativeEntryPath(String raw) {
  final norm = raw.replaceAll(r'\', '/');
  final parts = <String>[];
  for (final seg in norm.split('/')) {
    final trimmed = seg.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') continue;
    if (trimmed == '__MACOSX' || trimmed.startsWith('.')) return '';
    parts.add(trimmed);
  }
  return parts.join('/');
}
