import 'package:flutter/foundation.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

import 'studio_spacy_host_unsupported.dart'
    if (dart.library.io) 'studio_spacy_host_native.dart'
    as platform;

/// Where the active analysis configuration comes from.
enum StudioSpacySource {
  /// Nothing installed or configured.
  none,

  /// A verified package installed by the user from the immutable Hub
  /// revision into the app's private data directory.
  installed,

  /// Developer environment variables (`QUDS_SPACY_BUNDLE`, ...).
  developer,
}

/// A snapshot of the optional local German analysis setup.
@immutable
class StudioSpacyStatus {
  const StudioSpacyStatus({
    required this.platformLabel,
    required this.source,
    this.package,
    this.unavailableReason,
    this.installedDirectory,
    this.librarySha256,
    this.qualification,
    this.problem,
    this.analysisEnabled = false,
    this.grammarEnabled = false,
    this.nerOffered = false,
    this.nerEnabled = false,
  });

  /// e.g. `macos-arm64`.
  final String platformLabel;
  final StudioSpacySource source;

  /// The downloadable package for this platform, if one is published.
  final SpacyPlatformPackage? package;

  /// Why no package is offered on this platform.
  final String? unavailableReason;
  final String? installedDirectory;

  /// Exact native build in use (installed or developer-configured).
  final String? librarySha256;

  /// Recorded claims for [librarySha256]; null for an unrecorded build.
  final SpacyBuildQualification? qualification;

  /// A verification or configuration failure the user should see.
  final String? problem;
  final bool analysisEnabled;
  final bool grammarEnabled;

  /// A published NER model exists for this catalog (optional, opt-in).
  final bool nerOffered;

  /// The user downloaded and enabled named entities.
  final bool nerEnabled;

  bool get configured => source != StudioSpacySource.none;

  /// The manual grammar provider may be offered only for an exact build with
  /// recorded grammar qualification, or for an explicit developer setup.
  bool get grammarOffered =>
      configured &&
      problem == null &&
      ((qualification?.grammarQualified ?? false) ||
          source == StudioSpacySource.developer);

  String get configurationKey => [
    source.name,
    librarySha256 ?? '',
    installedDirectory ?? '',
    analysisEnabled,
    grammarEnabled,
    nerEnabled,
  ].join('|');
}

/// Owns acquisition and opt-in state for optional local German analysis.
/// Analysis and grammar never download; only [install] uses the network,
/// and only when the user explicitly asks for it.
abstract class StudioSpacyHost extends ChangeNotifier {
  StudioSpacyStatus get status;

  /// Re-reads settings and fully re-verifies any installation.
  Future<void> refresh();

  /// Cheap startup check: refreshes (and so re-verifies) only when the user
  /// previously opted in to manual grammar. Otherwise does no file I/O.
  Future<void> restoreGrammarOptIn();

  /// Downloads and installs the published package for this platform.
  Future<void> install({
    void Function(int received, int total)? onProgress,
    StudioSpacyInstallCancellation? cancellation,
  });

  Future<void> remove();
  Future<void> setAnalysisEnabled(bool enabled);
  Future<void> setGrammarEnabled(bool enabled);

  /// Downloads (when enabling) the optional verified NER model and toggles it.
  Future<void> setNerEnabled(bool enabled) async =>
      throw UnsupportedError('Named entities are unavailable here.');

  /// Opens a new owned worker for the current verified configuration.
  Future<SpacyTransport> openTransport();
}

/// Host-neutral cancellation handle for [StudioSpacyHost.install].
class StudioSpacyInstallCancellation {
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

  void addListener(VoidCallback listener) => _listeners.add(listener);
}

StudioSpacyHost? _host;

/// The process-wide Studio host (created lazily; no I/O until [refresh]).
StudioSpacyHost get studioSpacyHost => _host ??= platform.createHost();

/// Replaces the process host (tests and embedding hosts).
@visibleForTesting
set studioSpacyHost(StudioSpacyHost host) => _host = host;
