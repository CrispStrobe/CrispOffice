import 'dart:io';

/// Raster references belong to their actual host, independently of the
/// platform simulated by a widget test. Preserve existing Linux references.
String officeGolden(String name) {
  if (Platform.isMacOS) return 'goldens/macos/$name';
  if (Platform.isLinux && File('test/goldens/linux/$name').existsSync()) {
    return 'goldens/linux/$name';
  }
  return 'goldens/$name';
}
