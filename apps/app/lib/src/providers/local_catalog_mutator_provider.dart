import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/local/cover_thumbnail_generator.dart';
import 'package:yomu/src/data/local/local_catalog_delete_dao.dart';
import 'package:yomu/src/data/local/local_catalog_edit_dao.dart';
import 'package:yomu/src/data/local/local_catalog_ids.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 本地书库删除与变更控制器（协调句柄释放、SQLite 事务、沙盒物理文件清理与 UI 刷新）。
final Provider<LocalCatalogMutator> localCatalogMutatorProvider =
    Provider<LocalCatalogMutator>(LocalCatalogMutator.new);

class LocalCatalogMutator {
  LocalCatalogMutator(this._ref);

  final Ref _ref;

  String _nextSeriesId() => generateLocalEntityId('s');

  /// 修改本地系列元数据并立即刷新详情与书架。
  Future<void> editSeries(
    String seriesId, {
    required String title,
    String? summary,
    List<String>? authors,
    List<String>? tags,
    ReadingDirection? readingDirection,
  }) async {
    await _ref
        .read(progressDatabaseProvider)
        .updateLocalSeriesMetadata(
          seriesId,
          title: title,
          summary: summary,
          authors: authors,
          tags: tags,
          readingDirection: readingDirection,
        );
    _invalidateAfterMutation();
  }

  /// 修改本地单本书籍标题与卷号。
  Future<void> editBook(
    String bookId, {
    required String seriesId,
    required String name,
    required String number,
  }) async {
    await _ref
        .read(progressDatabaseProvider)
        .updateLocalBookMetadata(bookId, name: name, number: number);
    _invalidateAfterMutation();
  }

  /// 将多个本地散装单卷系列合并为一个系列。
  Future<void> mergeSeries({
    required List<String> sourceSeriesIds,
    required String targetSeriesId,
    String? mergedTitle,
  }) async {
    await _ref
        .read(progressDatabaseProvider)
        .mergeLocalSeriesInto(
          sourceSeriesIds: sourceSeriesIds,
          targetSeriesId: targetSeriesId,
          mergedTitle: mergedTitle,
        );
    _invalidateAfterMutation();
  }

  /// 将多卷系列中的单册拆分为独立系列。
  Future<String?> splitBookToOwnSeries(
    String bookId, {
    required String currentSeriesId,
  }) async {
    final newSeriesId = await _ref
        .read(progressDatabaseProvider)
        .splitLocalBookToStandaloneSeries(
          bookId,
          generateSeriesId: _nextSeriesId,
        );
    if (newSeriesId != null && newSeriesId != currentSeriesId) {
      _invalidateAfterMutation();
    }
    return newSeriesId;
  }

  /// 将阅读器当前页图像字节设为本地书籍及所属系列的封面（LMA-11）。
  Future<bool> setCustomCoverFromPageBytes({
    required String bookId,
    required String seriesId,
    required int pageNumber,
  }) async {
    final db = _ref.read(progressDatabaseProvider);
    if (await db.localBookRowById(bookId) == null) return false;
    final readerRepo = _ref.read(localReaderRepositoryProvider);
    final storage = _ref.read(localComicsStorageProvider);

    final rawBytes = await readerRepo.pageImage(bookId, pageNumber);
    final encoded = await encodeDefaultCoverThumbnail(
      rawBytes,
      direction: ReadingDirection.unknown,
    );
    final payload = (encoded != null && encoded.isNotEmpty)
        ? encoded
        : rawBytes;

    final safeBook = bookId.replaceAll(':', '_');
    final relPath =
        'covers/custom_${safeBook}_${DateTime.now().microsecondsSinceEpoch}.png';
    final file = await storage.resolveFile(relPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(payload, flush: true);

    await db.setLocalCoverPaths(
      bookId: bookId,
      seriesId: seriesId,
      coverRelativePath: relPath,
    );
    _ref.invalidate(
      bookCoverProvider((sourceKey: kLocalSourceKey, id: bookId)),
    );
    _ref.invalidate(
      seriesCoverProvider((sourceKey: kLocalSourceKey, id: seriesId)),
    );
    _invalidateAfterMutation();
    return true;
  }

  /// 删除单本本地书籍并回收其沙盒存储空间。返回所属系列是否已变空被一并移除。
  Future<bool> deleteBook(String bookId, {String? seriesId}) async {
    await _ref.read(localReaderRepositoryProvider).closeBookHandle(bookId);
    final db = _ref.read(progressDatabaseProvider);
    final deleted = await db.deleteLocalBookFromDb(bookId);
    if (deleted == null) return false;
    await _purgePhysicalFiles(deleted);
    _invalidateAfterMutation();
    return deleted.seriesDeleted;
  }

  /// 批量删除一个或多个本地系列及其全部沙盒文件。
  Future<int> deleteSeries(Iterable<String> seriesIds) async {
    final db = _ref.read(progressDatabaseProvider);
    final readerRepo = _ref.read(localReaderRepositoryProvider);
    var removedCount = 0;

    for (final sid in seriesIds) {
      final books = await db.queryLocalSeriesBooks(sid, size: 10000);
      for (final b in books.items) {
        await readerRepo.closeBookHandle(b.id);
      }
      final deleted = await db.deleteLocalSeriesFromDb(sid);
      if (deleted != null) {
        removedCount++;
        await _purgePhysicalFiles(deleted);
      }
    }

    if (removedCount > 0) {
      _invalidateAfterMutation();
    }
    return removedCount;
  }

  Future<void> _purgePhysicalFiles(DeletedLocalPaths paths) async {
    final storage = _ref.read(localComicsStorageProvider);
    for (final rel in paths.bookRelativePaths) {
      try {
        final targetFile = await storage.resolveFile(rel);
        // 统一清理 `books/<safeBookFolder>` 整棵子目录，避免空目录残留。
        final bookContainerDir = targetFile.parent;
        if (await bookContainerDir.exists() &&
            bookContainerDir.path.replaceAll(r'\', '/').contains('/books/')) {
          await bookContainerDir.delete(recursive: true);
        } else if (await targetFile.exists()) {
          await targetFile.delete(recursive: true);
        } else {
          final targetDir = await storage.resolveDirectory(rel);
          if (await targetDir.exists()) {
            await targetDir.parent.delete(recursive: true);
          }
        }
      } on FileSystemException catch (error) {
        // 磁盘文件已不存在时忽略。
        debugPrint('LocalCatalogMutator: delete book file skipped: $error');
      }
    }
    for (final coverRel in paths.coverRelativePaths) {
      try {
        final coverFile = await storage.resolveFile(coverRel);
        if (await coverFile.exists()) {
          await coverFile.delete();
        }
      } on FileSystemException catch (error) {
        // 缩略图不存在时忽略。
        debugPrint('LocalCatalogMutator: delete cover file skipped: $error');
      }
    }
  }

  void _invalidateAfterMutation() {
    invalidateLocalCatalogProviders(_ref, includeCuration: true);
  }
}

/// 弹出「从本机删除？」二次确认对话框。
Future<bool> confirmDeleteLocalItems(
  BuildContext context, {
  required int count,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      key: const Key('confirm-delete-local-dialog'),
      title: Text(l10n.deleteLocalSeriesTitle),
      content: Text(l10n.deleteLocalSeriesBody(count)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('confirm-delete-local-ok'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
