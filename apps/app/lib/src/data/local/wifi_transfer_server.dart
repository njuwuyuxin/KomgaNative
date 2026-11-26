import 'dart:async';
import 'dart:io';

import 'package:yomu/src/data/local/local_comic_importer.dart';
import 'package:yomu/src/data/local/wifi_transfer_handlers.dart';
import 'package:yomu/src/data/local/wifi_transfer_html.dart';

export 'package:yomu/src/data/local/wifi_transfer_handlers.dart'
    show discoverLanIpv4Addresses;

enum WifiTransferEventKind { receiving, imported, failed }

/// 局域网 Wi-Fi 传书服务端产生的单条实时事件（供 UI 与 Provider 订阅刷新书架）。
final class WifiTransferEvent {
  const WifiTransferEvent({
    required this.fileName,
    required this.kind,
    required this.timestamp,
    this.importedCount = 0,
    this.errorDetail,
  });

  final String fileName;
  final WifiTransferEventKind kind;
  final DateTime timestamp;
  final int importedCount;
  final String? errorDetail;
}

/// 内置局域网 HTTP Wi-Fi 传书服务端（纯 `dart:io`，零外部依赖，LMB-07）。
///
/// 流式落盘上传的压缩包或图片目录，直接委托 [LocalComicImporter] 校验并入库，
/// 完成后立即清理暂存目录，可选 4 位 PIN 防局域网误连。
final class WifiTransferServer {
  WifiTransferServer({
    required LocalComicImporter importer,
    Future<Directory> Function()? stagingRootResolver,
    Future<List<String>> Function()? lanAddressesResolver,
  }) : _importer = importer,
       _stagingRootResolver = stagingRootResolver,
       _lanAddressesResolver = lanAddressesResolver ?? discoverLanIpv4Addresses;

  final LocalComicImporter _importer;
  final Future<Directory> Function()? _stagingRootResolver;
  final Future<List<String>> Function() _lanAddressesResolver;
  final StreamController<WifiTransferEvent> _events =
      StreamController<WifiTransferEvent>.broadcast();

  HttpServer? _server;
  Directory? _stagingDir;
  String? _pin;
  int _receivedCount = 0;

  Stream<WifiTransferEvent> get events => _events.stream;
  bool get isRunning => _server != null;
  int? get port => _server?.port;
  int get receivedCount => _receivedCount;
  String? get pin => _pin;

  void setPin(String? pin) {
    final cleaned = pin?.trim() ?? '';
    _pin = cleaned.isEmpty ? null : cleaned;
  }

  /// 启动 HTTP 传书服务，返回可供浏览器访问的完整 URL 列表。
  Future<List<String>> start({
    InternetAddress? bindAddress,
    int preferredPort = 8080,
    String? pin,
  }) async {
    if (_server != null) {
      return _buildUrls(_server!.port);
    }
    setPin(pin);
    final addr = bindAddress ?? InternetAddress.anyIPv4;
    HttpServer bound;
    try {
      bound = await HttpServer.bind(addr, preferredPort, shared: false);
    } on SocketException {
      bound = await HttpServer.bind(addr, 0, shared: false);
    }
    _server = bound;
    _stagingDir = await _createStagingDir();
    unawaited(_serveLoop(bound));
    return _buildUrls(bound.port);
  }

  /// 停止服务并清理本次会话的临时暂存目录。
  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
    final dir = _stagingDir;
    _stagingDir = null;
    if (dir != null) {
      await tryDeleteImportDir(dir);
    }
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  Future<Directory> _createStagingDir() async {
    if (_stagingRootResolver != null) {
      final root = await _stagingRootResolver();
      final sub = Directory(
        '${root.path}/wifi_${DateTime.now().microsecondsSinceEpoch}',
      );
      await sub.create(recursive: true);
      return sub;
    }
    return Directory.systemTemp.createTemp('yomu_wifi_transfer_');
  }

  Future<List<String>> _buildUrls(int boundPort) async {
    final ips = await _lanAddressesResolver();
    if (ips.isEmpty) {
      return <String>['http://127.0.0.1:$boundPort'];
    }
    return <String>[for (final ip in ips) 'http://$ip:$boundPort'];
  }

  Future<void> _serveLoop(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && (path == '/' || path == '/index.html')) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(buildWifiTransferHtml(pinRequired: _pin != null));
        await request.response.close();
        return;
      }

      if (request.method == 'GET' && path == '/api/status') {
        await writeWifiJson(request.response, HttpStatus.ok, <String, Object?>{
          'ok': true,
          'pinRequired': _pin != null,
          'receivedCount': _receivedCount,
        });
        return;
      }

      if (request.method == 'POST' &&
          (path == '/api/upload' ||
              path == '/api/upload-image' ||
              path == '/api/commit-folder' ||
              path == '/api/upload-series-cover')) {
        if (!_checkPin(request)) {
          await writeWifiJson(
            request.response,
            HttpStatus.unauthorized,
            const <String, Object?>{'ok': false, 'error': 'invalid_pin'},
          );
          return;
        }
        final staging = _stagingDir ?? await _createStagingDir();
        if (path == '/api/upload') {
          _receivedCount += await handleWifiArchiveUpload(
            request: request,
            importer: _importer,
            staging: staging,
            emit: _emit,
          );
        } else if (path == '/api/upload-image') {
          await handleWifiImageUpload(request: request, staging: staging);
        } else if (path == '/api/upload-series-cover') {
          await handleWifiSeriesCoverUpload(
            request: request,
            importer: _importer,
            staging: staging,
            emit: _emit,
          );
        } else {
          _receivedCount += await handleWifiCommitFolder(
            request: request,
            importer: _importer,
            staging: _stagingDir,
            emit: _emit,
          );
        }
        return;
      }

      await writeWifiJson(
        request.response,
        HttpStatus.notFound,
        const <String, Object?>{'ok': false, 'error': 'not_found'},
      );
    } on Object {
      try {
        await writeWifiJson(
          request.response,
          HttpStatus.internalServerError,
          const <String, Object?>{'ok': false, 'error': 'internal_error'},
        );
      } on Object {
        // 响应流已关闭时安全忽略。
      }
    }
  }

  bool _checkPin(HttpRequest request) {
    final expected = _pin;
    if (expected == null || expected.isEmpty) return true;
    final headerPin = request.headers.value('x-yomu-pin')?.trim();
    final queryPin = request.uri.queryParameters['pin']?.trim();
    return headerPin == expected || queryPin == expected;
  }

  void _emit(
    String fileName,
    WifiTransferEventKind kind, {
    int importedCount = 0,
    String? errorDetail,
  }) {
    if (_events.isClosed) return;
    _events.add(
      WifiTransferEvent(
        fileName: fileName,
        kind: kind,
        timestamp: DateTime.now().toUtc(),
        importedCount: importedCount,
        errorDetail: errorDetail,
      ),
    );
  }
}
