import 'dart:io';

import 'package:quds_language_id/quds_language_id.dart';

import 'studio_language_id_host.dart';

StudioLanguageIdHost createLanguageIdHost() => BundledStudioLanguageIdHost(
  createIdentifier: (model) => Cld3LanguageIdentifier(
    model: model,
    nativeLibraryPath: studioLanguageIdLibraryPath(),
  ),
);

/// The classifier library packaged with the app: `QUDS_LANGUAGE_ID_LIBRARY`
/// (Dart define or environment), then the platform's packaged location next
/// to the executable, otherwise null (the platform loader's search path,
/// which finds `libquds_language_id.so` in an Android APK's jniLibs).
String? studioLanguageIdLibraryPath() {
  const defined = String.fromEnvironment('QUDS_LANGUAGE_ID_LIBRARY');
  if (defined.isNotEmpty) return defined;
  final env = Platform.environment['QUDS_LANGUAGE_ID_LIBRARY'];
  if (env != null && env.isNotEmpty) return env;
  final executable = File(Platform.resolvedExecutable).parent.path;
  final candidates = Platform.isMacOS
      ? ['$executable/../Frameworks/libquds_language_id.dylib']
      : Platform.isWindows
      ? ['$executable\\quds_language_id.dll']
      : Platform.isLinux
      ? ['$executable/lib/libquds_language_id.so']
      : const <String>[];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
