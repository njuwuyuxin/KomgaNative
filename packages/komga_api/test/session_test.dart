import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:test/test.dart';

import 'support/fake_http.dart';

void main() {
  final address = ServerAddress.parse('https://komga.example.com');

  group('withBasic', () {
    test('发 Basic Auth 头，并解析库列表', () async {
      final adapter = FakeAdapter(
        (_) async => jsonResponse(<Object?>[
          <String, Object?>{
            'id': 'lib1',
            'name': 'Comics',
            'unavailable': false,
          },
          <String, Object?>{'id': 'lib2', 'name': 'Manga'},
        ]),
      );
      final session = KomgaSession.withBasic(
        address: address,
        username: 'me@example.com',
        password: 'secret',
        dio: dioWith(adapter),
      );

      final libraries = await session.fetchLibraries();

      expect(libraries, hasLength(2));
      expect(libraries.first.name, 'Comics');
      expect(libraries[1].unavailable, isFalse);
      final auth = adapter.requests.single.headers['Authorization'] as String;
      expect(auth, startsWith('Basic '));
      expect(
        utf8.decode(base64Decode(auth.substring(6))),
        'me@example.com:secret',
      );
      expect(
        adapter.requests.single.uri.toString(),
        'https://komga.example.com/api/v1/libraries',
      );
    });

    test('保留反代子路径', () async {
      final adapter = FakeAdapter((_) async => jsonResponse(<Object?>[]));
      final session = KomgaSession.withBasic(
        address: ServerAddress.parse('https://host/komga'),
        username: 'u',
        password: 'p',
        dio: dioWith(adapter),
      );
      await session.fetchLibraries();
      expect(
        adapter.requests.single.uri.toString(),
        'https://host/komga/api/v1/libraries',
      );
    });

    test('401 折叠成认证错误（UI 提示"账号或密码不对"）', () async {
      final adapter = FakeAdapter(
        (_) async => jsonResponse(<String, Object?>{}, status: 401),
      );
      final session = KomgaSession.withBasic(
        address: address,
        username: 'u',
        password: 'bad',
        dio: dioWith(adapter),
      );
      expect(session.fetchLibraries(), throwsA(isA<KomgaAuthError>()));
    });

    test('500 折叠成服务端错误（可重试）', () async {
      final adapter = FakeAdapter(
        (_) async => jsonResponse(<String, Object?>{}, status: 503),
      );
      final session = KomgaSession.withBasic(
        address: address,
        username: 'u',
        password: 'p',
        dio: dioWith(adapter),
      );
      expect(session.fetchLibraries(), throwsA(isA<KomgaServerError>()));
    });

    test('连接失败折叠成网络错误', () async {
      final adapter = FakeAdapter(
        (RequestOptions o) async => throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
          message: 'refused',
        ),
      );
      final session = KomgaSession.withBasic(
        address: address,
        username: 'u',
        password: 'p',
        dio: dioWith(adapter),
      );
      expect(session.fetchLibraries(), throwsA(isA<KomgaNetworkError>()));
    });

    test('响应不是数组时抛协议错误（例如反代返回了 HTML）', () async {
      final adapter = FakeAdapter(
        (_) async => jsonResponse(<String, Object?>{'oops': true}),
      );
      final session = KomgaSession.withBasic(
        address: address,
        username: 'u',
        password: 'p',
        dio: dioWith(adapter),
      );
      expect(session.fetchLibraries(), throwsA(isA<KomgaProtocolError>()));
    });
  });

  group('withApiKey', () {
    test('发 X-API-Key 头并解析账号', () async {
      final adapter = FakeAdapter(
        (_) async => jsonResponse(<String, Object?>{
          'id': 'u1',
          'email': 'me@example.com',
          'roles': <String>['ADMIN', 'USER'],
        }),
      );
      final session = KomgaSession.withApiKey(
        address: address,
        apiKey: 'KEY-123',
        dio: dioWith(adapter),
      );

      final account = await session.fetchAccount();

      expect(account.email, 'me@example.com');
      expect(account.isAdmin, isTrue);
      expect(adapter.requests.single.headers['X-API-Key'], 'KEY-123');
      expect(
        adapter.requests.single.uri.toString(),
        'https://komga.example.com/api/v2/users/me',
      );
    });

    test('创建 API Key：发送 comment 并取出 key', () async {
      final adapter = FakeAdapter((RequestOptions o) async {
        final body = jsonDecode(jsonEncode(o.data)) as Map<String, Object?>;
        expect(body['comment'], 'KomgaNative (test)');
        return jsonResponse(<String, Object?>{
          'id': 'k1',
          'key': 'NEW-KEY',
          'comment': 'KomgaNative (test)',
        });
      });
      final session = KomgaSession.withBasic(
        address: address,
        username: 'u',
        password: 'p',
        dio: dioWith(adapter),
      );

      final key = await session.createApiKey(comment: 'KomgaNative (test)');
      expect(key, 'NEW-KEY');
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.uri.path, '/api/v2/users/me/api-keys');
    });

    test('服务端没返回 key 时抛协议错误，不把空串存起来', () async {
      final adapter = FakeAdapter(
        (_) async => jsonResponse(<String, Object?>{'id': 'k1'}),
      );
      final session = KomgaSession.withBasic(
        address: address,
        username: 'u',
        password: 'p',
        dio: dioWith(adapter),
      );
      expect(
        session.createApiKey(comment: 'x'),
        throwsA(isA<KomgaProtocolError>()),
      );
    });
  });

  group('阅读进度回写', () {
    KomgaSession sessionFor(FakeAdapter adapter) => KomgaSession.withApiKey(
      address: address,
      apiKey: 'K',
      dio: dioWith(adapter),
    );

    test('发 PATCH，页码与完成标记一起发', () async {
      final adapter = FakeAdapter(
        (_) async => ResponseBody.fromString('', 204),
      );
      await sessionFor(adapter)
          .updateReadProgress('b1', page: 3, completed: true);

      final request = adapter.requests.single;
      expect(request.method, 'PATCH');
      expect(request.uri.path, '/api/v1/books/b1/read-progress');
      expect(request.data, <String, Object>{'page': 3, 'completed': true});
    });

    test('只发 completed 时不带 page（服务端支持局部更新）', () async {
      final adapter = FakeAdapter(
        (_) async => ResponseBody.fromString('', 204),
      );
      await sessionFor(adapter).updateReadProgress('b1', completed: true);

      expect(adapter.requests.single.data, <String, Object>{'completed': true});
    });

    test('什么都不传就不发请求', () async {
      final adapter = FakeAdapter(
        (_) async => ResponseBody.fromString('', 204),
      );
      await sessionFor(adapter).updateReadProgress('b1');

      expect(adapter.requests, isEmpty);
    });

    test('400 折叠成可识别的请求错误', () async {
      final adapter = FakeAdapter(
        (_) async => rawResponse(
          '{"status":400,"message":"Page argument (0) must be within 1 and book page count (3)"}',
          status: 400,
        ),
      );

      expect(
        sessionFor(adapter).updateReadProgress('b1', page: 0),
        throwsA(isA<KomgaBadRequestError>()),
      );
    });
  });

  group('请求头按资源类型分离', () {
    KomgaSession sessionFor(FakeAdapter adapter) => KomgaSession.withApiKey(
      address: address,
      apiKey: 'K',
      dio: dioWith(adapter),
    );

    test('JSON 请求声明 Accept: application/json', () async {
      final adapter = FakeAdapter((_) async => jsonResponse(<Object?>[]));
      await sessionFor(adapter).fetchLibraries();

      expect(adapter.requests.single.headers['Accept'], 'application/json');
    });

    test('页图请求要字节 + 图片 Accept（实测服务器不认 application/json）', () async {
      final adapter = FakeAdapter(
        (_) async => bytesResponse(<int>[1, 2, 3], contentType: 'image/png'),
      );
      final bytes = await sessionFor(adapter).fetchPageImage('b1', 1);

      final request = adapter.requests.single;
      expect(bytes, <int>[1, 2, 3]);
      expect(request.responseType, ResponseType.bytes);
      expect(request.headers['Accept'], contains('image/'));
      expect(
        request.uri.toString(),
        'https://komga.example.com/api/v1/books/b1/pages/1?zero_based=false',
      );
    });

    test('缩略图只接受 image/jpeg，客户端不再发 application/json', () async {
      final adapter = FakeAdapter(
        (_) async => bytesResponse(<int>[9], contentType: 'image/jpeg'),
      );
      final bytes = await sessionFor(adapter).fetchSeriesThumbnail('s1');

      final request = adapter.requests.single;
      expect(bytes, <int>[9]);
      expect(request.headers['Accept'], contains('image/'));
      expect(request.headers['Accept'], contains('image/'));
    });

    test('去掉全局 Accept 后，JSON 与图片请求互不污染', () async {
      final adapter = FakeAdapter(
        (RequestOptions o) async => o.responseType == ResponseType.bytes
            ? bytesResponse(<int>[1])
            : jsonResponse(<Object?>[]),
      );
      final session = sessionFor(adapter);
      await session.fetchBookThumbnail('b1');
      await session.fetchLibraries();

      expect(adapter.requests.first.headers['Accept'], contains('image/'));
      expect(adapter.requests.last.headers['Accept'], 'application/json');
    });
  });
}
