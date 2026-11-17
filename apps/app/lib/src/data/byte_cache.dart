import 'dart:typed_data';

/// 定长 LRU 字节缓存（封面、页图共用）。
///
/// 为什么需要：Riverpod 的 provider 会随列表滚动/翻页反复重建，
/// 没有缓存时每滚回来一次就要重新下载（移动网络下很痛）。
///
/// 为什么有上限：一张 2 MB 的页图乘以几百页会把内存吃穿。
/// 默认容量由调用方决定（封面 48 张；阅读器页图 8 张，因为单张更大）。
class ByteLruCache {
  ByteLruCache({this.capacity = 48}) : assert(capacity > 0);

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
