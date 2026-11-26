import 'package:drift/drift.dart';
import 'package:yomu/src/data/local/local_catalog_delete_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// 外部挂载目录数据访问与安全卸载扩展（LMB-08）。
extension ExternalRootsDao on ProgressDatabase {
  Future<List<LocalMountedRootsRow>> allMountedRoots() =>
      (select(localMountedRootsRows)
            ..orderBy(<OrderClauseGenerator<LocalMountedRootsRows>>[
              (t) => OrderingTerm(expression: t.createdAt),
            ]))
          .get();

  Future<LocalMountedRootsRow?> mountedRootById(String rootId) => (select(
    localMountedRootsRows,
  )..where((t) => t.id.equals(rootId))).getSingleOrNull();

  Stream<Set<TableUpdate>> mountedRootsUpdates() =>
      tableUpdates(TableUpdateQuery.onTable(localMountedRootsRows));

  Future<void> upsertMountedRoot(
    MountedExternalRoot root, {
    DateTime? nowOverride,
  }) async {
    final now = (nowOverride ?? DateTime.now()).toUtc();
    await into(localMountedRootsRows).insertOnConflictUpdate(
      LocalMountedRootsRowsCompanion.insert(
        id: root.id,
        displayName: root.displayName,
        uriOrBookmark: root.uriOrBookmark,
        kind: root.kind.name,
        hasNomedia: Value<bool>(root.hasNomedia),
        createdAt: now,
      ),
    );
  }

  Future<void> updateMountedRootScanStats({
    required String rootId,
    required int booksCount,
    bool? hasNomedia,
    DateTime? scannedAt,
  }) {
    return (update(
      localMountedRootsRows,
    )..where((t) => t.id.equals(rootId))).write(
      LocalMountedRootsRowsCompanion(
        booksCount: Value<int>(booksCount),
        lastScannedAt: Value<DateTime?>((scannedAt ?? DateTime.now()).toUtc()),
        hasNomedia: hasNomedia != null
            ? Value<bool>(hasNomedia)
            : const Value.absent(),
      ),
    );
  }

  Future<List<LocalBooksRow>> booksForMountedRoot(String rootId) => (select(
    localBooksRows,
  )..where((t) => t.mountRootId.equals(rootId))).get();

  /// 安全卸载外部挂载目录：仅删除本库索引行与缩略图缓存路径，**绝不删除用户的外部源文件**。
  Future<List<String>> unmountExternalRootFromDb(String rootId) {
    return transaction(() async {
      final books = await booksForMountedRoot(rootId);
      final coverPathsToClean = <String>[];
      for (final book in books) {
        final deleted = await deleteLocalBookFromDb(book.id);
        if (deleted != null) {
          coverPathsToClean.addAll(deleted.coverRelativePaths);
        }
      }
      await (delete(
        localMountedRootsRows,
      )..where((t) => t.id.equals(rootId))).go();
      return coverPathsToClean;
    });
  }
}

MountedExternalRoot mountedRootFromRow(LocalMountedRootsRow row) {
  final kind = switch (row.kind) {
    'androidSaf' => ExternalRootKind.androidSaf,
    'iosBookmark' => ExternalRootKind.iosBookmark,
    _ => ExternalRootKind.localDirectory,
  };
  return MountedExternalRoot(
    id: row.id,
    displayName: row.displayName,
    uriOrBookmark: row.uriOrBookmark,
    kind: kind,
    hasNomedia: row.hasNomedia,
  );
}
