import 'dart:convert';

import 'package:flutter/services.dart';

import 'studio_settings.dart';
import 'studio_window.dart';

class StudioRecentFile {
  const StudioRecentFile(this.path, this.name, {this.bookmark});

  final String path;
  final String name;
  final String? bookmark;

  Map<String, String> toJson() => {
    'path': path,
    'name': name,
    'bookmark': ?bookmark,
  };
}

class StudioRecentAccess {
  const StudioRecentAccess(this.path, this._token);

  final String path;
  final String? _token;

  Future<void> close() async {
    if (_token == null) return;
    try {
      await StudioRecentFiles.channel.invokeMethod<void>('end', _token);
    } on PlatformException {
      // Disposing an editor must not depend on a platform reply.
    } on MissingPluginException {
      // No platform scope was established in this process.
    }
  }
}

class StudioRecentFiles {
  StudioRecentFiles(this._backend);

  static final local = StudioRecentFiles(
    createDefaultStudioSettingsBackend(name: 'studio-recent-files'),
  );
  static const channel = MethodChannel('crispoffice/recent-files');
  static const limit = 12;

  final StudioSettingsBackend _backend;
  Future<void> _pending = Future<void>.value();

  Future<List<StudioRecentFile>> read() async {
    await _pending;
    return _read();
  }

  Future<List<StudioRecentFile>> _read() async {
    try {
      final contents = await _backend.read();
      if (contents == null || contents.length > 1000000) return const [];
      final decoded = jsonDecode(contents);
      if (decoded is! List) return const [];
      final entries = <StudioRecentFile>[];
      for (final entry in decoded.take(limit)) {
        if (entry is! Map) continue;
        final path = entry['path'];
        final name = entry['name'];
        final bookmark = entry['bookmark'];
        if (path is String &&
            path.isNotEmpty &&
            name is String &&
            name.isNotEmpty) {
          entries.add(
            StudioRecentFile(
              path,
              name,
              bookmark: bookmark is String ? bookmark : null,
            ),
          );
        }
      }
      return entries;
    } on Object {
      return const [];
    }
  }

  Future<void> remember(String path, String name) => _enqueue(() async {
    final existing = await _read();
    String? bookmark;
    if (StudioWindow.isMacOS) {
      try {
        bookmark = await channel.invokeMethod<String>('bookmark', path);
      } on PlatformException {
        // A file in the sandbox may have no security scope to persist.
      } on MissingPluginException {
        // Older macOS runners still support reopening accessible paths.
      }
    }
    final entries = [
      StudioRecentFile(
        path,
        name,
        bookmark:
            bookmark ??
            existing.where((entry) => entry.path == path).firstOrNull?.bookmark,
      ),
      ...existing.where((entry) => entry.path != path),
    ];
    await _backend.write(
      jsonEncode(entries.take(limit).map((entry) => entry.toJson()).toList()),
    );
  });

  Future<void> clear() => _enqueue(() => _backend.write('[]'));

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<StudioRecentAccess> begin(StudioRecentFile file) async {
    if (!StudioWindow.isMacOS || file.bookmark == null) {
      return StudioRecentAccess(file.path, null);
    }
    final scope = await channel.invokeMapMethod<String, String>(
      'begin',
      file.bookmark,
    );
    if (scope == null || scope['path'] == null || scope['token'] == null) {
      throw StateError('Recent file access is unavailable.');
    }
    return StudioRecentAccess(scope['path']!, scope['token']);
  }
}
