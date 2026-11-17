import 'package:dio/dio.dart';
import 'package:komga_api/komga_api.dart';
import 'package:test/test.dart';

void main() {
  group('KomgaUrls', () {
    test('去掉 baseUrl 结尾斜杠，支持子路径部署', () {
      expect(KomgaUrls('https://x.dev/komga/').base, 'https://x.dev/komga');
      expect(
        KomgaUrls('https://x.dev/komga/').libraries(),
        'https://x.dev/komga/api/v1/libraries',
      );
      expect(KomgaUrls(' https://x.dev ').base, 'https://x.dev');
    });

    test('页图默认 1 基，并可切 jpeg 转换', () {
      final urls = KomgaUrls('https://x.dev');
      expect(
        urls.pageImage('b1', 3),
        'https://x.dev/api/v1/books/b1/pages/3?zero_based=false',
      );
      expect(
        urls.pageImage('b1', 3, convertToJpeg: true),
        'https://x.dev/api/v1/books/b1/pages/3?zero_based=false&convert=jpeg',
      );
    });

    test('查询参数做 URL 编码（搜索词含空格/中文）', () {
      final urls = KomgaUrls('https://x.dev');
      final url = urls.series(search: '葬送的芙莉莲 1');
      expect(url, contains('search=%E8%91%AC%E9%80%81'));
      expect(url, contains('page=0'));
      expect(url, contains('size=20'));
    });

    test('空搜索词不写入查询串', () {
      expect(
        KomgaUrls('https://x.dev').series(search: ''),
        isNot(contains('search')),
      );
    });
  });

  group('mapDioException', () {
    DioException make(DioExceptionType type, {int? status}) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      response: status == null
          ? null
          : Response<Object?>(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: status,
            ),
    );

    test('401/403 折叠为认证错误（不可重试）', () {
      expect(
        mapDioException(make(DioExceptionType.badResponse, status: 401)),
        isA<KomgaAuthError>(),
      );
      expect(
        mapDioException(make(DioExceptionType.badResponse, status: 403)),
        isA<KomgaAuthError>(),
      );
    });

    test('404 / 5xx / 其它状态码分别映射', () {
      expect(
        mapDioException(make(DioExceptionType.badResponse, status: 404)),
        isA<KomgaNotFoundError>(),
      );
      expect(
        mapDioException(make(DioExceptionType.badResponse, status: 503)),
        isA<KomgaServerError>(),
      );
      expect(
        mapDioException(make(DioExceptionType.badResponse, status: 400)),
        isA<KomgaBadRequestError>(),
      );
    });

    test('超时与连接失败映射为网络错误', () {
      expect(
        mapDioException(make(DioExceptionType.connectionTimeout)),
        isA<KomgaNetworkError>(),
      );
      expect(
        mapDioException(make(DioExceptionType.connectionError)),
        isA<KomgaNetworkError>(),
      );
    });

    test('取消映射为取消错误（翻页竞态下不应弹提示）', () {
      expect(
        mapDioException(make(DioExceptionType.cancel)),
        isA<KomgaCancelledError>(),
      );
    });
  });
}
