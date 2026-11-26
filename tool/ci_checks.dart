import 'dart:io';

const int kMaxFileLines = 350;
const int kMaxClassLines = 300;

const List<String> _productionRoots = <String>[
  'packages/yomu_domain/lib',
  'packages/yomu_reader/lib',
  'packages/yomu_sync/lib',
  'packages/yomu_local_archive/lib',
  'packages/komga_api/lib',
  'packages/yomu_platform/lib',
  'packages/yomu_design_system/lib',
  'apps/app/lib',
];

/// 分层与代码规范规则（ADR-0001 + ARC-12 门禁加固）：
/// - `yomu_domain` / `yomu_reader` / `yomu_sync` / `yomu_local_archive` 不得依赖 Flutter、HTTP、数据库；
/// - UI 层（screens/widgets）不得直接依赖 `komga_api`，只能经 Repository；
/// - 非生成生产 `.dart` 文件严格 ≤ 350 行，单类 ≤ 300 行；
/// - 非注释生产代码中禁止裸 `catch (_)`。
Future<int> layerCheck() async {
  final violations = <String>[];

  final pureForbidden = <String>[
    'package:flutter/',
    'package:dio/',
    'package:drift/',
    'package:go_router/',
  ];
  for (final pkg in <String>[
    'packages/yomu_domain',
    'packages/yomu_reader',
    'packages/yomu_sync',
    'packages/yomu_local_archive',
  ]) {
    violations.addAll(
      _scanImports(pkg, pureForbidden, reason: '纯逻辑包不得依赖 UI / 网络 / 数据库'),
    );
  }

  for (final dir in <String>[
    'apps/app/lib/src/screens',
    'apps/app/lib/src/widgets',
  ]) {
    violations.addAll(
      _scanImports(dir, <String>[
        'package:komga_api/',
      ], reason: 'UI 不得直接访问 API 层'),
    );
    violations.addAll(
      _scanImports(dir, <String>[
        'package:drift/',
        'package:yomu/src/data/cache/',
        'package:yomu/src/data/progress/progress_database.dart',
        'package:yomu/src/data/progress/progress_tables.dart',
      ], reason: 'UI 不得直接依赖 Drift 数据库或表行类型，请经由 Provider 暴露纯领域/视图模型'),
    );
    violations.addAll(
      _scanCode(dir, <String>[
        'BackdropFilter(',
        'HapticFeedback.',
      ], reason: '用 FrostedSurface / AppHaptics，保证墨水屏退化与设置开关生效'),
    );
  }

  for (final root in _productionRoots) {
    violations.addAll(_scanSizeAndBareCatch(root));
  }

  violations.addAll(_scanLocalPrefixLeak('apps/app/lib/src'));
  violations.addAll(_scanSilentObjectCatch('apps/app/lib/src'));

  if (violations.isEmpty) {
    stdout.writeln(
      '分层与规范规则通过（含 ≤350 行文件、≤300 行类、零裸 catch (_)、零静默空 on Object、零 local: 前缀泄漏）',
    );
    return 0;
  }
  for (final v in violations) {
    stderr.writeln('VIOLATION: $v');
  }
  return 1;
}

/// 黄金图里不得读系统时钟。
Future<int> goldenDeterminismCheck() async {
  const reason = '黄金图会随运行日期/时区漂移；把"今天"注入进页面，测试里传固定值';
  final violations = _scanCode('apps/app/test/golden', <String>[
    'DateTime.now(',
  ], reason: reason);

  if (violations.isEmpty) {
    stdout.writeln('黄金图确定性检查通过');
    return 0;
  }
  for (final v in violations) {
    stderr.writeln('VIOLATION: $v');
  }
  return 1;
}

bool _isGeneratedDart(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.endsWith('.g.dart') ||
      normalized.contains('/l10n/app_localizations');
}

final RegExp _bareCatchPattern = RegExp(r'(^|[\s\}])catch\s*\(\s*_\s*\)');
final RegExp _classHeaderPattern = RegExp(
  r'^\s*(abstract\s+|sealed\s+|final\s+|base\s+|interface\s+|mixin\s+)*class\s+(\w+)',
);

List<String> _scanSizeAndBareCatch(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return <String>[];
  final violations = <String>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (_isGeneratedDart(entity.path)) continue;

    final lines = entity.readAsLinesSync();
    if (lines.length > kMaxFileLines) {
      violations.add(
        '${entity.path} 共 ${lines.length} 行，超过单文件 $kMaxFileLines 行上限',
      );
    }

    var inClass = false;
    var className = '';
    var classStart = 0;
    var braceDepth = 0;

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final trimmed = raw.trimLeft();
      if (!trimmed.startsWith('//')) {
        if (_bareCatchPattern.hasMatch(raw)) {
          violations.add('${entity.path}:${i + 1} 禁止裸 catch (_)（会吞掉 Error）');
        }
        if (!inClass) {
          final match = _classHeaderPattern.firstMatch(raw);
          if (match != null && raw.contains('{')) {
            inClass = true;
            className = match.group(2)!;
            classStart = i + 1;
            braceDepth = 0;
          }
        }
        if (inClass) {
          for (var c = 0; c < raw.length; c++) {
            final ch = raw[c];
            if (ch == '{') braceDepth++;
            if (ch == '}') braceDepth--;
          }
          if (braceDepth <= 0) {
            final classLen = (i + 1) - classStart + 1;
            if (classLen > kMaxClassLines) {
              violations.add(
                '${entity.path}:$classStart 类 $className 共 $classLen 行，超过单类 $kMaxClassLines 行上限',
              );
            }
            inClass = false;
          }
        }
      }
    }
  }
  return violations;
}

List<String> _scanImports(
  String dir,
  List<String> forbidden, {
  required String reason,
}) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return <String>[];
  final violations = <String>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.contains('import ')) continue;
      for (final f in forbidden) {
        if (line.contains(f)) {
          violations.add('${entity.path}:${i + 1} 禁止 import $f（$reason）');
        }
      }
    }
  }
  return violations;
}

List<String> _scanCode(
  String dir,
  List<String> forbidden, {
  required String reason,
}) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return <String>[];
  final violations = <String>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimLeft();
      if (line.startsWith('//')) continue;
      for (final f in forbidden) {
        if (line.contains(f)) {
          violations.add('${entity.path}:${i + 1} 禁止直接使用 $f（$reason）');
        }
      }
    }
  }
  return violations;
}

/// 禁止 `data/local/` 以外的业务与 UI 代码嗅探 `'local:'` ID 前缀（P1-1）。
List<String> _scanLocalPrefixLeak(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return <String>[];
  final violations = <String>[];
  const forbiddenLiterals = <String>["'local:'", '"local:"'];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (_isGeneratedDart(entity.path)) continue;
    final normalized = entity.path.replaceAll(r'\', '/');
    if (normalized.contains('/data/local/')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimLeft();
      if (line.startsWith('//')) continue;
      for (final lit in forbiddenLiterals) {
        if (line.contains(lit)) {
          violations.add(
            '${entity.path}:${i + 1} 禁止在 data/local/ 之外使用 $lit（请改用 SourceCapabilities）',
          );
        }
      }
    }
  }
  return violations;
}

final RegExp _onObjectCatchHeader = RegExp(
  r'\bon\s+Object(?:\s+catch\s*\([^)]*\))?\s*\{',
);

/// 禁止 `apps/app/lib/src` 中出现完全静默（无可执行语句、未记日志、未抛错、未返回值）的 `on Object` 吞异常块（P3-2）。
List<String> _scanSilentObjectCatch(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return <String>[];
  final violations = <String>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (_isGeneratedDart(entity.path)) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('//')) continue;
      final match = _onObjectCatchHeader.firstMatch(lines[i]);
      if (match == null) continue;

      final afterOpen = lines[i].substring(match.end);
      final bodyCode = StringBuffer();
      var depth = 1;

      void consume(String text) {
        for (var c = 0; c < text.length && depth > 0; c++) {
          final ch = text[c];
          if (ch == '/' && c + 1 < text.length && text[c + 1] == '/') {
            break;
          }
          if (ch == '{') {
            depth++;
            bodyCode.write(ch);
          } else if (ch == '}') {
            depth--;
            if (depth > 0) bodyCode.write(ch);
          } else {
            bodyCode.write(ch);
          }
        }
      }

      consume(afterOpen);
      var j = i + 1;
      while (depth > 0 && j < lines.length) {
        consume(lines[j]);
        j++;
      }

      if (bodyCode.toString().trim().isEmpty) {
        violations.add(
          '${entity.path}:${i + 1} 禁止静默空 on Object 块（请至少记录 debugPrint、更新错误态、返回降级值或 rethrow）',
        );
      }
    }
  }
  return violations;
}
