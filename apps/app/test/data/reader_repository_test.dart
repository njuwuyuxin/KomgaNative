import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/progress/progress_store.dart';
import 'package:komga_native/src/data/progress/progress_sync_service.dart';
import 'package:komga_native/src/data/reader_repository.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/widgets/reader_preloader.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

KomgaReaderRepository _repository(_Adapter adapter) {
  final session = KomgaSession.withApiKey(
    address: ServerAddress.parse('https://komga.example.com'),
    apiKey: 'KEY',
    dio: Dio()..httpClientAdapter = adapter,
  );
  final sync = ProgressSyncService(
    store: InMemoryProgressStore(),
    upload: (ProgressTarget target) async {},
  );
  return KomgaReaderRepository(session, sync);
}

void main() {
  test('并发请求同一页只发一次网络请求，且返回同一个 Uint8List 引用（保证 ImageCache 键一致）', () async {
    final started = Completer<void>();
    final gate = Completer<ResponseBody>();
    final adapter = _Adapter((_) {
      if (!started.isCompleted) started.complete();
      return gate.future;
    });
    final repo = _repository(adapter);

    final f1 = repo.pageImage('b1', 5);
    final f2 = repo.pageImage('b1', 5);
    final f3 = repo.pageImage('b1', 5);
    await started.future;
    expect(adapter.requests, hasLength(1));

    gate.complete(
      ResponseBody.fromBytes(
        <int>[137, 80, 78, 71, 5],
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['image/png'],
        },
      ),
    );

    final results = await Future.wait(<Future<Uint8List>>[f1, f2, f3]);
    expect(identical(results[0], results[1]), isTrue);
    expect(identical(results[1], results[2]), isTrue);
    expect(identical(repo.cachedPageImage('b1', 5), results[0]), isTrue);
    expect(adapter.requests, hasLength(1));
  });

  test('在途请求失败后清理去重槽位，后续重试能正常恢复', () async {
    var fail = true;
    final adapter = _Adapter((_) async {
      if (fail) {
        throw DioException.connectionError(
          requestOptions: RequestOptions(path: '/'),
          reason: 'offline',
        );
      }
      return ResponseBody.fromBytes(<int>[1, 2, 3], 200);
    });
    final repo = _repository(adapter);

    await expectLater(repo.pageImage('b1', 1), throwsA(isA<ShelfFailure>()));
    fail = false;
    final bytes = await repo.pageImage('b1', 1);
    expect(bytes, <int>[1, 2, 3]);
    expect(adapter.requests, hasLength(2));
  });

  test('64 页字节 LRU：连续浏览及缩略图预取 40 页后，早期已读页仍保留在内存中不重拉网络', () async {
    final adapter = _Adapter((RequestOptions options) async {
      final page = int.parse(options.uri.pathSegments.last);
      return ResponseBody.fromBytes(<int>[page], 200);
    });
    final repo = _repository(adapter);

    for (var p = 1; p <= 40; p++) {
      await repo.pageImage('b1', p);
    }
    expect(adapter.requests, hasLength(40));

    // 往回翻第 2、3 页：仍在 64 页 LRU 内，同步缓存存在且零网络请求。
    expect(repo.cachedPageImage('b1', 2), isNotNull);
    expect(repo.cachedPageImage('b1', 3), isNotNull);
    await repo.pageImage('b1', 2);
    await repo.pageImage('b1', 3);
    expect(adapter.requests, hasLength(40));
  });

  test('ReaderPreloader 同时对前后各 2 屏触发预解码，保证连续回翻同样热命中 ImageCache', () async {
    final decoded = <int>[];
    final preloader = ReaderPreloader(
      fetch: (int page) async => Uint8List.fromList(<int>[page]),
      decode: (Uint8List bytes) => decoded.add(bytes.first),
      isActive: () => true,
    );

    // 双页分屏：[0], [1,2], [3,4], [5,6], [7,8], [9,10]；当前在 [5,6]（1 基第 6 页）。
    preloader.planAround(
      page: 6,
      total: 11,
      spreads: const <List<int>>[
        <int>[0],
        <int>[1, 2],
        <int>[3, 4],
        <int>[5, 6],
        <int>[7, 8],
        <int>[9, 10],
      ],
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 往前 2 屏（[7,8],[9,10] → 1 基 8,9,10,11）与往后 2 屏（[3,4],[1,2] → 1 基 4,5,2,3）均被预解码。
    expect(decoded, containsAll(<int>[8, 9, 10, 11, 4, 5, 2, 3]));
    // 封面 [0]（距离 3 屏）不进入预解码。
    expect(decoded, isNot(contains(1)));
  });

  test('pageThumbnail 请求低精度缩略图端点，去重并独立缓存；网络失败时回退到原图', () async {
    var failThumbnail = false;
    final adapter = _Adapter((RequestOptions options) async {
      final path = options.uri.path;
      if (path.endsWith('/thumbnail')) {
        if (failThumbnail) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'offline',
          );
        }
        return ResponseBody.fromBytes(<int>[9, 9, 1], 200);
      }
      return ResponseBody.fromBytes(<int>[1, 2, 3, 4], 200);
    });
    final repo = _repository(adapter);

    final thumb = await repo.pageThumbnail('b1', 3);
    expect(thumb, <int>[9, 9, 1]);
    expect(
      adapter.requests.single.uri.path,
      '/api/v1/books/b1/pages/3/thumbnail',
    );
    expect(identical(repo.cachedPageThumbnail('b1', 3), thumb), isTrue);

    // 命中内存缓存时不发第二次网络请求。
    final again = await repo.pageThumbnail('b1', 3);
    expect(identical(again, thumb), isTrue);
    expect(adapter.requests, hasLength(1));

    // 低清缩略图不可用时（例如离线已下载整本），回退到 pageImage。
    failThumbnail = true;
    final fallback = await repo.pageThumbnail('b1', 4);
    expect(fallback, <int>[1, 2, 3, 4]);
    expect(
      adapter.requests.map((RequestOptions r) => r.uri.path),
      containsAllInOrder(<String>[
        '/api/v1/books/b1/pages/4/thumbnail',
        '/api/v1/books/b1/pages/4',
      ]),
    );
  });
}
