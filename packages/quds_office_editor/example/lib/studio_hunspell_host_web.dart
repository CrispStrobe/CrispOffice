import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

import 'studio_hunspell_host.dart';
import 'studio_web_data_store.dart';

StudioHunspellHost createHost() => WebStudioHunspellHost();

/// Browser host: the user's download is verified, kept in browser storage
/// across sessions ([StudioWebDataStore], re-verified against the pins on
/// every load) and run by the bundled WebAssembly engine in a Web Worker.
class WebStudioHunspellHost extends StudioHunspellHost {
  WebStudioHunspellHost({
    http.Client Function()? client,
    List<HunspellBundleDownload> catalog = hunspellCatalog,
    StudioWebDataStore? store,
  }) : _client = client ?? http.Client.new,
       store = store ?? createDefaultStudioWebDataStore(),
       _statuses = [for (final b in catalog) StudioHunspellStatus(bundle: b)];

  final http.Client Function() _client;

  /// Where verified downloads are kept between sessions.
  final StudioWebDataStore store;

  static String _key(HunspellBundleDownload bundle, HunspellArtifact file) =>
      'hunspell/${bundle.id}/${bundle.revision}/${file.file}';

  Future<void> _forget(HunspellBundleDownload bundle) async {
    for (final file in [bundle.aff, bundle.dic]) {
      await store.delete(_key(bundle, file));
    }
  }

  List<StudioHunspellStatus> _statuses;
  final Map<String, HunspellDictionaryBytes> _bytes = {};

  @override
  List<StudioHunspellStatus> get statuses => List.unmodifiable(_statuses);

  void _set(StudioHunspellStatus next) {
    _statuses = [
      for (final item in _statuses)
        item.bundle.id == next.bundle.id ? next : item,
    ];
    notifyListeners();
  }

  /// Restores dictionaries kept from an earlier session. Stored bytes are
  /// verified against the compiled-in pins; anything else is deleted.
  @override
  Future<void> refresh() async {
    for (final item in List.of(_statuses)) {
      final bundle = item.bundle;
      if (_bytes.containsKey(bundle.id)) continue;
      final aff = await store.read(_key(bundle, bundle.aff));
      final dic = await store.read(_key(bundle, bundle.dic));
      if (aff == null && dic == null) continue;
      try {
        if (aff == null || dic == null) {
          throw const FormatException('Incomplete stored dictionary.');
        }
        _bytes[bundle.id] = HunspellDictionaryBytes.verified(
          bundle,
          aff: aff,
          dic: dic,
        );
        _set(
          StudioHunspellStatus(
            bundle: bundle,
            installed: true,
            location: studioWebStoredLocation(aff.length + dic.length),
          ),
        );
      } on FormatException {
        await _forget(bundle);
        _set(
          StudioHunspellStatus(
            bundle: bundle,
            problem:
                'The dictionary stored in this browser failed verification '
                'and was removed. Download it again.',
          ),
        );
      }
    }
  }

  @override
  Future<void> install(
    HunspellBundleDownload bundle, {
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {
    void checkCancellation() {
      if (cancellation?.isCancelled ?? false) {
        throw StateError('Download cancelled.');
      }
    }

    checkCancellation();
    final client = _client();
    final aborted = Completer<void>();
    void abort() {
      if (!aborted.isCompleted) aborted.complete();
      client.close();
    }

    cancellation?.addListener(abort);
    final total = bundle.aff.bytes + bundle.dic.bytes;
    var received = 0;
    Future<Uint8List> fetch(HunspellArtifact artifact) async {
      checkCancellation();
      final response = await client.send(
        http.AbortableRequest(
          'GET',
          bundle.url(artifact),
          abortTrigger: aborted.future,
        ),
      );
      checkCancellation();
      if (response.statusCode != 200) {
        throw StateError('Download failed (${response.statusCode}).');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        checkCancellation();
        builder.add(chunk);
        received += chunk.length;
        if (builder.length > artifact.bytes) {
          throw StateError('Unexpected size for ${artifact.file}.');
        }
        onProgress?.call(received, total);
        checkCancellation();
      }
      checkCancellation();
      return builder.takeBytes();
    }

    try {
      final dictionary = HunspellDictionaryBytes.verified(
        bundle,
        aff: await fetch(bundle.aff),
        dic: await fetch(bundle.dic),
      );
      checkCancellation();
      _bytes[bundle.id] = dictionary;
      final stored =
          await store.write(_key(bundle, bundle.aff), dictionary.aff) &&
          await store.write(_key(bundle, bundle.dic), dictionary.dic);
      if (!stored) await _forget(bundle);
      _set(
        StudioHunspellStatus(
          bundle: bundle,
          installed: true,
          location: stored
              ? studioWebStoredLocation(
                  dictionary.aff.length + dictionary.dic.length,
                )
              : 'This session only (the browser refused storage)',
        ),
      );
    } on Object catch (error, stack) {
      final problem = (cancellation?.isCancelled ?? false)
          ? StateError('Download cancelled.')
          : error;
      _set(StudioHunspellStatus(bundle: bundle, problem: '$problem'));
      Error.throwWithStackTrace(problem, stack);
    } finally {
      cancellation?.removeListener(abort);
      client.close();
    }
  }

  @override
  Future<void> remove(HunspellBundleDownload bundle) async {
    _bytes.remove(bundle.id);
    await _forget(bundle);
    _set(StudioHunspellStatus(bundle: bundle));
  }

  @override
  List<OfficeProofingProvider> createProviders(
    OfficeProofingVocabulary vocabulary,
  ) => [
    for (final item in _statuses)
      if (item.installed && _bytes[item.bundle.id] != null)
        HunspellProofingProvider(
          bundle: item.bundle,
          dictionary: _bytes[item.bundle.id]!,
          vocabulary: vocabulary,
        ),
  ];
}
