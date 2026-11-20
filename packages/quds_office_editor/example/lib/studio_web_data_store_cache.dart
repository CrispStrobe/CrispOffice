import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'studio_web_data_store.dart';

StudioWebDataStore createDefaultStudioWebDataStore() =>
    const CacheStorageStudioWebDataStore();

/// [StudioWebDataStore] on the browser's Cache Storage (origin-private,
/// survives reloads, cleared with the site data). Keys become same-origin
/// request paths that the app never serves.
final class CacheStorageStudioWebDataStore implements StudioWebDataStore {
  const CacheStorageStudioWebDataStore({
    this.cacheName = 'quds-proofing-data-v1',
  });

  final String cacheName;

  static String _request(String key) =>
      '/__quds_proofing_data__/${Uri.encodeComponent(key)}';

  Future<web.Cache?> _open() async {
    try {
      return await web.window.caches.open(cacheName).toDart;
    } on Object {
      return null;
    }
  }

  @override
  Future<Uint8List?> read(String key) async {
    final cache = await _open();
    if (cache == null) return null;
    try {
      final found = await cache.match(_request(key).toJS).toDart;
      if (found == null) return null;
      final buffer = await found.arrayBuffer().toDart;
      return buffer.toDart.asUint8List();
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> write(String key, Uint8List bytes) async {
    final cache = await _open();
    if (cache == null) return false;
    try {
      await cache
          .put(
            _request(key).toJS,
            web.Response(
              bytes.toJS,
              web.ResponseInit(
                headers: web.Headers()
                  ..set('content-type', 'application/octet-stream'),
              ),
            ),
          )
          .toDart;
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> delete(String key) async {
    final cache = await _open();
    if (cache == null) return;
    try {
      await cache.delete(_request(key).toJS).toDart;
    } on Object {
      // Nothing stored or storage unavailable.
    }
  }
}
