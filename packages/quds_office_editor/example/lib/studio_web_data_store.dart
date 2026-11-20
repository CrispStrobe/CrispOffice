import 'dart:typed_data';

import 'studio_web_data_store_none.dart'
    if (dart.library.js_interop) 'studio_web_data_store_cache.dart'
    as platform;

/// Keeps verified proofing downloads (dictionaries, morphology database)
/// across browser sessions.
///
/// The store holds bytes only; it is never trusted. Every read is verified
/// again by the caller against the same compiled-in SHA-256/length pins the
/// native installers use, and anything that fails is deleted.
abstract interface class StudioWebDataStore {
  /// The stored bytes for [key], or null (also when storage is unavailable).
  Future<Uint8List?> read(String key);

  /// Stores [bytes]; returns false when the browser refused (quota, private
  /// mode, insecure origin). The download still works for this session.
  Future<bool> write(String key, Uint8List bytes);

  Future<void> delete(String key);
}

/// Cache Storage in browsers; a store that keeps nothing elsewhere.
StudioWebDataStore createDefaultStudioWebDataStore() =>
    platform.createDefaultStudioWebDataStore();

/// Status text for data kept in browser storage, with its size.
String studioWebStoredLocation(int bytes) =>
    'Stored in this browser (${(bytes / 1048576).toStringAsFixed(1)} MB, '
    're-verified against its pins on load)';
