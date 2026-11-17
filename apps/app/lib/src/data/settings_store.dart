import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 应用设置的持久化。
///
/// 只存少量偏好（目前只有语言），与 API Key / 阅读偏好分开 key，互不影响。
/// 用 JSON blob 是为了以后加字段不用换存储结构；读取一律容错，坏存档回默认。
abstract interface class SettingsStore {
  /// 返回存档里的语言代码；没有/读不出/格式不对都返回 null。
  Future<String?> loadLanguage();

  Future<void> saveLanguage(String language);
}

/// 真机实现：沿用钥匙串（与服务器、阅读偏好同一套基础设施）。
class SecureSettingsStore implements SettingsStore {
  SecureSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'komganative.settings.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> loadLanguage() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final language = decoded['language'];
      return language is String ? language : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveLanguage(String language) => _storage.write(
    key: _key,
    value: jsonEncode(<String, Object?>{'language': language}),
  );
}

/// 测试/黄金图用。
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([this.language]);

  String? language;
  int saveCount = 0;

  @override
  Future<String?> loadLanguage() async => language;

  @override
  Future<void> saveLanguage(String next) async {
    saveCount++;
    language = next;
  }
}
