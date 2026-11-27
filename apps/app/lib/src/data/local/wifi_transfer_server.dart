import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yomu/src/data/local/local_comic_importer.dart';
import 'package:yomu/src/data/local/local_import_cleanup.dart';
import 'package:yomu/src/data/local/wifi_transfer_handlers.dart';
import 'package:yomu/src/data/local/wifi_transfer_html.dart';
import 'package:yomu/src/data/local/wifi_transfer_security.dart';

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

/// 内置局域网 HTTP Wi-Fi 传书服务端（纯 `dart:io`，零外部依赖，LMB-07 / P2-1 安全加固）。
///
/// 安全机制：
/// - 仅经 `X-Yomu-Pin` 请求头校验 PIN（拒绝 query string）+ 按 IP 限流锁定（[WifiPinGuard]）；
/// - 并发上传上限 + 原子预占与逐块实时扣减的整次会话流量上限（[WifiSessionQuota]）；
/// - 未提交的暂存文件夹图片按 TTL 定时回收，并支持 `/api/abort-folder` 即时清理。
final class WifiTransferServer {
  WifiTransferServer({
    required LocalComicImporter importer,
    Future<Directory> Function()? stagingRootResolver,
    Future<List<String>> Function()? lanAddressesResolver,
    this.maxArchiveBytes = defaultMaxArchiveBytes,
    this.maxImageBytes = defaultMaxImageBytes,
    this.maxSessionBytes = defaultMaxSessionBytes,
    this.maxConcurrentUploads = defaultMaxConcurrentUploads,
    Duration stagedFolderTtl = defaultStagedFolderTtl,
    Duration stagedFolderSweepInterval = defaultStagedFolderSweepInterval,
    int maxPinFailures = defaultMaxPinFailures,
    Duration pinLockoutDuration = defaultPinLockoutDuration,
    DateTime Function()? now,
  }) : _importer = importer,
       _stagingRootResolver = stagingRootResolver,
       _lanAddressesResolver = lanAddressesResolver ?? discoverLanIpv4Addresses,
       _now = now ?? (() => DateTime.now().toUtc()),
       _stagedFolderSweepInterval = stagedFolderSweepInterval,
       _quota = WifiSessionQuota(
         maxSessionBytes: maxSessionBytes,
         maxConcurrentUploads: maxConcurrentUploads,
       ),
       _stagedFolders = WifiStagedFolderTracker(
         ttl: stagedFolderTtl,
         now: now ?? (() => DateTime.now().toUtc()),
       ),
       _pinGuard = WifiPinGuard(
         maxFailures: maxPinFailures,
         lockoutDuration: pinLockoutDuration,
         now: now ?? (() => DateTime.now().toUtc()),
       );

  static const int defaultMaxArchiveBytes = 512 * 1024 * 1024;
  static const int defaultMaxImageBytes = 32 * 1024 * 1024;
  static const int defaultMaxSessionBytes = 4 * 1024 * 1024 * 1024;
  static const int defaultMaxConcurrentUploads = 4;
  static const Duration defaultStagedFolderTtl = Duration(minutes: 5);
  static const Duration defaultStagedFolderSweepInterval = Duration(minutes: 1);
  static const int defaultMaxPinFailures = 5;
  static const Duration defaultPinLockoutDuration = Duration(seconds: 30);

  final LocalComicImporter _importer;
  final Future<Directory> Function()? _stagingRootResolver;
  final Future<List<String>> Function() _lanAddressesResolver;
  final int maxArchiveBytes;
  final int maxImageBytes;
  final int maxSessionBytes;
  final int maxConcurrentUploads;
  final Duration _stagedFolderSweepInterval;
  final DateTime Function() _now;
  final WifiSessionQuota _quota;
  final WifiStagedFolderTracker _stagedFolders;
  final WifiPinGuard _pinGuard;
  final StreamController<WifiTransferEvent> _events =
      StreamController<WifiTransferEvent>.broadcast();

  HttpServer? _server;
  Directory? _stagingDir;
  Timer? _sweepTimer;
  String? _pin;
  int _receivedCount = 0;

  Stream<WifiTransferEvent> get events => _events.stream;
  bool get isRunning => _server != null;
  int? get port => _server?.port;
  int get receivedCount => _receivedCount;
  String? get pin => _pin;
  int get sessionBytesUsed => _quota.usedBytes;

  void setPin(String? pin) {
    final cleaned = pin?.trim() ?? '';
    _pin = cleaned.isEmpty ? null : cleaned;
    _pinGuard.reset();
  }

  /// 启动 HTTP 传书服务，返回可供浏览器访问的完整 URL 列表。
  Future<List<String>> start({
    InternetAddress? bindAddress,
    int preferredPort = 8080,
    String? pin,
  }) async {
    if (_server != null) return _buildUrls(_server!.port);
    setPin(pin);
    _quota.reset();
    _stagedFolders.reset();
    final addr = bindAddress ?? InternetAddress.anyIPv4;
    HttpServer bound;
    try {
      bound = await HttpServer.bind(addr, preferredPort, shared: false);
    } on SocketException {
      bound = await HttpServer.bind(addr, 0, shared: false);
    }
    _server = bound;
    _stagingDir = await _createStagingDir();
    _sweepTimer = Timer.periodic(_stagedFolderSweepInterval, (_) {
      unawaited(sweepExpiredStagedFolders());
    });
    unawaited(_serveLoop(bound));
    return _buildUrls(bound.port);
  }

  /// 停止服务并清理本次会话的临时暂存目录。
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _quota.reset();
    _stagedFolders.reset();
    _pinGuard.reset();
    if (server != null) await server.close(force: true);
    final dir = _stagingDir;
    _stagingDir = null;
    if (dir != null) await tryDeleteImportDir(dir);
  }

  /// 清理已超过 TTL 且无在途写入/提交的未提交暂存文件夹，返回被回收的目录数。
  Future<int> sweepExpiredStagedFolders() =>
      _stagedFolders.sweepExpired(_stagingDir);

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
    if (ips.isEmpty) return <String>['http://127.0.0.1:$boundPort'];
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
              path == '/api/abort-folder' ||
              path == '/api/upload-series-cover')) {
        if (!await authorizeWifiPost(request, _pinGuard, expectedPin: _pin)) {
          return;
        }
        await _dispatchPost(path, request);
        return;
      }

      await writeWifiJson(
        request.response,
        HttpStatus.notFound,
        const <String, Object?>{'ok': false, 'error': 'not_found'},
      );
    } on Object catch (error) {
      debugPrint('WifiTransferServer: unhandled request error: $error');
      try {
        await writeWifiJson(
          request.response,
          HttpStatus.internalServerError,
          const <String, Object?>{'ok': false, 'error': 'internal_error'},
        );
      } on Object catch (writeError) {
        // 响应流已关闭时安全忽略。
        debugPrint(
          'WifiTransferServer: error response write skipped: $writeError',
        );
      }
    }
  }

  Future<void> _dispatchPost(String path, HttpRequest request) async {
    final staging = _stagingDir;
    if (_server == null || staging == null) {
      await writeWifiJson(
        request.response,
        HttpStatus.serviceUnavailable,
        const <String, Object?>{'ok': false, 'error': 'server_stopped'},
        closeConnection: true,
      );
      return;
    }
    final sessionGeneration = _quota.generation;
    if (!_quota.tryEnterUpload()) {
      await drainUpToLimit(request);
      request.response.headers.set(HttpHeaders.retryAfterHeader, '1');
      await writeWifiJson(
        request.response,
        HttpStatus.serviceUnavailable,
        const <String, Object?>{'ok': false, 'error': 'too_many_uploads'},
        closeConnection: true,
      );
      return;
    }
    try {
      if (path == '/api/abort-folder') {
        await handleWifiAbortFolder(
          request: request,
          staging: staging,
          stagedFolders: _stagedFolders,
        );
        return;
      }
      unawaited(sweepExpiredStagedFolders());
      if (path == '/api/upload') {
        final outcome = await handleWifiArchiveUpload(
          request: request,
          importer: _importer,
          staging: staging,
          emit: _emit,
          maxBytes: maxArchiveBytes,
          quota: _quota,
        );
        _receivedCount += outcome.importedCount;
      } else if (path == '/api/upload-image') {
        await handleWifiImageUpload(
          request: request,
          staging: staging,
          maxBytes: maxImageBytes,
          quota: _quota,
          stagedFolders: _stagedFolders,
        );
      } else if (path == '/api/upload-series-cover') {
        await handleWifiSeriesCoverUpload(
          request: request,
          importer: _importer,
          staging: staging,
          emit: _emit,
          maxBytes: maxImageBytes,
          quota: _quota,
        );
      } else {
        _receivedCount += await handleWifiCommitFolder(
          request: request,
          importer: _importer,
          staging: staging,
          stagedFolders: _stagedFolders,
          emit: _emit,
        );
      }
    } finally {
      _quota.leaveUpload(generation: sessionGeneration);
      // 若请求在途期间服务已 stop/重启，清掉其可能残留的旧会话暂存目录，防止泄露孤儿目录。
      if (_quota.generation != sessionGeneration || _stagingDir != staging) {
        unawaited(tryDeleteImportDir(staging));
      }
    }
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
        timestamp: _now(),
        importedCount: importedCount,
        errorDetail: errorDetail,
      ),
    );
  }
}
