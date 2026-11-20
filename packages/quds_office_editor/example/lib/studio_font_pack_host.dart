import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// App-owned optional font packs used by the Downloads Manager and Studio.
///
/// The store lives in the writable application-support directory. The signed
/// application bundle is never modified, and no Microsoft font is downloaded.
class StudioFontPackHost extends ChangeNotifier {
  OfficeFontPackStore? _store;
  List<OfficeFontPackStatus> _statuses = const <OfficeFontPackStatus>[];
  bool _busy = false;
  String? _error;

  List<OfficeFontPackStatus> get statuses => _statuses;
  bool get busy => _busy;
  String? get error => _error;

  Future<OfficeFontPackStore> _ensureStore() async {
    final existing = _store;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    return _store = OfficeFontPackStore('${support.path}/fonts');
  }

  Future<void> refresh() async {
    try {
      final store = await _ensureStore();
      _statuses = await store.statuses();
      _error = null;
    } on Object catch (error) {
      _error = '$error';
    }
    notifyListeners();
  }

  Future<void> install(OfficeFontPack pack) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final store = await _ensureStore();
      await store.install(pack);
      await store.registerInstalled();
      _statuses = await store.statuses();
    } on Object catch (error) {
      _error = '$error';
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> remove(OfficeFontPack pack) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final store = await _ensureStore();
      await store.remove(pack);
      _statuses = await store.statuses();
    } on Object catch (error) {
      _error = '$error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Registers already-installed faces after the host Office fonts.
  Future<void> registerInstalled() async {
    try {
      final store = await _ensureStore();
      await store.registerInstalled();
    } on Object {
      // Missing/corrupt optional packs keep the bundled/system fallbacks.
    }
  }
}

final StudioFontPackHost studioFontPackHost = StudioFontPackHost();
