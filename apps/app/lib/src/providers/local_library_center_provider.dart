import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yomu/src/data/local/external_directory_scanner.dart';
import 'package:yomu/src/data/local/external_roots_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/cross_source_reading_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu_platform/yomu_platform.dart';

export 'package:yomu/src/data/local/external_directory_scanner.dart';
export 'package:yomu/src/data/local/external_roots_dao.dart';

/// 外部挂载目录桥接 Provider（测试可覆盖注入假桥）。
final Provider<ExternalRootsBridge> externalRootsBridgeProvider =
    Provider<ExternalRootsBridge>((Ref _) => ChannelExternalRootsBridge());

final Provider<ExternalDirectoryScanner> externalDirectoryScannerProvider =
    Provider<ExternalDirectoryScanner>((Ref ref) {
      return ExternalDirectoryScanner(
        db: ref.watch(progressDatabaseProvider),
        storage: ref.watch(localComicsStorageProvider),
        bridge: ref.watch(externalRootsBridgeProvider),
      );
    });

/// 已挂载外部漫画目录的实时流。
final StreamProvider<List<LocalMountedRootsRow>> mountedRootsProvider =
    StreamProvider<List<LocalMountedRootsRow>>((Ref ref) async* {
      final db = ref.watch(progressDatabaseProvider);
      yield await db.allMountedRoots();
      await for (final _ in db.mountedRootsUpdates()) {
        yield await db.allMountedRoots();
      }
    });

/// 本地书库扫描控制器状态。
final class LocalLibraryScanState {
  const LocalLibraryScanState({
    this.scanning = false,
    this.currentRootName = '',
    this.scanned = 0,
    this.total = 0,
    this.lastSummary,
  });

  final bool scanning;
  final String currentRootName;
  final int scanned;
  final int total;
  final ExternalScanSummary? lastSummary;

  LocalLibraryScanState copyWith({
    bool? scanning,
    String? currentRootName,
    int? scanned,
    int? total,
    ExternalScanSummary? lastSummary,
  }) => LocalLibraryScanState(
    scanning: scanning ?? this.scanning,
    currentRootName: currentRootName ?? this.currentRootName,
    scanned: scanned ?? this.scanned,
    total: total ?? this.total,
    lastSummary: lastSummary ?? this.lastSummary,
  );
}

/// 本地书库管理中心控制器：外部目录挂载、增量扫描、`.nomedia` 保护、iOS Files 自发现与安全卸载（LMB-09）。
class LocalLibraryScanController extends Notifier<LocalLibraryScanState> {
  @override
  LocalLibraryScanState build() => const LocalLibraryScanState();

  /// 拉起系统目录选择器（Android SAF / iOS Folder Picker）挂载外部目录并立即执行首次扫描。
  Future<ExternalScanSummary?> mountExternalDirectory() async {
    if (state.scanning) return null;
    final bridge = ref.read(externalRootsBridgeProvider);
    final picked = await bridge.pickDirectory();
    if (picked == null) return null;

    var hasNomedia = picked.hasNomedia;
    if (!hasNomedia && picked.kind != ExternalRootKind.iosBookmark) {
      hasNomedia = await bridge.ensureNomedia(picked);
    }
    final root = MountedExternalRoot(
      id: picked.id,
      displayName: picked.displayName,
      uriOrBookmark: picked.uriOrBookmark,
      kind: picked.kind,
      hasNomedia: hasNomedia,
    );
    await ref.read(progressDatabaseProvider).upsertMountedRoot(root);
    return scanSingleRoot(root);
  }

  /// 对单个已挂载目录执行增量扫描。
  Future<ExternalScanSummary?> scanSingleRoot(MountedExternalRoot root) async {
    if (state.scanning) return null;
    state = LocalLibraryScanState(
      scanning: true,
      currentRootName: root.displayName,
    );
    try {
      final scanner = ref.read(externalDirectoryScannerProvider);
      final summary = await scanner.scanRoot(
        root,
        onProgress: (ExternalScanProgress p) {
          if (!ref.mounted) return;
          state = state.copyWith(scanned: p.scanned, total: p.total);
        },
      );
      if (!ref.mounted) return summary;
      state = LocalLibraryScanState(scanning: false, lastSummary: summary);
      _refreshShelf();
      return summary;
    } on Object {
      if (ref.mounted) {
        state = state.copyWith(scanning: false);
      }
      rethrow;
    }
  }

  /// 增量扫描所有已挂载外部目录（含 iOS `Files.app` 目录自发现）。
  Future<ExternalScanSummary?> scanAllRoots() async {
    if (state.scanning) return null;
    state = const LocalLibraryScanState(scanning: true);
    var totalSummary = const ExternalScanSummary();
    try {
      final db = ref.read(progressDatabaseProvider);
      final scanner = ref.read(externalDirectoryScannerProvider);

      if (Platform.isIOS) {
        try {
          final docs = await getApplicationDocumentsDirectory();
          totalSummary =
              totalSummary +
              await scanner.discoverAndScanDocumentsDirectory(docs);
        } on Object {
          // Documents 路径不可用时跳过。
        }
      }

      final roots = await db.allMountedRoots();
      for (final row in roots) {
        if (!row.enabled) continue;
        if (Platform.isIOS && row.id == kIosFilesRootId) continue;
        if (!ref.mounted) break;
        state = state.copyWith(currentRootName: row.displayName);
        final summary = await scanner.scanRoot(
          mountedRootFromRow(row),
          onProgress: (ExternalScanProgress p) {
            if (!ref.mounted) return;
            state = state.copyWith(scanned: p.scanned, total: p.total);
          },
        );
        totalSummary = totalSummary + summary;
      }

      if (!ref.mounted) return totalSummary;
      state = LocalLibraryScanState(scanning: false, lastSummary: totalSummary);
      _refreshShelf();
      return totalSummary;
    } on Object {
      if (ref.mounted) state = state.copyWith(scanning: false);
      rethrow;
    }
  }

  /// 为指定目录创建 `.nomedia` 文件并写回状态。
  Future<bool> ensureNomedia(LocalMountedRootsRow row) async {
    final root = mountedRootFromRow(row);
    final ok = await ref.read(externalRootsBridgeProvider).ensureNomedia(root);
    if (ok) {
      await ref
          .read(progressDatabaseProvider)
          .updateMountedRootScanStats(
            rootId: row.id,
            booksCount: row.booksCount,
            hasNomedia: true,
          );
    }
    return ok;
  }

  /// 安全卸载外部挂载目录（仅清库索引与缩略图缓存，绝不删用户外部源文件）。
  Future<void> unmountRoot(LocalMountedRootsRow row) async {
    final root = mountedRootFromRow(row);
    final db = ref.read(progressDatabaseProvider);
    final storage = ref.read(localComicsStorageProvider);
    final coverPaths = await db.unmountExternalRootFromDb(row.id);
    for (final rel in coverPaths) {
      try {
        final f = await storage.resolveFile(rel);
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // 缩略图清理失败不阻断卸载。
      }
    }
    await ref.read(externalRootsBridgeProvider).releasePermission(root);
    _refreshShelf();
  }

  void _refreshShelf() {
    ref.read(localLibraryRepositoryProvider).evictCoverCache();
    ref.invalidate(crossSourceOndeckProvider);
    ref.invalidate(recentSeriesProvider);
    if (!ref.read(activeSourceProvider).isCloud) {
      unawaited(ref.read(shelfProvider.notifier).refreshInPlace());
    }
  }
}

final NotifierProvider<LocalLibraryScanController, LocalLibraryScanState>
localLibraryScanProvider =
    NotifierProvider<LocalLibraryScanController, LocalLibraryScanState>(
      LocalLibraryScanController.new,
    );
