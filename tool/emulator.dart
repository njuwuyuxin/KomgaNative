#!/usr/bin/env dart

// KomgaNative 本地 Android 模拟器启动器。
//
// 为什么是 Dart 而不是 .ps1：与 tool/ci.dart 同样的理由（Windows 执行策略会拦
// 仓库里的 .ps1；Dart 脚本跨平台，且团队已经习惯用 tool/ 下的 Dart 入口）。
//
// 用法：
//   dart run tool/emulator.dart                 # 启动（首次自动建 AVD），等到开机完成
//   dart run tool/emulator.dart --run           # 启动后直接 flutter run
//   dart run tool/emulator.dart --list          # 看已有 AVD 与硬件加速状态
//   dart run tool/emulator.dart --cold          # 冷启动（忽略 quickboot 快照）
//   dart run tool/emulator.dart --wipe          # 清空用户数据后启动
//   dart run tool/emulator.dart --headless      # 无窗口（脚本化跑）
//   dart run tool/emulator.dart --stop          # 关闭正在运行的模拟器
//
// 一次性环境（见 docs/environment-setup.md §11.1）：
//   sdkmanager "emulator" "system-images;android-36;google_apis;x86_64"
//   + AEHD 驱动（需要管理员，silent_install.bat）
import 'dart:async';
import 'dart:io';

const String _defaultAvd = 'kn_api36';
const String _defaultImage = 'system-images;android-36;google_apis;x86_64';
const String _defaultDevice = 'pixel_7';
const String _defaultGpu = 'host';
const int _defaultMemoryMb = 4096;
const int _bootTimeoutSeconds = 300;

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final sdk = _sdkRoot();
  if (sdk == null) {
    stderr.writeln('找不到 Android SDK：请设置 ANDROID_HOME 或 ANDROID_SDK_ROOT。');
    exit(2);
  }
  final tools = _Tools(sdk);
  if (!tools.emulator.existsSync()) {
    stderr
      ..writeln('未安装模拟器：${tools.emulator.path} 不存在。')
      ..writeln('先执行（无需管理员）：')
      ..writeln('  sdkmanager "emulator" "$_defaultImage"');
    exit(2);
  }

  if (options.list) {
    await _list(tools, options);
    return;
  }
  if (options.stop) {
    await _stop(tools);
    return;
  }
  await _start(tools, options);
}

// ---------------------------------------------------------------- actions

Future<void> _list(_Tools tools, _Options options) async {
  final avds = await _listAvds(tools);
  stdout.writeln('AVD（默认：${options.avd}）：');
  if (avds.isEmpty) {
    stdout.writeln('  （无，首次启动会自动创建）');
  } else {
    for (final name in avds) {
      stdout.writeln('  ${name == options.avd ? '*' : ' '} $name');
    }
  }
  stdout.writeln('\n硬件加速：');
  final accel = await _accelCheck(tools);
  for (final line in '${accel.out}\n${accel.err}'.split('\n')) {
    if (line.trim().isNotEmpty) stdout.writeln('  $line');
  }
  stdout.writeln('  （exit ${accel.code}，0 = 可用）');
  final imageDir = _imageDir(tools.sdk, options.image);
  stdout.writeln(
    '\n系统镜像 ${options.image}：${imageDir.existsSync() ? '已安装' : '缺失'}',
  );
}

Future<void> _stop(_Tools tools) async {
  final serials = await _emulatorSerials(tools);
  if (serials.isEmpty) {
    stdout.writeln('没有正在运行的模拟器。');
    return;
  }
  for (final serial in serials) {
    stdout.writeln('关闭 $serial ...');
    await _run(tools.adb.path, <String>['-s', serial, 'emu', 'kill']);
  }
}

Future<void> _start(_Tools tools, _Options options) async {
  final running = await _emulatorSerials(tools);
  for (final serial in running) {
    if (await _avdName(tools, serial) == options.avd) {
      stdout.writeln('${options.avd} 已在运行（$serial），跳过启动。');
      await _afterBoot(options, serial);
      return;
    }
  }

  final accel = await _accelCheck(tools);
  if (accel.code != 0) {
    stderr
      ..writeln('硬件加速不可用，x86_64 镜像无法启动：')
      ..writeln('${accel.out}\n${accel.err}'.trim())
      ..writeln('装 AEHD（需要管理员，见 docs/environment-setup.md §11.1）。');
    exit(3);
  }
  stdout.writeln('硬件加速：${accel.out.trim()}');

  if (!(await _listAvds(tools)).contains(options.avd)) {
    await _createAvd(tools, options);
  }

  final before = running.toSet();
  final log = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}komganative-emulator.log',
  );
  final launchArgs = <String>[
    '-avd',
    options.avd,
    '-gpu',
    options.gpu,
    '-memory',
    '${options.memoryMb}',
    '-no-boot-anim',
    // gfxstream 的 Vulkan 后端在部分 NVIDIA 驱动上会让 guest 卡在开机（本机 2026-11-17：
    // `-gpu host` 下 adb 一直 offline，关掉 Vulkan 后 25 秒开机）。关掉它仍走 host GLES，
    // 硬件加速不受影响。
    '-feature',
    '-Vulkan',
    if (options.cold) '-no-snapshot-load',
    if (options.wipe) '-wipe-data',
    if (options.headless) '-no-window',
  ];
  stdout.writeln('启动：${tools.emulator.path} ${launchArgs.join(' ')}');
  final process = await Process.start(
    tools.emulator.path,
    launchArgs,
    mode: ProcessStartMode.detachedWithStdio,
  );
  final sink = log.openWrite();
  final subs = <StreamSubscription<List<int>>>[
    process.stdout.listen(sink.add),
    process.stderr.listen(sink.add),
  ];
  Future<void> stopLogging() async {
    for (final sub in subs) {
      await sub.cancel();
    }
    await sink.flush();
    await sink.close();
  }

  // detachedWithStdio 的 Process 不支持 exitCode（会抛 StateError），
  // 所以"进程是否活着"只能靠 adb 是否看到设备来判断（见 _waitForBoot）。
  stdout.write('等待开机');
  final serial = await _waitForBoot(tools, before, logPath: log.path);
  stdout.writeln();
  if (serial == null) {
    final tail = _tail(log, 25);
    await stopLogging();
    stderr
      ..writeln('开机失败或超时（${_bootTimeoutSeconds}s）。模拟器日志：${log.path}')
      ..writeln(tail);
    exit(4);
  }
  // 日志订阅会一直挂住事件循环，开完机就收掉，否则脚本不会退出。
  await stopLogging();
  await _afterBoot(options, serial);
}

/// 开机之后的统一收尾：打印下一步提示，`--run` 时转交 `flutter run`。
Future<void> _afterBoot(_Options options, String serial) async {
  stdout
    ..writeln('模拟器已就绪：$serial')
    ..writeln('  flutter run -d $serial')
    ..writeln(
      '  adb install -r apps/app/build/app/outputs/flutter-apk/app-debug.apk',
    )
    ..writeln('  本机 Komga 用 http://10.0.2.2:25600');

  if (options.run) {
    stdout.writeln('\n=== flutter run ===');
    final result = await _run(
      'flutter',
      <String>['run', '-d', serial],
      workingDirectory: 'apps/app',
      inheritStdio: true,
    );
    if (result.code != 0) exit(result.code);
  }
}

// ---------------------------------------------------------------- AVD

Future<void> _createAvd(_Tools tools, _Options options) async {
  final imageDir = _imageDir(tools.sdk, options.image);
  if (!imageDir.existsSync()) {
    stderr
      ..writeln('系统镜像未安装：$options.image')
      ..writeln('先执行（无需管理员）：')
      ..writeln('  sdkmanager "$options.image"');
    exit(2);
  }
  final avdmanager = _avdmanager(tools.sdk);
  if (avdmanager == null) {
    stderr.writeln('找不到 avdmanager（cmdline-tools 未安装？）');
    exit(2);
  }
  stdout.writeln(
    '创建 AVD ${options.avd}（${options.device} / ${options.image}）...',
  );
  final java = _javaHome();
  final process = await Process.start(
    avdmanager,
    <String>[
      'create',
      'avd',
      '-n',
      options.avd,
      '-k',
      options.image,
      '-d',
      options.device,
      '--force',
    ],
    runInShell: Platform.isWindows,
    environment: <String, String>{
      ...Platform.environment,
      if (java != null) 'JAVA_HOME': java,
    },
  );
  process.stdin.writeln('no');
  await process.stdin.close();
  final out = await process.stdout.transform(systemEncoding.decoder).join();
  final err = await process.stderr.transform(systemEncoding.decoder).join();
  final code = await process.exitCode;
  if (code != 0) {
    stderr
      ..writeln('创建 AVD 失败（exit $code）')
      ..writeln(out)
      ..writeln(err);
    exit(3);
  }
  stdout.writeln('已创建 AVD ${options.avd}');
}

Future<List<String>> _listAvds(_Tools tools) async {
  final result = await _run(tools.emulator.path, <String>['-list-avds']);
  if (result.code != 0) return <String>[];
  return result.out
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('INFO'))
      .toList();
}

// ---------------------------------------------------------------- boot

Future<String?> _waitForBoot(
  _Tools tools,
  Set<String> before, {
  required String logPath,
}) async {
  final deadline = DateTime.now().add(
    const Duration(seconds: _bootTimeoutSeconds),
  );
  var waited = 0;
  while (DateTime.now().isBefore(deadline)) {
    final states = await _emulatorStates(tools);
    final fresh = states.keys
        .where((serial) => !before.contains(serial))
        .toList();
    if (fresh.isEmpty) {
      // adb 在 60 秒内一次都没看到新设备：多半是 emulator 启动失败（AVD 损坏、
      // 加速不可用、端口占用……），提前失败，别让用户干等 5 分钟。
      if (waited >= 60) {
        stderr.writeln('\nadb 60 秒内没有看到新的模拟器设备，判定启动失败。');
        stderr.writeln('日志：$logPath');
        return null;
      }
    } else {
      final serial = fresh.first;
      if (states[serial] == 'device') {
        final booted = await _run(tools.adb.path, <String>[
          '-s',
          serial,
          'shell',
          'getprop',
          'sys.boot_completed',
        ]);
        if (booted.out.trim() == '1') return serial;
      }
    }
    if (waited % 10 == 0) stdout.write('.');
    await Future<void>.delayed(const Duration(seconds: 2));
    waited += 2;
  }
  return null;
}

Future<Map<String, String>> _emulatorStates(_Tools tools) async {
  final result = await _run(tools.adb.path, <String>['devices']);
  if (result.code != 0) return <String, String>{};
  final states = <String, String>{};
  for (final line in result.out.split('\n').skip(1)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].startsWith('emulator-')) {
      states[parts[0]] = parts[1];
    }
  }
  return states;
}

Future<List<String>> _emulatorSerials(_Tools tools) async =>
    (await _emulatorStates(tools)).keys.toList();

/// 查运行中的模拟器用的是哪个 AVD（`adb emu avd name` 返回 "名字\nOK"）。
Future<String?> _avdName(_Tools tools, String serial) async {
  final result = await _run(tools.adb.path, <String>[
    '-s',
    serial,
    'emu',
    'avd',
    'name',
  ]);
  if (result.code != 0) return null;
  for (final line in result.out.split('\n')) {
    final text = line.trim();
    if (text.isNotEmpty && text != 'OK') return text;
  }
  return null;
}

Future<_Result> _accelCheck(_Tools tools) =>
    _run(tools.emulator.path, <String>['-accel-check']);

// ---------------------------------------------------------------- helpers

Directory? _sdkRoot() {
  for (final key in <String>['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    final value = Platform.environment[key];
    if (value != null && value.trim().isNotEmpty) {
      final dir = Directory(value.trim());
      if (dir.existsSync()) return dir;
    }
  }
  final home = Platform.environment['HOME'] ?? '';
  final fallback = Platform.isWindows
      ? r'D:\DevTools\android-sdk'
      : '$home/Android/Sdk';
  final dir = Directory(fallback);
  return dir.existsSync() ? dir : null;
}

String? _javaHome() {
  final env = Platform.environment['JAVA_HOME'];
  if (env != null && env.trim().isNotEmpty) return env.trim();
  if (Platform.isWindows) {
    const fallback = r'D:\DevTools\jdk-17';
    if (Directory(fallback).existsSync()) return fallback;
  }
  return null;
}

Directory _imageDir(Directory sdk, String image) => Directory(
  '${sdk.path}${Platform.pathSeparator}'
  '${image.split(';').join(Platform.pathSeparator)}',
);

String? _avdmanager(Directory sdk) {
  final cmdline = Directory(
    '${sdk.path}${Platform.pathSeparator}cmdline-tools',
  );
  if (!cmdline.existsSync()) return null;
  final sep = Platform.pathSeparator;
  final candidates = <String>[
    '${cmdline.path}${sep}latest${sep}bin',
    ...cmdline.listSync().whereType<Directory>().map(
      (dir) => '${dir.path}${sep}bin',
    ),
  ];
  for (final dir in candidates) {
    final file = File(
      '$dir${sep}avdmanager${Platform.isWindows ? '.bat' : ''}',
    );
    if (file.existsSync()) return file.path;
  }
  return null;
}

String _tail(File file, int lines) {
  if (!file.existsSync()) return '（无日志）';
  final all = file.readAsLinesSync();
  return all.length <= lines
      ? all.join('\n')
      : all.sublist(all.length - lines).join('\n');
}

Future<_Result> _run(
  String executable,
  List<String> args, {
  String? workingDirectory,
  bool inheritStdio = false,
}) async {
  try {
    if (inheritStdio) {
      final process = await Process.start(
        executable,
        args,
        workingDirectory: workingDirectory,
        runInShell: Platform.isWindows,
        mode: ProcessStartMode.inheritStdio,
      );
      return _Result(await process.exitCode, '', '');
    }
    final result = await Process.run(
      executable,
      args,
      workingDirectory: workingDirectory,
      runInShell: Platform.isWindows,
    );
    return _Result(result.exitCode, '${result.stdout}', '${result.stderr}');
  } on ProcessException catch (error) {
    stderr.writeln('执行失败：$executable -> $error');
    return const _Result(127, '', '');
  }
}

void _printUsage() {
  stdout.writeln('''
KomgaNative 本地模拟器

  dart run tool/emulator.dart              启动并等到开机完成（首次自动建 AVD）
  dart run tool/emulator.dart --run        启动后立即 flutter run
  dart run tool/emulator.dart --list       列出 AVD / 硬件加速状态
  dart run tool/emulator.dart --stop       关闭正在运行的模拟器

选项：
  --avd <name>       AVD 名（默认 $_defaultAvd）
  --image <pkg>      系统镜像（默认 $_defaultImage）
  --device <id>      设备模板（默认 $_defaultDevice）
  --gpu <mode>       host / swiftshader_indirect（默认 $_defaultGpu）
  --memory <mb>      内存（默认 $_defaultMemoryMb）
  --cold             忽略快照冷启动
  --wipe             清空数据
  --headless         无窗口
''');
}

// ---------------------------------------------------------------- types

class _Options {
  const _Options({
    required this.avd,
    required this.image,
    required this.device,
    required this.gpu,
    required this.memoryMb,
    required this.run,
    required this.list,
    required this.stop,
    required this.cold,
    required this.wipe,
    required this.headless,
    required this.help,
  });

  factory _Options.parse(List<String> args) {
    var avd = _defaultAvd;
    var image = _defaultImage;
    var device = _defaultDevice;
    var gpu = _defaultGpu;
    var memory = _defaultMemoryMb;
    var run = false;
    var list = false;
    var stop = false;
    var cold = false;
    var wipe = false;
    var headless = false;
    var help = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String? next() => i + 1 < args.length ? args[++i] : null;
      final eq = arg.indexOf('=');
      final key = eq >= 0 ? arg.substring(0, eq) : arg;
      final inline = eq >= 0 ? arg.substring(eq + 1) : null;
      switch (key) {
        case '--avd':
          avd = inline ?? next() ?? avd;
        case '--image':
          image = inline ?? next() ?? image;
        case '--device':
          device = inline ?? next() ?? device;
        case '--gpu':
          gpu = inline ?? next() ?? gpu;
        case '--memory':
          memory = int.tryParse(inline ?? next() ?? '') ?? memory;
        case '--run':
          run = true;
        case '--list':
          list = true;
        case '--stop':
          stop = true;
        case '--cold':
          cold = true;
        case '--wipe':
          wipe = true;
        case '--headless':
          headless = true;
        case '--help':
          help = true;
        default:
          stderr.writeln('未知参数：$arg');
          help = true;
      }
    }
    return _Options(
      avd: avd,
      image: image,
      device: device,
      gpu: gpu,
      memoryMb: memory,
      run: run,
      list: list,
      stop: stop,
      cold: cold,
      wipe: wipe,
      headless: headless,
      help: help,
    );
  }

  final String avd;
  final String image;
  final String device;
  final String gpu;
  final int memoryMb;
  final bool run;
  final bool list;
  final bool stop;
  final bool cold;
  final bool wipe;
  final bool headless;
  final bool help;
}

class _Tools {
  _Tools(this.sdk);

  final Directory sdk;

  String get _sep => Platform.pathSeparator;
  String get _exe => Platform.isWindows ? '.exe' : '';

  File get emulator => File('${sdk.path}${_sep}emulator${_sep}emulator$_exe');
  File get adb => File('${sdk.path}${_sep}platform-tools${_sep}adb$_exe');
}

class _Result {
  const _Result(this.code, this.out, this.err);

  final int code;
  final String out;
  final String err;
}
