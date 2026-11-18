import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 应用设置的持久化。
///
/// 只存少量偏好（语言、触感反馈），与 API Key / 阅读偏好分开 key，互不影响。
/// 用 JSON blob 是为了以后加字段不用换存储结构；读取一律容错，坏存档回默认。
/// 写入是"读出整个 blob → 改一个字段 → 写回"，不会把别的字段冲掉。
abstract interface class SettingsStore {
  /// 返回存档里的语言代码；没有/读不出/格式不对都返回 null。
  Future<String?> loadLanguage();

  Future<void> saveLanguage(String language);

  /// 触感反馈开关；没有/读不出/类型不对都返回 null（调用方按默认开启处理）。
  Future<bool?> loadHaptics();

  Future<void> saveHaptics(bool enabled);
}

/// 真机实现：沿用钥匙串（与服务器、阅读偏好同一套基础设施）。
class SecureSettingsStore implements SettingsStore {
  SecureSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'komganative.settings.v1';

  final FlutterSecureStorage _storage;

  Future<Map<String, Object?>> _read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
    } on FormatException {
      return <String, Object?>{};
    }
  }

  Future<void> _write(String field, Object value) async {
    final current = await _read();
    current[field] = value;
    await _storage.write(key: _key, value: jsonEncode(current));
  }

  @override
  Future<String?> loadLanguage() async {
    final language = (await _read())['language'];
    return language is String ? language : null;
  }

  @override
  Future<void> saveLanguage(String language) => _write('language', language);

  @override
  Future<bool?> loadHaptics() async {
    final haptics = (await _read())['haptics'];
    return haptics is bool ? haptics : null;
  }

  @override
  Future<void> saveHaptics(bool enabled) => _write('haptics', enabled);
}

/// 测试/黄金图用。
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([this.language, this.haptics]);

  String? language;
  bool? haptics;
  int saveCount = 0;

  @override
  Future<String?> loadLanguage() async => language;

  @override
  Future<void> saveLanguage(String next) async {
    saveCount++;
    language = next;
  }

  @override
  Future<bool?> loadHaptics() async => haptics;

  @override
  Future<void> saveHaptics(bool enabled) async {
    saveCount++;
    haptics = enabled;
  }
}
