import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

// Runs `tool/macros/office_macro.dart` in a child Dart VM for CLI tests.
//
// The CLI is compiled to kernel once and shared by every test file (and every
// later run) until the engine sources change, so an invocation skips
// front-end compilation of the whole engine and per-test time stays bounded.
// Every child has a hard deadline and is killed on timeout and on test
// teardown (including a test-level timeout), so no orphan survives its test.
//
// Call [registerOfficeMacroCliCleanup] from `main`: it starts preparing the
// kernel in `setUpAll` without blocking it, so neither the setUpAll timeout
// nor a test that times out can stop the shared compile; leftover children
// are killed after the file's tests.

/// Per-invocation deadline. Generous for slow CI runners; a hang still fails.
const Duration officeMacroCliTimeout = Duration(minutes: 2);

/// Per-test timeout for tests that start several CLI processes.
const Timeout officeMacroCliTestTimeout = Timeout(Duration(minutes: 5));

const Duration _compileTimeout = Duration(minutes: 10);
const String _script = 'tool/macros/office_macro.dart';
const String _cachePath = '.dart_tool/office_macro_cli';

final Set<Process> _live = <Process>{};
Future<String>? _entry;

/// Prepares the shared kernel for this file and kills leftover children.
void registerOfficeMacroCliCleanup() {
  setUpAll(() {
    _entry ??= _prepare();
  });
  tearDownAll(_killAll);
}

/// Runs the office macro CLI with [args] and returns its decoded result.
Future<ProcessResult> runOfficeMacroCli(
  List<String> args, {
  Duration timeout = officeMacroCliTimeout,
}) async {
  final entry = await (_entry ??= _prepare());
  final result = await _run(_dartExecutable(), <String>[
    if (entry.endsWith('.dart')) ..._packagesArgument(),
    entry,
    ...args,
  ], timeout);
  if (result == null) {
    fail(
      'office_macro ${args.join(' ')} did not exit within $timeout and was '
      'killed',
    );
  }
  return result;
}

List<String> _packagesArgument() => <String>[
  if (Platform.packageConfig case final String packages) '--packages=$packages',
];

/// The cached kernel for the current sources, compiling it when missing.
///
/// Test files run as isolates of one process, so a lock file created
/// exclusively (not an fcntl lock, which is per process) elects one compiler;
/// the others wait for its kernel. Falls back to the source script.
Future<String> _prepare() async {
  final cache = Directory(_cachePath)..createSync(recursive: true);
  final kernel = File('${cache.path}/office_macro-${_sourceKey()}.dill');
  final lock = File('${cache.path}/compile.lock');
  final deadline = DateTime.now().add(_compileTimeout);
  while (!kernel.existsSync()) {
    try {
      lock.createSync(exclusive: true);
    } on FileSystemException {
      final stale =
          lock.existsSync() &&
          DateTime.now().difference(lock.statSync().modified) > _compileTimeout;
      if (stale) lock.deleteSync();
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      continue;
    }
    try {
      if (!kernel.existsSync()) await _compile(cache, kernel);
    } finally {
      lock.deleteSync();
    }
    break;
  }
  if (kernel.existsSync()) return kernel.absolute.path;
  stderr.writeln(
    'office_macro kernel unavailable; running $_script from source',
  );
  return _script;
}

Future<void> _compile(Directory cache, File kernel) async {
  final staging = File('${kernel.path}.$pid.tmp');
  final result = await _run(
    _dartExecutable(),
    <String>[
      'compile',
      'kernel',
      // `dart compile` takes a file path here, not the VM's file: URI.
      if (Platform.packageConfig case final String config)
        '--packages=${Uri.parse(config).toFilePath()}',
      _script,
      '-o',
      staging.path,
    ],
    _compileTimeout,
    ownedByTest: false,
  );
  if (result == null || result.exitCode != 0 || !staging.existsSync()) {
    stderr.writeln(
      'office_macro kernel compile failed: '
      '${result == null ? 'timed out' : '${result.exitCode} ${result.stderr}'}',
    );
    if (staging.existsSync()) staging.deleteSync();
    return;
  }
  staging.renameSync(kernel.path);
  for (final old in cache.listSync().whereType<File>()) {
    if (old.path != kernel.path && old.path.endsWith('.dill')) {
      old.deleteSync();
    }
  }
}

/// Identifies the CLI sources: engine library, CLI script and package config.
String _sourceKey() {
  final files = <File>[
    File(_script),
    if (Platform.packageConfig case final String config)
      File.fromUri(Uri.parse(config)),
    ...Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart')),
  ]..sort((a, b) => a.path.compareTo(b.path));
  var hash = 0xcbf29ce484222325;
  for (final file in files) {
    final stat = file.statSync();
    for (final unit in utf8.encode(
      '${file.path}|${stat.size}|${stat.modified.microsecondsSinceEpoch};',
    )) {
      hash = ((hash ^ unit) * 0x100000001b3) & 0xffffffffffffffff;
    }
  }
  return hash.toUnsigned(64).toRadixString(16);
}

/// A Dart VM, also when the tests themselves run under `flutter_tester`.
///
/// `flutter_tester` does not exit when a script's `main` returns, so it must
/// never be used to host the CLI.
String _dartExecutable() {
  final executable = Platform.resolvedExecutable;
  final name = executable.split(Platform.pathSeparator).last.toLowerCase();
  if (name == 'dart' || name == 'dart.exe') return executable;
  final dartName = Platform.isWindows ? 'dart.exe' : 'dart';
  var directory = File(executable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = File(
      [
        directory.path,
        'dart-sdk',
        'bin',
        dartName,
      ].join(Platform.pathSeparator),
    );
    if (candidate.existsSync()) return candidate.path;
    directory = directory.parent;
  }
  return dartName;
}

/// Runs a child with a deadline; null when it had to be killed.
Future<ProcessResult?> _run(
  String executable,
  List<String> args,
  Duration timeout, {
  bool ownedByTest = true,
}) async {
  final process = await Process.start(executable, args);
  _live.add(process);
  if (ownedByTest) {
    try {
      addTearDown(() => _kill(process));
    } on StateError {
      // Outside a test body; [registerOfficeMacroCliCleanup] still kills it.
    }
  }
  final stdoutText = process.stdout.transform(utf8.decoder).join();
  final stderrText = process.stderr.transform(utf8.decoder).join();
  final int code;
  try {
    code = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    _kill(process);
    return null;
  }
  _live.remove(process);
  return ProcessResult(process.pid, code, await stdoutText, await stderrText);
}

void _kill(Process process) {
  if (_live.remove(process)) process.kill(ProcessSignal.sigkill);
}

void _killAll() {
  for (final process in _live.toList()) {
    _kill(process);
  }
}
