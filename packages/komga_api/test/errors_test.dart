import 'dart:io';

import 'package:dio/dio.dart';
import 'package:komga_api/komga_api.dart';
import 'package:test/test.dart';

/// 这些用例全部对着**真实抓到的响应**（fixture）或真实异常形态写：
/// 反代的 HTML 错误页、dio 对证书过期给出的 `unknown + HandshakeException`。
void main() {
  DioException responseError(int status, Object? body) => DioException(
    requestOptions: RequestOptions(path: '/api/v1/libraries'),
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: RequestOptions(path: '/api/v1/libraries'),
      statusCode: status,
      data: body,
    ),
  );

  group('明文打到 HTTPS 端口（openresty 实测回 400 + HTML）', () {
    late String html;

    setUpAll(() {
      // 真实响应体，原样保存。
      html = File('test/fixtures/proxy-400-plain-http.html').readAsStringSync();
    });

    test('识别成 KomgaHttpsRequiredError，而不是普通 400', () {
      final error = mapDioException(responseError(400, html));
      expect(error, isA<KomgaHttpsRequiredError>());
      expect(error.statusCode, 400);
    });

    test('错误文案里带上反代原话，用户搜得到', () {
      final error = mapDioException(responseError(400, html));
      expect(error.message, contains('plain HTTP request was sent to HTTPS'));
      // HTML 标签必须被剥掉，不能把整页塞进一行提示。
      expect(error.message, isNot(contains('<')));
      expect(error.message, isNot(contains('\n')));
    });

    test('Apache 的同类提示也能识别', () {
      const apache =
          '<html><head><title>Bad Request</title></head><body>'
          "You're speaking plain HTTP to an SSL-enabled server port.</body></html>";
      expect(
        mapDioException(responseError(400, apache)),
        isA<KomgaHttpsRequiredError>(),
      );
    });

    test('其它 400 仍然走 KomgaBadRequestError（不误判）', () {
      final error = mapDioException(
        responseError(400, '{"message":"ERR_1034"}'),
      );
      expect(error, isA<KomgaBadRequestError>());
      expect((error as KomgaBadRequestError).serverCode, 'ERR_1034');
    });
  });

  group('反代返回 HTML 时的提示', () {
    test('从 <title> 里抠出人话，而不是只给一个 400', () {
      final error = mapDioException(
        responseError(502, '<html><title>502 Bad Gateway</title></html>'),
      );
      expect(error, isA<KomgaServerError>());
      expect(error.message, contains('502 Bad Gateway'));
    });

    test('HTML 实体被还原', () {
      final error = mapDioException(
        responseError(500, '<html><title>Tom &amp; Jerry</title></html>'),
      );
      expect(error.message, contains('Tom & Jerry'));
    });

    test('空 body 不产生空提示（实测 page=0 的 400 就是空 body）', () {
      final error = mapDioException(responseError(400, ''));
      expect(error.message, isNotEmpty);
      expect(error.message, isNot(contains('：')));
    });
  });

  group('证书错误', () {
    test('dio 把证书过期报成 unknown + HandshakeException，必须折叠成 KomgaTlsError', () {
      // 实测：Dart 不接受过期证书时 type 是 unknown，不是 badCertificate。
      final error = mapDioException(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.unknown,
          error: const HandshakeException(
            'Handshake error in client (OS Error: '
            'CERTIFICATE_VERIFY_FAILED: certificate has expired)',
          ),
        ),
      );
      expect(error, isA<KomgaTlsError>());
    });

    test('证书错误不能退化成"网络不可达"', () {
      final error = mapDioException(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
          error: const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
        ),
      );
      expect(error, isA<KomgaTlsError>());
    });
  });
}
