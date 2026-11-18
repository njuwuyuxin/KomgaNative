#!/usr/bin/env dart

// 本地 Komga 服务器启停（联调用；不参与 CI）。
//
// 为什么是 Dart 而不是 .ps1：本机执行策略是 MachinePolicy=RemoteSigned，仓库里
// 未签名的 .ps1 直接执行会 PSSecurityException（tool/ci.dart、tool/emulator.dart 同因）。
//
// 服务器是原生 `java -jar komga-x.y.z.jar`，不是 Docker；背景与验证记录见
// docs/komga-api-verification.md §2，目录约定与用法见 docs/environment-setup.md §12。
//
// 用法：
//   dart run tool/komga.dart start     # 启动并等到 HTTP 就绪（首次约 10–20 秒）
//   dart run tool/komga.dart status    # 进程 / 端口 / 日志位置
//   dart run tool/komga.dart stop      # 停止（Windows 上是强杀，见 §12）
//   dart run tool/komga.dart start --port 25601 --home D:\tmp\komga
//
// 站点目录（KOMGA_HOME）里是：jar、config\（SQLite 数据库）、library\（漫画）、pages\（页图缓存）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const int _defaultPort = 25600;
const int _defaultWaitSeconds = 120;
const int _minJavaMajor = 17;
const String _stateFileName = '.komga-run.json';
const String _legacyHome = r'D:\DevTools\_verify\komga';

Future<void> main(List<String> args) async {
  final _Options options;
  try {
    options = _Options.parse(args);
  } on _UsageError catch (e) {
    stderr.writeln('${e.message}\n');
    _printUsage();
    exit(64);
  }
  if (options.help) {
    _printUsage();
    return;
  }
  final command = options.command;
  if (command == null) {
    _printUsage();
    exit(64);
  }
  final code = switch (command) {
    'start' => await _start(options),
    'stop' => await _stop(options),
    'status' => await _status(options),
    _ => _unknown(command),
  };
  exit(code);
}

// ---------------------------------------------------------------- commands

Future<int> _start(_Options options) async {
  final home = _resolveHome(options);
  final port = _portFor(options, null);
  stdout.writeln('站点目录：${home.path}（${home.source}）');

  final jar = _resolveJar(options, home.path);
  if (jar == null) {
    _printJarHelp(home.path);
    return 2;
  }
  final java = await _resolveJava(options);
  if (java == null) {
    _printJavaHelp();
    return 3;
  }

  if (await _portOpen(port)) {
    if (await _komgaUp(port)) {
      stdout
        ..writeln('端口 $port 上已经有一个 Komga 在跑，不重复启动。')
        ..writeln();
      _printHints(port, home.path);
      return 0;
    }
    stderr.writeln('端口 $port 被其它程序占用（不响应 Komga API）。换端口：--port 25601');
    return 5;
  }

  Directory(home.path).createSync(recursive: true);
  final stateFile = File(_statePath(home.path));
  if (stateFile.existsSync()) stateFile.deleteSync();

  final configDir = _join(home.path, 'config');
  stdout
    ..writeln(
      '启动：${_baseName(java)} -jar ${_baseName(jar)} --server.port=$port',
    )
    ..writeln('工作目录：${home.path}（pages\\ 缓存跟着它走，别换）');
  final Process process;
  try {
    process = await Process.start(
      java,
      <String>[
        '-jar',
        jar,
        '--server.port=$port',
        '--komga.config-dir=$configDir',
      ],
      workingDirectory: home.path,
      // detached：脚本退出后服务器继续跑；stdout 不接管，日志走 config\logs\komga.log。
      mode: ProcessStartMode.detached,
    );
  } on ProcessException catch (e) {
    stderr.writeln('启动失败：${e.message}');
    return 3;
  }
  _writeState(
    home.path,
    _State(pid: process.pid, port: port, jar: jar, startedAt: _now()),
  );

  final wait = options.waitSeconds ?? _defaultWaitSeconds;
  stdout.write('等待就绪（上限 ${wait}s）');
  final ready = await _waitReady(port, process.pid, wait);
  stdout.writeln();
  if (!ready) {
    stderr
      ..writeln('启动超时或进程提前退出。日志：${_logPath(home.path)}')
      ..writeln('排查后可用 `dart run tool/komga.dart stop` 清理。');
    final tail = _tailLog(home.path, 20);
    if (tail.isNotEmpty) stderr.writeln(tail);
    return 4;
  }
  stdout.writeln('Komga 已就绪（PID ${process.pid}）。');
  _printHints(port, home.path);
  return 0;
}

Future<int> _stop(_Options options) async {
  final home = _resolveHome(options);
  final state = _State.read(File(_statePath(home.path)));
  final port = _portFor(options, state?.port);
  final pids = <int>{};
  if (state != null && await _looksLikeKomga(state.pid)) pids.add(state.pid);
  if (pids.isEmpty) pids.addAll(await _findKomgaPids());
  if (pids.isEmpty) {
    _deleteState(home.path);
    final open = await _portOpen(port);
    if (open) {
      stderr.writeln('端口 $port 仍被占用，但没找到 Komga 进程（可能是别的程序）。');
      return 5;
    }
    stdout.writeln('没有正在运行的 Komga。');
    return 0;
  }

  for (final pid in pids) {
    stdout.writeln('停止 PID $pid ...');
    if (!Process.killPid(pid)) stderr.writeln('  kill 返回 false（进程可能已经退出）');
  }
  final freed = await _waitPortClosed(port);
  _deleteState(home.path);
  if (!freed) {
    stderr
      ..writeln('20 秒内端口 $port 仍未释放。')
      ..writeln('日志：${_logPath(home.path)}');
    return 5;
  }
  stdout
    ..writeln('已停止。')
    ..writeln('（Windows 上是 TerminateProcess，SQLite 的 -wal 文件会在下次启动时恢复。）');
  return 0;
}

Future<int> _status(_Options options) async {
  final home = _resolveHome(options);
  final state = _State.read(File(_statePath(home.path)));
  final port = _portFor(options, state?.port);
  final up = await _komgaUp(port);
  final open = up || await _portOpen(port);
  final portText = up
      ? 'Komga 在线'
      : open
      ? '被其它进程占用（不响应 Komga API）'
      : '未监听';
  stdout
    ..writeln('站点目录：${home.path}（${home.source}）')
    ..writeln('端口 $port：$portText');
  if (state != null) {
    final alive = await _processAlive(state.pid);
    stdout.writeln('PID ${state.pid}：${alive ? '存活' : '已退出（状态文件过期）'}');
    if (!alive && !open) _deleteState(home.path);
  }
  final jar = _resolveJar(options, home.path) ?? state?.jar;
  stdout
    ..writeln('jar：${jar ?? '（没找到）'}')
    ..writeln('日志：${_logPath(home.path)}');
  return up ? 0 : 1;
}

int _unknown(String command) {
  stderr
    ..writeln('未知命令：$command')
    ..writeln();
  _printUsage();
  return 64;
}

// ---------------------------------------------------------------- probing

Future<bool> _waitReady(int port, int pid, int seconds) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  var elapsed = 0;
  while (DateTime.now().isBefore(deadline)) {
    if (await _komgaUp(port)) return true;
    // 启动 10 秒后还没就绪又查不到进程，说明它已经死了（端口被占、配置错误……），
    // 没必要让用户干等两分钟。
    if (elapsed >= 10 && !await _processAlive(pid)) return false;
    stdout.write('.');
    await Future<void>.delayed(const Duration(seconds: 1));
    elapsed++;
  }
  return _komgaUp(port);
}

Future<bool> _komgaUp(int port) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/api/v1/libraries'),
    );
    final response = await request.close().timeout(const Duration(seconds: 3));
    await response.drain<void>();
    // 未登录是 401，带凭据是 200；403 说明认证中间件在，也是 Komga。
    return response.statusCode == 200 ||
        response.statusCode == 401 ||
        response.statusCode == 403;
  } on SocketException {
    return false;
  } on HttpException {
    return false;
  } on TimeoutException {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<bool> _portOpen(int port) async {
  try {
    final socket = await Socket.connect(
      '127.0.0.1',
      port,
      timeout: const Duration(milliseconds: 500),
    );
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  }
}

Future<bool> _waitPortClosed(int port) async {
  for (var i = 0; i < 20; i++) {
    if (!await _portOpen(port)) return true;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return !await _portOpen(port);
}

// ---------------------------------------------------------------- processes

Future<bool> _processAlive(int pid) async {
  if (Platform.isWindows) {
    final result = await _run('tasklist', <String>[
      '/FI',
      'PID eq $pid',
      '/NH',
    ]);
    return result.code == 0 && result.out.contains('$pid');
  }
  final result = await _run('ps', <String>['-p', '$pid', '-o', 'pid=']);
  return result.code == 0 && result.out.trim().isNotEmpty;
}

/// 确认 pid 对应的确实是 Komga，避免状态文件过期后 PID 被复用、误杀别的进程。
Future<bool> _looksLikeKomga(int pid) async {
  final String commandLine;
  if (Platform.isWindows) {
    final script =
        'Get-CimInstance Win32_Process -Filter "ProcessId=$pid" | '
        'ForEach-Object { \$_.CommandLine }';
    final result = await _run('powershell', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
    commandLine = result.out;
  } else {
    final result = await _run('ps', <String>['-p', '$pid', '-o', 'command=']);
    commandLine = result.out;
  }
  return _isKomgaCommandLine(commandLine);
}

bool _isKomgaCommandLine(String commandLine) =>
    commandLine.contains('.jar') && commandLine.contains('komga');

Future<List<int>> _findKomgaPids() async {
  if (Platform.isWindows) {
    const script =
        'Get-CimInstance Win32_Process -Filter "Name=\'java.exe\'" | '
        'Where-Object { \$_.CommandLine -like \'*komga-*.jar*\' } | '
        'ForEach-Object { \$_.ProcessId }';
    final result = await _run('powershell', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
    return _parsePids(result.out);
  }
  final result = await _run('pgrep', <String>['-f', r'komga-[0-9].*\.jar']);
  return _parsePids(result.out);
}

List<int> _parsePids(String out) => out
    .split('\n')
    .map((line) => int.tryParse(line.trim()))
    .whereType<int>()
    .toList();

// ---------------------------------------------------------------- resolving

({String path, String source}) _resolveHome(_Options options) {
  final explicit = options.home ?? Platform.environment['KOMGA_HOME'];
  if (explicit != null) {
    return (
      path: explicit,
      source: options.home != null ? '--home' : r'$KOMGA_HOME',
    );
  }
  final repoHome = _join(_repoRoot().path, '.komga');
  if (Directory(repoHome).existsSync()) {
    return (path: repoHome, source: '仓库 .komga/');
  }
  if (Platform.isWindows && Directory(_legacyHome).existsSync()) {
    return (path: _legacyHome, source: '历史验证实例');
  }
  return (path: repoHome, source: '默认，尚不存在');
}

String? _resolveJar(_Options options, String home) {
  final explicit = options.jar ?? Platform.environment['KOMGA_JAR'];
  if (explicit != null) {
    return File(explicit).existsSync() ? explicit : null;
  }
  final dir = Directory(home);
  if (!dir.existsSync()) return null;
  final jars =
      dir
          .listSync()
          .whereType<File>()
          .where((file) => RegExp(r'komga-\d[^\\/]*\.jar$').hasMatch(file.path))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  return jars.isEmpty ? null : jars.first.path;
}

Future<String?> _resolveJava(_Options options) async {
  final env = Platform.environment;
  final candidates = <String>[
    if (options.java != null) options.java!,
    if (env['KOMGA_JAVA'] case final String value) value,
    if (env['JAVA_HOME'] case final String home)
      _join(_join(home, 'bin'), Platform.isWindows ? 'java.exe' : 'java'),
    if (Platform.isWindows) r'D:\DevTools\jdk-17\bin\java.exe',
    'java',
  ];
  for (final candidate in candidates) {
    final major = await _javaMajor(candidate);
    if (major != null && major >= _minJavaMajor) return candidate;
  }
  return null;
}

Future<int?> _javaMajor(String executable) async {
  final result = await _run(executable, const <String>['-version']);
  if (result.code != 0) return null;
  final match = RegExp(r'version "([^"]+)"')
      .firstMatch('${result.out}\n${result.err}');
  final value = match?.group(1);
  if (value == null) return null;
  final parts = value.split('.');
  if (parts.length > 1 && parts.first == '1') return int.tryParse(parts[1]);
  return int.tryParse(parts.first.split('-').first);
}

int _portFor(_Options options, int? statePort) =>
    options.port ??
    statePort ??
    int.tryParse(Platform.environment['KOMGA_PORT'] ?? '') ??
    _defaultPort;

// ---------------------------------------------------------------- state

class _State {
  const _State({
    required this.pid,
    required this.port,
    required this.jar,
    required this.startedAt,
  });

  final int pid;
  final int port;
  final String jar;
  final String startedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'pid': pid,
    'port': port,
    'jar': jar,
    'startedAt': startedAt,
  };

  static _State? read(File file) {
    if (!file.existsSync()) return null;
    final Object? raw;
    try {
      raw = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return null;
    }
    if (raw is! Map<String, Object?>) return null;
    final pid = raw['pid'];
    final port = raw['port'];
    if (pid is! int || port is! int) return null;
    final jar = raw['jar'];
    final startedAt = raw['startedAt'];
    return _State(
      pid: pid,
      port: port,
      jar: jar is String ? jar : '',
      startedAt: startedAt is String ? startedAt : '',
    );
  }
}

void _writeState(String home, _State state) =>
    File(_statePath(home)).writeAsStringSync(jsonEncode(state.toJson()));

void _deleteState(String home) {
  final file = File(_statePath(home));
  if (file.existsSync()) file.deleteSync();
}

String _statePath(String home) => _join(home, _stateFileName);
String _logPath(String home) =>
    _join(_join(_join(home, 'config'), 'logs'), 'komga.log');

// ---------------------------------------------------------------- helpers

String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

String _now() => DateTime.now().toIso8601String();

Directory _repoRoot() {
  final script = Platform.script;
  if (script.isScheme('file')) {
    final toolDir = File.fromUri(script).parent;
    if (_baseName(toolDir.path) == 'tool') return toolDir.parent;
  }
  return Directory.current;
}

String _tailLog(String home, int lines) {
  final file = File(_logPath(home));
  if (!file.existsSync()) return '';
  final all = file.readAsStringSync().split('\n');
  final start = all.length <= lines ? 0 : all.length - lines;
  return all.sublist(start).join('\n');
}

Future<({int code, String out, String err})> _run(
  String executable,
  List<String> args,
) async {
  try {
    final result = await Process.run(
      executable,
      args,
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );
    return (
      code: result.exitCode,
      out: result.stdout as String,
      err: result.stderr as String,
    );
  } on ProcessException catch (e) {
    return (code: -1, out: '', err: e.message);
  }
}

void _printHints(int port, String home) {
  stdout
    ..writeln('  宿主机 / iOS 模拟器：http://127.0.0.1:$port')
    ..writeln('  Android 模拟器：    http://10.0.2.2:$port')
    ..writeln('  日志：${_logPath(home)}')
    ..writeln('  停止：dart run tool/komga.dart stop');
}

void _printJarHelp(String home) {
  stderr
    ..writeln('找不到 Komga jar（站点目录：$home）')
    ..writeln('  用 --jar 指定，或设 KOMGA_JAR，或把 jar 放进站点目录（komga-1.30.1.jar 这种命名）。')
    ..writeln('下载（单文件，不需要 Docker）：')
    ..writeln(
      "  Invoke-WebRequest 'https://github.com/gotson/komga/releases/download/1.30.1/komga-1.30.1.jar' -OutFile '$home\\komga-1.30.1.jar'",
    );
}

void _printJavaHelp() {
  stderr
    ..writeln(
      '找不到 Java $_minJavaMajor+（Komga 1.30 要求 17；PATH 上的 java 可能还是 11）。',
    )
    ..writeln('  用 --java 指定，或设置 JAVA_HOME / KOMGA_JAVA，例如：')
    ..writeln(r"  $env:KOMGA_JAVA = 'D:\DevTools\jdk-17\bin\java.exe'");
}

void _printUsage() {
  stdout.writeln(r'''
KomgaNative 本地 Komga 服务器（原生 java -jar，不是 Docker）

  dart run tool/komga.dart start     启动并等到就绪（首次约 10–20 秒）
  dart run tool/komga.dart status    查看进程 / 端口 / 日志
  dart run tool/komga.dart stop      停止

选项：
  --home <dir>    站点目录：$KOMGA_HOME → 仓库 .komga/ → D:\DevTools\_verify\komga
  --port <port>   端口：$KOMGA_PORT → 25600
  --jar <path>    指定 jar（默认取站点目录里最新的 komga-*.jar）
  --java <path>   Java 可执行文件（默认 JAVA_HOME / 常见 JDK 17 位置 / PATH）
  --wait <秒>     启动等待上限（默认 120）

状态文件与日志：<站点目录>\.komga-run.json、<站点目录>\config\logs\komga.log
''');
}

class _UsageError implements Exception {
  const _UsageError(this.message);

  final String message;
}

class _Options {
  const _Options({
    required this.command,
    required this.help,
    this.home,
    this.port,
    this.jar,
    this.java,
    this.waitSeconds,
  });

  final String? command;
  final bool help;
  final String? home;
  final int? port;
  final String? jar;
  final String? java;
  final int? waitSeconds;

  static _Options parse(List<String> args) {
    String? command;
    final values = <String, String>{};
    var help = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--help' || arg == '-h' || arg == 'help') {
        help = true;
        continue;
      }
      if (arg.startsWith('--')) {
        final equals = arg.indexOf('=');
        if (equals > 0) {
          values[arg.substring(0, equals)] = arg.substring(equals + 1);
          continue;
        }
        if (i + 1 >= args.length) throw _UsageError('缺少参数值：$arg');
        values[arg] = args[++i];
        continue;
      }
      if (command != null) throw _UsageError('多余的参数：$arg');
      command = arg;
    }
    for (final key in values.keys) {
      if (!const <String>{
        '--home',
        '--port',
        '--jar',
        '--java',
        '--wait',
      }.contains(key)) {
        throw _UsageError('未知选项：$key');
      }
    }
    return _Options(
      command: command,
      help: help,
      home: values['--home'],
      port: _parseInt(values['--port'], '--port'),
      jar: values['--jar'],
      java: values['--java'],
      waitSeconds: _parseInt(values['--wait'], '--wait'),
    );
  }

  static int? _parseInt(String? value, String name) {
    if (value == null) return null;
    final parsed = int.tryParse(value);
    if (parsed == null) throw _UsageError('$name 需要整数：$value');
    return parsed;
  }
}
