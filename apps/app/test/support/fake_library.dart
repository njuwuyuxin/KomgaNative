import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/library_repository.dart';
import 'package:komga_native/src/data/shelf_failure.dart';

/// 书架假仓库：可指定数据、可随时切换失败、可把请求"卡住"以观察加载态。
///
/// 封面用 `test/fixtures/covers/*.png` 里的真实 PNG（4~5 KB），
/// 这样黄金图能看到"有封面"的真实版式，而不是一片灰块。
class FakeLibraryRepository implements LibraryRepository {
  FakeLibraryRepository({
    List<Library>? libraries,
    List<Series>? series,
    this.seriesFailure,
    this.librariesFailure,
    this.coverDirectory = 'test/fixtures/covers',
    this.coverNames = const <String>['c1', 'c2', 'c3', 'c4', 'c5', 'c6'],
  }) : librariesData = libraries ?? const <Library>[],
       seriesData = series ?? const <Series>[] {
    for (var i = 0; i < seriesData.length; i++) {
      _coverBySeries[seriesData[i].id] = coverNames[i % coverNames.length];
    }
  }

  final List<Library> librariesData;
  final List<Series> seriesData;

  /// 非 final：测试里可以先失败、再改成功来验证"重试"。
  ShelfFailure? seriesFailure;
  ShelfFailure? librariesFailure;

  final String coverDirectory;
  final List<String> coverNames;

  /// 记录每次 `series()` 的入参，用来断言分页/搜索/筛选真的传下去了。
  final List<({String? libraryId, String? query, int page})> seriesCalls =
      <({String? libraryId, String? query, int page})>[];

  int librariesCalls = 0;
  int coverCalls = 0;

  /// 设成非 null 后，`series()` 会等它完成——用来稳定观察 loading 态。
  Completer<void>? gate;

  final Map<String, String> _coverBySeries = <String, String>{};
  final Map<String, Uint8List> _coverBytes = <String, Uint8List>{};

  @override
  Future<List<Library>> libraries() async {
    librariesCalls++;
    final failure = librariesFailure;
    if (failure != null) throw failure;
    return librariesData;
  }

  @override
  Future<PageResult<Series>> series({
    String? libraryId,
    String? query,
    int page = 0,
    int size = 30,
  }) async {
    seriesCalls.add((libraryId: libraryId, query: query, page: page));

    final pending = gate;
    if (pending != null) await pending.future;

    final failure = seriesFailure;
    if (failure != null) throw failure;

    final filtered = seriesData
        .where((Series s) => libraryId == null || s.libraryId == libraryId)
        .where(
          (Series s) =>
              query == null ||
              query.isEmpty ||
              s.title.toLowerCase().contains(query.toLowerCase()),
        )
        .toList(growable: false);

    final start = page * size;
    final items = start >= filtered.length
        ? const <Series>[]
        : filtered.sublist(start, math.min(start + size, filtered.length));

    return PageResult<Series>(
      items: items,
      totalElements: filtered.length,
      page: page,
      size: size,
    );
  }

  @override
  Future<Uint8List?> seriesCover(String seriesId) async {
    coverCalls++;
    final name = _coverBySeries[seriesId] ?? coverNames.first;
    final cached = _coverBytes[name];
    if (cached != null) return cached;

    final file = File('$coverDirectory/$name.png');
    if (!file.existsSync()) return null;
    // 缓存同一份 Uint8List，让 Flutter 的 ImageCache 能按实例命中。
    return _coverBytes[name] = file.readAsBytesSync();
  }
}

/// 黄金图/UI 测试用的书架数据：覆盖"在读 / 已读完 / 未读 / 右到左"几种状态。
List<Series> demoShelf() => const <Series>[
  Series(
    id: 's1',
    libraryId: 'l1',
    title: 'Frieren',
    booksCount: 12,
    booksReadCount: 5,
  ),
  Series(
    id: 's2',
    libraryId: 'l1',
    title: 'Vagabond',
    booksCount: 37,
    booksReadCount: 37,
  ),
  Series(
    id: 's3',
    libraryId: 'l1',
    title: 'Blame!',
    booksCount: 10,
    booksReadCount: 0,
  ),
  Series(
    id: 's4',
    libraryId: 'l1',
    title: 'Akira',
    booksCount: 6,
    booksReadCount: 2,
    readingDirection: ReadingDirection.rightToLeft,
  ),
  Series(
    id: 's5',
    libraryId: 'l2',
    title: 'Sunny',
    booksCount: 6,
    booksReadCount: 3,
  ),
  Series(
    id: 's6',
    libraryId: 'l2',
    title: 'Pluto',
    booksCount: 8,
    booksReadCount: 8,
  ),
];

List<Library> demoLibraries() => const <Library>[
  Library(id: 'l1', name: 'Comics'),
  Library(id: 'l2', name: 'Manga'),
];

/// n 条假系列，用于分页测试。
List<Series> manySeries(int count, {String libraryId = 'l1'}) => <Series>[
  for (var i = 1; i <= count; i++)
    Series(
      id: 's$i',
      libraryId: libraryId,
      title: 'Series $i',
      booksCount: 10,
      booksReadCount: i % 10,
    ),
];
