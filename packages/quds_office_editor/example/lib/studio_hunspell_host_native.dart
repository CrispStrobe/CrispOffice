import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_hunspell/installer_io.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

import 'studio_native_paths.dart';
import 'studio_hunspell_host.dart';

StudioHunspellHost createHost() => NativeStudioHunspellHost(
  root: Directory(studioHunspellDataDirectory()),
  libraryPath: studioHunspellLibraryPath(),
);

/// Per-user private data directory for downloaded dictionaries.
String studioHunspellDataDirectory() => studioPrivateDataDirectory();

/// The engine library packaged with the app: `QUDS_HUNSPELL_LIBRARY` (Dart
/// define or environment), then the platform's packaged location next to the
/// executable, otherwise null (the platform loader's search path).
String? studioHunspellLibraryPath() {
  const defined = String.fromEnvironment('QUDS_HUNSPELL_LIBRARY');
  if (defined.isNotEmpty) return defined;
  final env = Platform.environment['QUDS_HUNSPELL_LIBRARY'];
  if (env != null && env.isNotEmpty) return env;
  return studioPackagedLibrary('quds_proofing_hunspell');
}

class NativeStudioHunspellHost extends StudioHunspellHost {
  NativeStudioHunspellHost({
    required Directory root,
    this.libraryPath,
    HunspellInstaller? installer,
    List<HunspellBundleDownload> catalog = hunspellCatalog,
  }) : _installer = installer ?? HunspellInstaller(root),
       _statuses = [for (final b in catalog) StudioHunspellStatus(bundle: b)];

  final HunspellInstaller _installer;
  final String? libraryPath;
  List<StudioHunspellStatus> _statuses;
  final Map<String, HunspellDictionaryFiles> _files = {};

  @override
  List<StudioHunspellStatus> get statuses => List.unmodifiable(_statuses);

  void _set(StudioHunspellStatus next) {
    _statuses = [
      for (final item in _statuses)
        item.bundle.id == next.bundle.id ? next : item,
    ];
    notifyListeners();
  }

  @override
  Future<void> refresh() async {
    for (final item in List.of(_statuses)) {
      try {
        final files = await _installer.installed(item.bundle);
        if (files == null) {
          _files.remove(item.bundle.id);
          _set(StudioHunspellStatus(bundle: item.bundle));
        } else {
          _files[item.bundle.id] = files;
          _set(
            StudioHunspellStatus(
              bundle: item.bundle,
              installed: true,
              location: File(files.dicPath).parent.path,
            ),
          );
        }
      } on Object catch (error) {
        _files.remove(item.bundle.id);
        _set(StudioHunspellStatus(bundle: item.bundle, problem: '$error'));
      }
    }
  }

  @override
  Future<void> install(
    HunspellBundleDownload bundle, {
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {
    final cancel = HunspellInstallCancellation();
    if (cancellation?.isCancelled ?? false) cancel.cancel();
    cancellation?.addListener(cancel.cancel);
    try {
      final files = await _installer.install(
        bundle,
        onProgress: onProgress,
        cancellation: cancel,
      );
      _files[bundle.id] = files;
      _set(
        StudioHunspellStatus(
          bundle: bundle,
          installed: true,
          location: File(files.dicPath).parent.path,
        ),
      );
    } on Object catch (error) {
      _set(StudioHunspellStatus(bundle: bundle, problem: '$error'));
      rethrow;
    } finally {
      cancellation?.removeListener(cancel.cancel);
    }
  }

  @override
  Future<void> remove(HunspellBundleDownload bundle) async {
    _files.remove(bundle.id);
    _set(StudioHunspellStatus(bundle: bundle));
    await _installer.remove(bundle);
  }

  @override
  List<OfficeProofingProvider> createProviders(
    OfficeProofingVocabulary vocabulary,
  ) => [
    for (final item in _statuses)
      if (item.installed && _files[item.bundle.id] != null)
        HunspellProofingProvider(
          bundle: item.bundle,
          dictionary: _files[item.bundle.id]!,
          vocabulary: vocabulary,
          nativeLibraryPath: libraryPath,
        ),
  ];
}
