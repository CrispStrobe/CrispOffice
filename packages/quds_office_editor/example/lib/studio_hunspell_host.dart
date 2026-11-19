import 'package:flutter/foundation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

import 'studio_hunspell_host_web.dart'
    if (dart.library.io) 'studio_hunspell_host_native.dart'
    as platform;

/// One user-downloadable Hunspell dictionary and whether it is installed.
@immutable
class StudioHunspellStatus {
  const StudioHunspellStatus({
    required this.bundle,
    this.installed = false,
    this.problem,
    this.unavailableReason,
    this.location,
  });

  final HunspellBundleDownload bundle;

  /// Downloaded and verified against the pinned SHA-256 values.
  final bool installed;

  /// A verification or download failure the user should see.
  final String? problem;

  /// Why this host cannot offer the dictionary at all.
  final String? unavailableReason;

  /// Where the verified files live (native) or `memory` (web session).
  final String? location;

  bool get offered => unavailableReason == null;

  Uri get sourceUri => Uri.https(
    'huggingface.co',
    '/${bundle.repository}/tree/${bundle.revision}',
  );
}

/// Host-neutral cancellation for [StudioHunspellHost.install].
class StudioHunspellCancellation {
  final _listeners = <VoidCallback>[];
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void addListener(VoidCallback listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(VoidCallback listener) => _listeners.remove(listener);
}

/// Owns the optional, user-downloaded Hunspell dictionaries (first Arabic).
/// Nothing is downloaded unless the user asks for it in the setup dialog;
/// once a dictionary is installed and verified, [createProviders] adds its
/// spelling provider to the Word proofing service.
abstract class StudioHunspellHost extends ChangeNotifier {
  List<StudioHunspellStatus> get statuses;

  StudioHunspellStatus status(HunspellBundleDownload bundle) =>
      statuses.firstWhere((item) => item.bundle.id == bundle.id);

  /// Re-verifies installed dictionaries (no network access).
  Future<void> refresh();

  /// Downloads, verifies and installs [bundle] (explicit user action).
  Future<void> install(
    HunspellBundleDownload bundle, {
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  });

  /// Removes [bundle]; its provider disappears from the next configuration.
  Future<void> remove(HunspellBundleDownload bundle);

  /// Fresh provider instances for every installed dictionary. The proofing
  /// session requires new instances for each configuration.
  List<OfficeProofingProvider> createProviders(
    OfficeProofingVocabulary vocabulary,
  );

  /// Changes whenever [createProviders] would return a different set.
  String get configurationKey => [
    for (final item in statuses)
      if (item.installed) '${item.bundle.id}@${item.bundle.revision}',
  ].join('|');
}

StudioHunspellHost? _host;

/// The process-wide Studio host (created lazily; no I/O until [refresh]).
StudioHunspellHost get studioHunspellHost => _host ??= platform.createHost();

/// Replaces the process host (tests and embedding hosts).
@visibleForTesting
set studioHunspellHost(StudioHunspellHost host) => _host = host;
