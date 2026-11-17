import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/library_repository.dart';
import 'package:komga_native/src/data/progress/progress_store.dart';
import 'package:komga_native/src/data/progress/progress_sync_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';

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
KomgaLibraryRepository _repository(_Adapter adapter) {
  final session = KomgaSession.withApiKey(
    address: ServerAddress.parse('https://komga.example.com'),
    apiKey: 'KEY',
    dio: Dio()..httpClientAdapter = adapter,
  );
  final sync = ProgressSyncService(
    store: InMemoryProgressStore(),
    upload: (ProgressTarget target) async {},
  );
  return KomgaLibraryRepository(session, sync);
}

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
  });
}
