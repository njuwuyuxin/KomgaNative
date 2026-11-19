import 'dart:convert';

import 'package:komga_native/src/data/app_settings.dart';
import 'package:komga_native/src/data/reader_prefs.dart';

/// 备份格式版本。导入时**只接受相同主版本**：
/// 老版本读得懂新文件是巧合，不是承诺。
const int kPrefsBackupVersion = 1;

/// 备份里出现的字段（也是"绝不包含什么"的清单）。
///
/// **不含服务器地址、邮箱、API Key、密码、token**：这些在安全存储里，
/// 导出的是"我怎么看书"，不是"我怎么登录"。
const List<String> kPrefsBackupKinds = <String>['reader', 'settings'];

/// 坏文件的统一失败类型。
class PrefsBackupException implements Exception {
  const PrefsBackupException(this.message);

  final String message;

  @override
  String toString() => 'PrefsBackupException: $message';
}

/// 本地偏好的导出/导入（SET-02）。
///
/// 只做两件事：把 `ReaderPrefs` 与 `AppSettings` 序列化成一个带版本的 JSON，
/// 以及反向解析并**校验**。不碰服务器、不碰安全存储、不联网。
class PrefsBackup {
  const PrefsBackup({required this.reader, required this.settings});

  final Map<String, Object?> reader;
  final Map<String, Object?> settings;

  /// 导出成可读 JSON（2 空格缩进：用户可以自己看一眼再决定要不要导入）。
  String encode() =>
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'version': kPrefsBackupVersion,
        'kinds': kPrefsBackupKinds,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'reader': reader,
        'settings': settings,
      });

  /// 解析并校验。任何不认识的形状都抛 [PrefsBackupException]，
  /// **绝不部分应用**——坏文件宁可整份拒绝，也不能把用户的设置改成半截。
  factory PrefsBackup.decode(String source) {
    Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException catch (error) {
      throw PrefsBackupException('不是合法的 JSON：${error.message}');
    }
    if (raw is! Map<String, Object?>) {
      throw const PrefsBackupException('备份文件的顶层必须是一个对象');
    }
    final version = raw['version'];
    if (version is! int) {
      throw const PrefsBackupException('缺少 version 字段');
    }
    if (version != kPrefsBackupVersion) {
      throw PrefsBackupException(
        '备份版本 $version 与当前版本 $kPrefsBackupVersion 不兼容',
      );
    }
    final reader = raw['reader'];
    final settings = raw['settings'];
    if (reader is! Map<String, Object?> || settings is! Map<String, Object?>) {
      throw const PrefsBackupException('缺少 reader / settings 段');
    }
    return PrefsBackup(reader: reader, settings: settings);
  }

  /// 用当前状态造一份备份。
  factory PrefsBackup.of({
    required ReaderPrefs reader,
    required AppSettings settings,
  }) => PrefsBackup(reader: reader.toJson(), settings: settings.toJson());

  /// 把备份里的阅读偏好解析出来；形状不对就抛。
  ReaderPrefs toReaderPrefs() {
    try {
      return ReaderPrefs.fromJson(reader);
    } on Object catch (error) {
      throw PrefsBackupException('阅读设置无法解析：$error');
    }
  }

  /// 把备份里的应用设置解析出来；形状不对就抛。
  ///
  /// `AppSettings.fromJson` 对每个字段都有默认值，所以"缺字段"不算坏；
  /// 但整体不是对象时会在上面就被拦下。
  AppSettings toAppSettings() {
    try {
      return AppSettings.fromJson(settings);
    } on Object catch (error) {
      throw PrefsBackupException('应用设置无法解析：$error');
    }
  }
}
