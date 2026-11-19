import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quds_language_id/quds_language_id.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'studio_language_id_host_web.dart'
    if (dart.library.io) 'studio_language_id_host_native.dart'
    as platform;

/// Owns the bundled language identifier (CLD3, Apache-2.0 model shipped with
/// the app) and the paragraph detector the Word proofing session routes
/// with. Nothing is downloaded: the model is an app asset, verified by its
/// pinned SHA-256 before the worker opens it.
abstract class StudioLanguageIdHost extends ChangeNotifier {
  /// The detector once the classifier has loaded, otherwise null.
  ParagraphLanguageDetector? get detector;

  /// Fixed public feedback when the classifier could not be loaded. Native
  /// library paths, asset diagnostics and transport errors are not exposed.
  String? get problem;

  /// Loads the model and starts the worker (once).
  Future<void> load();
}

/// The shared implementation: platform hooks create the identifier.
class BundledStudioLanguageIdHost extends StudioLanguageIdHost {
  BundledStudioLanguageIdHost({
    required this.createIdentifier,
    Future<Uint8List> Function()? loadModel,
  }) : _loadModel = loadModel ?? _bundledModel;

  final Cld3LanguageIdentifier Function(Uint8List model) createIdentifier;
  final Future<Uint8List> Function() _loadModel;
  Cld3LanguageIdentifier? _identifier;
  ParagraphLanguageDetector? _detector;
  String? _problem;
  Future<void>? _loading;
  bool _disposed = false;

  static const _unavailable = 'Automatic language detection is unavailable.';

  static Future<Uint8List> _bundledModel() async {
    final data = await rootBundle.load(Cld3Model.assetKey);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  ParagraphLanguageDetector? get detector => _detector;

  @override
  String? get problem => _problem;

  @override
  Future<void> load() =>
      _disposed ? Future<void>.value() : _loading ??= _load();

  Future<void> _load() async {
    Cld3LanguageIdentifier? identifier;
    try {
      final model = await _loadModel();
      if (_disposed) return;
      identifier = createIdentifier(model);
      // An embedding factory may synchronously dispose the host.
      if (_disposed) {
        await _retire(identifier);
        return;
      }
      _identifier = identifier;
      await identifier.load();
      if (_disposed || !identical(_identifier, identifier)) {
        await _retire(identifier);
        return;
      }
      if (!identifier.isAvailable) {
        _identifier = null;
        await _retire(identifier);
        if (_disposed) return;
        _problem = _unavailable;
      } else {
        _detector = ParagraphLanguageDetector(identifier);
      }
    } on Object {
      if (identifier != null) {
        if (identical(_identifier, identifier)) _identifier = null;
        await _retire(identifier);
      }
      if (_disposed) return;
      _detector = null;
      _problem = _unavailable;
    }
    if (!_disposed) notifyListeners();
  }

  static Future<void> _retire(Cld3LanguageIdentifier identifier) async {
    try {
      await identifier.dispose();
    } on Object {
      // Teardown cannot publish into a stopped host or expose diagnostics.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final identifier = _identifier;
    _identifier = null;
    _detector = null;
    _problem = null;
    if (identifier != null) unawaited(_retire(identifier));
    super.dispose();
  }
}

/// A host with a fixed detector (tests and embedding hosts).
class FixedStudioLanguageIdHost extends StudioLanguageIdHost {
  FixedStudioLanguageIdHost(this.detector);

  @override
  final ParagraphLanguageDetector? detector;

  @override
  String? get problem => null;

  @override
  Future<void> load() async {}
}

StudioLanguageIdHost? _host;

/// The process-wide Studio host (created lazily; no work until [load]).
StudioLanguageIdHost get studioLanguageIdHost =>
    _host ??= platform.createLanguageIdHost();

/// Replaces the process host (tests and embedding hosts).
@visibleForTesting
set studioLanguageIdHost(StudioLanguageIdHost host) => _host = host;
