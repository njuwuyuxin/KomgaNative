import 'dart:convert';

import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/reader_prefs.dart';

/// 备份格式版本。导入时**只接受相同主版本**：
/// 老版本读得懂新文件是巧合，不是承诺。
const int kPrefsBackupVersion = 1;

/// 备份里出现的字段（也是"绝不包含什么"的清单）。
///
/// **不含服务器地址、邮箱、API Key、密码、token**：这些在安全存储里，
/// 导出的是"我怎么看书"，不是"我怎么登录"。
const List<String> kPrefsBackupKinds = <String>['reader', 'settings'];

/// 备份解析失败的结构化原因（UI 按 Locale 渲染，避免硬编码单语种文案）。
enum PrefsBackupErrorKind {
  invalidJson,
  invalidFormat,
  unsupportedVersion,
  invalidPrefs,
}

/// 坏文件的统一失败类型。
class PrefsBackupException implements Exception {
  const PrefsBackupException(this.kind, this.message, {this.version});

  final PrefsBackupErrorKind kind;
  final String message;
  final int? version;

  @override
  String toString() => 'PrefsBackupException($kind): $message';
}

/// 本地偏好的导出/导入（SET-02）。
///
/// 只做两件事：把 `ReaderPrefs` 与 `AppSettings` 序列化成一个带版本的 JSON，
/// 以及反向解析并**校验**。不碰服务器、不碰安全存储、不联网。
class PrefsBackup {
  const PrefsBackup({
    required this.reader,
    required this.settings,
    this.pinnedSeries,
  });

  final Map<String, Object?> reader;
  final Map<String, Object?> settings;

  /// 可选的当前服务器置顶系列 ID 列表（不含服务器地址，兼容无此段的旧版备份）。
  final List<String>? pinnedSeries;

  /// 导出成可读 JSON（2 空格缩进：用户可以自己看一眼再决定要不要导入）。
  String encode() =>
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'version': kPrefsBackupVersion,
        'kinds': kPrefsBackupKinds,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'reader': reader,
        'settings': settings,
        if (pinnedSeries != null) 'pinnedSeries': pinnedSeries,
      });

  /// 解析并校验。任何不认识的形状都抛 [PrefsBackupException]，
  /// **绝不部分应用**——坏文件宁可整份拒绝，也不能把用户的设置改成半截。
  factory PrefsBackup.decode(String source) {
    Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException catch (error) {
      throw PrefsBackupException(
        PrefsBackupErrorKind.invalidJson,
        'Invalid JSON: ${error.message}',
      );
    }
    if (raw is! Map<String, Object?>) {
      throw const PrefsBackupException(
        PrefsBackupErrorKind.invalidFormat,
        'Backup root must be a JSON object',
      );
    }
    final version = raw['version'];
    if (version is! int) {
      throw const PrefsBackupException(
        PrefsBackupErrorKind.invalidFormat,
        'Missing version field',
      );
    }
    if (version != kPrefsBackupVersion) {
      throw PrefsBackupException(
        PrefsBackupErrorKind.unsupportedVersion,
        'Unsupported backup version $version',
        version: version,
      );
    }
    final reader = raw['reader'];
    final settings = raw['settings'];
    if (reader is! Map<String, Object?> || settings is! Map<String, Object?>) {
      throw const PrefsBackupException(
        PrefsBackupErrorKind.invalidFormat,
        'Missing reader or settings section',
      );
    }
    final rawPinned = raw['pinnedSeries'];
    final List<String>? pinnedSeries = rawPinned is List
        ? <String>[
            for (final item in rawPinned)
              if (item is String && item.trim().isNotEmpty) item.trim(),
          ]
        : null;
    return PrefsBackup(
      reader: reader,
      settings: settings,
      pinnedSeries: pinnedSeries,
    );
  }

  /// 用当前状态造一份备份，自动剥离所有以服务器地址为键的私有分区项。
  factory PrefsBackup.of({
    required ReaderPrefs reader,
    required AppSettings settings,
    List<String>? pinnedSeries,
  }) => PrefsBackup(
    reader: _sanitizeReaderJson(reader.toJson()),
    settings: _sanitizeSettingsJson(settings.toJson()),
    pinnedSeries: pinnedSeries,
  );

  /// 剥离 `seriesOverrides` / `spreadFrom` 中带 `serverKey|` 或 URL 的键，
  /// 确保导出的备份绝不泄露私有服务器域名或内网地址。
  static Map<String, Object?> _sanitizeReaderJson(Map<String, Object?> raw) {
    final copy = Map<String, Object?>.of(raw);
    _stripServerScopedMap(copy, 'seriesOverrides');
    _stripServerScopedMap(copy, 'spreadFrom');
    return copy;
  }

  /// 剥离 `libraryFilters` / `filterPresets`（键为服务器 `baseUrl`）。
  static Map<String, Object?> _sanitizeSettingsJson(Map<String, Object?> raw) {
    return Map<String, Object?>.of(raw)
      ..remove('libraryFilters')
      ..remove('filterPresets');
  }

  static void _stripServerScopedMap(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! Map) return;
    final filtered = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String && !_containsServerAddress(entry.key as String))
          entry.key as String: entry.value,
    };
    if (filtered.isEmpty) {
      map.remove(key);
    } else {
      map[key] = filtered;
    }
  }

  static bool _containsServerAddress(String key) =>
      key.contains('|') || key.contains('://');

  /// 把备份里的阅读偏好解析出来；形状不对就抛。
  ReaderPrefs toReaderPrefs() {
    try {
      return ReaderPrefs.fromJson(reader);
    } on FormatException catch (error) {
      throw PrefsBackupException(
        PrefsBackupErrorKind.invalidPrefs,
        'Failed to parse reader prefs: $error',
      );
    } on TypeError catch (error) {
      throw PrefsBackupException(
        PrefsBackupErrorKind.invalidPrefs,
        'Invalid field type in reader prefs: $error',
      );
    }
  }

  /// 把备份里的应用设置解析出来；形状不对就抛。
  AppSettings toAppSettings() {
    try {
      return AppSettings.fromJson(settings);
    } on FormatException catch (error) {
      throw PrefsBackupException(
        PrefsBackupErrorKind.invalidPrefs,
        'Failed to parse app settings: $error',
      );
    } on TypeError catch (error) {
      throw PrefsBackupException(
        PrefsBackupErrorKind.invalidPrefs,
        'Invalid field type in app settings: $error',
      );
    }
  }
}
