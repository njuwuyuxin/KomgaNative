#!/usr/bin/env dart

// KomgaNative 的统一校验入口。
//
// 为什么用 Dart 写而不是 .sh / .ps1：
//   1. Windows / macOS / Linux 同一份脚本（本项目双机开发，一台 Windows 一台可能不是）；
//   2. PowerShell 执行策略（本机 MachinePolicy=RemoteSigned + 工作区 ACL）会拦 .ps1；
//   3. Agent 只需要记住一个命令。
//
// 用法：
//   dart run tool/ci.dart check     # 格式 + 分析 + 分层检查 + 全部测试（CI 门禁）
//   dart run tool/ci.dart fix       # 自动格式化 + dart fix
//   dart run tool/ci.dart analyze   # 只跑静态分析
//   dart run tool/ci.dart test      # 只跑测试
//   dart run tool/ci.dart golden    # 重新生成黄金图基线（Windows 平台）
//   dart run tool/ci.dart contract  # 契约测试（M1 接入，当前只做占位）
import 'dart:io';

const List<String> _purePackages = <String>[
  'packages/komga_domain',
  'packages/komga_reader_engine',
  'packages/komga_sync_engine',
  'packages/komga_api',
];

const List<String> _flutterPackages = <String>[
  'packages/komga_platform',
  'packages/komga_design_system',
  'apps/app',
];

Future<void> main(List<String> args) async {
  final command = args.isEmpty ? 'check' : args.first;
  final code = switch (command) {
    'check' => await check(),
    'codegen' => await codegen(),
    'fix' => await fix(),
    'analyze' => await analyze(),
    'test' => await test(),
    'golden' => await golden(),
    'contract' => await contract(),
    'help' || '-h' || '--help' => await help(),
    _ => await help(unknown: command),
  };
  exit(code);
}

Future<int> help({String? unknown}) async {
  if (unknown != null) stderr.writeln('未知命令：$unknown');
  stdout.writeln('''
KomgaNative CI

  check     生成代码（按需）+ 格式检查 + 静态分析 + 分层规则 + 全部测试（默认）
  codegen   只跑生成代码（drift；生成物不入库，CI 上由 check 自动触发）
  fix       自动格式化 + dart fix --apply
  analyze   只跑静态分析
  test      只跑测试（纯 Dart 包用 dart test，Flutter 包用 flutter test）
  golden    重新生成黄金图基线（仅 Windows，与 CI 一致）
  contract  契约测试（M1）
''');
  return unknown == null ? 0 : 64;
}

// ---------------------------------------------------------------- commands

Future<int> check() async {
  final steps = <({String name, Future<int> Function() run})>[
    (name: 'codegen', run: codegen),
    (name: 'format', run: formatCheck),
    (name: 'analyze', run: analyze),
    (name: 'layers', run: layerCheck),
    (name: 'tests', run: test),
  ];

  final results = <String, int>{};
  for (final step in steps) {
    stdout.writeln('\n=== ${step.name} ===');
    final code = await step.run();
    results[step.name] = code;
    if (code != 0) {
      stdout.writeln('\n!!! ${step.name} 失败（exit $code），后续步骤仍会执行以便一次看到全部问题');
    }
  }

  stdout.writeln('\n=== 汇总 ===');
  var failed = false;
  results.forEach((name, code) {
    final ok = code == 0;
    failed |= !ok;
    stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $name');
  });
  return failed ? 1 : 0;
}

Future<int> fix() async {
  var code = await runProc('dart', <String>['format', '.']);
  final fixCode = await runProc('dart', <String>['fix', '--apply', '.']);
  if (code == 0) code = fixCode;
  stdout.writeln('\n建议再跑一次：dart run tool/ci.dart check');
  return code;
}

Future<int> formatCheck() => runProc('dart', <String>[
  'format',
  '--output=none',
  '--set-exit-if-changed',
  '.',
]);

/// 生成代码（drift）；只在需要时跑。
///
/// 仓库的 `.gitignore` 忽略 `*.g.dart`（生成物不入库），但 CI 是全新 clone，
/// 不生成就编译不过。放在门禁里而不是加一个 CI step：本地与 CI 仍走同一条命令，
/// 不会出现"CI 能过、本地不能"的双轨问题。
///
/// 判据是"生成物缺失 / 源文件更新"，不做无条件构建——build_runner 首次要 AOT 编译
/// 构建器（约 40s），每次 check 都跑太浪费。
Future<int> codegen() async {
  const source = 'apps/app/lib/src/data/progress/progress_database.dart';
  const generated = 'apps/app/lib/src/data/progress/progress_database.g.dart';

  final sourceFile = File(source);
  if (!sourceFile.existsSync()) {
    stdout.writeln('没有 drift 源文件，跳过 codegen');
    return 0;
  }
  final generatedFile = File(generated);
  final upToDate =
      generatedFile.existsSync() &&
      !sourceFile.lastModifiedSync().isAfter(generatedFile.lastModifiedSync());
  if (upToDate) {
    stdout.writeln('生成物已是最新，跳过 codegen');
    return 0;
  }

  stdout.writeln('生成物缺失或过期 → dart run build_runner build');
  return runProc('dart', <String>[
    'run',
    'build_runner',
    'build',
  ], workingDirectory: 'apps/app');
}

Future<int> analyze() => runProc('dart', <String>['analyze', '.']);

Future<int> test() async {
  var code = 0;
  for (final pkg in _purePackages) {
    stdout.writeln('--- dart test $pkg');
    final c = await runProc('dart', <String>['test'], workingDirectory: pkg);
    if (c != 0) code = c;
  }
  for (final pkg in _flutterPackages) {
    stdout.writeln('--- flutter test $pkg');
    final c = await runProc('flutter', <String>['test'], workingDirectory: pkg);
    if (c != 0) code = c;
  }
  return code;
}

Future<int> golden() async {
  stdout.writeln('基线平台必须与 CI 一致（Windows）。');
  return runProc('flutter', <String>[
    'test',
    'test/golden',
    '--update-goldens',
  ], workingDirectory: 'apps/app');
}

Future<int> contract() async {
  stdout.writeln('契约测试在 M1 接入：');
  stdout.writeln('  1. docker run -d -p 25600:25600 gotson/komga');
  stdout.writeln('  2. POST /api/v1/claim 初始化管理员');
  stdout.writeln('  3. 录制夹具到 test/fixtures/，再用真实响应跑分页/进度/页图用例');
  return 0;
}

// ---------------------------------------------------------------- layer rules

/// 分层规则（ADR-0001）：
/// - `komga_domain` / `*_engine` 不得依赖 Flutter、HTTP、数据库；
/// - UI 层（screens/widgets）不得直接依赖 `komga_api`，只能经 Repository。
Future<int> layerCheck() async {
  final violations = <String>[];

  final pureForbidden = <String>[
    'package:flutter/',
    'package:dio/',
    'package:drift/',
    'package:go_router/',
  ];
  for (final pkg in <String>[
    'packages/komga_domain',
    'packages/komga_reader_engine',
    'packages/komga_sync_engine',
  ]) {
    violations.addAll(
      _scanImports(pkg, pureForbidden, reason: '纯逻辑包不得依赖 UI / 网络 / 数据库'),
    );
  }

  violations.addAll(
    _scanImports('apps/app/lib/src/screens', <String>[
      'package:komga_api/',
    ], reason: 'UI 不得直接访问 API 层'),
  );
  violations.addAll(
    _scanImports('apps/app/lib/src/widgets', <String>[
      'package:komga_api/',
    ], reason: 'UI 不得直接访问 API 层'),
  );

  if (violations.isEmpty) {
    stdout.writeln('分层规则通过');
    return 0;
  }
  for (final v in violations) {
    stderr.writeln('VIOLATION: $v');
  }
  return 1;
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

// ---------------------------------------------------------------- process

Future<int> runProc(
  String executable,
  List<String> args, {
  String? workingDirectory,
}) async {
  stdout.writeln(
    '\$ $executable ${args.join(' ')}${workingDirectory == null ? '' : '  (cwd: $workingDirectory)'}',
  );
  final process = await Process.start(
    executable,
    args,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}
