import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'studio_arabic_morph_host.dart';
import 'studio_hunspell_host.dart' show StudioHunspellCancellation;
import 'studio_web_data_store.dart';

StudioArabicMorphHost createHost() => WebStudioArabicMorphHost();

/// Browser host: the user's download (12 MB) is verified and handed to the
/// bundled WebAssembly analyzer in a Web Worker (the worker keeps one copy of
/// the binary database in its Wasm memory). The verified files are kept in
/// browser storage ([StudioWebDataStore]) and re-verified against the pins
/// before every later load. The optional context model is handled the same
/// way and loads next to the database.
class WebStudioArabicMorphHost extends StudioArabicMorphHost {
  WebStudioArabicMorphHost({
    http.Client Function()? client,
    this.bundle = camelMorphMsaProofingBin,
    this.modelBundle = camelMorphMsaDisambig,
    this.workerUrl,
    StudioWebDataStore? store,
    ArabicMorphTransport Function()? transportFactory,
  }) : _client = client ?? http.Client.new,
       _transportFactory = transportFactory,
       store = store ?? createDefaultStudioWebDataStore(),
       _status = StudioArabicMorphStatus(bundle: bundle),
       _modelStatus = StudioArabicMorphStatus(bundle: modelBundle);

  final http.Client Function() _client;
  final ArabicMorphTransport Function()? _transportFactory;

  /// Where verified downloads are kept between sessions.
  final StudioWebDataStore store;

  String _key(MorphArtifact file, [MorphBundleDownload? of]) {
    final b = of ?? bundle;
    return 'morph/${b.id}/${b.revision}/${file.file}';
  }

  Future<void> _forget([MorphBundleDownload? of]) async {
    for (final file in (of ?? bundle).files) {
      await store.delete(_key(file, of));
    }
  }

  final MorphBundleDownload bundle;

  /// The context disambiguation model ([camelMorphMsaDisambig]).
  final MorphBundleDownload modelBundle;
  final Uri? workerUrl;
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

  /// The verified model kept in browser storage, or null (a stored copy that
  /// fails verification is deleted).
  Future<MorphDatabaseBytes?> _storedModel() async {
    final stored = <String, Uint8List>{};
    for (final file in modelBundle.files) {
      final bytes = await store.read(_key(file, modelBundle));
      if (bytes != null) stored[file.file] = bytes;
    }
    if (stored.isEmpty) return null;
    try {
      return MorphDatabaseBytes.verified(modelBundle, stored);
    } on FormatException {
      await _forget(modelBundle);
      return null;
    }
  }

  /// Opens [model] in the current analyzer and reports the outcome.
  Future<void> _loadModel(MorphDatabaseBytes model, String location) async {
    final morphology = _morphology;
    if (morphology == null) return;
    _setModel(
      StudioArabicMorphStatus(
        bundle: modelBundle,
        installed: true,
        location: location,
      ),
    );
    await morphology.loadDisambiguator(model);
    if (!identical(_morphology, morphology)) return;
    _setModel(
      StudioArabicMorphStatus(
        bundle: modelBundle,
        installed: true,
        loaded: morphology.canDisambiguate,
        location: location,
        problem: morphology.disambiguatorFailure == null
            ? null
            : 'Downloaded, but the context model could not load: '
                  '${morphology.disambiguatorFailure}',
      ),
    );
  }

  @override
  Future<void> installModel({
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {
    if (_morphology == null || !_morphology!.isAvailable) {
      throw StateError('Download the Arabic morphology data first.');
    }
    final client = _client();
    var received = 0;
    final MorphDatabaseBytes model;
    try {
      final files = <String, Uint8List>{};
      for (final artifact in modelBundle.files) {
        final response = await client.send(
          http.Request('GET', modelBundle.url(artifact)),
        );
        if (response.statusCode != 200) {
          throw StateError('Download failed (${response.statusCode}).');
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (cancellation?.isCancelled ?? false) {
            throw StateError('Download cancelled.');
          }
          builder.add(chunk);
          received += chunk.length;
          if (builder.length > artifact.bytes) {
            throw StateError('Unexpected size for ${artifact.file}.');
          }
          onProgress?.call(received, modelBundle.totalBytes);
        }
        files[artifact.file] = builder.takeBytes();
      }
      model = MorphDatabaseBytes.verified(modelBundle, files);
    } on Object catch (error) {
      _setModel(
        StudioArabicMorphStatus(bundle: modelBundle, problem: '$error'),
      );
      rethrow;
    } finally {
      client.close();
    }
    var kept = true;
    for (final file in modelBundle.files) {
      kept =
          kept &&
          await store.write(_key(file, modelBundle), model.files[file.file]!);
    }
    if (!kept) await _forget(modelBundle);
    await _loadModel(
      model,
      kept
          ? studioWebStoredLocation(_bytes(model.files))
          : 'This session only (the browser refused storage)',
    );
  }

  @override
  Future<void> removeModel() async {
    final morphology = _morphology;
    _setModel(StudioArabicMorphStatus(bundle: modelBundle));
    await _forget(modelBundle);
    // The database bytes already belong to the worker. Release only its model;
    // reopening would attempt to transfer the detached host buffers again.
    await morphology?.unloadDisambiguator();
    if (morphology == null || !identical(_morphology, morphology)) return;
    if (morphology.disambiguatorFailure != null) {
      _setModel(
        StudioArabicMorphStatus(
          bundle: modelBundle,
          problem:
              'The context model could not be unloaded: '
              '${morphology.disambiguatorFailure}',
        ),
      );
      _set(
        StudioArabicMorphStatus(
          bundle: bundle,
          installed: _status.installed,
          loaded: morphology.isAvailable,
          location: _status.location,
          problem: '${morphology.failure}',
        ),
      );
    }
  }

  @override
  ArabicMorphology get morphology =>
      _morphology ?? const UnavailableArabicMorphology();

  void _set(StudioArabicMorphStatus next) {
    _status = next;
    notifyListeners();
  }

  /// Restores a database kept from an earlier session after verifying it
  /// against the pins; a stored copy that fails is deleted.
  @override
  Future<void> refresh() async {
    if (_status.installed) return;
    final stored = <String, Uint8List>{};
    for (final file in bundle.files) {
      final bytes = await store.read(_key(file));
      if (bytes != null) stored[file.file] = bytes;
    }
    if (stored.isEmpty) return;
    final MorphDatabaseBytes database;
    try {
      if (stored.length != bundle.files.length) {
        throw const FormatException('Incomplete stored database.');
      }
      database = MorphDatabaseBytes.verified(bundle, stored);
    } on FormatException {
      await _forget();
      _set(
        StudioArabicMorphStatus(
          bundle: bundle,
          problem:
              'The morphology data stored in this browser failed '
              'verification and was removed. Download it again.',
        ),
      );
      return;
    }
    await _activate(database, studioWebStoredLocation(_bytes(stored)));
  }

  static int _bytes(Map<String, Uint8List> files) =>
      files.values.fold(0, (sum, bytes) => sum + bytes.length);

  @override
  Future<void> install({
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {
    final client = _client();
    var received = 0;
    Future<Uint8List> fetch(MorphArtifact artifact) async {
      final response = await client.send(
        http.Request('GET', bundle.url(artifact)),
      );
      if (response.statusCode != 200) {
        throw StateError('Download failed (${response.statusCode}).');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (cancellation?.isCancelled ?? false) {
          throw StateError('Download cancelled.');
        }
        builder.add(chunk);
        received += chunk.length;
        if (builder.length > artifact.bytes) {
          throw StateError('Unexpected size for ${artifact.file}.');
        }
        onProgress?.call(received, bundle.totalBytes);
      }
      return builder.takeBytes();
    }

    final MorphDatabaseBytes database;
    try {
      database = MorphDatabaseBytes.verified(bundle, {
        for (final artifact in bundle.files)
          artifact.file: await fetch(artifact),
      });
    } on Object catch (error) {
      _set(StudioArabicMorphStatus(bundle: bundle, problem: '$error'));
      rethrow;
    } finally {
      client.close();
    }
    final files = <String, Uint8List>{
      for (final file in bundle.files) file.file: database.files[file.file]!,
    };
    var kept = true;
    for (final file in bundle.files) {
      kept = kept && await store.write(_key(file), files[file.file]!);
    }
    if (!kept) await _forget();
    await _activate(
      database,
      kept
          ? studioWebStoredLocation(_bytes(files))
          : 'This session only (the browser refused storage)',
    );
  }

  Future<void> _activate(MorphDatabaseBytes database, String location) async {
    await _morphology?.dispose();
    final morphology = _morphology = CamelArabicMorphology(
      database: database,
      workerUrl: workerUrl,
      transport: _transportFactory?.call(),
    );
    _set(
      StudioArabicMorphStatus(
        bundle: bundle,
        installed: true,
        location: location,
      ),
    );
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
            : 'Downloaded, but the analyzer could not load it: '
                  '${morphology.failure}',
      ),
    );
    final model = morphology.isAvailable ? await _storedModel() : null;
    if (model != null && identical(_morphology, morphology)) {
      await _loadModel(model, studioWebStoredLocation(_bytes(model.files)));
    }
  }

  @override
  Future<void> remove() async {
    final previous = _morphology;
    _morphology = null;
    _modelStatus = StudioArabicMorphStatus(bundle: modelBundle);
    _set(StudioArabicMorphStatus(bundle: bundle));
    await _forget();
    await previous?.dispose();
  }
}
