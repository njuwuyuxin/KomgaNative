import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yomu/src/providers/local_import_provider.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// 外部系统打开文件通道 Provider（单测可注入假实现）。
final Provider<IncomingFiles> incomingFilesProvider = Provider<IncomingFiles>((
  Ref ref,
) {
  final incoming = ChannelIncomingFiles();
  ref.onDispose(incoming.dispose);
  return incoming;
});

/// 外部传入漫画文件的入库处理器（包含 Android Intent 暂存清理与 iOS `Documents/Inbox` 回收）。
final Provider<IncomingComicCoordinator> incomingComicCoordinatorProvider =
    Provider<IncomingComicCoordinator>(IncomingComicCoordinator.new);

class IncomingComicCoordinator {
  IncomingComicCoordinator(this._ref);

  final Ref _ref;
  bool _processing = false;

  /// 导入单个外部传入的漫画文件并清理临时副本，成功时返回新入库的 `bookId`。
  Future<String?> handleIncomingFile(IncomingComicFile incoming) async {
    if (_processing) return null;
    _processing = true;
    try {
      final result = await _ref
          .read(localImportProvider.notifier)
          .importExternalFile(incoming.path, fileName: incoming.name);
      await _tryDeleteTempCopy(incoming.path);
      if (result != null && result.importedBookIds.isNotEmpty) {
        return result.importedBookIds.first;
      }
      return null;
    } on Object {
      await _tryDeleteTempCopy(incoming.path);
      return null;
    } finally {
      _processing = false;
    }
  }

  /// 扫描 iOS 系统「用其他应用打开」自动投递的 `Documents/Inbox/` 目录并入库清理。
  Future<String?> sweepIosInboxIfPresent() async {
    if (!Platform.isIOS) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final inbox = Directory('${docs.path}/Inbox');
      if (!await inbox.exists()) return null;
      String? lastOpenedBookId;
      await for (final entity in inbox.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.path.replaceAll(r'\', '/').split('/').last;
        final lower = name.toLowerCase();
        if (!lower.endsWith('.cbz') && !lower.endsWith('.zip')) continue;
        final bookId = await handleIncomingFile(
          IncomingComicFile(path: entity.path, name: name),
        );
        if (bookId != null) lastOpenedBookId = bookId;
      }
      return lastOpenedBookId;
    } on MissingPluginException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static Future<void> _tryDeleteTempCopy(String path) async {
    final norm = path.replaceAll(r'\', '/');
    if (!norm.contains('/incoming/') && !norm.contains('/Inbox/')) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 忽略临时文件删除异常。
    }
  }
}
