import 'dart:async';

import 'package:drift/drift.dart';

/// 全局测试配置：
/// 每个 `testWidgets` 都会创建独立的内存 Drift 数据库实例（`ProgressDatabase` /
/// `HttpCacheDatabase`），属于预期行为。统一关闭多实例警告，避免单次测试输出
/// 数十 MB 的重复堆栈日志（也会导致 GitHub Actions 日志截断与额外 CPU 开销）。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}
