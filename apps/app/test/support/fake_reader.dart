import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/reader_repository.dart';
import 'package:komga_native/src/data/shelf_failure.dart';

/// 阅读器假仓库：页图用 `test/fixtures/pages/*.png` 里的真实 PNG，
/// 这样黄金图能看到"真的把一页画出来"的样子。
class FakeReaderRepository implements ReaderRepository {
  FakeReaderRepository({
    this.stubBook,
    this.pageCount = 3,
    this.pagesFailure,
    this.imageFailure,
    this.saveFailure,
    this.pageDirectory = 'test/fixtures/pages',
    this.pageNames = const <String>['p1', 'p2', 'p3'],
    this.pageSizes,
  });

  /// 不给就用默认书（3 页、读到第 1 页）。
  Book? stubBook;
  int pageCount;
  ShelfFailure? pagesFailure;
  ShelfFailure? imageFailure;
  ShelfFailure? saveFailure;

  /// 页图文件名**循环复用**：页数超过 `pageNames.length` 时第 4 页与第 1 页是同一张图。
  /// 断言"字节缓存里有没有"时要记住这一点（页面别开太多，否则 p2 会被 p5 顺手填上）。
  final String pageDirectory;
  final List<String> pageNames;

  /// 每页尺寸（第 i 项对应第 i 页）；不给就全部 800×1200。
  /// 双页测试需要"宽页单独成屏"，所以尺寸必须可控。
  final List<({int width, int height})>? pageSizes;

  /// 记录每次进度回写，用来断言"翻到哪页就存哪页、最后一页标 completed"。
  final List<({int page, bool completed})> saved =
      <({int page, bool completed})>[];

  int pageImageCalls = 0;

  /// 每次 `pageImage` 被请求的页码（1 基，按调用顺序）。
  /// 预加载测试用它断言"翻过去之前就已经取过"，而不是只看总数。
  final List<int> pageRequests = <int>[];

  /// 给某几页装一道闸：`pageImage` 会停在这里，直到测试手动放行。
  /// 用来造"这一页还没加载好"的状态（冷页 loading 态）。
  final Map<int, Completer<void>> pageGates = <int, Completer<void>>{};

  /// 只让这些页（1 基）取图失败。
  ///
  /// 与 [imageFailure] 的区别：那个是"整本都取不到"，这个是"其中几页取不到"。
  /// 缩略图占位这类测试需要在**首帧之前**就确定哪些页失败——首帧之后再设
  /// [imageFailure] 是来不及的，那时缩略图早就把字节请回来了。
  final Set<int> failingPages = <int>{};

  final Map<String, Uint8List> _bytes = <String, Uint8List>{};

  @override
  Future<Book?> book(String bookId) async =>
      stubBook ??
      Book(
        id: bookId,
        seriesId: 's1',
        name: 'Vol. 1',
        number: '1',
        pagesCount: pageCount,
      );

  @override
  Future<List<PageInfo>> pages(String bookId) async {
    final failure = pagesFailure;
    if (failure != null) throw failure;
    final sizes = pageSizes;
    return <PageInfo>[
      for (var i = 1; i <= pageCount; i++)
        PageInfo(
          number: i,
          width: sizes == null ? 800 : sizes[(i - 1) % sizes.length].width,
          height: sizes == null ? 1200 : sizes[(i - 1) % sizes.length].height,
          mediaType: 'image/png',
        ),
    ];
  }

  @override
  Future<Uint8List> pageImage(String bookId, int page) async {
    pageImageCalls++;
    pageRequests.add(page);
    final gate = pageGates[page];
    if (gate != null) await gate.future;
    if (failingPages.contains(page)) throw const NetworkFailure();
    final failure = imageFailure;
    if (failure != null) throw failure;

    final name = pageNames[(page - 1) % pageNames.length];
    final cached = _bytes[name];
    if (cached != null) return cached;

    final file = File('$pageDirectory/$name.png');
    if (!file.existsSync()) {
      throw StateError('缺少页图 fixture: ${file.path}');
    }
    return _bytes[name] = file.readAsBytesSync();
  }

  @override
  Uint8List? cachedPageImage(String bookId, int page) =>
      _bytes[pageNames[(page - 1) % pageNames.length]];

  Future<void> uploadProgress(
    String bookId, {
    required int page,
    required bool completed,
  }) async {
    final failure = saveFailure;
    if (failure != null) throw failure;
    saved.add((page: page, completed: completed));
  }

  /// 黄金图预热用：拿到与页面里**同一个 bytes 实例**，ImageCache 才能命中。
  Future<Uint8List?> warmPage(int page) async {
    try {
      return await pageImage('warm', page);
    } on ShelfFailure {
      return null;
    }
  }
}

/// 测试/黄金图用的书：3 页、读到第 1 页。
Book demoReaderBook() => Book(
  id: 'b1',
  seriesId: 's1',
  name: 'Vol. 1',
  number: '1',
  pagesCount: 3,
  readProgress: ReadProgress(
    page: 1,
    completed: false,
    lastModified: DateTime.utc(2026, 1, 1),
  ),
);
