import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'studio_settings.dart';

/// Local ribbon preferences. IDs are stable command IDs, never translated text.
/// Unknown IDs are retained so contextual groups and newer versions can return.
class StudioRibbonPreferences extends ChangeNotifier {
  StudioRibbonPreferences({
    this.persist = true,
    Future<File> Function()? file,
    StudioSettingsBackend? backend,
  }) : _file = file ?? _defaultFile,
       _backend =
           backend ??
           (kIsWeb && persist
               ? createDefaultStudioSettingsBackend(name: 'ribbon')
               : null);

  final bool persist;
  final Future<File> Function() _file;

  /// Storage other than the native file (the browser's Cache Storage on the
  /// web); the document format is the same.
  final StudioSettingsBackend? _backend;
  final Map<String, List<String>> _orders = <String, List<String>>{};
  final Map<String, Set<String>> _hidden = <String, Set<String>>{};
  Future<void>? _loadFuture;
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;
  int _revision = 0;

  bool _compact = true;
  bool _showCommandLabels = false;
  bool _showGroupLabels = true;
  bool _collapsed = false;
  String? _saveError;

  bool get compact => _compact;
  bool get showCommandLabels => _showCommandLabels;
  bool get showGroupLabels => _showGroupLabels;
  bool get collapsed => _collapsed;
  String? get saveError => _saveError;

  static String tabsScope(String app) => 'tabs.$app';
  static String groupsScope(String app, String tab) => 'groups.$app.$tab';

  static Future<File> _defaultFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/CrispOffice/ribbon.json');
  }

  /// Missing, malformed, or newer settings leave the usable defaults intact.
  /// Edits made while a slow read is in flight take precedence over that read.
  Future<void> load() => _loadFuture ??= _read();

  Future<void> _read() async {
    if (!persist) return;
    final revision = _revision;
    try {
      final String? text;
      final backend = _backend;
      if (backend != null) {
        text = await backend.read();
      } else {
        final file = await _file();
        if (!await file.exists() || await file.length() > 262144) return;
        text = await file.readAsString();
      }
      if (text == null || text.length > 262144) return;
      final Object? decoded = jsonDecode(text);
      if (_disposed || _revision != revision) return;
      if (decoded is! Map<String, Object?> || decoded['version'] != 1) return;
      _compact = decoded['compact'] is bool
          ? decoded['compact']! as bool
          : true;
      _showCommandLabels = decoded['showCommandLabels'] == true;
      _showGroupLabels = decoded['showGroupLabels'] is bool
          ? decoded['showGroupLabels']! as bool
          : true;
      _collapsed = decoded['collapsed'] == true;
      _readLists(decoded['orders'], (key, values) => _orders[key] = values);
      _readLists(
        decoded['hidden'],
        (key, values) => _hidden[key] = values.toSet(),
      );
      notifyListeners();
    } on Object {
      // Preference loading must never prevent opening or editing a document.
    }
  }

  static void _readLists(
    Object? source,
    void Function(String, List<String>) accept,
  ) {
    if (source is! Map<String, Object?>) return;
    for (final entry in source.entries.take(64)) {
      if (entry.value is! List<Object?> || entry.key.length > 100) continue;
      final values = (entry.value! as List<Object?>)
          .whereType<String>()
          .where((value) => value.isNotEmpty && value.length <= 100)
          .take(128)
          .toSet()
          .toList();
      accept(entry.key, values);
    }
  }

  List<String> orderedIds(String scope, Iterable<String> defaults) {
    final available = defaults.toSet();
    return <String>[
      for (final id in _orders[scope] ?? const <String>[])
        if (available.remove(id)) id,
      ...available,
    ];
  }

  bool isVisible(String scope, String id) =>
      !(_hidden[scope]?.contains(id) ?? false);

  void setVisible(String scope, String id, bool visible) {
    final hidden = _hidden.putIfAbsent(scope, () => <String>{});
    final changed = visible ? hidden.remove(id) : hidden.add(id);
    if (changed) _changed();
  }

  void setOrder(String scope, List<String> ids) {
    final unique = ids.toSet().toList();
    final ordered = <String>[
      ...unique,
      for (final id in _orders[scope] ?? const <String>[])
        if (!unique.contains(id)) id,
    ];
    if (listEquals(_orders[scope], ordered)) return;
    _orders[scope] = ordered;
    _changed();
  }

  void setCompact(bool value) {
    if (_compact == value) return;
    _compact = value;
    _changed();
  }

  void setShowCommandLabels(bool value) {
    if (_showCommandLabels == value) return;
    _showCommandLabels = value;
    _changed();
  }

  void setShowGroupLabels(bool value) {
    if (_showGroupLabels == value) return;
    _showGroupLabels = value;
    _changed();
  }

  void setCollapsed(bool value) {
    if (_collapsed == value) return;
    _collapsed = value;
    _changed();
  }

  void reset() {
    _orders.clear();
    _hidden.clear();
    _compact = true;
    _showCommandLabels = false;
    _showGroupLabels = true;
    _collapsed = false;
    _changed();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'compact': _compact,
    'showCommandLabels': _showCommandLabels,
    'showGroupLabels': _showGroupLabels,
    'collapsed': _collapsed,
    'orders': _orders,
    'hidden': <String, Object?>{
      for (final entry in _hidden.entries) entry.key: entry.value.toList(),
    },
  };

  void _changed() {
    _revision++;
    notifyListeners();
    if (!persist) return;
    final contents = jsonEncode(toJson());
    // Serialize snapshots so a slower earlier write cannot replace a new one.
    _writes = _writes.then((_) async {
      try {
        final backend = _backend;
        if (backend != null) {
          await backend.write(contents);
        } else {
          final file = await _file();
          await file.parent.create(recursive: true);
          final temporary = File('${file.path}.tmp');
          await temporary.writeAsString(contents, flush: true);
          await temporary.rename(file.path);
        }
        if (_saveError != null && !_disposed) {
          _saveError = null;
          notifyListeners();
        }
      } on Object {
        if (!_disposed && _saveError == null) {
          _saveError = 'save';
          notifyListeners();
        }
      }
    });
  }

  Future<void> flush() => _writes;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
