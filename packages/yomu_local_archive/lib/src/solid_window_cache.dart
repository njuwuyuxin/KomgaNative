import 'dart:collection';
import 'dart:typed_data';

/// 固实压缩包（Solid CBR / CB7）滑动窗口解码缓存（LMB-12 / P2-2）。
///
/// 固实压缩包内多页共用同一条压缩流；若逐页单独从头解压，200 页将退化为 \(O(N^2)\)。
/// 本缓存每次未命中时按 `windowSize`（默认 6 页）单趟顺序批量解压一个连续窗口并缓存，
/// 合并同一窗口的并发请求，按 [maxCachedBytes]（默认 64 MiB）与 [maxCachedPages] 双上限做 LRU 淘汰，
/// 并通过代际号（epoch）防止 `clear()` 后仍在途的旧批次将字节回灌进已关闭阅读器的缓存。
final class SolidArchiveWindowCache {
  SolidArchiveWindowCache({
    required List<String> orderedEntryNames,
    required Future<Map<String, Uint8List>> Function(List<String> entryNames)
    extractWindow,
    this.windowSize = 6,
    this.maxCachedPages = 18,
    this.maxCachedBytes = defaultMaxCachedBytes,
  }) : _orderedEntryNames = List<String>.unmodifiable(orderedEntryNames),
       _extractWindow = extractWindow;

  /// 默认内存上限：64 MiB（避免超高分辨率漫画 18 页 × 30 MB 撑爆内存）。
  static const int defaultMaxCachedBytes = 64 * 1024 * 1024;

  final List<String> _orderedEntryNames;
  final Future<Map<String, Uint8List>> Function(List<String> entryNames)
  _extractWindow;
  final int windowSize;
  final int maxCachedPages;
  final int maxCachedBytes;

  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();
  final Map<int, Future<Uint8List?>> _inFlight = <int, Future<Uint8List?>>{};
  int _cachedBytes = 0;
  int _epoch = 0;

  int get cachedPageCount => _cache.length;
  int get cachedBytes => _cachedBytes;

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
    final epoch = _epoch;

    final batchFuture = _extractWindow(windowNames).then((batch) {
      if (epoch == _epoch) {
        for (final i in windowIndices) {
          final name = _orderedEntryNames[i];
          final bytes = batch[name];
          if (bytes != null) {
            _putCache(i, bytes);
          }
        }
      }
      return batch;
    });

    for (final i in windowIndices) {
      final entryName = _orderedEntryNames[i];
      _inFlight[i] = batchFuture.then((batch) => batch[entryName]).whenComplete(
        () {
          if (epoch == _epoch) {
            _inFlight.remove(i);
          }
        },
      );
    }

    return _inFlight[index]!;
  }

  void _putCache(int index, Uint8List bytes) {
    final existing = _cache.remove(index);
    if (existing != null) {
      _cachedBytes -= existing.length;
    }
    if (bytes.length > maxCachedBytes || maxCachedPages <= 0) {
      return;
    }
    _cache[index] = bytes;
    _cachedBytes += bytes.length;
    while (_cache.length > maxCachedPages || _cachedBytes > maxCachedBytes) {
      final oldestKey = _cache.keys.first;
      final removed = _cache.remove(oldestKey);
      if (removed != null) {
        _cachedBytes -= removed.length;
      }
    }
  }

  void clear() {
    _epoch++;
    _cache.clear();
    _cachedBytes = 0;
    _inFlight.clear();
  }
}
