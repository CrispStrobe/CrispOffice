import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

import 'studio_hunspell_host.dart';

StudioHunspellHost createHost() => WebStudioHunspellHost();

/// Browser host: the user's download is verified and kept in memory for the
/// session; the bundled WebAssembly engine runs it in a Web Worker.
class WebStudioHunspellHost extends StudioHunspellHost {
  WebStudioHunspellHost({
    http.Client Function()? client,
    List<HunspellBundleDownload> catalog = hunspellCatalog,
  }) : _client = client ?? http.Client.new,
       _statuses = [for (final b in catalog) StudioHunspellStatus(bundle: b)];

  final http.Client Function() _client;
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

  @override
  Future<void> refresh() async {}

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
      _set(
        StudioHunspellStatus(
          bundle: bundle,
          installed: true,
          location: 'memory',
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
