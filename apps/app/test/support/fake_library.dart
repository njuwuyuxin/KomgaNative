import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/read_status_repository.dart';
import 'package:yomu/src/data/shelf_failure.dart';

/// 书架假仓库：可指定数据、可随时切换失败、可把请求"卡住"以观察加载态。
///
/// 封面用 `test/fixtures/covers/*.png` 里的真实 PNG（4~5 KB），
/// 这样黄金图能看到"有封面"的真实版式，而不是一片灰块。
class FakeLibraryRepository
    implements LibraryRepository, CollectionsRepository, ReadStatusRepository {
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
    List<Collection>? collections,
    List<ReadList>? readLists,
  }) : librariesData = libraries ?? const <Library>[],
       seriesData = series ?? const <Series>[],
       ondeckData = ondeck ?? const <Book>[] {
    for (var i = 0; i < seriesData.length; i++) {
      _coverBySeries[seriesData[i].id] = coverNames[i % coverNames.length];
    }
    collectionsData = collections != null
        ? List<Collection>.of(collections)
        : <Collection>[
            Collection(
              id: 'c1',
              name: 'Reading order',
              ordered: true,
              seriesIds: seriesData.take(2).map((Series s) => s.id).toList(),
            ),
            const Collection(
              id: 'c2',
              name: 'Empty shelf',
              ordered: false,
              seriesIds: <String>[],
            ),
          ];
    readListsData = readLists != null
        ? List<ReadList>.of(readLists)
        : <ReadList>[
            ReadList(
              id: 'r1',
              name: 'Weekend reading',
              summary: 'Two books for the weekend',
              ordered: false,
              bookIds: ondeckData.map((Book b) => b.id).toList(),
            ),
          ];
  }

  late List<Collection> collectionsData;
  late List<ReadList> readListsData;

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

  /// 最近一次系列查询收到的标签筛选（SCH-02 断言用）。
  String? lastSeriesTag;
  SeriesReadStatus? lastSeriesReadStatus;

  /// 最近一次 `books()` 收到的排序 / 筛选（SER-01 断言用）。
  BooksSort? lastBooksSort;
  SeriesReadStatus? lastBooksReadStatus;
  final List<({int page, int size})> booksPageCalls =
      <({int page, int size})>[];
  int bookCoverCalls = 0;

  /// 设成非 null 后，`series()` 会等它完成——用来稳定观察 loading 态。
  Completer<void>? gate;

  /// 同上，但卡住的是"继续阅读"（ondeck）：用来观察加载中的骨架（FIX-05）。
  Completer<void>? ondeckGate;

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
    String? tag,
  }) async {
    lastSeriesTag = tag;
    lastSeriesReadStatus = readStatus;
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
    final pending = ondeckGate;
    if (pending != null) await pending.future;
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

  /// 新建/改名/更新/删除的记录，测试里断言用。
  final List<Collection> createdCollections = <Collection>[];
  final Map<String, String> renamedCollections = <String, String>{};
  final Map<String, List<String>> updatedCollectionSeries =
      <String, List<String>>{};
  final List<String> deletedCollections = <String>[];

  final List<ReadList> createdReadLists = <ReadList>[];
  final Map<String, ({String? name, String? summary, List<String>? bookIds})>
  updatedReadLists =
      <String, ({String? name, String? summary, List<String>? bookIds})>{};
  final List<String> deletedReadLists = <String>[];

  /// 人为让写操作失败。
  ShelfFailure? collectionFailure;

  @override
  Future<PageResult<Collection>> collections({
    int page = 0,
    int size = 20,
  }) async {
    final start = page * size;
    final items = start >= collectionsData.length
        ? const <Collection>[]
        : collectionsData.sublist(
            start,
            math.min(start + size, collectionsData.length),
          );
    return PageResult<Collection>(
      items: items,
      totalElements: collectionsData.length,
      page: page,
      size: size,
    );
  }

  @override
  Future<Collection?> collectionById(String collectionId) async {
    for (final c in collectionsData) {
      if (c.id == collectionId) return c;
    }
    return null;
  }

  @override
  Future<List<Collection>> seriesCollections(String seriesId) async =>
      collectionsData
          .where((Collection c) => c.seriesIds.contains(seriesId))
          .toList(growable: false);

  @override
  Future<Collection> createCollection({
    required String name,
    required List<String> seriesIds,
    bool ordered = false,
  }) async {
    if (collectionFailure != null) throw collectionFailure!;
    if (name.trim().isEmpty || seriesIds.isEmpty) {
      throw const ProtocolFailure();
    }
    final created = Collection(
      id: 'c${createdCollections.length + 10}',
      name: name,
      ordered: ordered,
      seriesIds: List<String>.of(seriesIds),
    );
    createdCollections.add(created);
    collectionsData.add(created);
    return created;
  }

  @override
  Future<void> renameCollection(String collectionId, String name) =>
      updateCollection(collectionId, name: name);

  @override
  Future<void> updateCollection(
    String collectionId, {
    String? name,
    bool? ordered,
    List<String>? seriesIds,
  }) async {
    if (collectionFailure != null) throw collectionFailure!;
    if (seriesIds != null && seriesIds.isEmpty) {
      throw const ProtocolFailure();
    }
    if (name != null) renamedCollections[collectionId] = name;
    if (seriesIds != null) {
      updatedCollectionSeries[collectionId] = List<String>.of(seriesIds);
    }
    final idx = collectionsData.indexWhere(
      (Collection c) => c.id == collectionId,
    );
    if (idx != -1) {
      final old = collectionsData[idx];
      collectionsData[idx] = Collection(
        id: old.id,
        name: name ?? old.name,
        ordered: ordered ?? old.ordered,
        seriesIds: seriesIds ?? old.seriesIds,
        createdDate: old.createdDate,
        lastModifiedDate: old.lastModifiedDate,
      );
    }
  }

  @override
  Future<void> deleteCollection(String collectionId) async {
    if (collectionFailure != null) throw collectionFailure!;
    deletedCollections.add(collectionId);
    collectionsData.removeWhere((Collection c) => c.id == collectionId);
  }

  @override
  Future<PageResult<Series>> collectionSeries(
    String collectionId, {
    int page = 0,
    int size = 20,
  }) async {
    final collection = await collectionById(collectionId);
    final byId = <String, Series>{for (final s in seriesData) s.id: s};
    final ordered = <Series>[
      for (final id in collection?.seriesIds ?? const <String>[])
        if (byId[id] != null) byId[id]!,
    ];
    final start = page * size;
    final items = start >= ordered.length
        ? const <Series>[]
        : ordered.sublist(start, math.min(start + size, ordered.length));
    return PageResult<Series>(
      items: items,
      totalElements: ordered.length,
      page: page,
      size: size,
    );
  }

  @override
  Future<PageResult<ReadList>> readLists({int page = 0, int size = 20}) async {
    final start = page * size;
    final items = start >= readListsData.length
        ? const <ReadList>[]
        : readListsData.sublist(
            start,
            math.min(start + size, readListsData.length),
          );
    return PageResult<ReadList>(
      items: items,
      totalElements: readListsData.length,
      page: page,
      size: size,
    );
  }

  @override
  Future<ReadList?> readListById(String readListId) async {
    for (final list in readListsData) {
      if (list.id == readListId) return list;
    }
    return null;
  }

  @override
  Future<List<ReadList>> bookReadLists(String bookId) async => readListsData
      .where((ReadList r) => r.bookIds.contains(bookId))
      .toList(growable: false);

  @override
  Future<ReadList> createReadList({
    required String name,
    String summary = '',
    required List<String> bookIds,
    bool ordered = false,
  }) async {
    if (collectionFailure != null) throw collectionFailure!;
    if (name.trim().isEmpty || bookIds.isEmpty) {
      throw const ProtocolFailure();
    }
    final created = ReadList(
      id: 'r${createdReadLists.length + 10}',
      name: name,
      summary: summary,
      ordered: ordered,
      bookIds: List<String>.of(bookIds),
    );
    createdReadLists.add(created);
    readListsData.add(created);
    return created;
  }

  @override
  Future<void> updateReadList(
    String readListId, {
    String? name,
    String? summary,
    bool? ordered,
    List<String>? bookIds,
  }) async {
    if (collectionFailure != null) throw collectionFailure!;
    if (bookIds != null && bookIds.isEmpty) {
      throw const ProtocolFailure();
    }
    updatedReadLists[readListId] = (
      name: name,
      summary: summary,
      bookIds: bookIds == null ? null : List<String>.of(bookIds),
    );
    final idx = readListsData.indexWhere((ReadList r) => r.id == readListId);
    if (idx != -1) {
      final old = readListsData[idx];
      readListsData[idx] = ReadList(
        id: old.id,
        name: name ?? old.name,
        summary: summary ?? old.summary,
        ordered: ordered ?? old.ordered,
        bookIds: bookIds ?? old.bookIds,
        createdDate: old.createdDate,
        lastModifiedDate: old.lastModifiedDate,
      );
    }
  }

  @override
  Future<void> deleteReadList(String readListId) async {
    if (collectionFailure != null) throw collectionFailure!;
    deletedReadLists.add(readListId);
    readListsData.removeWhere((ReadList r) => r.id == readListId);
  }

  @override
  Future<PageResult<Book>> readListBooks(
    String readListId, {
    int page = 0,
    int size = 20,
  }) async {
    final list = await readListById(readListId);
    final byId = <String, Book>{for (final b in ondeckData) b.id: b};
    final ordered = <Book>[
      for (final id in list?.bookIds ?? const <String>[])
        byId[id] ??
            Book(id: id, seriesId: 's1', name: 'Book $id', pagesCount: 3),
    ];
    final start = page * size;
    final items = start >= ordered.length
        ? const <Book>[]
        : ordered.sublist(start, math.min(start + size, ordered.length));
    return PageResult<Book>(
      items: items,
      totalElements: ordered.length,
      page: page,
      size: size,
    );
  }

  @override
  Future<PageResult<Book>> searchBooks(
    String query, {
    int page = 0,
    int size = 20,
  }) async {
    final normalized = query.toLowerCase();
    final all = <Book>[
      ...ondeckData,
      for (var i = 0; i < bookCount; i++)
        Book(
          id: 's1-b${i + 1}',
          seriesId: 's1',
          name: 'Search result $i',
          pagesCount: 3,
          number: '${i + 1}',
        ),
    ].where((Book b) => b.name.toLowerCase().contains(normalized)).toList();
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
    BooksSort? sort,
    SeriesReadStatus? readStatus,
  }) async {
    booksCalls++;
    booksPageCalls.add((page: page, size: size));
    lastBooksSort = sort;
    lastBooksReadStatus = readStatus;
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
    // 排序 / 筛选和真实服务端一样作用在**全量**上，再切片。
    final filtered = <Book>[
      for (final book in all)
        if (_matchesBookReadStatus(book, readStatus)) book,
    ];
    final ordered = sort == BooksSort.numberDesc
        ? filtered.reversed.toList()
        : filtered;
    final start = page * size;
    final items = start >= ordered.length
        ? const <Book>[]
        : ordered.sublist(start, math.min(start + size, ordered.length));

    return PageResult<Book>(
      items: items,
      totalElements: ordered.length,
      page: page,
      size: size,
    );
  }

  /// 与真实服务端一致：`read_status` 只看"这本书自己"，不是整个系列。
  static bool _matchesBookReadStatus(Book book, SeriesReadStatus? status) {
    if (status == null) return true;
    final progress = book.readProgress;
    return switch (status) {
      SeriesReadStatus.unread => progress == null || progress.page == 0,
      SeriesReadStatus.read => progress?.completed ?? false,
      SeriesReadStatus.inProgress =>
        progress != null && progress.page > 0 && !progress.completed,
    };
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
///
/// 带 `seriesTitle`：真实 Komga 的 `BookDto` 就有这个字段，继续阅读卡要显示
/// 系列名而不是 "Vol. 1"（FIX-06）。
List<Book> demoOndeck() => <Book>[
  Book(
    id: 's1-b1',
    seriesId: 's1',
    seriesTitle: 'Frieren',
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
    seriesTitle: 'Sunny',
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
