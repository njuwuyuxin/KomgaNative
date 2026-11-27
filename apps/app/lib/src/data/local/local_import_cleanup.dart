import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yomu/src/data/local/archive_password_store.dart';
import 'package:yomu/src/data/local/local_catalog_delete_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

Future<void> tryDeleteImportDir(Directory dir) async {
  try {
    if (await dir.exists()) await dir.delete(recursive: true);
  } on FileSystemException {
    // 清理失败不覆盖主异常。
  }
}

/// 安全关闭归档读取器：避免回滚路径里重复 `close()` 抛错吞掉主异常或阻断清理。
Future<void> tryCloseArchiveReader(ComicArchiveReader? reader) async {
  if (reader == null) return;
  try {
    await reader.close();
  } on Exception catch (error) {
    debugPrint('localImport: reader.close failed during cleanup: $error');
  }
}

/// 导入写库后若后续步骤（保存密码 / 关闭句柄等）抛错，事务性回滚数据库记录、封面缩略图与钥匙串密码，
/// 彻底避免书架留下指向已删除目录的"幽灵书"。
Future<void> rollbackCommittedLocalBook({
  required ProgressDatabase db,
  required LocalComicsStorage storage,
  required String bookId,
  ArchivePasswordStore? passwordStore,
}) async {
  try {
    final deleted = await db.deleteLocalBookFromDb(bookId);
    if (deleted != null) {
      for (final rel in deleted.coverRelativePaths) {
        final file = await storage.resolveFile(rel);
        if (await file.exists()) await file.delete();
      }
    }
  } on Exception catch (error) {
    debugPrint('localImport: DB rollback failed for $bookId: $error');
  }
  if (passwordStore != null) {
    try {
      await passwordStore.deleteBookPassword(bookId);
    } on Exception catch (error) {
      debugPrint('localImport: password rollback failed for $bookId: $error');
    }
  }
}
