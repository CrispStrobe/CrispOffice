import 'dart:async';
import 'dart:io';

import 'package:quds_arabic_morph/installer_io.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'studio_arabic_morph_host.dart';
import 'studio_hunspell_host.dart' show StudioHunspellCancellation;
import 'studio_hunspell_host_native.dart' show studioHunspellDataDirectory;

StudioArabicMorphHost createHost() => NativeStudioArabicMorphHost(
  root: Directory(studioHunspellDataDirectory()),
  libraryPath: studioArabicMorphLibraryPath(),
);

/// The analyzer library packaged with the app: `QUDS_ARABIC_MORPH_LIBRARY`
/// (Dart define or environment), then the platform's packaged location next
/// to the executable, otherwise null (the platform loader's search path,
/// which finds `libquds_arabic_morph.so` in an Android APK's jniLibs).
String? studioArabicMorphLibraryPath() {
  const defined = String.fromEnvironment('QUDS_ARABIC_MORPH_LIBRARY');
  if (defined.isNotEmpty) return defined;
  final env = Platform.environment['QUDS_ARABIC_MORPH_LIBRARY'];
  if (env != null && env.isNotEmpty) return env;
  final executable = File(Platform.resolvedExecutable).parent.path;
  final candidates = Platform.isMacOS
      ? ['$executable/../Frameworks/libquds_arabic_morph.dylib']
      : Platform.isWindows
      ? ['$executable\\quds_arabic_morph.dll']
      : Platform.isLinux
      ? ['$executable/lib/libquds_arabic_morph.so']
      : const <String>[];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

class NativeStudioArabicMorphHost extends StudioArabicMorphHost {
  NativeStudioArabicMorphHost({
    required Directory root,
    this.libraryPath,
    MorphInstaller? installer,
    this.bundle = camelMorphMsaProofingBin,
    this.modelBundle = camelMorphMsaDisambig,
  }) : _installer = installer ?? MorphInstaller(root),
       _status = StudioArabicMorphStatus(bundle: bundle),
       _modelStatus = StudioArabicMorphStatus(bundle: modelBundle);

  final MorphInstaller _installer;
  final String? libraryPath;
  final MorphBundleDownload bundle;

  /// The context disambiguation model installed next to [bundle].
  final MorphBundleDownload modelBundle;
  StudioArabicMorphStatus _status;
  StudioArabicMorphStatus _modelStatus;
  CamelArabicMorphology? _morphology;

  @override
  StudioArabicMorphStatus get status => _status;

  @override
  StudioArabicMorphStatus get modelStatus => _modelStatus;

  void _setModel(StudioArabicMorphStatus next) {
    _modelStatus = next;
    notifyListeners();
  }

  /// Loads the installed model [files] into the current analyzer.
  Future<void> _activateModel(MorphDatabaseFiles files) async {
    final morphology = _morphology;
    final location = File(files.manifestPath).parent.path;
    _setModel(
      StudioArabicMorphStatus(
        bundle: modelBundle,
        installed: true,
        location: location,
      ),
    );
    if (morphology == null) return; // loaded with the database
    await morphology.loadDisambiguator(files);
    if (!identical(_morphology, morphology)) return;
    _setModel(
      StudioArabicMorphStatus(
        bundle: modelBundle,
        installed: true,
        loaded: morphology.canDisambiguate,
        location: location,
        problem: morphology.disambiguatorFailure == null
            ? null
            : 'Installed, but the context model could not load: '
                  '${morphology.disambiguatorFailure}',
      ),
    );
  }

  @override
  Future<void> installModel({
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {
    final cancel = MorphInstallCancellation();
    if (cancellation?.isCancelled ?? false) cancel.cancel();
    cancellation?.addListener(cancel.cancel);
    final MorphDatabaseFiles files;
    try {
      files = await _installer.install(
        modelBundle,
        onProgress: onProgress,
        cancellation: cancel,
      );
    } on Object catch (error) {
      _setModel(
        StudioArabicMorphStatus(bundle: modelBundle, problem: '$error'),
      );
      rethrow;
    }
    await _activateModel(files);
  }

  @override
  Future<void> removeModel() async {
    _setModel(StudioArabicMorphStatus(bundle: modelBundle));
    await _installer.remove(modelBundle);
    // The analyzer keeps a loaded model; reopen the database without it.
    final files = await _installer.installed(bundle);
    await _deactivate();
    if (files != null) await _activate(files);
  }

  @override
  ArabicMorphology get morphology =>
      _morphology ?? const UnavailableArabicMorphology();

  void _set(StudioArabicMorphStatus next) {
    _status = next;
    notifyListeners();
  }

  /// Opens [files] in a new analyzer (in the background isolate) and reports
  /// the outcome; the previous analyzer, if any, is disposed.
  Future<void> _activate(MorphDatabaseFiles files) async {
    final previous = _morphology;
    MorphDatabaseFiles? model;
    try {
      model = await _installer.installed(modelBundle);
    } on Object catch (error) {
      _setModel(
        StudioArabicMorphStatus(bundle: modelBundle, problem: '$error'),
      );
    }
    final morphology = _morphology = CamelArabicMorphology(
      database: files,
      disambiguator: model,
      nativeLibraryPath: libraryPath,
    );
    final location = File(files.manifestPath).parent.path;
    _set(
      StudioArabicMorphStatus(
        bundle: bundle,
        installed: true,
        location: location,
      ),
    );
    unawaited(previous?.dispose());
    await morphology.load();
    if (!identical(_morphology, morphology)) return;
    if (model != null) {
      _modelStatus = StudioArabicMorphStatus(
        bundle: modelBundle,
        installed: true,
        loaded: morphology.canDisambiguate,
        location: File(model.manifestPath).parent.path,
        problem: morphology.disambiguatorFailure == null
            ? null
            : 'Installed, but the context model could not load: '
                  '${morphology.disambiguatorFailure}',
      );
    }
    _set(
      StudioArabicMorphStatus(
        bundle: bundle,
        installed: true,
        loaded: morphology.isAvailable,
        location: location,
        problem: morphology.failure == null
            ? null
            : 'Installed, but the analyzer could not load it: '
                  '${morphology.failure}',
      ),
    );
  }

  Future<void> _deactivate() async {
    final previous = _morphology;
    _morphology = null;
    await previous?.dispose();
  }

  @override
  Future<void> refresh() async {
    try {
      // Earlier bundles (the 78 MB noprob text database) are replaced, not
      // migrated: they are removed and the user downloads this one.
      await _installer.removeOtherBundles(bundle, alsoKeep: [modelBundle]);
      final files = await _installer.installed(bundle);
      if (files == null) {
        await _deactivate();
        final model = await _installer.installed(modelBundle);
        _modelStatus = StudioArabicMorphStatus(
          bundle: modelBundle,
          installed: model != null,
          location: model == null ? null : File(model.manifestPath).parent.path,
        );
        _set(StudioArabicMorphStatus(bundle: bundle));
      } else if (_morphology == null) {
        await _activate(files);
      }
    } on Object catch (error) {
      await _deactivate();
      _set(StudioArabicMorphStatus(bundle: bundle, problem: '$error'));
    }
  }

  @override
  Future<void> install({
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {
    final cancel = MorphInstallCancellation();
    if (cancellation?.isCancelled ?? false) cancel.cancel();
    cancellation?.addListener(cancel.cancel);
    final MorphDatabaseFiles files;
    try {
      files = await _installer.install(
        bundle,
        onProgress: onProgress,
        cancellation: cancel,
      );
    } on Object catch (error) {
      _set(StudioArabicMorphStatus(bundle: bundle, problem: '$error'));
      rethrow;
    }
    await _activate(files);
  }

  @override
  Future<void> remove() async {
    await _deactivate();
    _set(StudioArabicMorphStatus(bundle: bundle));
    await _installer.remove(bundle);
  }
}
