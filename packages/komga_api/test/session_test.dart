import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:test/test.dart';

/// 假的 dio 适配器：不发网络请求，按路径返回预设响应。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

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

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
  },
);

Dio _dioWith(_FakeAdapter adapter) => Dio()..httpClientAdapter = adapter;

void main() {
  final address = ServerAddress.parse('https://komga.example.com');

  group('withBasic', () {
    test('发 Basic Auth 头，并解析库列表', () async {
      final adapter = _FakeAdapter(
        (RequestOptions o) async => _json(<Object?>[
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
        dio: _dioWith(adapter),
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
      final adapter = _FakeAdapter(
        (RequestOptions o) async => _json(<Object?>[]),
      );
      final session = KomgaSession.withBasic(
        address: ServerAddress.parse('https://host/komga'),
        username: 'u',
        password: 'p',
        dio: _dioWith(adapter),
      );
      await session.fetchLibraries();
      expect(
        adapter.requests.single.uri.toString(),
        'https://host/komga/api/v1/libraries',
      );
    });

    test('401 折叠成认证错误（UI 提示"账号或密码不对"）', () async {
      final adapter = _FakeAdapter(
        (RequestOptions o) async => _json(<String, Object?>{}, status: 401),
      );
      final session = KomgaSession.withBasic(
        address: address,
        username: 'u',
        password: 'bad',
        dio: _dioWith(adapter),
      );
      expect(session.fetchLibraries(), throwsA(isA<KomgaAuthError>()));
    });

    test('500 折叠成服务端错误（可重试）', () async {
      final adapter = _FakeAdapter(
        (RequestOptions o) async => _json(<String, Object?>{}, status: 503),
      );
      final session = KomgaSession.withBasic(
        address: address,
        username: 'u',
        password: 'p',
        dio: _dioWith(adapter),
      );
      expect(session.fetchLibraries(), throwsA(isA<KomgaServerError>()));
    });

    test('连接失败折叠成网络错误', () async {
      final adapter = _FakeAdapter(
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
        dio: _dioWith(adapter),
      );
      expect(session.fetchLibraries(), throwsA(isA<KomgaNetworkError>()));
    });

    test('响应不是数组时抛协议错误（例如反代返回了 HTML）', () async {
      final adapter = _FakeAdapter(
        (RequestOptions o) async => _json(<String, Object?>{'oops': true}),
      );
      final session = KomgaSession.withBasic(
        address: address,
        username: 'u',
        password: 'p',
        dio: _dioWith(adapter),
      );
      expect(session.fetchLibraries(), throwsA(isA<KomgaProtocolError>()));
    });
  });

  group('withApiKey', () {
    test('发 X-API-Key 头并解析账号', () async {
      final adapter = _FakeAdapter(
        (RequestOptions o) async => _json(<String, Object?>{
          'id': 'u1',
          'email': 'me@example.com',
          'roles': <String>['ADMIN', 'USER'],
        }),
      );
      final session = KomgaSession.withApiKey(
        address: address,
        apiKey: 'KEY-123',
        dio: _dioWith(adapter),
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
      final adapter = _FakeAdapter((RequestOptions o) async {
        final body = jsonDecode(jsonEncode(o.data)) as Map<String, Object?>;
        expect(body['comment'], 'KomgaNative (test)');
        return _json(<String, Object?>{
          'id': 'k1',
          'key': 'NEW-KEY',
          'comment': 'KomgaNative (test)',
        });
      });
      final session = KomgaSession.withBasic(
        address: address,
        username: 'u',
        password: 'p',
        dio: _dioWith(adapter),
      );

      final key = await session.createApiKey(comment: 'KomgaNative (test)');
      expect(key, 'NEW-KEY');
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.uri.path, '/api/v2/users/me/api-keys');
    });

    test('服务端没返回 key 时抛协议错误，不把空串存起来', () async {
      final adapter = _FakeAdapter(
        (RequestOptions o) async => _json(<String, Object?>{'id': 'k1'}),
      );
      final session = KomgaSession.withBasic(
        address: address,
        username: 'u',
        password: 'p',
        dio: _dioWith(adapter),
      );
      expect(
        session.createApiKey(comment: 'x'),
        throwsA(isA<KomgaProtocolError>()),
      );
    });
  });
}
