import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 钉住 Android 的网络权限，因为这类错误连测试套件都发现不了。
///
/// 踩过的坑：`INTERNET` 只写在 `src/debug` 与 `src/profile` 的 manifest 里时，
/// debug 包（模拟器、`flutter run`）一切正常，release 包装到真机后**任何** socket
/// 都被系统直接拒绝（`Operation not permitted`），连接页只能报"无法连接到 xxx"，
/// 看起来像地址、端口、反代或局域网隔离的问题。只有检查合并后的 release manifest
/// 才能提前发现，所以这里直接读源文件。
void main() {
  final manifest = _readMainManifest();

  test('src/main 声明 INTERNET 权限（release APK 只合并 main）', () {
    expect(
      manifest,
      contains('android.permission.INTERNET'),
      reason: 'debug/profile 的 INTERNET 不会进 release APK；缺了它真机连不上任何服务器',
    );
  });

  test('src/main 放行明文 http（局域网 NAS 默认是 http）', () {
    expect(
      manifest,
      contains('android:usesCleartextTraffic="true"'),
      reason: 'Android 9+ 默认禁止明文，放开是连接页已提示过的有意取舍',
    );
  });

  test('WRITE_EXTERNAL_STORAGE 严格限制在 API 28 及以下（Android 10+ 免权限存相册）', () {
    expect(manifest, contains('android.permission.WRITE_EXTERNAL_STORAGE'));
    expect(
      manifest,
      contains('android:maxSdkVersion="28"'),
      reason: 'Android 10+ 走分区存储 MediaStore，不应向现代系统申请旧版外部存储权限',
    );
  });
}

/// 从当前目录向上找 main manifest：`flutter test` 可能以 `apps/app` 或仓库根为 cwd。
String _readMainManifest() {
  const relative = 'android/app/src/main/AndroidManifest.xml';
  var dir = Directory.current;
  for (var depth = 0; depth < 4; depth++) {
    for (final path in <String>[
      '${dir.path}/$relative',
      '${dir.path}/apps/app/$relative',
    ]) {
      final file = File(path);
      if (file.existsSync()) return file.readAsStringSync();
    }
    dir = dir.parent;
  }
  throw StateError('找不到 $relative（cwd: ${Directory.current.path}）');
}
