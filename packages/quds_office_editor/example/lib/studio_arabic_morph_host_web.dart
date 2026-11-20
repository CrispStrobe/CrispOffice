import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'studio_arabic_morph_host.dart';
import 'studio_hunspell_host.dart' show StudioHunspellCancellation;

StudioArabicMorphHost createHost() => WebStudioArabicMorphHost();

/// Browser host: the user's download (12 MB) is verified in memory and handed
/// to the bundled WebAssembly analyzer in a Web Worker for this session (the
/// worker keeps one copy of the binary database in its Wasm memory). The
/// optional context model is handled the same way. Nothing is stored; a
/// reload needs a new download.
class WebStudioArabicMorphHost extends StudioArabicMorphHost {
  WebStudioArabicMorphHost({
    http.Client Function()? client,
    this.bundle = camelMorphMsaProofingBin,
    this.modelBundle = camelMorphMsaDisambig,
    this.workerUrl,
  }) : _client = client ?? http.Client.new,
       _status = StudioArabicMorphStatus(bundle: bundle),
       _modelStatus = StudioArabicMorphStatus(bundle: modelBundle);

  final http.Client Function() _client;
  final MorphBundleDownload bundle;

  /// The context disambiguation model, also kept for the session only.
  final MorphBundleDownload modelBundle;
  final Uri? workerUrl;
  StudioArabicMorphStatus _status;
  StudioArabicMorphStatus _modelStatus;
  CamelArabicMorphology? _morphology;

  @override
  StudioArabicMorphStatus get status => _status;

  @override
  StudioArabicMorphStatus get modelStatus => _modelStatus;

  /// Downloads every file of [target] into memory and verifies it.
  Future<MorphDatabaseBytes> _download(
    MorphBundleDownload target,
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  ) async {
    final client = _client();
    var received = 0;
    Future<Uint8List> fetch(MorphArtifact artifact) async {
      final response = await client.send(
        http.Request('GET', target.url(artifact)),
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
        onProgress?.call(received, target.totalBytes);
      }
      return builder.takeBytes();
    }

    try {
      return MorphDatabaseBytes.verified(target, {
        for (final artifact in target.files)
          artifact.file: await fetch(artifact),
      });
    } finally {
      client.close();
    }
  }

  @override
  Future<void> installModel({
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {
    final morphology = _morphology;
    if (morphology == null || !morphology.isAvailable) {
      throw StateError('Download the Arabic morphology data first.');
    }
    final MorphDatabaseBytes model;
    try {
      model = await _download(modelBundle, onProgress, cancellation);
    } on Object catch (error) {
      _setModel(
        StudioArabicMorphStatus(bundle: modelBundle, problem: '$error'),
      );
      rethrow;
    }
    _setModel(
      StudioArabicMorphStatus(
        bundle: modelBundle,
        installed: true,
        location: 'memory',
      ),
    );
    await morphology.loadDisambiguator(model);
    if (!identical(_morphology, morphology)) return;
    _setModel(
      StudioArabicMorphStatus(
        bundle: modelBundle,
        installed: true,
        loaded: morphology.canDisambiguate,
        location: 'memory',
        problem: morphology.disambiguatorFailure == null
            ? null
            : 'Downloaded, but the context model could not load: '
                  '${morphology.disambiguatorFailure}',
      ),
    );
  }

  @override
  Future<void> removeModel() async {
    // The worker keeps the model; start a fresh analyzer without it.
    _setModel(StudioArabicMorphStatus(bundle: modelBundle));
    final database = _database;
    if (database == null) return;
    await _morphology?.dispose();
    final morphology = _morphology = CamelArabicMorphology(
      database: database,
      workerUrl: workerUrl,
    );
    await morphology.load();
    notifyListeners();
  }

  void _setModel(StudioArabicMorphStatus next) {
    _modelStatus = next;
    notifyListeners();
  }

  /// The verified database bytes of this session, kept to reopen the
  /// analyzer when the context model is removed.
  MorphDatabaseBytes? _database;

  @override
  ArabicMorphology get morphology =>
      _morphology ?? const UnavailableArabicMorphology();

  void _set(StudioArabicMorphStatus next) {
    _status = next;
    notifyListeners();
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> install({
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {
    final MorphDatabaseBytes database;
    try {
      database = await _download(bundle, onProgress, cancellation);
    } on Object catch (error) {
      _set(StudioArabicMorphStatus(bundle: bundle, problem: '$error'));
      rethrow;
    }
    _database = database;
    _modelStatus = StudioArabicMorphStatus(bundle: modelBundle);
    await _morphology?.dispose();
    final morphology = _morphology = CamelArabicMorphology(
      database: database,
      workerUrl: workerUrl,
    );
    _set(
      StudioArabicMorphStatus(
        bundle: bundle,
        installed: true,
        location: 'memory',
      ),
    );
    await morphology.load();
    if (!identical(_morphology, morphology)) return;
    _set(
      StudioArabicMorphStatus(
        bundle: bundle,
        installed: true,
        loaded: morphology.isAvailable,
        location: 'memory',
        problem: morphology.failure == null
            ? null
            : 'Downloaded, but the analyzer could not load it: '
                  '${morphology.failure}',
      ),
    );
  }

  @override
  Future<void> remove() async {
    final previous = _morphology;
    _morphology = null;
    _database = null;
    _modelStatus = StudioArabicMorphStatus(bundle: modelBundle);
    _set(StudioArabicMorphStatus(bundle: bundle));
    await previous?.dispose();
  }
}
