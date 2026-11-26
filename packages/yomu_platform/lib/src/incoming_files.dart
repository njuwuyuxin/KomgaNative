import 'dart:async';

import 'package:flutter/services.dart';

/// 外部系统（「用 Yomu 打开」或系统分享）传入的待导入漫画文件。
final class IncomingComicFile {
  const IncomingComicFile({required this.path, required this.name});

  final String path;
  final String name;
}

/// 外部打开文件接收通道抽象。
abstract interface class IncomingFiles {
  /// 拉取并清空冷启动期间原生侧暂存的待导入文件列表。
  Future<List<IncomingComicFile>> consumeInitialFiles();

  /// 运行期热启动传入的新文件事件流。
  Stream<IncomingComicFile> get stream;

  void dispose();
}

/// 基于独立 `yomu/incoming_files` 通道的实现（不与 `komganative/device` 抢处理器）。
class ChannelIncomingFiles implements IncomingFiles {
  ChannelIncomingFiles({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('yomu/incoming_files');

  final MethodChannel _channel;
  final StreamController<IncomingComicFile> _controller =
      StreamController<IncomingComicFile>.broadcast();
  bool _attached = false;

  @override
  Future<List<IncomingComicFile>> consumeInitialFiles() async {
    _ensureAttached();
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'consumeInitialFiles',
      );
      if (raw == null || raw.isEmpty) return const <IncomingComicFile>[];
      return <IncomingComicFile>[
        for (final item in raw)
          if (_parseItem(item) case final IncomingComicFile f) f,
      ];
    } on MissingPluginException {
      return const <IncomingComicFile>[];
    } on PlatformException {
      return const <IncomingComicFile>[];
    }
  }

  @override
  Stream<IncomingComicFile> get stream {
    _ensureAttached();
    return _controller.stream;
  }

  void _ensureAttached() {
    if (_attached) return;
    _attached = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'incomingFile') return;
      final parsed = _parseItem(call.arguments);
      if (parsed != null && !_controller.isClosed) {
        _controller.add(parsed);
      }
    });
  }

  static IncomingComicFile? _parseItem(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final path = raw['path'];
    final name = raw['name'];
    if (path is! String || path.isEmpty) return null;
    final resolvedName = (name is String && name.trim().isNotEmpty)
        ? name.trim()
        : path.replaceAll(r'\', '/').split('/').last;
    return IncomingComicFile(path: path, name: resolvedName);
  }

  @override
  void dispose() {
    if (_attached) {
      _channel.setMethodCallHandler(null);
      _attached = false;
    }
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }
}
