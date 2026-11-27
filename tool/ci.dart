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
  final rest = args.length > 1 ? args.sublist(1) : const <String>[];
  final code = switch (command) {
    'check' => await check(includeGoldens: !rest.contains('--no-goldens')),
    'check-golden' => await checkGolden(),
    'codegen' => await codegen(),
    'fix' => await fix(),
    'analyze' => await analyze(),
    'test' => await test(
      includeGoldens: !rest.contains('--no-goldens'),
      onlyGoldens: rest.contains('--only-goldens'),
    ),
    'golden' => await golden(),
    'layers' => await layerCheck(),
    'install' => await installApp(
      deviceId: rest.isNotEmpty ? rest.first : null,
    ),
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

  check [--no-goldens]  生成代码（按需）+ 格式 + 分析 + 分层规则 + 全部测试（默认；--no-goldens 跳过 apps/app/test/golden）
  check-golden          生成代码（按需）+ 黄金图确定性检查 + 黄金图测试（Windows CI 基线 Job 用）
  codegen               只跑生成代码（drift + l10n；生成物不入库，CI 上由 check 自动触发）
  fix                   自动格式化 + dart fix --apply
  analyze               只跑静态分析
  layers                只跑分层、单文件 ≤350 行、单类 ≤300 行与裸 catch (_) 检查
  test [--no-goldens|--only-goldens]
                        只跑测试（纯 Dart 包用 dart test，Flutter 包用 flutter test）
  golden                重新生成黄金图基线（仅 Windows，与 CI 一致）
  install [device]      构建 release、装到模拟器并启动（保留应用数据；提交前必跑）
  contract              契约测试（M1）
''');
  return unknown == null ? 0 : 64;
}

Future<int> check({bool includeGoldens = true}) async {
  final steps = <({String name, Future<int> Function() run})>[
    (name: 'codegen', run: codegen),
    (name: 'format', run: formatCheck),
    (name: 'analyze', run: analyze),
    (name: 'layers', run: layerCheck),
    (name: 'goldens', run: goldenDeterminismCheck),
    (name: 'tests', run: () => test(includeGoldens: includeGoldens)),
  ];
  return _runSteps(steps);
}

Future<int> checkGolden() async {
  final steps = <({String name, Future<int> Function() run})>[
    (name: 'codegen', run: codegen),
    (name: 'goldens', run: goldenDeterminismCheck),
    (name: 'golden-tests', run: () => test(onlyGoldens: true)),
  ];
  return _runSteps(steps);
}

Future<int> _runSteps(
  List<({String name, Future<int> Function() run})> steps,
) async {
  final results = <String, ({int code, Duration elapsed})>{};
  for (final step in steps) {
    stdout.writeln('\n=== ${step.name} ===');
    final sw = Stopwatch()..start();
    final code = await step.run();
    sw.stop();
    results[step.name] = (code: code, elapsed: sw.elapsed);
    if (code != 0) {
      stdout.writeln(
        '\n!!! ${step.name} 失败（exit $code，耗时 ${_fmtDuration(sw.elapsed)}），后续步骤仍会执行以便一次看到全部问题',
      );
    }
  }

  stdout.writeln('\n=== 汇总 ===');
  var failed = false;
  results.forEach((name, r) {
    final ok = r.code == 0;
    failed |= !ok;
    stdout.writeln(
      '${ok ? 'PASS' : 'FAIL'}  ${name.padRight(14)} (${_fmtDuration(r.elapsed)})',
    );
  });
  return failed ? 1 : 0;
}

String _fmtDuration(Duration d) =>
    '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';

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
  final code = await runProc('dart', <String>[
    'run',
    'build_runner',
    'build',
  ], workingDirectory: 'apps/app');
  if (code == 0) {
    final now = DateTime.now();
    for (final group in driftGroups) {
      final generatedFile = File(group.generated);
      if (generatedFile.existsSync()) {
        generatedFile.setLastModifiedSync(now);
      }
    }
  }
  return code;
}

Future<int> analyze() => runProc('dart', <String>['analyze', '.']);

List<String> _testRunnerFlags() {
  final flags = <String>[];
  if (Platform.environment['GITHUB_ACTIONS'] == 'true') {
    flags.add('--reporter=github');
  }
  if (Platform.environment['CI'] == 'true') {
    final cpus = Platform.numberOfProcessors;
    if (cpus > 0) {
      flags.add('--concurrency=${cpus.clamp(1, 8)}');
    }
  }
  return flags;
}

/// 收集 `apps/app/test/` 下除 `golden/` 之外的全部测试入口（目录或根级 `*_test.dart`）。
/// 新增非黄金测试文件或子目录会自动纳入，无需手动维护白名单或 tag。
List<String> _nonGoldenAppTestTargets() {
  final root = Directory('apps/app/test');
  if (!root.existsSync()) return const <String>[];
  final targets = <String>[];
  for (final entity in root.listSync()) {
    final name = entity.uri.pathSegments.where((String s) => s.isNotEmpty).last;
    if (entity is Directory) {
      if (name == 'golden') continue;
      final hasTests = entity
          .listSync(recursive: true)
          .any(
            (FileSystemEntity e) => e is File && e.path.endsWith('_test.dart'),
          );
      if (hasTests) targets.add('test/$name');
    } else if (entity is File && name.endsWith('_test.dart')) {
      targets.add('test/$name');
    }
  }
  targets.sort();
  return targets;
}

Future<int> test({bool includeGoldens = true, bool onlyGoldens = false}) async {
  final flags = _testRunnerFlags();
  if (onlyGoldens) {
    stdout.writeln('--- flutter test apps/app (test/golden)');
    return runProc('flutter', <String>[
      'test',
      ...flags,
      'test/golden',
    ], workingDirectory: 'apps/app');
  }

  var code = 0;
  for (final pkg in _purePackages) {
    stdout.writeln('--- dart test $pkg');
    final c = await runProc('dart', <String>[
      'test',
      ...flags,
    ], workingDirectory: pkg);
    if (c != 0) code = c;
  }
  for (final pkg in _flutterPackages) {
    if (pkg == 'apps/app' && !includeGoldens) {
      final targets = _nonGoldenAppTestTargets();
      stdout.writeln(
        '--- flutter test apps/app (excluding test/golden, ${targets.length} targets)',
      );
      final c = await runProc('flutter', <String>[
        'test',
        ...flags,
        ...targets,
      ], workingDirectory: pkg);
      if (c != 0) code = c;
      continue;
    }
    stdout.writeln('--- flutter test $pkg');
    final c = await runProc('flutter', <String>[
      'test',
      ...flags,
    ], workingDirectory: pkg);
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
  final summary = args.length <= 10
      ? args.join(' ')
      : '${args.take(6).join(' ')} ... (${args.length} args)';
  stdout.writeln(
    '\$ $executable $summary${workingDirectory == null ? '' : '  (cwd: $workingDirectory)'}',
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
