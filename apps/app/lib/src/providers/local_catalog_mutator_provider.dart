import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/local/local_catalog_delete_dao.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/providers/cross_source_reading_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';

/// 本地书库删除与变更控制器（协调句柄释放、SQLite 事务、沙盒物理文件清理与 UI 刷新）。
final Provider<LocalCatalogMutator> localCatalogMutatorProvider =
    Provider<LocalCatalogMutator>(LocalCatalogMutator.new);

class LocalCatalogMutator {
  LocalCatalogMutator(this._ref);

  final Ref _ref;

  /// 删除单本本地书籍并回收其沙盒存储空间。返回所属系列是否已变空被一并移除。
  Future<bool> deleteBook(String bookId, {String? seriesId}) async {
    await _ref.read(localReaderRepositoryProvider).closeBookHandle(bookId);
    final db = _ref.read(progressDatabaseProvider);
    final deleted = await db.deleteLocalBookFromDb(bookId);
    if (deleted == null) return false;
    await _purgePhysicalFiles(deleted);
    _invalidateAfterMutation(seriesId: seriesId);
    return deleted.seriesDeleted;
  }

  /// 批量删除一个或多个本地系列及其全部沙盒文件。
  Future<int> deleteSeries(Iterable<String> seriesIds) async {
    final db = _ref.read(progressDatabaseProvider);
    final readerRepo = _ref.read(localReaderRepositoryProvider);
    var removedCount = 0;

    for (final sid in seriesIds) {
      if (!sid.startsWith('local:')) continue;
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
      } on Object {
        // 磁盘文件已不存在时忽略。
      }
    }
    for (final coverRel in paths.coverRelativePaths) {
      try {
        final coverFile = await storage.resolveFile(coverRel);
        if (await coverFile.exists()) {
          await coverFile.delete();
        }
      } on Object {
        // 缩略图不存在时忽略。
      }
    }
  }

  void _invalidateAfterMutation({String? seriesId}) {
    _ref.read(localLibraryRepositoryProvider).evictCoverCache();
    _ref.invalidate(crossSourceOndeckProvider);
    _ref.invalidate(recentSeriesProvider);
    _ref.invalidate(collectionsProvider);
    _ref.invalidate(readListsProvider);
    _ref.invalidate(seriesBooksProvider);
    if (seriesId != null) {
      _ref.invalidate(seriesDetailProvider(seriesId));
    }
    unawaited(_ref.read(shelfProvider.notifier).refreshInPlace());
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
