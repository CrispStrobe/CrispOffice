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
    this.nerInstalled = false,
    this.nerProblem,
    this.languages = const [],
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
  final bool nerInstalled;
  final String? nerProblem;

  /// Additional analysis languages (English, French) on this platform.
  final List<StudioSpacyLanguageStatus> languages;

  StudioSpacyLanguageStatus? language(SpacyLanguage language) {
    for (final item in languages) {
      if (item.language == language) return item;
    }
    return null;
  }

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
    for (final item in languages) item.configurationKey,
  ].join('|');
}

/// One separately downloadable analysis language (English or French): its
/// pinned bundle, the v2-capable native package that opens it, and whether
/// both are installed and verified. Analysis only; never grammar.
@immutable
class StudioSpacyLanguageStatus {
  const StudioSpacyLanguageStatus({
    required this.language,
    this.download,
    this.runtime,
    this.unavailableReason,
    this.installed = false,
    this.runtimeInstalled = false,
    this.problem,
  });

  final SpacyLanguage language;
  final SpacyLanguageDownload? download;

  /// The native package whose library opens [download] on this platform.
  final SpacyPlatformPackage? runtime;
  final String? unavailableReason;

  /// Bundle and runtime installed and verified.
  final bool installed;
  final bool runtimeInstalled;
  final String? problem;

  bool get offered => download != null && runtime != null;

  /// Bytes an install would download now (bundle, plus the runtime package
  /// when it is not installed yet).
  int get downloadBytes =>
      (download?.totalBytes ?? 0) +
      (runtimeInstalled ? 0 : (runtime?.archiveBytes ?? 0));

  String get configurationKey => [
    language.code,
    installed,
    runtime?.librarySha256 ?? '',
    download?.revision ?? '',
  ].join(':');
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
  Future<void> removeNer() async =>
      throw UnsupportedError('Named entities are unavailable here.');

  Future<void> setNerEnabled(bool enabled) async =>
      throw UnsupportedError('Named entities are unavailable here.');

  /// Opens a new owned worker for the current verified configuration.
  Future<SpacyTransport> openTransport();

  /// Downloads (explicit user action) and verifies an additional analysis
  /// language and, when needed, the native package that opens it.
  Future<void> installLanguage(
    SpacyLanguage language, {
    void Function(int received, int total)? onProgress,
    StudioSpacyInstallCancellation? cancellation,
  }) async => throw UnsupportedError(
    '${language.displayName} analysis is unavailable here.',
  );

  /// Removes an additional language bundle (the shared package stays).
  Future<void> removeLanguage(SpacyLanguage language) async {}

  /// Opens a worker for [language]; German is [openTransport].
  Future<SpacyTransport> openLanguageTransport(SpacyLanguage language) async {
    if (language == SpacyLanguage.german) return openTransport();
    throw SpacyUnavailableException(
      'Local ${language.displayName} analysis is not available here.',
    );
  }
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
