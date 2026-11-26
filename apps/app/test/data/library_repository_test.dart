import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_api/komga_api.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu_sync/yomu_sync.dart';

/// 假的 dio 适配器：按路径回放响应并记录请求。
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

ResponseBody _rawJson(String body, {int status = 200}) =>
    ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

/// 仓库只做网络 + 叠加；测试里给一个"永远没有本地进度"的同步服务，
/// 叠加就不改变任何东西（本文件测的是 URL/解析，不是 outbox）。
KomgaLibraryRepository _repository(_Adapter adapter, {ProgressStore? store}) {
  final session = KomgaSession.withApiKey(
    address: ServerAddress.parse('https://komga.example.com'),
    apiKey: 'KEY',
    dio: Dio()..httpClientAdapter = adapter,
  );
  final sync = ProgressSyncService(
    store: store ?? InMemoryProgressStore(),
    upload: (ProgressTarget target) async {
      // 保留 pending 状态：测试离线未同步进度在各查询出口的叠加效果。
      throw const NetworkFailure();
    },
  );
  return KomgaLibraryRepository(session, sync);
}

String _bookJson({String id = 'b1', int remotePage = 2}) =>
    '{'
    '"id":"$id",'
    '"seriesId":"s1",'
    '"seriesTitle":"Frieren",'
    '"name":"Vol. 1",'
    '"number":1,'
    '"media":{"pagesCount":20},'
    '"readProgress":{"page":$remotePage,"completed":false,"lastModified":"2026-01-01T00:00:00Z"}'
    '}';

String _bookPageJson({String id = 'b1', int remotePage = 2}) =>
    '{"content":[${_bookJson(id: id, remotePage: remotePage)}],"totalElements":1,"number":0,"size":20}';

void main() {
  group('KomgaLibraryRepository', () {
    test('系列查询把 libraryId/query/分页透传成 Komga 参数', () async {
      final adapter = _Adapter(
        (_) async =>
            _rawJson('{"content":[],"totalElements":0,"number":2,"size":30}'),
      );
      final repository = _repository(adapter);

      await repository.series(libraryId: 'lib1', query: 'akira', page: 2);

      final uri = adapter.requests.single.uri;
      expect(uri.path, '/api/v1/series');
      expect(uri.queryParameters['page'], '2');
      expect(uri.queryParameters['size'], '30');
      expect(uri.queryParameters['library_id'], 'lib1');
      expect(uri.queryParameters['search'], 'akira');
      expect(adapter.requests.single.headers['X-API-Key'], 'KEY');
    });

    test('空 query 不写 search 参数（避免把"不过滤"当成搜索空串）', () async {
      final adapter = _Adapter(
        (_) async =>
            _rawJson('{"content":[],"totalElements":0,"number":0,"size":30}'),
      );
      await _repository(adapter).series(query: '');

      expect(
        adapter.requests.single.uri.queryParameters.containsKey('search'),
        isFalse,
      );
    });

    test('401 翻成 AuthFailure，而不是把 dio 细节漏给 UI', () async {
      final adapter = _Adapter(
        (_) async => _rawJson('{"message":"Unauthorized"}', status: 401),
      );

      expect(_repository(adapter).libraries(), throwsA(isA<AuthFailure>()));
    });

    test('连不上时翻成 NetworkFailure', () async {
      final adapter = _Adapter(
        (RequestOptions o) async => throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        ),
      );

      expect(_repository(adapter).series(), throwsA(isA<NetworkFailure>()));
    });

    test('5xx 翻成 ServerFailure（可重试）', () async {
      final adapter = _Adapter(
        (_) async => _rawJson('{"message":"boom"}', status: 503),
      );

      expect(_repository(adapter).series(), throwsA(isA<ServerFailure>()));
    });

    test('封面失败返回 null，绝不把异常抛给书架', () async {
      final adapter = _Adapter(
        (_) async => _rawJson('{"message":"boom"}', status: 500),
      );

      expect(await _repository(adapter).seriesCover('s1'), isNull);
    });

    test('封面成功会进缓存，第二次不再发请求', () async {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final adapter = _Adapter(
        (_) async => ResponseBody.fromBytes(
          bytes,
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['image/jpeg'],
          },
        ),
      );
      final repository = _repository(adapter);

      final first = await repository.seriesCover('s1');
      final second = await repository.seriesCover('s1');

      expect(first, bytes);
      expect(second, bytes);
      expect(adapter.requests, hasLength(1), reason: '第二次应命中 LRU 缓存');
      expect(adapter.requests.single.headers['Accept'], contains('image/'));
    });

    test('books() 把 sort 与 readStatus 透传到 /series/{id}/books 查询串', () async {
      final adapter = _Adapter(
        (_) async =>
            _rawJson('{"content":[],"totalElements":0,"number":1,"size":50}'),
      );
      final repository = _repository(adapter);

      await repository.books(
        's1',
        page: 1,
        size: 50,
        sort: BooksSort.numberDesc,
        readStatus: SeriesReadStatus.unread,
      );

      final uri = adapter.requests.single.uri;
      expect(uri.path, '/api/v1/series/s1/books');
      expect(uri.queryParameters['page'], '1');
      expect(uri.queryParameters['size'], '50');
      expect(uri.queryParameters['sort'], 'metadata.numberSort,desc');
      expect(uri.queryParameters['read_status'], 'UNREAD');
    });

    test('books() 未指定排序与筛选时不写 sort / read_status 参数', () async {
      final adapter = _Adapter(
        (_) async =>
            _rawJson('{"content":[],"totalElements":0,"number":0,"size":100}'),
      );
      await _repository(adapter).books('s1');

      final query = adapter.requests.single.uri.queryParameters;
      expect(query.containsKey('sort'), isFalse);
      expect(query.containsKey('read_status'), isFalse);
    });

    test('book(bookId) 在服务端返回 404 时遵守契约返回 null', () async {
      final adapter = _Adapter(
        (_) async => _rawJson('{"message":"Not Found"}', status: 404),
      );

      expect(await _repository(adapter).book('missing-book'), isNull);
    });

    test(
      'book / books / searchBooks / readListBooks / ondeck 均叠加本地未提交进度',
      () async {
        final store = InMemoryProgressStore();
        await store.enqueue(
          const ProgressTarget(bookId: 'b1', page: 17, completed: false),
          scope: 'https://komga.example.com',
        );
        final adapter = _Adapter((RequestOptions options) async {
          if (options.uri.path == '/api/v1/books/b1') {
            return _rawJson(_bookJson());
          }
          return _rawJson(_bookPageJson());
        });
        final repository = _repository(adapter, store: store);
        final collectionsRepo = KomgaCollectionsRepository(
          repository.debugSession,
          ProgressSyncService(
            store: store,
            upload: (ProgressTarget target) async {
              throw const NetworkFailure();
            },
          ),
        );

        final single = await repository.book('b1');
        final seriesBooks = await repository.books('s1');
        final searched = await repository.searchBooks('frieren');
        final readList = await collectionsRepo.readListBooks('rl-1');
        final ondeck = await repository.ondeck();

        expect(single?.readProgress?.page, 17);
        expect(seriesBooks.items.single.readProgress?.page, 17);
        expect(searched.items.single.readProgress?.page, 17);
        expect(readList.items.single.readProgress?.page, 17);
        expect(ondeck.items.single.readProgress?.page, 17);
      },
    );

    test('ondeck 优先返回 IN_PROGRESS 在读书，不同系列的 ondeck 下一卷排在后面', () async {
      final adapter = _Adapter((RequestOptions options) async {
        if (options.uri.path == '/api/v1/books') {
          expect(options.uri.queryParameters['read_status'], 'IN_PROGRESS');
          expect(
            options.uri.queryParameters['sort'],
            'readProgress.readDate,desc',
          );
          return _rawJson(
            '{"content":['
            '{"id":"s1-b1","seriesId":"s1","seriesTitle":"Frieren","name":"Vol. 1","number":1,'
            '"media":{"pagesCount":20},'
            '"readProgress":{"page":4,"completed":false,"lastModified":"2026-11-20T00:00:00Z"}}'
            '],"totalElements":1,"number":0,"size":20}',
          );
        }
        if (options.uri.path == '/api/v1/books/ondeck') {
          return _rawJson(
            '{"content":['
            '{"id":"s1-b2","seriesId":"s1","seriesTitle":"Frieren","name":"Vol. 2","number":2,'
            '"media":{"pagesCount":20},"readProgress":null},'
            '{"id":"s2-b2","seriesId":"s2","seriesTitle":"Akira","name":"Vol. 2","number":2,'
            '"media":{"pagesCount":18},"readProgress":null}'
            '],"totalElements":2,"number":0,"size":20}',
          );
        }
        throw StateError('unexpected path: ${options.uri.path}');
      });

      final page = await _repository(adapter).ondeck();
      // s1 已有在读书 s1-b1，同系列的 s1-b2 不重复占位；s2 无在读书，s2-b2 作为下一卷兜底。
      expect(page.items.map((Book b) => b.id), <String>['s1-b1', 's2-b2']);
    });

    test('本地刚读完但尚未同步时，从继续阅读剔除已读本并放行下一卷', () async {
      final store = InMemoryProgressStore();
      await store.enqueue(
        const ProgressTarget(bookId: 's1-b1', page: 20, completed: true),
        scope: 'https://komga.example.com',
      );
      final adapter = _Adapter((RequestOptions options) async {
        if (options.uri.path == '/api/v1/books') {
          return _rawJson(_bookPageJson(id: 's1-b1', remotePage: 19));
        }
        return _rawJson(
          '{"content":['
          '{"id":"s1-b2","seriesId":"s1","seriesTitle":"Frieren","name":"Vol. 2","number":2,'
          '"media":{"pagesCount":20},"readProgress":null}'
          '],"totalElements":1,"number":0,"size":20}',
        );
      });

      final page = await _repository(adapter, store: store).ondeck();
      expect(page.items.map((Book b) => b.id), <String>['s1-b2']);
    });

    test('同步失败时，本地刚打开的未读新书仍能出现在继续阅读首位', () async {
      final store = InMemoryProgressStore();
      final adapter = _Adapter((RequestOptions options) async {
        if (options.uri.path == '/api/v1/series/s1/books') {
          return _rawJson(
            '{"content":['
            '{"id":"s1-b1","seriesId":"s1","seriesTitle":"Frieren","name":"Vol. 1","number":1,'
            '"media":{"pagesCount":12},"readProgress":null}'
            '],"totalElements":1,"number":0,"size":100}',
          );
        }
        // 服务端尚未收到 PATCH，IN_PROGRESS 与 ondeck 仍为空。
        return _rawJson(
          '{"content":[],"totalElements":0,"number":0,"size":20}',
        );
      });

      final repository = _repository(adapter, store: store);
      // 用户先在系列页浏览过该书（缓存了 Book 元信息），随后打开第 1 页但 PATCH 断网失败。
      await repository.books('s1');
      await store.enqueue(
        const ProgressTarget(bookId: 's1-b1', page: 1, completed: false),
        scope: 'https://komga.example.com',
      );

      final page = await repository.ondeck();
      expect(page.items, hasLength(1));
      expect(page.items.single.id, 's1-b1');
      expect(page.items.single.readProgress?.page, 1);
      expect(page.items.single.readProgress?.completed, isFalse);
    });
  });
}
