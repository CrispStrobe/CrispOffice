import 'dart:typed_data';

import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

final class _FakeTransport implements ArabicMorphTransport {
  final requests = <List<String>>[];
  bool failOpen = false;
  bool failAnalyze = false;
  bool disposed = false;

  @override
  Future<Map<String, Object?>> open(MorphDatabase database) async {
    if (failOpen) throw const ArabicMorphUnavailableException('no library');
    return {'variant': 'noprob'};
  }

  @override
  Future<List<List<ArabicAnalysis>?>> analyze(List<String> words) async {
    if (failAnalyze) throw const ArabicMorphUnavailableException('stopped');
    requests.add(List.of(words));
    return [
      for (final word in words)
        word == 'bad'
            ? null
            : word.startsWith('x')
            ? const <ArabicAnalysis>[]
            : [
                {'lex': word, 'pos': 'noun'},
              ],
    ];
  }

  @override
  Future<void> dispose() async => disposed = true;
}

CamelArabicMorphology _morphology(_FakeTransport transport, {int cache = 10}) =>
    CamelArabicMorphology(
      database: const MorphDatabaseFiles(
        camelMorphMsaNoprob,
        manifestPath: 'unused',
      ),
      transport: transport,
      cacheWords: cache,
      batchWords: 2,
    );

void main() {
  group('ArabicAnalysisDecoder', () {
    test('keeps strings, formats numbers, omits nulls, shares layouts', () {
      final decoder = ArabicAnalysisDecoder();
      final analyses = decoder.decode([
        {
          'diac': 'كَتَبُوا',
          'pos': 'verb',
          'pos_lex_logprob': -99.0,
          'x': null,
        },
        {'diac': 'كُتُب', 'pos': 'noun', 'pos_lex_logprob': -99, 'x': null},
      ]);
      expect(analyses, hasLength(2));
      expect(analyses[0], {
        'diac': 'كَتَبُوا',
        'pos': 'verb',
        'pos_lex_logprob': '-99.0',
      });
      expect(analyses[1]['pos_lex_logprob'], '-99.0');
      expect(analyses[1].containsKey('x'), isFalse);
      expect(analyses[1]['missing'], isNull);
      expect(identical(analyses[0].keys, analyses[1].keys), isTrue);
      expect(() => analyses[0]['pos'] = 'noun', throwsUnsupportedError);
    });

    test('rejects malformed input', () {
      final decoder = ArabicAnalysisDecoder();
      expect(() => decoder.decode({'a': 1}), throwsFormatException);
      expect(() => decoder.decode(['x']), throwsFormatException);
      expect(
        () => decoder.decode([
          {
            'a': [1],
          },
        ]),
        throwsFormatException,
      );
    });
  });

  group('catalog', () {
    test('noprob bundle is pinned to the immutable revision', () {
      final bundle = camelMorphMsaNoprob;
      expect(bundle.revision, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(
        bundle.url(bundle.database).toString(),
        'https://huggingface.co/cstr/camel-morph-msa-v1.0/resolve/'
        'b31cf4a83f8ad63bb1989cf2879e72f23fadbfb0/noprob/'
        'camel_morph_msa_v1.0.noprob.db',
      );
      expect(bundle.files.map((f) => f.file).toSet(), {
        'manifest.json',
        'camel_morph_msa_v1.0.noprob.db',
        'NOTICE',
        'LICENSE',
      });
      expect(bundle.totalBytes, 78083392 + 1430 + 1381 + 442);
      expect(bundle.license, 'CC-BY-4.0');
      expect(bundle.attribution, contains('New York University Abu Dhabi'));
    });

    test('web bytes are admitted only when every file matches', () {
      final files = {
        for (final a in camelMorphMsaNoprob.files) a.file: Uint8List(a.bytes),
      };
      expect(
        () => MorphDatabaseBytes.verified(camelMorphMsaNoprob, files),
        throwsFormatException,
      );
      expect(
        () => MorphDatabaseBytes.verified(camelMorphMsaNoprob, {}),
        throwsFormatException,
      );
    });
  });

  group('CamelArabicMorphology', () {
    test('is unavailable until loaded, then batches distinct words', () async {
      final transport = _FakeTransport();
      final morphology = _morphology(transport);
      expect(morphology.isAvailable, isFalse);
      await morphology.load();
      expect(morphology.isAvailable, isTrue);
      final result = await morphology.analyzeWords([
        'a',
        'b',
        'a',
        'c',
        'bad',
        'xq',
      ]);
      expect(result.keys, unorderedEquals(['a', 'b', 'c', 'bad', 'xq']));
      expect(result['bad'], isEmpty);
      expect(result['xq'], isEmpty);
      expect(result['c']!.single['lex'], 'c');
      expect(transport.requests, [
        ['a', 'b'],
        ['c', 'bad'],
        ['xq'],
      ]);
      // Cached: no new request.
      await morphology.analyzeWords(['c', 'a']);
      expect(transport.requests, hasLength(3));
      await morphology.dispose();
      expect(transport.disposed, isTrue);
      expect(morphology.isAvailable, isFalse);
    });

    test('the cache is bounded, oldest first', () async {
      final transport = _FakeTransport();
      final morphology = _morphology(transport, cache: 2);
      await morphology.analyzeWords(['a', 'b', 'c']);
      expect(morphology.cachedWords, 2);
      transport.requests.clear();
      await morphology.analyzeWords(['a']);
      expect(transport.requests, [
        ['a'],
      ]);
    });

    test('a failed load or a stopped worker means unavailable', () async {
      final failing = _FakeTransport()..failOpen = true;
      final morphology = _morphology(failing);
      expect(await morphology.analyzeWords(['a']), {'a': isEmpty});
      expect(morphology.isAvailable, isFalse);
      expect(morphology.failure, isA<ArabicMorphUnavailableException>());

      final stopping = _FakeTransport();
      final second = _morphology(stopping);
      await second.load();
      stopping.failAnalyze = true;
      expect(await second.analyzeWords(['a', 'b', 'c']), {
        'a': isEmpty,
        'b': isEmpty,
        'c': isEmpty,
      });
      expect(second.isAvailable, isFalse);
    });

    test('implements the engine interface', () {
      expect(_morphology(_FakeTransport()), isA<ArabicMorphology>());
    });
  });
}
