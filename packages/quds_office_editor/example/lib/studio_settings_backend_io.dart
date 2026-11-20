import 'dart:convert';
import 'dart:io';

import 'studio_native_paths.dart';
import 'studio_settings.dart';

StudioSettingsBackend createDefaultStudioSettingsBackend(String name) =>
    Platform.environment.containsKey('FLUTTER_TEST')
    ? MemoryStudioSettingsBackend()
    : FileStudioSettingsBackend(
        File('${studioPrivateDataDirectory()}/settings/$name.json'),
      );

/// A settings document in one file. Writes go to a sibling temporary file
/// that is flushed and then renamed over the document (an atomic replace on
/// every supported file system), so a crash leaves the old or the new
/// document, never a mix. Unreadable documents are kept as `<file>.corrupt`.
final class FileStudioSettingsBackend implements StudioSettingsBackend {
  FileStudioSettingsBackend(this.file);

  final File file;

  @override
  String get location => file.path;

  @override
  Future<String?> read() async {
    try {
      // Invalid UTF-8 decodes to U+FFFD and then fails validation as a
      // corrupt document instead of throwing here.
      return utf8.decode(await file.readAsBytes(), allowMalformed: true);
    } on PathNotFoundException {
      return null;
    }
  }

  @override
  Future<void> write(String contents) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<void> quarantine(String contents) async {
    try {
      if (await file.exists()) await file.rename('${file.path}.corrupt');
    } on Object {
      // Best effort: the next save replaces the document anyway.
    }
  }
}
