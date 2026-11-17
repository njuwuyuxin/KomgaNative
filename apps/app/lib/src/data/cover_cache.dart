import 'dart:typed_data';

/// 封面字节的 LRU 缓存。
///
/// 为什么需要：Riverpod 的 cover provider 会随列表滚动反复重建，
/// 没有缓存时每滚回来一次就要重新下载一张封面（移动网络下很痛）。
///
/// 为什么有上限：一本 2 MB 的封面乘以几百个系列会把内存吃穿。
/// 默认 48 张（按单张 ~40 KB 估约 2 MB 上限），超了就丢最久未用的。
class CoverCache {
  CoverCache({this.capacity = 48}) : assert(capacity > 0);

  final int capacity;

  /// Dart 的 Map 保持插入顺序：用"删除后重插"把最近使用的挤到末尾。
  final Map<String, Uint8List> _entries = <String, Uint8List>{};

  int _hits = 0;
  int _misses = 0;

  int get hits => _hits;
  int get misses => _misses;
  int get length => _entries.length;

  Uint8List? get(String key) {
    final bytes = _entries.remove(key);
    if (bytes == null) {
      _misses++;
      return null;
    }
    // 重新插入到末尾 = 标记为"刚刚用过"。
    _entries[key] = bytes;
    _hits++;
    return bytes;
  }

  void put(String key, Uint8List bytes) {
    _entries.remove(key);
    _entries[key] = bytes;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}
