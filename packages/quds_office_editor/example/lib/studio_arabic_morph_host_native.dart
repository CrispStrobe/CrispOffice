import 'dart:async';
import 'dart:io';

import 'package:quds_arabic_morph/installer_io.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'studio_native_paths.dart';
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
  return studioPackagedLibrary('quds_arabic_morph');
}

class NativeStudioArabicMorphHost extends StudioArabicMorphHost {
  NativeStudioArabicMorphHost({
    required Directory root,
    this.libraryPath,
    MorphInstaller? installer,
    this.bundle = camelMorphMsaProofingBin,
  }) : _installer = installer ?? MorphInstaller(root),
       _status = StudioArabicMorphStatus(bundle: bundle);

  final MorphInstaller _installer;
  final String? libraryPath;
  final MorphBundleDownload bundle;
  StudioArabicMorphStatus _status;
  CamelArabicMorphology? _morphology;

  @override
  StudioArabicMorphStatus get status => _status;

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
    final morphology = _morphology = CamelArabicMorphology(
      database: files,
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
      await _installer.removeOtherBundles(bundle);
      final files = await _installer.installed(bundle);
      if (files == null) {
        await _deactivate();
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
