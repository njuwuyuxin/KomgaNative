import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/cache/http_cache_tables.dart';
import 'package:yomu/src/data/local/comic_file_picker.dart';
import 'package:yomu/src/data/local/local_archive_import_stream.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_comic_importer.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/archive_password_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu_domain/yomu_domain.dart';

export 'package:yomu/src/data/local/comic_file_picker.dart';
export 'package:yomu/src/data/local/local_comic_importer.dart';

/// 本地导入状态快照（供书架进度胶囊与结果 SnackBar 订阅）。
final class LocalImportState {
  const LocalImportState({
    this.busy = false,
    this.completed = 0,
    this.total = 0,
    this.currentName = '',
    this.lastResult,
  });

  final bool busy;
  final int completed;
  final int total;
  final String currentName;
  final LocalImportBatchResult? lastResult;

  LocalImportState copyWith({
    bool? busy,
    int? completed,
    int? total,
    String? currentName,
    LocalImportBatchResult? lastResult,
    bool clearLastResult = false,
  }) => LocalImportState(
    busy: busy ?? this.busy,
    completed: completed ?? this.completed,
    total: total ?? this.total,
    currentName: currentName ?? this.currentName,
    lastResult: clearLastResult ? null : (lastResult ?? this.lastResult),
  );
}

final Provider<ComicFilePicker> comicFilePickerProvider =
    Provider<ComicFilePicker>((Ref ref) => const PlatformComicFilePicker());

final Provider<LocalComicImporter> localComicImporterProvider =
    Provider<LocalComicImporter>((Ref ref) {
      return LocalComicImporter(
        db: ref.watch(progressDatabaseProvider),
        storage: ref.watch(localComicsStorageProvider),
        passwordStore: ref.watch(archivePasswordStoreProvider),
      );
    });

/// 本机已导入漫画的空间占用统计（Drift 表变更后自动响应式更新）。
final FutureProvider<CacheUsage> localStorageUsageProvider =
    FutureProvider<CacheUsage>((Ref ref) async {
      final db = ref.watch(progressDatabaseProvider);
      final sub = db.localCatalogUpdates().listen((_) => ref.invalidateSelf());
      ref.onDispose(sub.cancel);
      final usage = await db.localStorageUsage();
      return CacheUsage(bytes: usage.totalBytes, entries: usage.booksCount);
    });

/// 本地导入控制器：编排系统选择器、流式入库、清理临时缓存与刷新书架。
class LocalImportController extends Notifier<LocalImportState> {
  @override
  LocalImportState build() => const LocalImportState();

  ComicFilePicker get _picker => ref.read(comicFilePickerProvider);
  LocalComicImporter get _importer => ref.read(localComicImporterProvider);

  Future<LocalImportBatchResult?> pickAndImportArchives({
    ArchivePasswordPromptCallback? onPasswordPrompt,
  }) async {
    if (state.busy) return null;
    final picked = await _picker.pickArchiveFiles();
    if (picked.isEmpty) return null;

    state = LocalImportState(
      busy: true,
      completed: 0,
      total: picked.length,
      currentName: picked.first.name,
    );
    try {
      final result = await _importer.importArchiveFiles(
        picked,
        onProgress: _onProgress,
        onPasswordPrompt: onPasswordPrompt,
      );
      await _picker.clearTemporaryCache();
      await _finishImport(result);
      return result;
    } on Object {
      state = state.copyWith(busy: false, currentName: '');
      rethrow;
    }
  }

  Future<LocalImportBatchResult?> pickAndImportDirectory() async {
    if (state.busy) return null;
    final dirPath = await _picker.pickComicDirectory();
    if (dirPath != null && dirPath.isNotEmpty) {
      state = const LocalImportState(busy: true, completed: 0, total: 1);
      try {
        final result = await _importer.importDirectory(
          dirPath,
          onProgress: _onProgress,
        );
        await _finishImport(result);
        return result;
      } on Object {
        state = state.copyWith(busy: false, currentName: '');
        rethrow;
      }
    }

    // Android SAF 目录选择返回 content:// 时回退引导多选漫画图片页合成为单册。
    final pages = await _picker.pickImagePages();
    if (pages.isEmpty) return null;
    final defaultTitle = pages.first.name.split('.').first;
    state = LocalImportState(
      busy: true,
      completed: 0,
      total: pages.length,
      currentName: pages.first.name,
    );
    try {
      final result = await _importer.importImageFilesAsBook(
        pages,
        bookTitle: defaultTitle.isEmpty ? 'Imported Comic' : defaultTitle,
        onProgress: _onProgress,
      );
      await _picker.clearTemporaryCache();
      await _finishImport(result);
      return result;
    } on Object {
      state = state.copyWith(busy: false, currentName: '');
      rethrow;
    }
  }

  /// 直接导入外部传入的单个文件路径（供系统「用 Yomu 打开」Intent 调用，LMA-12）。
  Future<LocalImportBatchResult?> importExternalFile(
    String filePath, {
    String? fileName,
  }) async {
    if (state.busy) return null;
    final resolvedName =
        fileName ?? filePath.replaceAll(r'\', '/').split('/').last;
    state = LocalImportState(
      busy: true,
      completed: 0,
      total: 1,
      currentName: resolvedName,
    );
    try {
      final result = await _importer.importArchiveFiles(<PickedComicFile>[
        PickedComicFile.fromFile(File(filePath), name: resolvedName),
      ], onProgress: _onProgress);
      await _finishImport(result, switchToLocal: true);
      return result;
    } on Object {
      state = state.copyWith(busy: false, currentName: '');
      rethrow;
    }
  }

  void _onProgress(int completed, int total, String currentName) {
    if (!ref.mounted) return;
    state = state.copyWith(
      completed: completed,
      total: total,
      currentName: currentName,
    );
  }

  Future<void> _finishImport(
    LocalImportBatchResult result, {
    bool switchToLocal = false,
  }) async {
    if (!ref.mounted) return;
    state = LocalImportState(busy: false, lastResult: result);
    if (result.importedCount <= 0) return;

    if (switchToLocal) {
      await ref
          .read(activeSourceProvider.notifier)
          .selectSource(kLocalSourceKey);
    }
    invalidateLocalCatalogProviders(ref);
  }
}

final NotifierProvider<LocalImportController, LocalImportState>
localImportProvider = NotifierProvider<LocalImportController, LocalImportState>(
  LocalImportController.new,
);
