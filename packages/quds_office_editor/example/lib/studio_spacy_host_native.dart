import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:quds_proofing_spacy/quds_proofing_spacy_install.dart';

import 'studio_spacy_host.dart';

StudioSpacyHost createHost() => NativeStudioSpacyHost(
  root: Directory(studioSpacyDataDirectory()),
  environment: Platform.environment,
);

SpacyPlatform? _currentPlatform() => switch (Abi.current()) {
  Abi.linuxX64 => SpacyPlatform.linuxX64,
  Abi.linuxArm64 => SpacyPlatform.linuxArm64,
  Abi.macosArm64 => SpacyPlatform.macosArm64,
  Abi.macosX64 => SpacyPlatform.macosX64,
  Abi.windowsX64 => SpacyPlatform.windowsX64,
  Abi.windowsArm64 => SpacyPlatform.windowsArm64,
  Abi.iosArm64 => SpacyPlatform.iosArm64,
  Abi.androidArm64 => SpacyPlatform.androidArm64,
  _ => null,
};

/// Private per-user data directory; the app sandbox container on macOS.
String studioSpacyDataDirectory() {
  final env = Platform.environment;
  final home = env['HOME'] ?? '';
  const app = 'quds_office_studio';
  if (Platform.isMacOS) {
    return '$home/Library/Application Support/$app/spacy';
  }
  if (Platform.isWindows) {
    return '${env['APPDATA'] ?? env['LOCALAPPDATA'] ?? '.'}\\$app\\spacy';
  }
  final data = env['XDG_DATA_HOME'];
  return '${data == null || data.isEmpty ? '$home/.local/share' : data}/$app/spacy';
}

class NativeStudioSpacyHost extends StudioSpacyHost {
  NativeStudioSpacyHost({
    required this.root,
    required this.environment,
    SpacyPackageInstaller? installer,
    SpacyPlatform? platform,
    bool detectPlatform = true,
  }) : _installer = installer ?? SpacyPackageInstaller(root: root),
       _platform = platform ?? (detectPlatform ? _currentPlatform() : null) {
    _status = _initialStatus();
  }

  final Directory root;
  final Map<String, String> environment;
  final SpacyPackageInstaller _installer;
  final SpacyPlatform? _platform;
  late StudioSpacyStatus _status;

  @override
  StudioSpacyStatus get status => _status;

  File get _settings => File('${root.path}/settings.json');

  bool get _developerConfigured {
    final bundle = environment['QUDS_SPACY_BUNDLE'];
    return bundle != null && bundle.isNotEmpty;
  }

  StudioSpacyStatus _initialStatus() {
    final platform = _platform;
    final availability = platform == null
        ? null
        : spacyPlatformStatus(platform);
    return StudioSpacyStatus(
      platformLabel: platform?.id ?? Abi.current().toString(),
      source: _developerConfigured
          ? StudioSpacySource.developer
          : StudioSpacySource.none,
      package: availability?.package,
      unavailableReason: platform == null
          ? 'This platform has no native analysis build.'
          : availability!.reason,
      librarySha256: _developerConfigured
          ? environment['QUDS_SPACY_LIBRARY_SHA256']
          : null,
      qualification: _developerConfigured
          ? spacyQualificationFor(
              environment['QUDS_SPACY_LIBRARY_SHA256'] ?? '',
            )
          : null,
      analysisEnabled: _developerConfigured,
    );
  }

  ({bool analysis, bool grammar}) _readSettings() {
    try {
      if (!_settings.existsSync()) return (analysis: false, grammar: false);
      final decoded = jsonDecode(_settings.readAsStringSync());
      if (decoded is! Map<String, Object?>) {
        return (analysis: false, grammar: false);
      }
      return (
        analysis: decoded['analysis_enabled'] == true,
        grammar: decoded['grammar_enabled'] == true,
      );
    } on Object {
      return (analysis: false, grammar: false);
    }
  }

  void _writeSettings({required bool analysis, required bool grammar}) {
    root.createSync(recursive: true);
    final temporary = File(
      '${root.path}/.settings-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    temporary.writeAsStringSync(
      jsonEncode({
        'schema': 'quds.studio.spacy.settings.v1',
        'analysis_enabled': analysis,
        'grammar_enabled': grammar,
      }),
      flush: true,
    );
    temporary.renameSync(_settings.path);
  }

  @override
  Future<void> refresh() async {
    final base = _initialStatus();
    final settings = _readSettings();
    if (base.source == StudioSpacySource.developer) {
      _status = StudioSpacyStatus(
        platformLabel: base.platformLabel,
        source: base.source,
        package: base.package,
        unavailableReason: base.unavailableReason,
        librarySha256: base.librarySha256,
        qualification: base.qualification,
        analysisEnabled: true,
        grammarEnabled: settings.grammar,
      );
      notifyListeners();
      return;
    }
    final package = base.package;
    SpacyInstallation? installation;
    String? problem;
    if (package != null) {
      try {
        installation = await _installer.installed(package);
      } on SpacyInstallException catch (error) {
        problem =
            'The installed analysis files failed verification '
            '(${error.message}). Remove and install them again.';
      }
    }
    final configured = installation != null || problem != null;
    _status = StudioSpacyStatus(
      platformLabel: base.platformLabel,
      source: configured ? StudioSpacySource.installed : StudioSpacySource.none,
      package: package,
      unavailableReason: base.unavailableReason,
      installedDirectory: installation?.directory,
      librarySha256: installation?.librarySha256,
      qualification: installation?.qualification,
      problem: problem,
      analysisEnabled: installation != null && settings.analysis,
      grammarEnabled:
          installation != null &&
          settings.grammar &&
          (installation.qualification?.grammarQualified ?? false),
    );
    notifyListeners();
  }

  @override
  Future<void> restoreGrammarOptIn() async {
    if (_readSettings().grammar) await refresh();
  }

  @override
  Future<void> install({
    void Function(int received, int total)? onProgress,
    StudioSpacyInstallCancellation? cancellation,
  }) async {
    final package = _status.package;
    if (package == null) {
      throw SpacyInstallException(
        _status.unavailableReason ??
            'No package is published for this platform.',
      );
    }
    final token = SpacyInstallCancellation();
    cancellation?.addListener(token.cancel);
    await _installer.install(
      package,
      onProgress: onProgress,
      cancellation: token,
    );
    // Installing is the explicit opt-in to the analysis view; grammar stays
    // off until separately enabled.
    _writeSettings(analysis: true, grammar: _readSettings().grammar);
    await refresh();
  }

  @override
  Future<void> remove() async {
    final package = _status.package;
    _writeSettings(analysis: false, grammar: false);
    if (package != null) await _installer.remove(package);
    await refresh();
  }

  @override
  Future<void> setAnalysisEnabled(bool enabled) async {
    final settings = _readSettings();
    _writeSettings(analysis: enabled, grammar: enabled && settings.grammar);
    await refresh();
  }

  @override
  Future<void> setGrammarEnabled(bool enabled) async {
    if (enabled && !_status.grammarOffered) {
      throw const SpacyUnavailableException(
        'Manual grammar is not qualified for this exact native build.',
      );
    }
    _writeSettings(
      analysis: _readSettings().analysis || enabled,
      grammar: enabled,
    );
    await refresh();
  }

  @override
  Future<SpacyTransport> openTransport() async {
    if (_developerConfigured) return _openDeveloperTransport();
    if (!_status.analysisEnabled) {
      throw const SpacyUnavailableException(
        'Local German analysis is not set up. Use “Analysis setup” to '
        'download and verify it.',
      );
    }
    final package = _status.package;
    // Re-verify the complete installation before every worker start.
    final installation = package == null
        ? null
        : await _installer.installed(package);
    if (installation == null) {
      throw const SpacyUnavailableException(
        'The local German analysis files are missing. Install them again.',
      );
    }
    if (!enableSpacyNativeGateForProcess()) {
      throw const SpacyUnavailableException(
        'Native analysis cannot be enabled on this platform.',
      );
    }
    return startSpacyWorker(
      bundle: const SpacyBundle.germanF32(),
      backendFactory: installation.backendFactory(),
    );
  }

  /// Unchanged developer contract: the caller sets CRISPEMBED_SPACY and the
  /// three explicit paths/digest before process start.
  Future<SpacyTransport> _openDeveloperTransport() async {
    final gate = environment['CRISPEMBED_SPACY']?.toLowerCase();
    if (gate == null || const ['', '0', 'false', 'off', 'no'].contains(gate)) {
      throw const SpacyUnavailableException(
        'Local German text analysis is disabled. Enable the optional analysis '
        'installation in the host configuration.',
      );
    }
    final bundle = environment['QUDS_SPACY_BUNDLE'];
    final library = environment['QUDS_SPACY_LIBRARY'];
    final digest = environment['QUDS_SPACY_LIBRARY_SHA256'];
    if (bundle == null ||
        bundle.isEmpty ||
        library == null ||
        library.isEmpty ||
        digest == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const SpacyUnavailableException(
        'Local German text analysis is not installed. Configure the verified '
        'German model bundle and native library in the host application.',
      );
    }
    return startSpacyWorker(
      bundle: const SpacyBundle.germanF32(),
      backendFactory: SpacyNativeBackendFactory(
        bundleDirectory: bundle,
        libraryPath: library,
        librarySha256: digest,
      ),
    );
  }
}
