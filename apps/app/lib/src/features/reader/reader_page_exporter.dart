import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/page_save.dart';
import 'package:yomu/src/data/page_share.dart';
import 'package:yomu/src/data/reader_repository.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/features/reader/reader_layout.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_platform/yomu_platform.dart';
import 'package:yomu_reader/yomu_reader.dart';

/// 阅读器纯业务导出与分组执行器：画面保存至相册、系统分享与双页分组切换（无 UI / 路由依赖，P1-5）。
class ReaderPageExporter {
  bool _savingImage = false;

  /// 保存当前单页或双页合图至系统相册；返回应提示给用户的文案（被重入跳过时返回 null）。
  Future<String?> saveScreenImage({
    required String bookId,
    required ReaderLayout layout,
    required bool rightToLeft,
    required ReaderRepository repository,
    required ImageSaver imageSaver,
    required AppLocalizations Function() l10n,
  }) async {
    if (_savingImage || layout.total <= 0) return null;
    _savingImage = true;
    try {
      final orderedPages = resolveSavePages(
        mode: layout.mode,
        currentPage: layout.page,
        spread: layout.spread,
        rightToLeft: rightToLeft,
      );
      final prepared = await prepareScreenImageForSave(
        bookId: bookId,
        orderedPages: orderedPages,
        loadPage: (int p) => repository.pageImage(bookId, p),
      );
      final result = await imageSaver.saveImage(
        prepared.bytes,
        fileName: prepared.fileName,
        mimeType: prepared.mimeType,
      );
      final strings = l10n();
      return switch (result) {
        ImageSaveSuccess() => _onSaveSuccess(strings),
        ImageSaveFailure(kind: ImageSaveFailureKind.permissionDenied) =>
          strings.savePageImagePermissionDenied,
        ImageSaveFailure(
          kind: ImageSaveFailureKind.unsupported ||
              ImageSaveFailureKind.ioError,
        ) =>
          strings.savePageImageFailed,
      };
    } on ShelfFailure catch (failure) {
      return l10n().failureTitle(failure.kind);
    } on FormatException {
      return l10n().savePageImageFailed;
    } finally {
      _savingImage = false;
    }
  }

  String _onSaveSuccess(AppLocalizations strings) {
    unawaited(AppHaptics.selection());
    return strings.savePageImageSuccess;
  }

  /// 分享指定页图至系统分享面板；失败时返回提示文案，成功返回 null。
  Future<String?> sharePage({
    required String bookId,
    required int page,
    required ReaderRepository repository,
    required AppLocalizations Function() l10n,
    Future<void> Function(int page)? overrideHandler,
  }) async {
    if (overrideHandler != null) {
      await overrideHandler(page);
      return null;
    }
    try {
      final bytes = await repository.pageImage(bookId, page);
      await sharePageImage(bytes, fileName: 'yomu-$bookId-page-$page.png');
      return null;
    } on ShelfFailure catch (failure) {
      return l10n().failureTitle(failure.kind);
    } on PlatformException {
      return l10n().sharePageFailed;
    }
  }

  /// 切换指定页的双页分组起点（已设置于该页则恢复自动），返回新的 1 基页码（自动时为 null）及提示文案。
  ({int? groupedPage, String toast}) toggleGroupFrom({
    required String bookId,
    required int page,
    required int total,
    required String serverKey,
    required int? currentSpreadFrom,
    required ReaderPrefsController prefsController,
    required AppLocalizations l10n,
  }) {
    final clamped = page.clamp(1, total);
    final index = clamped - 1;
    final next = currentSpreadFrom == index ? null : index;
    prefsController.setSpreadFrom(bookId, next, serverKey: serverKey);
    unawaited(AppHaptics.selection());
    return (
      groupedPage: next == null ? null : clamped,
      toast: next == null
          ? l10n.readerGroupAutomatic
          : l10n.readerGroupFrom(clamped),
    );
  }
}
