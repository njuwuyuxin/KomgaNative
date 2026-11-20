import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// 若 [bytes] 对应的 `MemoryImage` 已经在 Flutter 的 [ImageCache]（含当前屏幕上
/// 正在渲染的 live image 或预解码条目）中完成解码，**同步**克隆并返回一份独立句柄的
/// [ui.Image]；否则无副作用地返回 null。
///
/// 这是打通"屏幕上已显示的页图 / 预加载解码缓存"与"卷页着色器位图"的关键桥梁：
/// 只要页面已在屏幕上渲染好或已被 `precacheImage` 预热，起手翻页的那一帧就能 0 延迟
/// 拿到纹理，绝不因为异步二次解码而退化成平移或闪纯白背面；同时 `clone()` 共享底层
/// GPU 纹理（零额外显存），各自独立 `dispose()` 互不干扰。
ui.Image? trySyncImageFromCache(Uint8List bytes) {
  final key = MemoryImage(bytes);
  final status = PaintingBinding.instance.imageCache.statusForKey(key);
  if ((!status.keepAlive && !status.live) || status.pending) {
    return null;
  }
  final stream = key.resolve(ImageConfiguration.empty);
  ui.Image? cloned;
  var added = false;
  var removed = false;
  late final ImageStreamListener listener;
  void detach() {
    if (added && !removed) {
      removed = true;
      stream.removeListener(listener);
    }
  }

  listener = ImageStreamListener((ImageInfo info, bool synchronousCall) {
    if (synchronousCall && cloned == null) {
      cloned = info.image.clone();
    }
    detach();
  }, onError: (Object error, StackTrace? stackTrace) => detach());
  stream.addListener(listener);
  added = true;
  detach();
  return cloned;
}

/// 经由 Flutter [ImageCache] 异步解码 [bytes] 并克隆出一份独立句柄的 [ui.Image]。
///
/// 与 `ReaderPage` / `ReaderPreloader` 共用同一个 `MemoryImage(bytes)` 键：
/// - 已经在途的解码直接合并，不重复跑原生编解码器；
/// - 卷页先解完的页会自动暖热 `ImageCache`，翻页落地后 `Image.memory` 首帧同步命中；
/// - [onRegisterCancel] 注册取消钩子：换书或组件销毁时立即摘掉监听，不留悬挂回调。
Future<ui.Image?> decodeThroughImageCache(
  Uint8List bytes, {
  void Function(VoidCallback cancel)? onRegisterCancel,
}) async {
  final sync = trySyncImageFromCache(bytes);
  if (sync != null) return sync;

  final cache = PaintingBinding.instance.imageCache;
  if (cache.maximumSize <= 0 || cache.maximumSizeBytes <= 0) {
    return _decodeBytesDirectly(bytes);
  }

  final completer = Completer<ui.Image?>();
  final stream = MemoryImage(bytes).resolve(ImageConfiguration.empty);
  var added = false;
  var removed = false;
  late final ImageStreamListener listener;

  void detach() {
    if (added && !removed) {
      removed = true;
      stream.removeListener(listener);
    }
  }

  listener = ImageStreamListener(
    (ImageInfo info, bool _) {
      if (!completer.isCompleted) {
        completer.complete(info.image.clone());
      }
      detach();
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      detach();
    },
  );
  onRegisterCancel?.call(() {
    detach();
    if (!completer.isCompleted) completer.complete(null);
  });
  stream.addListener(listener);
  added = true;
  if (completer.isCompleted) detach();
  return completer.future;
}

Future<ui.Image?> _decodeBytesDirectly(Uint8List bytes) async {
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  } on Object {
    return null;
  } finally {
    codec?.dispose();
  }
}

/// 卷页要用的位图缓存，按页（0 基）索引。
///
/// - **LRU 保留**：默认保留最近 [maxRetained] 页（双页约 8 屏），连续往后翻几屏再
///   往回翻时，刚看过的页面句柄仍在手边，0 延迟起卷；[maxRetained] 设为 0 时只留当前所需页。
/// - **翻动保护（[pinned]）**：正在卷页的图层不会被中途淘汰，后台预解码也无需因翻页进行中而中断。
/// - **延后释放**：被淘汰的句柄可能仍被上一帧 raster 线程引用，统一等下一帧结束再 `dispose()`。
class CurlSheets {
  CurlSheets({this.maxRetained = defaultMaxRetained, this.onImageReady})
    : assert(maxRetained >= 0);

  /// 默认最多保留 16 页（双页约 8 屏）：与 `ImageCache` 共享底层 GPU 纹理，不占双倍显存。
  static const int defaultMaxRetained = 16;

  final int maxRetained;

  /// 某一页异步解码入库时的通知（供进行中的卷页把刚到达的纸背平滑淡入）。
  final ValueChanged<int>? onImageReady;

  final Map<int, ui.Image> _images = <int, ui.Image>{};
  final List<ui.Image> _retired = <ui.Image>[];
  final Map<int, Future<void>> _pending = <int, Future<void>>{};
  final Map<int, VoidCallback> _cancels = <int, VoidCallback>{};
  Set<int> _wanted = <int>{};
  Set<int> _pinned = <int>{};
  bool Function() _stillWanted = () => false;
  int _generation = 0;
  bool _disposed = false;

  /// 第 [page] 页的位图；还没解码好时为 null。
  ui.Image? imageFor(int page) => _images[page];

  /// 同步接纳一张从 `ImageCache` 克隆出来的位图。
  ///
  /// 若该页已有句柄则保留原句柄（避免替换正被 `ReaderPage` 借用的实例）并释放新克隆句柄。
  void putSync(int page, ui.Image image) {
    if (_disposed) {
      image.dispose();
      return;
    }
    final existing = _images.remove(page);
    if (existing != null) {
      _images[page] = existing;
      image.dispose();
      return;
    }
    _images[page] = image;
    _trimToBudget();
  }

  /// 确保 [pages] 并发解码就绪，同时保护 [pinned] 页不被淘汰。
  Future<void> ensure({
    required Set<int> pages,
    Set<int> pinned = const <int>{},
    required Future<ui.Image?> Function(int page) decode,
    required bool Function() stillWanted,
  }) async {
    if (_disposed || !stillWanted()) return;
    _wanted = Set<int>.of(pages);
    _pinned = Set<int>.of(pinned);
    _stillWanted = stillWanted;
    // 刷新当前所需页的 LRU 顺序，确保要淘汰时先淘汰最久未访问的历史页。
    for (final page in pages) {
      final existing = _images.remove(page);
      if (existing != null) _images[page] = existing;
    }
    _trimToBudget();

    final generation = _generation;
    final tasks = <Future<void>>[];
    for (final page in pages) {
      if (_images.containsKey(page)) continue;
      tasks.add(
        _pending[page] ??= _decodeAndAdopt(
          page,
          generation,
          decode,
          stillWanted,
        ),
      );
    }
    if (tasks.isNotEmpty) {
      await Future.wait<void>(tasks);
    }
  }

  /// 注册第 [page] 页在途解码的取消回调（清理 `ImageStream` 监听用）。
  void registerCancel(int page, VoidCallback cancel) {
    if (_disposed) {
      cancel();
      return;
    }
    _cancels[page] = cancel;
  }

  /// 清空所有缓存并作废在途解码（切出卷页效果或换书时调用）。
  void clear() {
    _generation++;
    _wanted.clear();
    _pinned.clear();
    _cancelAllPending();
    for (final page in _images.keys.toList()) {
      _retire(_images.remove(page));
    }
  }

  Future<void> _decodeAndAdopt(
    int page,
    int generation,
    Future<ui.Image?> Function(int page) decode,
    bool Function() requestStillWanted,
  ) async {
    try {
      final image = await decode(page);
      if (image == null) return;
      final keepInLru = maxRetained > 0 || _wanted.contains(page);
      if (_disposed ||
          generation != _generation ||
          !requestStillWanted() ||
          !_stillWanted() ||
          !keepInLru) {
        image.dispose();
        return;
      }
      final existing = _images[page];
      if (existing != null) {
        // 同步路径已先一步填入，直接释放重复句柄。
        image.dispose();
        return;
      }
      _images[page] = image;
      _trimToBudget();
      onImageReady?.call(page);
    } finally {
      if (generation == _generation) {
        _cancels.remove(page);
        _pending.remove(page)?.ignore();
      }
    }
  }

  void _trimToBudget() {
    for (final page in _images.keys.toList()) {
      final isProtected = _wanted.contains(page) || _pinned.contains(page);
      if (isProtected) continue;
      if (maxRetained == 0 || _images.length > maxRetained) {
        _retire(_images.remove(page));
      }
    }
  }

  void _cancelAllPending() {
    final callbacks = _cancels.values.toList(growable: false);
    _cancels.clear();
    _pending.clear();
    for (final cancel in callbacks) {
      cancel();
    }
  }

  void _retire(ui.Image? image) {
    if (image == null) return;
    _retired.add(image);
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushRetired());
  }

  void _flushRetired() {
    for (final image in _retired) {
      image.dispose();
    }
    _retired.clear();
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _wanted.clear();
    _pinned.clear();
    _cancelAllPending();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _flushRetired();
  }
}
