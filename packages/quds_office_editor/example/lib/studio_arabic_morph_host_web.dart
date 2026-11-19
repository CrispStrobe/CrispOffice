import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'studio_arabic_morph_host.dart';
import 'studio_hunspell_host.dart' show StudioHunspellCancellation;

StudioArabicMorphHost createHost() => WebStudioArabicMorphHost();

/// Browser host: the user's download is verified in memory and handed to the
/// bundled WebAssembly analyzer in a Web Worker for this session (the worker
/// then holds about 320 MB). Nothing is stored; a reload needs a new
/// download.
class WebStudioArabicMorphHost extends StudioArabicMorphHost {
  WebStudioArabicMorphHost({
    http.Client Function()? client,
    this.bundle = camelMorphMsaNoprob,
    this.workerUrl,
  }) : _client = client ?? http.Client.new,
       _status = StudioArabicMorphStatus(bundle: bundle);

  final http.Client Function() _client;
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

  @override
  Future<void> refresh() async {}

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
    _set(StudioArabicMorphStatus(bundle: bundle));
    await previous?.dispose();
  }
}
