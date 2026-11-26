import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/data/secure_storage.dart';

/// 阅读偏好的持久化。
///
/// 为什么不用 Drift：只有四个字段、几字节，读写频率是"用户改设置时"，
/// 用已有的 secure storage 就能落盘；Drift 留给真正需要查询的东西
/// （书架缓存、页图缓存、进度 outbox）。接口留在这里，将来换实现不动调用方。
abstract interface class ReaderPrefsStore {
  Future<ReaderPrefs?> load();

  Future<void> save(ReaderPrefs prefs);
}

/// 真机实现：与 API Key 分开一个 key，互不影响。
class SecureReaderPrefsStore implements ReaderPrefsStore {
  SecureReaderPrefsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? createAppSecureStorage();

  static const String _key = 'komganative.reader.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<ReaderPrefs?> load() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _key);
    } on Object {
      try {
        await _storage.delete(key: _key);
      } on Object {
        // 清理失败不阻断阅读器回退默认偏好。
      }
      return null;
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      return ReaderPrefs.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(ReaderPrefs prefs) =>
      _storage.write(key: _key, value: jsonEncode(prefs.toJson()));
}

/// 测试/黄金图用。
class InMemoryReaderPrefsStore implements ReaderPrefsStore {
  InMemoryReaderPrefsStore([this.prefs]);

  ReaderPrefs? prefs;
  int saveCount = 0;

  @override
  Future<ReaderPrefs?> load() async => prefs;

  @override
  Future<void> save(ReaderPrefs next) async {
    saveCount++;
    prefs = next;
  }
}
