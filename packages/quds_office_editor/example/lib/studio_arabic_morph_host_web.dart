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
/// before every later load.
class WebStudioArabicMorphHost extends StudioArabicMorphHost {
  WebStudioArabicMorphHost({
    http.Client Function()? client,
    this.bundle = camelMorphMsaProofingBin,
    this.workerUrl,
    StudioWebDataStore? store,
  }) : _client = client ?? http.Client.new,
       store = store ?? createDefaultStudioWebDataStore(),
       _status = StudioArabicMorphStatus(bundle: bundle);

  final http.Client Function() _client;

  /// Where verified downloads are kept between sessions.
  final StudioWebDataStore store;

  String _key(MorphArtifact file) =>
      'morph/${bundle.id}/${bundle.revision}/${file.file}';

  Future<void> _forget() async {
    for (final file in bundle.files) {
      await store.delete(_key(file));
    }
  }

  final MorphBundleDownload bundle;
  final Uri? workerUrl;
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
  }

  @override
  Future<void> remove() async {
    final previous = _morphology;
    _morphology = null;
    _set(StudioArabicMorphStatus(bundle: bundle));
    await _forget();
    await previous?.dispose();
  }
}
