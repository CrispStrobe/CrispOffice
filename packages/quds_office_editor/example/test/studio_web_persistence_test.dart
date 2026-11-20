// Browser-only: flutter test --platform chrome test/studio_web_persistence_test.dart
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_studio/studio_arabic_morph_host_web.dart';
import 'package:quds_office_studio/studio_hunspell_host_web.dart';
import 'package:quds_office_studio/studio_web_data_store_cache.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

const _revision = '0123456789abcdef0123456789abcdef01234567';
final _aff = Uint8List.fromList(utf8.encode('SET UTF-8\n'));
final _dic = Uint8List.fromList(utf8.encode('1\nword\n'));
final _manifest = Uint8List.fromList(utf8.encode('{"variant":"test"}'));
final _database = Uint8List.fromList(List<int>.generate(4096, (i) => i % 251));

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

final _bundle = HunspellBundleDownload(
  id: 'persist-test',
  displayName: 'Persistence test',
  languages: const {'xx'},
  repository: 'test/persist',
  revision: _revision,
  license: 'test',
  aff: HunspellArtifact('t.aff', _sha(_aff), _aff.length),
  dic: HunspellArtifact('t.dic', _sha(_dic), _dic.length),
  notices: const [],
);

final _morph = MorphBundleDownload(
  id: 'persist-morph',
  displayName: 'Morphology persistence test',
  repository: 'test/morph',
  revision: _revision,
  directory: 'db',
  license: 'test',
  licenseUrl: 'https://example.invalid/license',
  attribution: 'test',
  sourceUrl: 'https://example.invalid/source',
  manifest: MorphArtifact('manifest.json', _sha(_manifest), _manifest.length),
  database: MorphArtifact('db.bin', _sha(_database), _database.length),
  notices: const [],
);

/// The browser analyzer transfers database buffers to its worker (they are
/// detached afterwards), so every use gets its own copy.
Uint8List _copy(Uint8List bytes) => Uint8List.fromList(bytes);

MockClient _server(Map<String, Uint8List> files, List<String> requests) =>
    MockClient((request) async {
      requests.add(request.url.pathSegments.last);
      final body = files[request.url.pathSegments.last];
      return body == null
          ? http.Response('missing', 404)
          : http.Response.bytes(_copy(body), 200);
    });

void main() {
  var run = 0;
  late CacheStorageStudioWebDataStore store;
  setUp(() {
    store = CacheStorageStudioWebDataStore(
      cacheName:
          'quds-proofing-test-${DateTime.now().microsecondsSinceEpoch}-${run++}',
    );
  });

  test(
    'a verified dictionary survives a new session and is removable',
    () async {
      final requests = <String>[];
      final first = WebStudioHunspellHost(
        client: () => _server({'t.aff': _aff, 't.dic': _dic}, requests),
        catalog: [_bundle],
        store: store,
      );
      await first.install(_bundle);
      expect(requests, ['t.aff', 't.dic']);
      expect(
        first.status(_bundle).location,
        contains('Stored in this browser'),
      );

      // A reload: a new host restores without any network request.
      final second = WebStudioHunspellHost(
        client: () => _server(const {}, requests),
        catalog: [_bundle],
        store: store,
      );
      await second.refresh();
      expect(requests, ['t.aff', 't.dic']);
      final restored = second.status(_bundle);
      expect(restored.installed, isTrue);
      expect(restored.location, contains('0.0 MB'));
      expect(second.createProviders(OfficeProofingVocabulary()), hasLength(1));

      await second.remove(_bundle);
      final third = WebStudioHunspellHost(catalog: [_bundle], store: store);
      await third.refresh();
      expect(third.status(_bundle).installed, isFalse);
      expect(
        await store.read('hunspell/persist-test/$_revision/t.dic'),
        isNull,
      );
    },
  );

  test('stored bytes that no longer match the pins are deleted', () async {
    await store.write('hunspell/persist-test/$_revision/t.aff', _aff);
    await store.write(
      'hunspell/persist-test/$_revision/t.dic',
      Uint8List.fromList(utf8.encode('1\nchanged\n')),
    );
    final host = WebStudioHunspellHost(catalog: [_bundle], store: store);
    await host.refresh();
    final status = host.status(_bundle);
    expect(status.installed, isFalse);
    expect(status.problem, contains('failed verification'));
    expect(await store.read('hunspell/persist-test/$_revision/t.aff'), isNull);
    expect(await store.read('hunspell/persist-test/$_revision/t.dic'), isNull);
  });

  test('the morphology database is restored only after verification', () async {
    final requests = <String>[];
    final first = WebStudioArabicMorphHost(
      client: () =>
          _server({'manifest.json': _manifest, 'db.bin': _database}, requests),
      bundle: _morph,
      store: store,
    );
    await first.install();
    expect(first.status.installed, isTrue);
    expect(first.status.location, contains('Stored in this browser'));
    await first.remove();

    // Removal deleted it; a fresh install stores it again.
    final second = WebStudioArabicMorphHost(bundle: _morph, store: store);
    await second.refresh();
    expect(second.status.installed, isFalse);

    for (final file in _morph.files) {
      await store.write(
        'morph/persist-morph/$_revision/${file.file}',
        _copy(file.file == 'db.bin' ? _database : _manifest),
      );
    }
    final third = WebStudioArabicMorphHost(bundle: _morph, store: store);
    await third.refresh();
    expect(third.status.installed, isTrue, reason: third.status.problem);
    expect(third.status.location, contains('Stored in this browser'));
    await third.remove();

    await store.write(
      'morph/persist-morph/$_revision/manifest.json',
      _manifest,
    );
    await store.write(
      'morph/persist-morph/$_revision/db.bin',
      Uint8List.fromList(_database.reversed.toList()),
    );
    final tampered = WebStudioArabicMorphHost(bundle: _morph, store: store);
    await tampered.refresh();
    expect(tampered.status.installed, isFalse);
    expect(tampered.status.problem, contains('failed verification'));
    expect(await store.read('morph/persist-morph/$_revision/db.bin'), isNull);
  });
}
