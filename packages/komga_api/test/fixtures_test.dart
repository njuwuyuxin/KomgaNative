import 'package:komga_api/komga_api.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:test/test.dart';

import 'support/fake_http.dart';
import 'support/fixtures.dart';

/// 用**真实服务器响应**（`test/fixtures/` 从 Komga 1.30.1 实例抓取）驱动解析层。
///
/// 假实现证明"我调了我以为的方法"；这一组测试证明"我以为的响应形状是真的"。
/// 字段名、类型、时间戳格式的每一处假设，都能在这里被真实 payload 打红。
const String _base = 'https://komga.example.com';

KomgaSession _sessionWith(
  FakeAdapter adapter, {
  bool basic = false,
  String apiKey = 'TESTKEY',
}) {
  final address = ServerAddress.parse(_base);
  return basic
      ? KomgaSession.withBasic(
          address: address,
          username: 'u',
          password: 'p',
          dio: dioWith(adapter),
        )
      : KomgaSession.withApiKey(
          address: address,
          apiKey: apiKey,
          dio: dioWith(adapter),
        );
}

FakeAdapter _replay(String body, {int status = 200}) =>
    FakeAdapter((_) async => rawResponse(body, status: status));

void main() {
  group('真实响应 → 领域模型', () {
    test('库列表：裸数组，字段 id/name/unavailable', () async {
      final session = _sessionWith(_replay(fixture('libraries.json')));
      final libraries = await session.fetchLibraries();

      expect(libraries, hasLength(1));
      expect(libraries.single.name, 'Verify');
      expect(libraries.single.id, isNotEmpty);
      expect(libraries.single.unavailable, isFalse);
    });

    test('收藏集：真实响应带 seriesIds / ordered / 时间', () async {
      final session = _sessionWith(_replay(fixture('collections.json')));
      final page = await session.fetchCollections();
      expect(page.totalElements, 1);
      final collection = page.items.single;
      expect(collection.name, 'Test Collection');
      expect(collection.ordered, isFalse);
      expect(collection.seriesIds, hasLength(2));
      expect(collection.createdDate, isNotNull);
    });

    test('收藏集里的系列按真实响应解析', () async {
      final session = _sessionWith(_replay(fixture('collection-series.json')));
      final page = await session.fetchCollectionSeries('C1');
      expect(page.items, hasLength(2));
      expect(page.items.first.title, 'Akira v01');
    });

    test('阅读列表：summary / bookIds', () async {
      final session = _sessionWith(_replay(fixture('readlists.json')));
      final page = await session.fetchReadLists();
      final list = page.items.single;
      expect(list.name, 'Test ReadList');
      expect(list.summary, 'Two books for tests');
      expect(list.bookIds, hasLength(2));
    });

    test('阅读列表里的书按真实响应解析', () async {
      final session = _sessionWith(_replay(fixture('readlist-books.json')));
      final page = await session.fetchReadListBooks('R1');
      expect(page.items, hasLength(2));
      expect(page.items.first.name, 'Akira v01');
    });

    test('系列所属收藏集：真实响应为裸数组', () async {
      final session = _sessionWith(_replay(fixture('series_collections.json')));
      final collections = await session.fetchSeriesCollections('S1');
      expect(collections, hasLength(1));
      expect(collections.single.name, 'Test Collection');
      expect(collections.single.seriesIds, hasLength(2));
    });

    test('书籍所属阅读列表：真实响应为裸数组', () async {
      final session = _sessionWith(_replay(fixture('book_readlists.json')));
      final lists = await session.fetchBookReadLists('B1');
      expect(lists, hasLength(1));
      expect(lists.single.name, 'Test ReadList');
      expect(lists.single.bookIds, hasLength(2));
    });

    test('新建阅读列表：解析真实 200 响应并携带 name/summary/ordered/bookIds', () async {
      final adapter = FakeAdapter(
        (_) async => rawResponse(fixture('readlist_created_200.json')),
      );
      final session = _sessionWith(adapter);
      final created = await session.createReadList(
        name: 'ApiVerifyRL',
        summary: 'test summary',
        bookIds: const <String>['0S8NJYAVHZCCY', '0S8NJYAVNZ9DF'],
      );
      expect(created.name, 'ApiVerifyRL');
      expect(created.summary, 'test summary');
      expect(created.bookIds, hasLength(2));
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.data, <String, Object?>{
        'name': 'ApiVerifyRL',
        'summary': 'test summary',
        'ordered': false,
        'bookIds': const <String>['0S8NJYAVHZCCY', '0S8NJYAVNZ9DF'],
      });
    });

    test('更新收藏集 seriesIds 与更新/删除阅读列表发送正确载荷', () async {
      final adapter = FakeAdapter((_) async => rawResponse('', status: 204));
      final session = _sessionWith(adapter);

      await session.updateCollection(
        'C1',
        seriesIds: const <String>['S1', 'S2'],
      );
      await session.updateReadList(
        'R1',
        name: 'Renamed',
        summary: 'New desc',
        bookIds: const <String>['B1'],
      );
      await session.deleteReadList('R1');

      expect(adapter.requests, hasLength(3));
      expect(adapter.requests[0].method, 'PATCH');
      expect(adapter.requests[0].data, <String, Object?>{
        'seriesIds': const <String>['S1', 'S2'],
      });
      expect(adapter.requests[1].method, 'PATCH');
      expect(adapter.requests[1].data, <String, Object?>{
        'name': 'Renamed',
        'summary': 'New desc',
        'bookIds': const <String>['B1'],
      });
      expect(adapter.requests[2].method, 'DELETE');
    });

    test('书籍搜索：/books?search= 返回 PageBookDto', () async {
      final session = _sessionWith(_replay(fixture('books-search.json')));
      final page = await session.searchBooks('akira');
      expect(page.items, hasLength(1));
      expect(page.items.single.name, 'Akira v01');
      expect(page.items.single.seriesId, isNotEmpty);
    });

    test('账号：没有 username 字段，用 email 作展示名', () async {
      final session = _sessionWith(_replay(fixture('users_me.json')));
      final account = await session.fetchAccount();

      expect(account.email, 'komga@example.com');
      expect(account.displayName, 'komga@example.com');
      expect(account.roles, contains('ADMIN'));
      expect(account.isAdmin, isTrue);
    });

    test('系列分页：readingDirection 解析成 RTL，标题取 metadata.title', () async {
      final session = _sessionWith(_replay(fixture('series_page.json')));
      final page = await session.fetchSeries();

      expect(page.totalElements, 1);
      expect(page.items, hasLength(1));
      expect(page.page, 0);
      expect(page.size, 20);
      expect(page.totalPages, 1);
      expect(page.hasMore, isFalse);

      final series = page.items.single;
      expect(series.title, 'library');
      expect(series.readingDirection, ReadingDirection.rightToLeft);
      expect(series.booksCount, 1);
      expect(series.booksReadCount, 0);
      expect(series.progress, 0);
      // 真实响应里这本书的作者/标签/出版日期都是空，解析层要给出空集合而不是 null 崩溃。
      expect(series.authors, isEmpty);
      expect(series.tags, isEmpty);
      expect(series.releaseDate, isNull);
    });

    test('系列元数据：作者 / 出版社 / 出版日期 / 标签（UI-P2-4）', () {
      // 这两项在真实 fixture 里是空的（那个测试库没填元数据），所以这里用构造的
      // 响应验证**字段映射**：结构照 OpenAPI 的 SeriesDto + BookMetadataAggregationDto。
      final series = seriesFromJson(<Object?, Object?>{
        'id': 'S1',
        'libraryId': 'L1',
        'name': 'folder-name',
        'booksCount': 3,
        'booksReadCount': 1,
        'metadata': <Object?, Object?>{
          'title': 'Frieren',
          'publisher': 'Shogakukan',
          'summary': '系列简介',
          'readingDirection': 'RIGHT_TO_LEFT',
        },
        'booksMetadata': <Object?, Object?>{
          'summary': '来自书籍的简介',
          'releaseDate': '2019-04-15',
          'authors': <Object?>[
            <Object?, Object?>{'name': 'Kanehito Yamada', 'role': 'WRITER'},
            <Object?, Object?>{'name': 'Tsukasa Abe', 'role': 'PENCILLER'},
            <Object?, Object?>{'name': 'Kanehito Yamada', 'role': 'WRITER'},
            <Object?, Object?>{'role': 'WRITER'},
          ],
          'tags': <Object?>['fantasy', 42, 'adventure'],
        },
      });

      expect(series.title, 'Frieren');
      expect(series.summary, '系列简介', reason: '系列自己的简介优先于书籍聚合的');
      expect(series.publisher, 'Shogakukan');
      expect(series.authors, <String>['Kanehito Yamada', 'Tsukasa Abe']);
      expect(series.tags, <String>['fantasy', 'adventure']);
      expect(series.releaseDate, DateTime(2019, 4, 15));
      expect(series.readingDirection, ReadingDirection.rightToLeft);
    });

    test('系列没有自己的简介时退回书籍聚合的简介', () {
      final series = seriesFromJson(<Object?, Object?>{
        'id': 'S1',
        'libraryId': 'L1',
        'name': 'Frieren',
        'metadata': <Object?, Object?>{'title': 'Frieren'},
        'booksMetadata': <Object?, Object?>{'summary': '来自书籍的简介'},
      });
      expect(series.summary, '来自书籍的简介');
      expect(series.publisher, isNull);
      expect(series.authors, isEmpty);
    });

    test('系列下的书：pagesCount / mediaProfile / number（服务器给的是 int）', () async {
      final session = _sessionWith(_replay(fixture('series_books_page.json')));
      final page = await session.fetchSeriesBooks('S1');

      expect(page.totalElements, 1);
      final book = page.items.single;
      expect(book.name, 'Verify Series #1');
      expect(book.pagesCount, 3);
      expect(book.mediaProfile, MediaProfile.divina);
      // OpenAPI 声明 string，服务器实际返回 int 1。
      expect(book.number, '1');
      expect(book.isUnread, isTrue);
    });

    test('未读的书：readProgress 为 null', () async {
      final session = _sessionWith(_replay(fixture('book_unread.json')));
      final book = await session.fetchBook('B1');

      expect(book.readProgress, isNull);
      expect(book.isUnread, isTrue);
      expect(book.isCompleted, isFalse);
      expect(book.pagesCount, 3);
    });

    test('在读的书：页码 1 基、带服务端时间戳', () async {
      final session = _sessionWith(_replay(fixture('book_in_progress.json')));
      final book = await session.fetchBook('B1');

      final progress = book.readProgress;
      expect(progress, isNotNull);
      expect(progress?.page, 2);
      expect(progress?.completed, isFalse);
      expect(progress?.lastModified.year, 2026);
      expect(book.isUnread, isFalse);
      // `seriesTitle` 来自真实响应（FIX-06）：离开系列页后要靠它补上下文。
      expect(book.seriesTitle, 'library');
    });

    test('搜索结果里的书也带 seriesTitle', () async {
      final session = _sessionWith(_replay(fixture('books-search.json')));
      final page = await session.searchBooks('verify');

      expect(page.items, isNotEmpty);
      expect(page.items.first.seriesTitle, isNotEmpty);
    });

    test('页列表：宽高/字节数可用，供双页排版算宽高比', () async {
      final session = _sessionWith(_replay(fixture('book_pages.json')));
      final pages = await session.fetchBookPages('B1');

      expect(pages, hasLength(3));
      final first = pages.first;
      expect(first.number, 1);
      expect(first.width, 800);
      expect(first.height, 1200);
      expect(first.mediaType, 'image/png');
      expect(first.sizeBytes, greaterThan(0));
      expect(first.aspectRatio, closeTo(2 / 3, 0.001));
    });

    test('创建 API Key：取出 key 字段', () async {
      final session = _sessionWith(
        _replay(fixture('api_key_created.json')),
        basic: true,
      );
      final key = await session.createApiKey(comment: 'KomgaNative');

      expect(key, hasLength(32));
      expect(key, startsWith('TESTONLY'));
    });

    test(
      '在读列表：/books?read_status=IN_PROGRESS&sort=readProgress.readDate,desc',
      () async {
        final session = _sessionWith(
          _replay(fixture('books-in-progress.json')),
        );
        final page = await session.fetchInProgressBooks();

        expect(page.totalElements, 2);
        expect(page.items, hasLength(2));
        expect(page.items.first.name, 'Sunny v01');
        expect(page.items.last.name, 'Akira v01');
        for (final book in page.items) {
          expect(book.readProgress, isNotNull);
          expect(book.readProgress!.completed, isFalse);
        }
        expect(
          page.items.first.readProgress!.lastModified.isAfter(
            page.items.last.readProgress!.lastModified,
          ),
          isTrue,
        );
      },
    );

    test('ondeck 空页也能解析（空态 UI 用）', () async {
      final session = _sessionWith(_replay(fixture('ondeck.json')));
      final page = await session.fetchOndeck();

      expect(page.totalElements, 0);
      expect(page.items, isEmpty);
    });

    test('ondeck 有数据时返回上一卷已读完系列的首本未读（readProgress 为 null）', () async {
      final session = _sessionWith(_replay(fixture('ondeck-next.json')));
      final page = await session.fetchOndeck();

      expect(page.totalElements, 1);
      final next = page.items.single;
      expect(next.seriesTitle, 'Frieren');
      expect(next.name, 'Frieren v02');
      expect(next.number, '2');
      expect(next.readProgress, isNull);
      expect(next.isUnread, isTrue);
    });

    test('read_status=UNREAD 的真实响应可解析，且确实全是未读', () async {
      final session = _sessionWith(
        _replay(fixture('series-read-status-unread.json')),
      );
      final page = await session.fetchSeries(
        readStatus: SeriesReadStatus.unread,
      );

      expect(page.items, isNotEmpty);
      expect(page.items.every((Series s) => s.booksReadCount == 0), isTrue);
    });
  });

  group('错误体的多种形态（全部来自真实抓包）', () {
    Future<KomgaError> capturedError(String name, {int? status}) async {
      final session = _sessionWith(
        _replay(fixture(name), status: status ?? 200),
      );
      try {
        await session.fetchBook('B1');
        fail('应该抛错');
      } on KomgaError catch (error) {
        return error;
      }
    }

    test('401 → 认证错误', () async {
      final error = await capturedError('error_401.json', status: 401);
      expect(error, isA<KomgaAuthError>());
      expect(error.statusCode, 401);
    });

    test('404 → 未找到', () async {
      final error = await capturedError('error_404_book.json', status: 404);
      expect(error, isA<KomgaNotFoundError>());
    });

    test('400 带人类可读 message → 提取出来（页码越界）', () async {
      final error = await capturedError(
        'error_400_read_progress.json',
        status: 400,
      );
      expect(error, isA<KomgaBadRequestError>());
      expect(error.message, contains('must be within 1 and book page count'));
    });

    test('400 但 body 为空 → 仍然给出可读消息，不崩', () async {
      final error = await capturedError('empty_400.json', status: 400);
      expect(error, isA<KomgaBadRequestError>());
      expect(error.message, isNotEmpty);
    });

    test('400 + 机器码 ERR_1034 → 暴露 serverCode 供重试决策', () async {
      final error = await capturedError(
        'error_400_duplicate_comment.json',
        status: 400,
      );
      expect(error, isA<KomgaBadRequestError>());
      expect((error as KomgaBadRequestError).serverCode, 'ERR_1034');
    });
  });

  group('撞上 comment 唯一约束时自动换一个重试', () {
    test('第二次登录：首个请求 400 ERR_1034，重试带时间戳后成功', () async {
      var attempt = 0;
      final adapter = FakeAdapter((_) async {
        attempt++;
        return attempt == 1
            ? rawResponse(
                '{"timestamp":"2026-11-17T09:20:16Z","status":400,'
                '"error":"Bad Request","message":"ERR_1034",'
                '"path":"/api/v2/users/me/api-keys"}',
                status: 400,
              )
            : rawResponse(fixture('api_key_created.json'));
      });
      final session = _sessionWith(adapter, basic: true);

      final key = await session.createApiKey(comment: 'KomgaNative');

      expect(key, hasLength(32));
      expect(adapter.requests, hasLength(2));
      expect(
        (adapter.requests.first.data! as Map<String, Object?>)['comment'],
        'KomgaNative',
      );
      expect(
        (adapter.requests.last.data! as Map<String, Object?>)['comment'],
        startsWith('KomgaNative '),
      );
    });
  });

  group('解析容错', () {
    test('7 位小数的时间戳（服务器真实格式）能解析', () async {
      const body =
          '{"id":"b","seriesId":"s","name":"n","number":1,'
          '"media":{"pagesCount":2,"mediaProfile":"DIVINA"},'
          '"readProgress":{"page":1,"completed":false,'
          '"lastModified":"2026-11-17T09:19:11.9617379Z"}}';
      final session = _sessionWith(_replay(body));
      final book = await session.fetchBook('b');

      expect(book.readProgress, isNotNull);
      expect(
        book.readProgress?.lastModified.millisecondsSinceEpoch,
        DateTime.utc(2026, 11, 17, 9, 19, 11, 961, 737).millisecondsSinceEpoch,
      );
    });

    test('number 是字符串时原样保留（"1.5"）', () async {
      const body =
          '{"id":"b","seriesId":"s","name":"n","number":"1.5",'
          '"media":{"pagesCount":2,"mediaProfile":"DIVINA"}}';
      final session = _sessionWith(_replay(body));
      final book = await session.fetchBook('b');
      expect(book.number, '1.5');
    });

    test('readingDirection 为空串时退化成 unknown，不抛异常', () async {
      const body =
          '{"content":[{"id":"s","libraryId":"l","name":"x",'
          '"metadata":{"title":"x","readingDirection":""}}],'
          '"totalElements":1,"number":0,"size":20}';
      final session = _sessionWith(_replay(body));
      final page = await session.fetchSeries();

      expect(page.items.single.readingDirection, ReadingDirection.unknown);
    });
  });
}
