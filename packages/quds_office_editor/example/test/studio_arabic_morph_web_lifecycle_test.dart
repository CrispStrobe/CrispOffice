// Controlled host/transport qualification on the VM. Real JS transfer behavior
// is covered by quds_arabic_morph/tool/worker_lifecycle_test.mjs; this does not
// claim a browser or native analyzer execution.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_studio/studio_arabic_morph_host_web.dart';
import 'package:quds_office_studio/studio_web_data_store.dart';

final _files = <String, Uint8List>{
  for (final name in ['db', 'model']) ...{
    '$name/manifest.json': Uint8List.fromList(utf8.encode('{"id":"$name"}')),
    '$name/data.bin': Uint8List.fromList(utf8.encode('$name verified data')),
  },
};

MorphBundleDownload _bundle(String name) {
  MorphArtifact artifact(String file) {
    final bytes = _files['$name/$file']!;
    return MorphArtifact(file, sha256.convert(bytes).toString(), bytes.length);
  }

  return MorphBundleDownload(
    id: name,
    displayName: 'Controlled $name',
    repository: 'test/arabic-morph',
    revision: '0123456789abcdef0123456789abcdef01234567',
    directory: name,
    license: 'test',
    licenseUrl: 'https://example.invalid/license',
    attribution: 'test',
    sourceUrl: 'https://example.invalid/source',
    manifest: artifact('manifest.json'),
    database: artifact('data.bin'),
    notices: const [],
  );
}

final class _MemoryStore implements StudioWebDataStore {
  _MemoryStore({required this.keep});
  final bool keep;
  final files = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String key) async {
    final bytes = files[key];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<bool> write(String key, Uint8List bytes) async {
    if (keep) files[key] = Uint8List.fromList(bytes);
    return keep;
  }

  @override
  Future<void> delete(String key) async => files.remove(key);
}

final class _OwnedBufferTransport implements ArabicMorphTransport {
  int databaseOpens = 0;
  int modelOpens = 0;
  int modelUnloads = 0;
  bool modelLoaded = false;
  bool disposed = false;
  bool failUnload = false;

  void _consume(MorphDatabase database) {
    final bytes = database as MorphDatabaseBytes;
    // The VM cannot detach an ArrayBuffer. Consume the supplied storage so
    // attempting to reuse these verified inputs fails instead of appearing
    // safe just because this transport is a fake.
    for (final file in bytes.bundle.files) {
      final data = bytes.files[file.file]!;
      if (!file.matches(data)) throw StateError('database buffers were reused');
      data.fillRange(0, data.length, 0);
    }
  }

  @override
  Future<Map<String, Object?>> open(MorphDatabase database) async {
    databaseOpens++;
    _consume(database);
    return {'variant': 'controlled'};
  }

  @override
  Future<Map<String, Object?>> openDisambiguator(MorphDatabase model) async {
    modelOpens++;
    _consume(model);
    modelLoaded = true;
    return {'model': 'controlled'};
  }

  @override
  Future<void> unloadDisambiguator() async {
    modelUnloads++;
    if (failUnload) {
      throw const ArabicMorphUnavailableException('controlled worker loss');
    }
    modelLoaded = false;
  }

  @override
  Future<List<List<ArabicAnalysis>?>> analyze(List<String> words) async => [
    for (final word in words)
      [
        {'lex': word, 'pos': 'noun'},
      ],
  ];

  @override
  Future<List<List<ArabicContextReading>>> disambiguate(
    List<List<String>> sentences,
  ) async => throw StateError('not needed by this host control');

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  for (final kept in [true, false]) {
    test(
      'removing model keeps transferred database, persistent=$kept',
      () async {
        final transport = _OwnedBufferTransport();
        final store = _MemoryStore(keep: kept);
        final requests = <String>[];
        var factories = 0;
        final host = WebStudioArabicMorphHost(
          bundle: _bundle('db'),
          modelBundle: _bundle('model'),
          store: store,
          transportFactory: () {
            factories++;
            return transport;
          },
          client: () => MockClient((request) async {
            final path = request.url.pathSegments;
            final key = '${path[path.length - 2]}/${path.last}';
            requests.add(key);
            return http.Response.bytes(Uint8List.fromList(_files[key]!), 200);
          }),
        );
        addTearDown(host.remove);
        await host.install();
        await host.installModel();
        final morphology = host.morphology;
        expect(host.status.loaded, isTrue);
        expect(host.modelStatus.loaded, isTrue);
        expect(transport.modelLoaded, isTrue);
        await host.removeModel();
        expect(identical(host.morphology, morphology), isTrue);
        expect(host.status.loaded, isTrue);
        expect(host.modelStatus.installed, isFalse);
        expect(host.modelStatus.loaded, isFalse);
        expect(
          (morphology as ArabicContextMorphology).canDisambiguate,
          isFalse,
        );
        expect(
          (await morphology.analyzeWords(['كتب']))['كتب']!.single['lex'],
          'كتب',
        );
        expect(transport.databaseOpens, 1);
        expect(transport.modelUnloads, 1);
        expect(transport.modelLoaded, isFalse);
        expect(transport.disposed, isFalse);
        expect(factories, 1);
        expect(requests, [
          'db/manifest.json',
          'db/data.bin',
          'model/manifest.json',
          'model/data.bin',
        ]);
        expect(
          store.files.keys.any((key) => key.startsWith('morph/model/')),
          isFalse,
        );
        expect(
          store.files.keys.any((key) => key.startsWith('morph/db/')),
          kept,
        );
        await host.installModel();
        expect(host.modelStatus.loaded, isTrue);
        expect(transport.modelOpens, 2);
        expect(transport.databaseOpens, 1);
      },
    );
  }

  test('worker loss during model removal updates host availability', () async {
    final transport = _OwnedBufferTransport()..failUnload = true;
    final host = WebStudioArabicMorphHost(
      bundle: _bundle('db'),
      modelBundle: _bundle('model'),
      store: _MemoryStore(keep: false),
      transportFactory: () => transport,
      client: () => MockClient((request) async {
        final path = request.url.pathSegments;
        return http.Response.bytes(
          Uint8List.fromList(_files['${path[path.length - 2]}/${path.last}']!),
          200,
        );
      }),
    );
    addTearDown(host.remove);
    await host.install();
    await host.installModel();
    await host.removeModel();
    expect(host.status.installed, isTrue);
    expect(host.status.loaded, isFalse);
    expect(host.morphology.isAvailable, isFalse);
    expect(host.status.problem, contains('controlled worker loss'));
    expect(host.modelStatus.loaded, isFalse);
    expect(host.modelStatus.problem, contains('could not be unloaded'));
  });
}
