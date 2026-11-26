import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/secure_storage.dart';

/// 应用设置的持久化。
///
/// 只有一个 JSON blob，与 API Key / 阅读偏好分开 key，互不影响。
/// 用 blob 而不是"一个字段一个 key"：加字段不用换存储结构，读改写也天然原子。
///
/// 写入走 [update]（读出最新 → 只改这次要改的 → 写回）：设置页与书架控制器
/// 共用同一份存档，各自保存自己那几个字段，不会互相冲掉。
abstract interface class SettingsStore {
  /// 读全部偏好。没有存档 / 读失败 / 写坏 / 字段类型不对都回默认值，
  /// **绝不抛错**：钥匙串出问题不能挡住启动。
  Future<AppSettings> load();

  /// 读出最新存档 → 应用 [mutate] → 写回。
  ///
  /// 写失败会被吞掉（偏好丢一次不影响当前会话），但读一定是最新的。
  Future<void> update(AppSettings Function(AppSettings current) mutate);
}

/// 真机实现：沿用钥匙串（与服务器、阅读偏好同一套基础设施）。
class SecureSettingsStore implements SettingsStore {
  SecureSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? createAppSecureStorage();

  static const String _key = 'komganative.settings.v1';

  final FlutterSecureStorage _storage;

  /// 串行化读改写：两个控制器同时保存时，"读 → 改 → 写"必须按顺序执行，
  /// 否则后写的那个会用读完的旧快照盖掉前一个刚写的字段。
  Future<void> _queue = Future<void>.value();

  @override
  Future<AppSettings> load() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _key);
    } on Object {
      return AppSettings.defaults;
    }
    if (raw == null || raw.isEmpty) return AppSettings.defaults;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return AppSettings.defaults;
    }
    if (decoded is! Map<String, Object?>) return AppSettings.defaults;
    return AppSettings.fromJson(decoded);
  }

  @override
  Future<void> update(AppSettings Function(AppSettings current) mutate) {
    final next = _queue.then((_) async {
      final updated = mutate(await load());
      try {
        await _storage.write(key: _key, value: jsonEncode(updated.toJson()));
      } on Object {
        // 偏好写失败只影响下次启动，不该冒泡成 UI 错误。
      }
    });
    // 队列不能被单次失败掐断：失败已被吞掉，这里只保证顺序。
    _queue = next;
    return next;
  }
}

/// 测试/黄金图用。
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([this.settings = AppSettings.defaults]);

  AppSettings settings;
  int saveCount = 0;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> update(AppSettings Function(AppSettings current) mutate) async {
    settings = mutate(settings);
    saveCount++;
  }
}
