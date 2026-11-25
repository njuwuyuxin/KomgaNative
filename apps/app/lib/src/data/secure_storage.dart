import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 应用级安全存储实例（Android Keystore / iOS Keychain）。
///
/// Android 端启用 `resetOnError: true`：当换机恢复或系统 Keystore 密钥失效导致
/// `BadPaddingException` 等解密失败时自动清理损坏条目，防止登录与设置读写永久报错。
FlutterSecureStorage createAppSecureStorage() =>
    const FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: true));
