import 'package:flutter/foundation.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'studio_arabic_morph_host_web.dart'
    if (dart.library.io) 'studio_arabic_morph_host_native.dart'
    as platform;
import 'studio_hunspell_host.dart' show StudioHunspellCancellation;

/// The user-downloadable Arabic morphology database and its state.
@immutable
class StudioArabicMorphStatus {
  const StudioArabicMorphStatus({
    required this.bundle,
    this.installed = false,
    this.loaded = false,
    this.problem,
    this.unavailableReason,
    this.location,
  });

  final MorphBundleDownload bundle;

  /// Downloaded and verified against the pinned SHA-256 values.
  final bool installed;

  /// The analyzer has opened the database ([ArabicMorphology.isAvailable]).
  final bool loaded;

  /// A verification, download or loading failure the user should see.
  final String? problem;

  /// Why this host cannot offer the database at all.
  final String? unavailableReason;

  /// Where the verified files live (native) or `memory` (web session).
  final String? location;

  bool get offered => unavailableReason == null;
}

/// Owns the optional, user-downloaded Camel Morph MSA database and the one
/// long-lived analyzer over it. Nothing is downloaded unless the user asks
/// for it in the Dictionaries dialog; once installed and verified,
/// [morphology] is a loaded [ArabicMorphology] that the Arabic rules receive.
abstract class StudioArabicMorphHost extends ChangeNotifier {
  StudioArabicMorphStatus get status;

  /// Re-verifies an installed database and starts loading it (no network).
  Future<void> refresh();

  /// Downloads, verifies and installs the database (explicit user action),
  /// then loads it.
  Future<void> install({
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  });

  /// Disposes the analyzer and removes the database.
  Future<void> remove();

  /// The shared analyzer: loaded while the database is installed, otherwise
  /// [UnavailableArabicMorphology]. Proofing providers are recreated per
  /// configuration; this instance is not.
  ArabicMorphology get morphology;

  /// Changes whenever [morphology] changes identity or availability.
  String get configurationKey => status.installed
      ? '${status.bundle.id}@${status.bundle.revision}:${status.loaded}'
      : '';
}

StudioArabicMorphHost? _host;

/// The process-wide Studio host (created lazily; no I/O until [refresh]).
StudioArabicMorphHost get studioArabicMorphHost =>
    _host ??= platform.createHost();

/// Replaces the process host (tests and embedding hosts).
@visibleForTesting
set studioArabicMorphHost(StudioArabicMorphHost host) => _host = host;
