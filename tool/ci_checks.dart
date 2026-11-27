import 'dart:io';

import 'ci_dart_scanner.dart';

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

/// 分层与代码规范规则（ADR-0001 + ARC-12 + P2-5 门禁加固）：
/// - `yomu_domain` / `yomu_reader` / `yomu_sync` / `yomu_local_archive` 不得 import 或 export Flutter、HTTP、数据库；
/// - UI 层（screens/widgets）不得 import 或 export `komga_api` 与数据库/DAO 层；
/// - 非生成生产 `.dart` 文件严格 ≤ 350 行，单 class / mixin / extension / extension type ≤ 300 行（支持多行头部，忽略字符串与注释内的大括号）；
/// - 非注释、非字符串字面量的生产代码中禁止裸 `catch (_)` 与静默空 `on Object`。
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
      _scanDirectives(pkg, pureForbidden, reason: '纯逻辑包不得依赖或转出 UI / 网络 / 数据库'),
    );
  }

  for (final dir in <String>[
    'apps/app/lib/src/screens',
    'apps/app/lib/src/widgets',
  ]) {
    violations.addAll(
      _scanDirectives(dir, <String>[
        'package:komga_api/',
      ], reason: 'UI 不得直接访问或转出 API 层'),
    );
    violations.addAll(
      _scanDirectives(
        dir,
        <String>[
          'package:drift/',
          'package:yomu/src/data/cache/',
          'package:yomu/src/data/progress/',
          'package:yomu/src/data/local/',
        ],
        allowed: const <String>[
          // 仅放行不含数据库/DAO/IO 副作用的纯视图模型文件；严禁放行 *_tables.dart / *_dao.dart / *_database.dart / *_repository.dart。
          'package:yomu/src/data/local/mounted_root_summary.dart',
        ],
        reason: 'UI 不得直接依赖或转出 Drift、缓存/进度/本地编目数据库或 DAO，请经由 Provider 暴露纯领域/视图模型',
      ),
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
      '分层与规范规则通过（含 ≤350 行文件、≤300 行类/mixin/extension、import/export 分层、零裸 catch (_)、零静默空 on Object、零 local: 前缀泄漏）',
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

List<String> _scanSizeAndBareCatch(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return <String>[];
  final violations = <String>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (_isGeneratedDart(entity.path)) continue;

    final source = entity.readAsStringSync();
    final rawLines = source.split('\n');
    final lineCount = rawLines.isNotEmpty && rawLines.last.isEmpty
        ? rawLines.length - 1
        : rawLines.length;
    if (lineCount > kMaxFileLines) {
      violations.add('${entity.path} 共 $lineCount 行，超过单文件 $kMaxFileLines 行上限');
    }

    final stripped = stripDartCommentsAndStrings(source);
    final strippedLines = stripped.split('\n');
    for (var i = 0; i < strippedLines.length; i++) {
      if (_bareCatchPattern.hasMatch(strippedLines[i])) {
        violations.add('${entity.path}:${i + 1} 禁止裸 catch (_)（会吞掉 Error）');
      }
    }

    for (final block in scanDartTypeBlocks(source)) {
      if (block.lineCount > kMaxClassLines) {
        violations.add(
          '${entity.path}:${block.startLine} ${block.kind} ${block.name} '
          '共 ${block.lineCount} 行，超过单类型 $kMaxClassLines 行上限',
        );
      }
    }
  }
  return violations;
}

List<String> _scanDirectives(
  String dir,
  List<String> forbidden, {
  List<String> allowed = const <String>[],
  required String reason,
}) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return <String>[];
  final violations = <String>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final directives = scanDartDirectives(entity.readAsStringSync());
    for (final d in directives) {
      if (allowed.any((String ok) => d.uri == ok || d.uri.contains(ok))) {
        continue;
      }
      for (final f in forbidden) {
        if (d.uri.contains(f)) {
          violations.add(
            '${entity.path}:${d.line} 禁止 ${d.keyword} ${d.uri}（$reason）',
          );
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
    final stripped = stripDartCommentsAndStrings(entity.readAsStringSync());
    final lines = stripped.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
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
final RegExp _silentCatchErrorHeader = RegExp(
  r'\.catchError\s*\(\s*\([^)]*\)\s*\{',
);

/// 禁止 `apps/app/lib/src` 中出现完全静默（无可执行语句、未记日志、未抛错、未返回值）的
/// `on Object` 或 `.catchError((...) {})` 吞异常块（P3-2）。
List<String> _scanSilentObjectCatch(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return <String>[];
  final violations = <String>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (_isGeneratedDart(entity.path)) continue;
    final stripped = stripDartCommentsAndStrings(entity.readAsStringSync());
    final lines = stripped.split('\n');
    for (var i = 0; i < lines.length; i++) {
      for (final (pattern, label) in <(RegExp, String)>[
        (_onObjectCatchHeader, '静默空 on Object 块'),
        (_silentCatchErrorHeader, '静默空 catchError 回调'),
      ]) {
        final match = pattern.firstMatch(lines[i]);
        if (match == null) continue;

        final afterOpen = lines[i].substring(match.end);
        final bodyCode = StringBuffer();
        var depth = 1;

        void consume(String text) {
          for (var c = 0; c < text.length && depth > 0; c++) {
            final ch = text[c];
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
            '${entity.path}:${i + 1} 禁止$label（请至少记录 debugPrint、更新错误态、返回降级值或 rethrow）',
          );
        }
      }
    }
  }
  return violations;
}
