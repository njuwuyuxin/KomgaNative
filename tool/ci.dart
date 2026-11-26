#!/usr/bin/env dart

// KomgaNative 的统一校验入口。
import 'dart:io';

import 'ci_checks.dart';

const List<String> _purePackages = <String>[
  'packages/yomu_domain',
  'packages/yomu_reader',
  'packages/yomu_sync',
  'packages/yomu_local_archive',
  'packages/komga_api',
];

const List<String> _flutterPackages = <String>[
  'packages/yomu_platform',
  'packages/yomu_design_system',
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
    'layers' => await layerCheck(),
    'install' => await installApp(deviceId: args.length > 1 ? args[1] : null),
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

  check     生成代码（按需）+ 格式检查 + 静态分析 + 分层与规范规则 + 全部测试（默认）
  codegen   只跑生成代码（drift + l10n；生成物不入库，CI 上由 check 自动触发）
  fix       自动格式化 + dart fix --apply
  analyze   只跑静态分析
  layers    只跑分层、单文件 ≤350 行、单类 ≤300 行与裸 catch (_) 检查
  test      只跑测试（纯 Dart 包用 dart test，Flutter 包用 flutter test）
  golden    重新生成黄金图基线（仅 Windows，与 CI 一致）
  install [device]  构建 release、装到模拟器并启动（保留应用数据；提交前必跑）
  contract  契约测试（M1）
''');
  return unknown == null ? 0 : 64;
}

Future<int> check() async {
  final steps = <({String name, Future<int> Function() run})>[
    (name: 'codegen', run: codegen),
    (name: 'format', run: formatCheck),
    (name: 'analyze', run: analyze),
    (name: 'layers', run: layerCheck),
    (name: 'goldens', run: goldenDeterminismCheck),
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

Future<int> codegen() async {
  final l10nCode = await _codegenL10n();
  final driftCode = await _codegenDrift();
  return l10nCode != 0 ? l10nCode : driftCode;
}

Future<int> _codegenL10n() async {
  const config = 'apps/app/l10n.yaml';
  const sources = <String>[
    config,
    'apps/app/lib/l10n/app_en.arb',
    'apps/app/lib/l10n/app_zh.arb',
  ];
  const generated = <String>[
    'apps/app/lib/l10n/app_localizations.dart',
    'apps/app/lib/l10n/app_localizations_en.dart',
    'apps/app/lib/l10n/app_localizations_zh.dart',
  ];

  final configFile = File(config);
  if (!configFile.existsSync()) {
    stdout.writeln('没有 $config，跳过 l10n 生成');
    return 0;
  }

  var newestSource = configFile.lastModifiedSync();
  for (final path in sources) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final modified = file.lastModifiedSync();
    if (modified.isAfter(newestSource)) newestSource = modified;
  }

  final upToDate = generated.every((String path) {
    final file = File(path);
    return file.existsSync() && !newestSource.isAfter(file.lastModifiedSync());
  });
  if (upToDate) {
    stdout.writeln('l10n 生成物已是最新，跳过 gen-l10n');
    return 0;
  }

  stdout.writeln('l10n 生成物缺失或过期 → flutter gen-l10n');
  return runProc('flutter', <String>['gen-l10n'], workingDirectory: 'apps/app');
}

Future<int> _codegenDrift() async {
  const driftGroups = <({List<String> sources, String generated})>[
    (
      sources: <String>[
        'apps/app/lib/src/data/local/local_tables.dart',
        'apps/app/lib/src/data/progress/progress_database.dart',
        'apps/app/lib/src/data/progress/progress_user_dao.dart',
        'apps/app/lib/src/data/progress/user_tables.dart',
      ],
      generated: 'apps/app/lib/src/data/progress/progress_database.g.dart',
    ),
    (
      sources: <String>[
        'apps/app/lib/src/data/cache/http_cache_database.dart',
        'apps/app/lib/src/data/cache/http_cache_downloads_dao.dart',
        'apps/app/lib/src/data/cache/http_cache_tables.dart',
      ],
      generated: 'apps/app/lib/src/data/cache/http_cache_database.g.dart',
    ),
  ];

  var stale = false;
  for (final group in driftGroups) {
    final generatedFile = File(group.generated);
    if (!generatedFile.existsSync()) {
      stale = true;
      break;
    }
    final genTime = generatedFile.lastModifiedSync();
    for (final src in group.sources) {
      final srcFile = File(src);
      if (srcFile.existsSync() && srcFile.lastModifiedSync().isAfter(genTime)) {
        stale = true;
      }
    }
  }
  if (!stale) {
    stdout.writeln('drift 生成物已是最新，跳过 codegen');
    return 0;
  }

  stdout.writeln('drift 生成物缺失或过期 → dart run build_runner build');
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
  stdout.writeln('契约测试见 packages/komga_api/test/contract_test.dart');
  return 0;
}

Future<int> installApp({String? deviceId}) async {
  final args = <String>['run', '--release', '--no-resident'];
  if (deviceId != null && deviceId.isNotEmpty) {
    args.addAll(<String>['-d', deviceId]);
  }
  return runProc('flutter', args, workingDirectory: 'apps/app');
}

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
