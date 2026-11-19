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
    List<Book>? ondeck,
    this.seriesFailure,
    this.librariesFailure,
    this.booksFailure,
    this.detailFailure,
    this.ondeckFailure,
    this.coverDirectory = 'test/fixtures/covers',
    this.coverNames = const <String>['c1', 'c2', 'c3', 'c4', 'c5', 'c6'],
  }) : librariesData = libraries ?? const <Library>[],
       seriesData = series ?? const <Series>[],
       ondeckData = ondeck ?? const <Book>[] {
    for (var i = 0; i < seriesData.length; i++) {
      _coverBySeries[seriesData[i].id] = coverNames[i % coverNames.length];
    }
  }

  final List<Library> librariesData;
  final List<Series> seriesData;
  final List<Book> ondeckData;

  /// 记录"标记系列已读/未读"的调用。
  final List<({String seriesId, bool read})> seriesReadCalls =
      <({String seriesId, bool read})>[];
  ShelfFailure? seriesReadFailure;

  /// 记录"标记单本书已读/未读"的调用（UI-P2-5）。
  final List<({String bookId, bool read, int pagesCount})> bookReadCalls =
      <({String bookId, bool read, int pagesCount})>[];
  ShelfFailure? bookReadFailure;

  /// 非 final：测试里可以先失败、再改成功来验证"重试"。
  ShelfFailure? seriesFailure;
  ShelfFailure? librariesFailure;
  ShelfFailure? booksFailure;
  ShelfFailure? detailFailure;
  ShelfFailure? ondeckFailure;

  /// 每个系列生成多少本书。
  int bookCount = 6;

  /// 书列表里要不要带阅读进度（第 1 本在读、第 2 本已读完）。
  ///
  /// 关掉就是"一本都没读过"的系列，用来测详情页的主按钮文案（UI-P2-4）。
  bool bookProgress = true;

  final String coverDirectory;
  final List<String> coverNames;

  /// 记录每次 `series()` 的入参，用来断言分页/搜索/筛选/排序真的传下去了。
  final List<
    ({
      String? libraryId,
      String? query,
      int page,
      SeriesSort? sort,
      SeriesReadStatus? readStatus,
    })
  >
  seriesCalls =
      <
        ({
          String? libraryId,
          String? query,
          int page,
          SeriesSort? sort,
          SeriesReadStatus? readStatus,
        })
      >[];

  int librariesCalls = 0;
  int coverCalls = 0;
  int seriesByIdCalls = 0;
  int booksCalls = 0;
  int bookCoverCalls = 0;

  /// 设成非 null 后，`series()` 会等它完成——用来稳定观察 loading 态。
  Completer<void>? gate;

  /// 同上，但卡住的是系列详情 / 书列表：用来观察"首次打开详情页"的占位态
  /// （封面 Hero 已经在，元信息还没到）。
  Completer<void>? detailGate;
  Completer<void>? booksGate;

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
    SeriesSort? sort,
    SeriesReadStatus? readStatus,
  }) async {
    seriesCalls.add((
      libraryId: libraryId,
      query: query,
      page: page,
      sort: sort,
      readStatus: readStatus,
    ));

    final pending = gate;
    if (pending != null) await pending.future;

    final failure = seriesFailure;
    if (failure != null) throw failure;

    var filtered = seriesData
        .where((Series s) => libraryId == null || s.libraryId == libraryId)
        .where(
          (Series s) =>
              query == null ||
              query.isEmpty ||
              s.title.toLowerCase().contains(query.toLowerCase()),
        )
        .where((Series s) => _matchesReadStatus(s, readStatus))
        .toList(growable: false);

    // 排序只实现标题：其余取值在假仓库里没有真实时间线，断言"参数传下去了"即可。
    if (sort == SeriesSort.titleAsc || sort == SeriesSort.titleDesc) {
      final ascending = sort == SeriesSort.titleAsc;
      filtered = <Series>[...filtered]
        ..sort(
          (Series a, Series b) => ascending
              ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
              : b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
    }

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
  Future<void> setSeriesRead(String seriesId, {required bool read}) async {
    seriesReadCalls.add((seriesId: seriesId, read: read));
    final failure = seriesReadFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> setBookRead(
    String bookId, {
    required bool read,
    required int pagesCount,
  }) async {
    bookReadCalls.add((bookId: bookId, read: read, pagesCount: pagesCount));
    final failure = bookReadFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<PageResult<Book>> ondeck({int size = 20}) async {
    final failure = ondeckFailure;
    if (failure != null) throw failure;
    return PageResult<Book>(
      items: ondeckData.take(size).toList(growable: false),
      totalElements: ondeckData.length,
      page: 0,
      size: size,
    );
  }

  @override
  Future<Uint8List?> seriesCover(String seriesId) async {
    coverCalls++;
    final name = _coverBySeries[seriesId] ?? coverNames.first;
    return _coverBytesFor(name);
  }

  @override
  Future<Series?> seriesById(String seriesId) async {
    seriesByIdCalls++;
    final pending = detailGate;
    if (pending != null) await pending.future;
    final failure = detailFailure;
    if (failure != null) throw failure;
    for (final series in seriesData) {
      if (series.id == seriesId) return series;
    }
    return null;
  }

  @override
  Future<PageResult<KomgaCollection>> collections({
    int page = 0,
    int size = 20,
  }) async {
    return PageResult<KomgaCollection>(
      items: <KomgaCollection>[
        KomgaCollection(
          id: 'c1',
          name: 'Reading order',
          ordered: true,
          seriesIds: seriesData.take(2).map((Series s) => s.id).toList(),
        ),
        KomgaCollection(
          id: 'c2',
          name: 'Empty shelf',
          ordered: false,
          seriesIds: const <String>[],
        ),
      ],
      totalElements: 2,
      page: page,
      size: size,
    );
  }

  @override
  Future<PageResult<Series>> collectionSeries(
    String collectionId, {
    int page = 0,
    int size = 20,
  }) async {
    final ids = collectionId == 'c1'
        ? seriesData.take(2).map((Series s) => s.id).toSet()
        : const <String>{};
    final items = seriesData
        .where((Series s) => ids.contains(s.id))
        .toList(growable: false);
    return PageResult<Series>(
      items: items,
      totalElements: items.length,
      page: page,
      size: size,
    );
  }

  @override
  Future<PageResult<ReadList>> readLists({int page = 0, int size = 20}) async {
    return PageResult<ReadList>(
      items: <ReadList>[
        ReadList(
          id: 'r1',
          name: 'Weekend reading',
          summary: 'Two books for the weekend',
          ordered: false,
          bookIds: ondeckData.map((Book b) => b.id).toList(),
        ),
      ],
      totalElements: 1,
      page: page,
      size: size,
    );
  }

  @override
  Future<PageResult<Book>> readListBooks(
    String readListId, {
    int page = 0,
    int size = 20,
  }) async {
    final items = readListId == 'r1'
        ? List<Book>.of(ondeckData)
        : const <Book>[];
    return PageResult<Book>(
      items: items,
      totalElements: items.length,
      page: page,
      size: size,
    );
  }

  @override
  Future<Book?> book(String bookId) async {
    for (final book in ondeckData) {
      if (book.id == bookId) return book;
    }
    // 下载管理页的测试：不在 ondeck 里的书给一个稳定标题即可。
    return Book(
      id: bookId,
      seriesId: 's1',
      name: 'Book $bookId',
      pagesCount: 3,
    );
  }

  @override
  Future<PageResult<Book>> books(
    String seriesId, {
    int page = 0,
    int size = 100,
  }) async {
    booksCalls++;
    final pending = booksGate;
    if (pending != null) await pending.future;
    final failure = booksFailure;
    if (failure != null) throw failure;

    // 按 size 切片：详情页的"加载更多"就是"要更多本"（UI-P2-4），
    // 假仓库必须尊重 size，否则 `items.length == totalElements` 永远成立，
    // 那段交互在测试里根本走不到。
    final all = <Book>[
      for (var i = 1; i <= bookCount; i++)
        Book(
          id: '$seriesId-b$i',
          seriesId: seriesId,
          name: 'Vol. $i',
          number: '$i',
          pagesCount: 18 + i,
          sizeBytes: 1024 * 512 * i,
          readProgress: !bookProgress
              ? null
              : (i == 1
                    ? ReadProgress(
                        page: 5,
                        completed: false,
                        lastModified: DateTime.utc(2026, 1, 1),
                      )
                    : (i == 2
                          ? ReadProgress(
                              page: 19,
                              completed: true,
                              lastModified: DateTime.utc(2026, 1, 2),
                            )
                          : null)),
        ),
    ];
    final start = page * size;
    final items = start >= all.length
        ? const <Book>[]
        : all.sublist(start, math.min(start + size, all.length));

    return PageResult<Book>(
      items: items,
      totalElements: all.length,
      page: page,
      size: size,
    );
  }

  @override
  Future<Uint8List?> bookCover(String bookId) async {
    bookCoverCalls++;
    // 按 id 结尾的数字选图，保证同一本书每次都是同一张（黄金图才稳定）。
    final digits = RegExp(r'(\d+)$').firstMatch(bookId)?.group(1) ?? '1';
    final index = (int.tryParse(digits) ?? 1) - 1;
    final name = coverNames[index % coverNames.length];
    return _coverBytesFor(name);
  }

  static bool _matchesReadStatus(Series series, SeriesReadStatus? status) {
    if (status == null) return true;
    final read = series.booksReadCount;
    final total = series.booksCount;
    return switch (status) {
      SeriesReadStatus.unread => read == 0,
      SeriesReadStatus.read => total > 0 && read >= total,
      SeriesReadStatus.inProgress => read > 0 && read < total,
    };
  }

  Uint8List? _coverBytesFor(String name) {
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

/// 黄金图/UI 测试用的"继续阅读"：两本在读的书（系列都在 [demoShelf] 里）。
List<Book> demoOndeck() => <Book>[
  Book(
    id: 's1-b1',
    seriesId: 's1',
    name: 'Vol. 1',
    number: '1',
    pagesCount: 12,
    readProgress: ReadProgress(
      page: 5,
      completed: false,
      lastModified: DateTime.utc(2026, 11, 1),
    ),
  ),
  Book(
    id: 's5-b2',
    seriesId: 's5',
    name: 'Vol. 2',
    number: '2',
    pagesCount: 8,
    readProgress: ReadProgress(
      page: 3,
      completed: false,
      lastModified: DateTime.utc(2026, 11, 2),
    ),
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
