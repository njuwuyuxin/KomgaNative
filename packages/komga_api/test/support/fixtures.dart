import 'dart:io';

/// 读取真实抓包的 fixture。
///
/// 测试既可能从仓库根目录跑（`dart test packages/komga_api`，CI 就是这么跑的），
/// 也可能从包目录跑（`dart test`）。所以不能写死相对路径，得先找到包根。
String fixture(String name) =>
    File('${_packageRoot().path}/test/fixtures/$name').readAsStringSync();

Directory? _cachedRoot;

final RegExp _namePattern = RegExp(r'^name:\s*komga_api\s*$', multiLine: true);

bool _isPackageRoot(Directory dir) {
  final pubspec = File('${dir.path}/pubspec.yaml');
  return pubspec.existsSync() &&
      _namePattern.hasMatch(pubspec.readAsStringSync());
}

Directory _packageRoot() {
  final cached = _cachedRoot;
  if (cached != null) return cached;

  var dir = Directory.current;
  while (true) {
    if (_isPackageRoot(dir)) return _cachedRoot = dir;

    // 从仓库根目录跑测试时（`dart test packages/komga_api`），包在下面一层。
    final nested = Directory('${dir.path}/packages/komga_api');
    if (nested.existsSync() && _isPackageRoot(nested)) {
      return _cachedRoot = nested;
    }

    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('找不到 komga_api 包根目录（cwd=${Directory.current.path}）');
    }
    dir = parent;
  }
}
