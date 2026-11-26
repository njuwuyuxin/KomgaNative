import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/local/external_roots_dao.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_folder_tree.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu_domain/yomu_domain.dart';

export 'package:yomu/src/data/local/local_folder_tree.dart';

/// 本地书架双模浏览状态（LMB-10）：按系列聚合 vs 按真实文件夹树浏览。
enum LocalShelfBrowseMode { series, folders }

class LocalShelfBrowseModeController extends Notifier<LocalShelfBrowseMode> {
  @override
  LocalShelfBrowseMode build() => LocalShelfBrowseMode.series;

  void setMode(LocalShelfBrowseMode mode) => state = mode;

  void toggle() => state = state == LocalShelfBrowseMode.series
      ? LocalShelfBrowseMode.folders
      : LocalShelfBrowseMode.series;
}

final NotifierProvider<LocalShelfBrowseModeController, LocalShelfBrowseMode>
localShelfBrowseModeProvider =
    NotifierProvider<LocalShelfBrowseModeController, LocalShelfBrowseMode>(
      LocalShelfBrowseModeController.new,
    );

/// 文件夹树当前所处路径面包屑栈（空列表 = 逻辑根目录）。
class LocalFolderBreadcrumbController extends Notifier<List<String>> {
  @override
  List<String> build() => const <String>[];

  void enter(String segment) => state = <String>[...state, segment];

  void popOne() {
    if (state.isEmpty) return;
    state = state.sublist(0, state.length - 1);
  }

  void popTo(int depth) {
    if (depth <= 0) {
      state = const <String>[];
      return;
    }
    if (depth >= state.length) return;
    state = state.sublist(0, depth);
  }

  void reset() => state = const <String>[];
}

final NotifierProvider<LocalFolderBreadcrumbController, List<String>>
localFolderBreadcrumbProvider =
    NotifierProvider<LocalFolderBreadcrumbController, List<String>>(
      LocalFolderBreadcrumbController.new,
    );

/// 构建完整的本地书库文件夹树（含外部原位挂载目录树与受管导入目录，表变更自动刷新）。
final localFolderTreeProvider = FutureProvider.autoDispose
    .family<LocalFolderNode, String>((
      Ref ref,
      String importedGroupLabel,
    ) async {
      final db = ref.watch(progressDatabaseProvider);
      final subCatalog = db.localCatalogUpdates().listen(
        (_) => ref.invalidateSelf(),
      );
      final subRoots = db.mountedRootsUpdates().listen(
        (_) => ref.invalidateSelf(),
      );
      ref.onDispose(() {
        subCatalog.cancel();
        subRoots.cancel();
      });

      final books = await db.select(db.localBooksRows).get();
      if (books.isEmpty) {
        return const LocalFolderNode(
          path: '',
          name: '',
          subfolders: <LocalFolderNode>[],
          books: <LocalFolderBookItem>[],
          totalBooksCount: 0,
        );
      }

      final seriesRows = await db.select(db.localSeriesRows).get();
      final seriesById = <String, LocalSeriesRow>{
        for (final s in seriesRows) s.id: s,
      };
      final rootRows = await db.allMountedRoots();
      final rootNameById = <String, String>{
        for (final r in rootRows) r.id: r.displayName,
      };
      final progressRows = await db.records(
        books.map((b) => b.id).toList(growable: false),
        scope: kLocalSourceKey,
      );
      final progressByBook = <String, ReadProgress>{
        for (final p in progressRows)
          p.bookId: ReadProgress(
            page: p.page,
            completed: p.completed,
            lastModified: p.updatedAt,
          ),
      };

      final items = <LocalFolderBookItem>[];
      for (final b in books) {
        final series = seriesById[b.seriesId];
        final seriesTitle = series?.title ?? '';
        final direction = ReadingDirection.parse(series?.readingDirection);
        final segments = folderSegmentsForLocalBook(
          mountRootId: b.mountRootId,
          sourceRelativePath: b.sourceRelativePath,
          mountRootDisplayName: b.mountRootId == null
              ? null
              : rootNameById[b.mountRootId!],
          seriesTitle: seriesTitle,
          importedGroupLabel: importedGroupLabel,
        );
        items.add(
          LocalFolderBookItem(
            book: Book(
              id: b.id,
              seriesId: b.seriesId,
              seriesTitle: seriesTitle,
              name: b.name,
              number: b.number,
              pagesCount: b.pagesCount,
              mediaProfile: MediaProfile.divina,
              readProgress: progressByBook[b.id],
              sizeBytes: b.sizeBytes,
              sourceKey: kLocalSourceKey,
            ),
            direction: direction,
            folderSegments: segments,
            numberSort: b.numberSort,
            isCloudPlaceholder: b.isCloudPlaceholder,
          ),
        );
      }

      return buildLocalFolderTree(items);
    });
