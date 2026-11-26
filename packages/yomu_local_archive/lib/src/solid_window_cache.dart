import 'dart:collection';
import 'dart:typed_data';

/// 固实压缩包（Solid CBR / CB7）滑动窗口解码缓存（LMB-12）。
///
/// 固实压缩包内多页共用同一条压缩流；若逐页单独从头解压，200 页将退化为 \(O(N^2)\)。
/// 本缓存每次未命中时按 `windowSize`（默认 6 页）单趟顺序批量解压一个连续窗口并缓存，
/// 同时合并同一窗口的并发请求，且严格按 `maxCachedPages` 做 LRU 内存淘汰。
final class SolidArchiveWindowCache {
  SolidArchiveWindowCache({
    required List<String> orderedEntryNames,
    required Future<Map<String, Uint8List>> Function(List<String> entryNames)
    extractWindow,
    this.windowSize = 6,
    this.maxCachedPages = 18,
  }) : _orderedEntryNames = List<String>.unmodifiable(orderedEntryNames),
       _extractWindow = extractWindow;

  final List<String> _orderedEntryNames;
  final Future<Map<String, Uint8List>> Function(List<String> entryNames)
  _extractWindow;
  final int windowSize;
  final int maxCachedPages;

  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();
  final Map<int, Future<Uint8List?>> _inFlight = <int, Future<Uint8List?>>{};

  int get cachedPageCount => _cache.length;

  /// 按 1 基页码读取页面字节；命中缓存直接返回，未命中触发窗口批量单趟解压。
  Future<Uint8List?> readPage(int pageNumber) {
    final index = pageNumber - 1;
    if (index < 0 || index >= _orderedEntryNames.length) {
      return Future<Uint8List?>.value(null);
    }
    final hit = _cache.remove(index);
    if (hit != null) {
      _cache[index] = hit;
      return Future<Uint8List?>.value(hit);
    }
    final pending = _inFlight[index];
    if (pending != null) return pending;

    final start = index;
    final end = (start + windowSize).clamp(0, _orderedEntryNames.length);
    final windowIndices = <int>[for (var i = start; i < end; i++) i];
    final windowNames = <String>[
      for (final i in windowIndices) _orderedEntryNames[i],
    ];

    final batchFuture = _extractWindow(windowNames).then((batch) {
      for (final i in windowIndices) {
        final name = _orderedEntryNames[i];
        final bytes = batch[name];
        if (bytes != null) {
          _putCache(i, bytes);
        }
      }
      return batch;
    });

    for (final i in windowIndices) {
      final entryName = _orderedEntryNames[i];
      _inFlight[i] = batchFuture.then((batch) => batch[entryName]).whenComplete(
        () {
          _inFlight.remove(i);
        },
      );
    }

    return _inFlight[index]!;
  }

  void _putCache(int index, Uint8List bytes) {
    _cache.remove(index);
    _cache[index] = bytes;
    while (_cache.length > maxCachedPages) {
      _cache.remove(_cache.keys.first);
    }
  }

  void clear() {
    _cache.clear();
  }
}
