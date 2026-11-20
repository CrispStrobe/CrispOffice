import 'dart:typed_data';

import 'studio_web_data_store.dart';

/// Outside the browser nothing is kept (the native hosts install to disk).
StudioWebDataStore createDefaultStudioWebDataStore() => const _NoStore();

final class _NoStore implements StudioWebDataStore {
  const _NoStore();

  @override
  Future<Uint8List?> read(String key) async => null;

  @override
  Future<bool> write(String key, Uint8List bytes) async => false;

  @override
  Future<void> delete(String key) async {}
}
