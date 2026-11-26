import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yomu/src/data/secure_storage.dart';

/// 归档与 PDF 密码安全存储（系统钥匙串 / Keystore + 常用解压密码词典，LMB-13）。
///
/// - 单本已解锁书籍的密码按 `bookId` 单独加密存入系统钥匙串，再次阅读零弹窗；
/// - 常用解压密码词典按最近使用顺序保存（上限 30 条），导入/打开加密包时自动静音尝试。
final class ArchivePasswordStore {
  ArchivePasswordStore({FlutterSecureStorage? storage})
    : _storage = storage ?? createAppSecureStorage(),
      _memory = null;

  /// 无平台插件依赖的内存实现（供单测与离线测试使用）。
  ArchivePasswordStore.inMemory([Map<String, String>? seed])
    : _storage = null,
      _memory = <String, String>{...?seed};

  static const String _dictKey = 'yomu_common_archive_passwords_v1';
  static const String _bookKeyPrefix = 'yomu_book_archive_pwd_';
  static const int maxDictionarySize = 30;

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _memory;

  Future<String?> _read(String key) async {
    final mem = _memory;
    if (mem != null) return mem[key];
    try {
      return await _storage!.read(key: key);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    final mem = _memory;
    if (mem != null) {
      mem[key] = value;
      return;
    }
    try {
      await _storage!.write(key: key, value: value);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> _delete(String key) async {
    final mem = _memory;
    if (mem != null) {
      mem.remove(key);
      return;
    }
    try {
      await _storage!.delete(key: key);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> saveBookPassword(String bookId, String password) async {
    if (bookId.isEmpty || password.isEmpty) return;
    await _write('$_bookKeyPrefix$bookId', password);
  }

  Future<String?> getBookPassword(String bookId) async {
    if (bookId.isEmpty) return null;
    final value = await _read('$_bookKeyPrefix$bookId');
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> deleteBookPassword(String bookId) async {
    if (bookId.isEmpty) return;
    await _delete('$_bookKeyPrefix$bookId');
  }

  Future<List<String>> loadCommonPasswords() async {
    final raw = await _read(_dictKey);
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List<Object?>) {
        return List<String>.unmodifiable(
          decoded.whereType<String>().where((s) => s.isNotEmpty),
        );
      }
    } on FormatException {
      return const <String>[];
    }
    return const <String>[];
  }

  /// 将常用解压密码置顶写入词典（去重并截断至 [maxDictionarySize]）。
  Future<List<String>> addCommonPassword(String password) async {
    if (password.isEmpty) return loadCommonPasswords();
    final current = await loadCommonPasswords();
    final next = <String>[
      password,
      for (final p in current)
        if (p != password) p,
    ];
    final trimmed = next.length > maxDictionarySize
        ? next.sublist(0, maxDictionarySize)
        : next;
    await _write(_dictKey, jsonEncode(trimmed));
    return List<String>.unmodifiable(trimmed);
  }

  Future<List<String>> removeCommonPassword(String password) async {
    final current = await loadCommonPasswords();
    final next = <String>[
      for (final p in current)
        if (p != password) p,
    ];
    await _write(_dictKey, jsonEncode(next));
    return List<String>.unmodifiable(next);
  }
}
