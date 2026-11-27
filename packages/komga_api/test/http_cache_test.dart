import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:komga_api/komga_api.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:test/test.dart';

import 'support/fake_http.dart';

/// 内存版缓存：只验证"传输层的回退决策"，不验证存储（那是 app 层的事）。
class FakeCache implements HttpCache {
  FakeCache({this.failOnWrite = false, this.failOnRead = false});

  final bool failOnWrite;
  final bool failOnRead;

  final Map<String, Uint8List> entries = <String, Uint8List>{};
  final Set<String> pinnedKeys = <String>{};
  final List<String> reads = <String>[];
  final List<String> writes = <String>[];
  CacheKind? lastKind;
  int onlineReports = 0;
  int offlineReports = 0;
  final List<RequestPriority> onlinePriorities = <RequestPriority>[];
  final List<RequestPriority> offlinePriorities = <RequestPriority>[];

  String _key(String scope, String url) => '$scope|$url';

  @override
  Future<Uint8List?> read(String scope, String url) async {
    reads.add(_key(scope, url));
    if (failOnRead) throw const FileSystemException('模拟磁盘读失败');
    return entries[_key(scope, url)];
  }

  @override
  Future<Uint8List?> readPinned(String scope, String url) async {
    final key = _key(scope, url);
    if (!pinnedKeys.contains(key)) return null;
    reads.add(key);
    if (failOnRead) throw const FileSystemException('模拟磁盘读失败');
    return entries[key];
  }

  @override
  Future<void> write(
    String scope,
    String url,
    CacheKind kind,
    Uint8List body,
  ) async {
    writes.add(_key(scope, url));
    lastKind = kind;
    if (failOnWrite) throw const FileSystemException('模拟磁盘写失败');
    entries[_key(scope, url)] = body;
  }

  @override
  void reportOnline(
    String scope, {
    RequestPriority priority = RequestPriority.primary,
  }) {
    onlineReports++;
    onlinePriorities.add(priority);
  }

  @override
  void reportOffline(
    String scope, {
    RequestPriority priority = RequestPriority.primary,
  }) {
    offlineReports++;
    offlinePriorities.add(priority);
  }
}

/// 断网：适配器直接抛 dio 的连接错误（与真机上 SocketException 折叠后同类）。
Dio offlineDio() => dioWith(
  FakeAdapter(
    (RequestOptions options) async => throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message: 'connection refused',
    ),
  ),
);

Dio dio(FakeAdapter adapter) => dioWith(adapter);

void main() {
  final address = ServerAddress.parse('https://komga.example.com');
  const librariesBody = <Object?>[
    <String, Object?>{'id': 'lib1', 'name': 'Comics', 'unavailable': false},
  ];

  KomgaSession sessionWith(Dio d, {HttpCache? cache}) =>
      KomgaSession.withApiKey(
        address: address,
        apiKey: 'key',
        dio: d,
        cache: cache,
      );

  group('JSON 缓存', () {
    test('成功响应写入缓存，键是完整 URL（含查询串）', () async {
      final cache = FakeCache();
      final session = sessionWith(
        dio(FakeAdapter((_) async => jsonResponse(librariesBody))),
        cache: cache,
      );

      await session.fetchLibraries();

      expect(cache.writes.single, contains('/api/v1/libraries'));
      expect(cache.lastKind, CacheKind.json);
      expect(cache.onlineReports, 1);
      expect(cache.offlineReports, 0);
    });

    test('搜索参数不同 → 缓存键不同（不会把搜索结果串到首页）', () async {
      final cache = FakeCache();
      final session = sessionWith(
        dio(
          FakeAdapter(
            (_) async => jsonResponse(<String, Object?>{
              'content': <Object?>[],
              'totalElements': 0,
              'number': 0,
              'size': 20,
            }),
          ),
        ),
        cache: cache,
      );

      await session.fetchSeries(search: 'naruto');
      await session.fetchSeries();

      expect(cache.writes, hasLength(2));
      expect(cache.writes.first, contains('search=naruto'));
      expect(cache.writes.last, isNot(contains('search=')));
    });

    test('断网时回退到缓存，并上报离线', () async {
      final cache = FakeCache();
      final warm = sessionWith(
        dio(FakeAdapter((_) async => jsonResponse(librariesBody))),
        cache: cache,
      );
      await warm.fetchLibraries();

      final offline = sessionWith(offlineDio(), cache: cache);
      final libraries = await offline.fetchLibraries();

      expect(libraries.single.name, 'Comics');
      expect(cache.offlineReports, 1);
      // 反向验证不是假通过：缓存里确实只有一条、且被读过。
      expect(cache.reads, hasLength(1));
    });

    test('缓存未命中：仍然抛网络错误，不能编造数据', () async {
      final cache = FakeCache();
      final offline = sessionWith(offlineDio(), cache: cache);

      await expectLater(
        offline.fetchLibraries(),
        throwsA(isA<KomgaNetworkError>()),
      );
      expect(cache.offlineReports, 1);
    });

    test('404 不回退：资源真被删了，不能拿旧数据糊弄', () async {
      final cache = FakeCache();
      cache.entries['${address.baseUrl}|${KomgaUrls(address.baseUrl).libraries()}'] =
          Uint8List.fromList(utf8.encode(jsonEncode(librariesBody)));

      final session = sessionWith(
        dio(
          FakeAdapter(
            (_) async => jsonResponse(<String, Object?>{}, status: 404),
          ),
        ),
        cache: cache,
      );

      await expectLater(
        session.fetchLibraries(),
        throwsA(isA<KomgaNotFoundError>()),
      );
      expect(cache.reads, isEmpty);
      expect(cache.offlineReports, 0);
    });

    test('401 不回退：这是登录态问题，不是离线', () async {
      final cache = FakeCache();
      final session = sessionWith(
        dio(
          FakeAdapter(
            (_) async => jsonResponse(<String, Object?>{}, status: 401),
          ),
        ),
        cache: cache,
      );

      await expectLater(
        session.fetchLibraries(),
        throwsA(isA<KomgaAuthError>()),
      );
      expect(cache.reads, isEmpty);
    });

    test('5xx 回退（服务端临时炸了，旧内容比错误页有用）', () async {
      final cache = FakeCache();
      final warm = sessionWith(
        dio(FakeAdapter((_) async => jsonResponse(librariesBody))),
        cache: cache,
      );
      await warm.fetchLibraries();

      final broken = sessionWith(
        dio(
          FakeAdapter(
            (_) async => jsonResponse(<String, Object?>{}, status: 503),
          ),
        ),
        cache: cache,
      );
      final libraries = await broken.fetchLibraries();

      expect(libraries, hasLength(1));
      expect(cache.offlineReports, 1);
    });
  });

  group('字节缓存', () {
    test('页图按 image 类型缓存，断网可读回同一份字节', () async {
      const body = <int>[1, 2, 3, 4];
      final cache = FakeCache();
      final warm = sessionWith(
        dio(FakeAdapter((_) async => bytesResponse(body))),
        cache: cache,
      );

      final first = await warm.fetchPageImage('book1', 1);
      expect(first, body);
      expect(cache.lastKind, CacheKind.image);

      final offline = sessionWith(offlineDio(), cache: cache);
      final cached = await offline.fetchPageImage('book1', 1);
      expect(cached, body);
    });

    test('不同页码是不同缓存键', () async {
      final cache = FakeCache();
      final session = sessionWith(
        dio(FakeAdapter((_) async => bytesResponse(<int>[7]))),
        cache: cache,
      );

      await session.fetchPageImage('book1', 1);
      await session.fetchPageImage('book1', 2);

      expect(cache.writes, hasLength(2));
      expect(cache.writes[0], endsWith('/pages/1?zero_based=false'));
      expect(cache.writes[1], endsWith('/pages/2?zero_based=false'));
    });

    test('已整本下载（pinned）的页图直接命中本地缓存，不发网络请求', () async {
      const body = <int>[9, 8, 7, 6];
      final cache = FakeCache();
      final url = KomgaUrls(address.baseUrl).pageImage('book1', 1);
      final key = '${address.baseUrl}|$url';
      cache.entries[key] = Uint8List.fromList(body);
      cache.pinnedKeys.add(key);

      var networkCalls = 0;
      final session = sessionWith(
        dio(
          FakeAdapter((_) async {
            networkCalls++;
            return bytesResponse(<int>[0]);
          }),
        ),
        cache: cache,
      );

      final result = await session.fetchPageImage('book1', 1);
      expect(result, body);
      expect(networkCalls, 0, reason: 'pinned 页图应走 Cache-First 零流量');
    });

    test('封面/页缩略图上报 decorative 优先级，正文页图与 JSON 上报 primary', () async {
      final cache = FakeCache();
      final online = sessionWith(
        dio(FakeAdapter((_) async => bytesResponse(<int>[1, 2]))),
        cache: cache,
      );
      await online.fetchSeriesThumbnail('s1');
      await online.fetchBookThumbnail('b1');
      await online.fetchPageThumbnail('b1', 1);
      await online.fetchPageImage('b1', 1);

      expect(cache.onlinePriorities, <RequestPriority>[
        RequestPriority.decorative,
        RequestPriority.decorative,
        RequestPriority.decorative,
        RequestPriority.primary,
      ]);

      final offline = sessionWith(offlineDio(), cache: cache);
      await offline.fetchSeriesThumbnail('s1');
      await offline.fetchPageImage('b1', 1);
      expect(cache.offlinePriorities, <RequestPriority>[
        RequestPriority.decorative,
        RequestPriority.primary,
      ]);
    });
  });

  group('缓存本身出问题不能拖垮在线请求', () {
    test('写缓存抛异常，请求仍然成功', () async {
      final cache = FakeCache(failOnWrite: true);
      final session = sessionWith(
        dio(FakeAdapter((_) async => jsonResponse(librariesBody))),
        cache: cache,
      );

      final libraries = await session.fetchLibraries();
      expect(libraries, hasLength(1));
    });

    test('读缓存抛异常，按未命中处理', () async {
      final cache = FakeCache(failOnRead: true);
      final offline = sessionWith(offlineDio(), cache: cache);

      await expectLater(
        offline.fetchLibraries(),
        throwsA(isA<KomgaNetworkError>()),
      );
    });
  });
}
