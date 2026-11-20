import 'dart:io';

import 'studio_data_root.dart';

/// Where the app's private, per-user data lives, synchronously (hosts create
/// their native backends before any async setup):
///
/// * macOS: `$HOME/Library/Application Support/<app>` (the sandbox
///   container when sandboxed).
/// * iOS and Android: `<application support>/<app>` as resolved at startup
///   by `initializeStudioDataRoot()` (iOS: the sandbox container's
///   `Library/Application Support`, backed up and never user-visible;
///   Android: the internal files directory, `Context.getFilesDir()`).
///   Without it, iOS derives the container from the temporary directory
///   (Flutter apps see no `$HOME`) and Android from the process name and
///   uid: `/data/user/<n>/<package>/files`.
/// * Windows: `%APPDATA%\<app>`; Linux: `$XDG_DATA_HOME/<app>`.
String studioPrivateDataDirectory({
  Map<String, String>? environment,
  String app = 'quds_office_studio',
}) {
  final env = environment ?? Platform.environment;
  final home = env['HOME'] ?? '';
  if ((Platform.isIOS || Platform.isAndroid) && studioMobileDataRoot != null) {
    return '$studioMobileDataRoot/$app';
  }
  if (Platform.isIOS) {
    final container = home.isNotEmpty
        ? home
        : Directory.systemTemp.absolute.parent.path;
    return '$container/Library/Application Support/$app';
  }
  if (Platform.isMacOS) {
    return '$home/Library/Application Support/$app';
  }
  if (Platform.isWindows) {
    return '${env['APPDATA'] ?? env['LOCALAPPDATA'] ?? '.'}\\$app';
  }
  if (Platform.isAndroid) {
    final files = androidFilesDirectory();
    if (files != null) return '$files/$app';
  }
  final data = env['XDG_DATA_HOME'];
  return '${data == null || data.isEmpty ? '$home/.local/share' : data}/$app';
}

/// `/data/user/<user>/<package>/files` for this Android process, or null
/// when it cannot be derived.
String? androidFilesDirectory({String? cmdline, String? status}) {
  try {
    final process = (cmdline ?? File('/proc/self/cmdline').readAsStringSync())
        .split('\u0000')
        .first
        .split(':')
        .first
        .trim();
    final uidLine = (status ?? File('/proc/self/status').readAsStringSync())
        .split('\n')
        .firstWhere((line) => line.startsWith('Uid:'));
    final uid = int.parse(
      uidLine.substring(4).trim().split(RegExp(r'\s+')).first,
    );
    if (!RegExp(
      r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$',
    ).hasMatch(process)) {
      return null;
    }
    return '/data/user/${uid ~/ 100000}/$process/files';
  } on Object {
    return null;
  }
}

/// The library a host packaged next to its executable, if present:
/// `Contents/Frameworks/lib<name>.dylib` (macOS), `<name>.dll` (Windows),
/// `lib/lib<name>.so` (Linux bundle) and `Frameworks/<name>.framework/<name>`
/// (iOS, embedded and signed). Android returns null: the default
/// `lib<name>.so` resolves through the APK's jniLibs.
String? studioPackagedLibrary(String name, {String? executable}) {
  final directory = File(executable ?? Platform.resolvedExecutable).parent.path;
  final candidates = Platform.isMacOS
      ? ['$directory/../Frameworks/lib$name.dylib']
      : Platform.isIOS
      ? ['$directory/Frameworks/$name.framework/$name']
      : Platform.isWindows
      ? ['$directory\\$name.dll']
      : Platform.isLinux
      ? ['$directory/lib/lib$name.so']
      : const <String>[];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
