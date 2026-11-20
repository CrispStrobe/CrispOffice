import 'dart:convert';
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

  bool failModel = false;
  final sentences = <List<List<String>>>[];

  @override
  Future<Map<String, Object?>> openDisambiguator(MorphDatabase model) async {
    if (failModel) throw StateError('bad model');
    return {'model_format': 'crispembed-camel-morph-disambig-v1'};
  }

  /// Every word reads as a noun (best, 0.9) or a verb (0.1).
  @override
  Future<List<List<ArabicContextReading>>> disambiguate(
    List<List<String>> batch,
  ) async {
    sentences.add(batch);
    return [
      for (final s in batch)
        [
          for (final word in s)
            ArabicContextReading(
              [
                {'lex': word, 'pos': 'noun'},
                {'lex': word, 'pos': 'verb'},
              ],
              const [0.9, 0.1],
              const [0, 1],
            ),
        ],
    ];
  }

  @override
  Future<void> dispose() async => disposed = true;
}

CamelArabicMorphology _morphology(
  _FakeTransport transport, {
  int cache = 10,
  bool model = false,
}) => CamelArabicMorphology(
  database: const MorphDatabaseFiles(
    camelMorphMsaProofingBin,
    manifestPath: 'unused',
  ),
  disambiguator: model
      ? const MorphDatabaseFiles(
          camelMorphMsaDisambig,
          manifestPath: 'unused-model',
        )
      : null,
  transport: transport,
  cacheWords: cache,
  batchWords: 2,
);

/// The score section of a disambiguation buffer: per word (rank, score)
/// for each analysis and the candidate count.
List<int> _scores(List<(int, List<(int, double)>)> words) {
  final out = BytesBuilder();
  void u32(int v) => out.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  u32(CompactAnalysisDecoder.scoresMagic);
  u32(words.length);
  for (final (candidates, analyses) in words) {
    u32(analyses.length);
    u32(candidates);
    for (final (rank, score) in analyses) {
      u32(rank);
      out.add(
        (ByteData(4)..setFloat32(0, score, Endian.little)).buffer.asUint8List(),
      );
    }
  }
  return out.takeBytes();
}

/// One word record of the compact format: [analyses] as (key id, value)
/// lists, null values allowed.
List<int> _record(List<List<(int, String?)>> analyses, {bool wide = false}) {
  final strings = <String>[];
  for (final a in analyses) {
    for (final (_, v) in a) {
      if (v != null && !strings.contains(v)) strings.add(v);
    }
  }
  final out = BytesBuilder();
  void u32(int v) => out.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  void u16(int v) => out.add(
    (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List(),
  );
  u32(analyses.length);
  u32(strings.length);
  out.add([wide ? 1 : 0, 0, 0, 0]);
  for (final s in strings) {
    final bytes = utf8.encode(s);
    out.addByte(0);
    u32(bytes.length);
    out.add(bytes);
  }
  for (final a in analyses) {
    u16(a.length);
    for (final (k, v) in a) {
      final ref = v == null ? -1 : strings.indexOf(v);
      if (wide) {
        u16(k);
        u32(ref < 0 ? 0xFFFFFFFF : ref);
      } else {
        out.addByte(k);
        u16(ref < 0 ? 0xFFFF : ref);
      }
    }
  }
  return out.takeBytes();
}

/// A batch buffer: per word a record, or null for a rejected word.
Uint8List _batch(List<List<int>?> records) {
  final out = BytesBuilder();
  void u32(int v) => out.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  u32(CompactAnalysisDecoder.magic);
  u32(records.length);
  for (final r in records) {
    u32(r == null ? 5 : 0);
    u32(r?.length ?? 0);
    if (r != null) out.add(r);
  }
  return out.takeBytes();
}

void main() {
  group('CompactAnalysisDecoder', () {
    const keys = ['diac', 'lex', 'pos', 'gen', 'source'];

    test('reads features lazily, omits nulls and rejects writes', () {
      final decoder = CompactAnalysisDecoder(keys);
      final words = decoder.decode(
        _batch([
          _record([
            [(0, 'كَتَبُوا'), (1, 'كَتَب'), (2, 'verb'), (3, null)],
            [(0, 'كُتُب'), (1, 'كِتَاب'), (2, 'noun'), (4, 'lex')],
          ]),
          null,
          _record([]),
        ]),
        3,
      );
      expect(words, hasLength(3));
      final first = words[0]!;
      expect(first, hasLength(2));
      expect(first[0], {'diac': 'كَتَبُوا', 'lex': 'كَتَب', 'pos': 'verb'});
      expect(first[0]['gen'], isNull);
      expect(first[0].containsKey('gen'), isFalse);
      expect(first[0]['missing'], isNull);
      expect(first[1]['source'], 'lex');
      expect(first[1].keys, ['diac', 'lex', 'pos', 'source']);
      expect(words[1], isNull);
      expect(words[2], isEmpty);
      expect(() => first[0]['pos'] = 'x', throwsUnsupportedError);
      expect(() => first.clear(), throwsUnsupportedError);
      expect(() => first[0] = const {}, throwsUnsupportedError);
      expect(() => first[2], throwsRangeError);
    });

    test('decodes the wide layout and shares equal values', () {
      final decoder = CompactAnalysisDecoder(keys);
      final words = decoder.decode(
        _batch([
          _record([
            [(2, 'noun'), (3, 'm')],
          ], wide: true),
          _record([
            [(2, 'noun')],
          ]),
        ]),
        2,
      );
      expect(words[0]!.single, {'pos': 'noun', 'gen': 'm'});
      expect(
        identical(words[0]!.single['pos'], words[1]!.single['pos']),
        isTrue,
      );
    });

    test('rejects malformed buffers', () {
      final decoder = CompactAnalysisDecoder(keys);
      final good = _batch([
        _record([
          [(2, 'noun')],
        ]),
      ]);
      expect(() => decoder.decode(good, 2), throwsFormatException);
      expect(
        () =>
            decoder.decode(Uint8List.sublistView(good, 0, good.length - 1), 1),
        throwsFormatException,
      );
      final bad = Uint8List.fromList(good)..[0] ^= 1;
      expect(() => decoder.decode(bad, 1), throwsFormatException);
      final status = Uint8List.fromList(good)..[8] = 6;
      expect(() => decoder.decode(status, 1), throwsFormatException);
    });
  });

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

    test('numeric feature text preserves fractions, signs and exponents', () {
      final analysis = ArabicAnalysisDecoder().decode([
        {
          'negative': -99,
          'positive': 7,
          'zero': 0,
          'negative_zero': -0.0,
          'fraction': -1.25,
          'tiny': 1e-7,
          'large_plain': 1e20,
          'exponent': 1e21,
          'text': '-99',
        },
      ]).single;
      expect(analysis, {
        'negative': '-99.0',
        'positive': '7.0',
        'zero': '0.0',
        'negative_zero': '-0.0',
        'fraction': '-1.25',
        'tiny': '1e-7',
        'large_plain': '100000000000000000000.0',
        'exponent': '1e+21',
        'text': '-99',
      });
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
    test('the catalog offers the binary proofing bundle', () {
      expect(morphCatalog, [camelMorphMsaProofingBin]);
      final bundle = camelMorphMsaProofingBin;
      expect(
        bundle.url(bundle.database).toString(),
        'https://huggingface.co/cstr/camel-morph-msa-v1.0/resolve/'
        'd5364e04af7a40b0c9044ed127606e585be15272/proofing-bin/'
        'camel_morph_msa_v1.0.proofing.cmorph',
      );
      expect(bundle.files.map((f) => f.file).toSet(), {
        'manifest.json',
        'camel_morph_msa_v1.0.proofing.cmorph',
        'NOTICE',
        'LICENSE',
      });
      expect(bundle.totalBytes, 12166992 + 2064 + 1799 + 442);
      expect(bundle.license, 'CC-BY-4.0');
      expect(bundle.attribution, contains('New York University Abu Dhabi'));
    });

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

  group('disambiguation buffers', () {
    const keys = ['lex', 'pos'];

    test('readings carry ranks and scores per analysis', () {
      final decoder = CompactAnalysisDecoder(keys);
      final buffer = Uint8List.fromList([
        ..._batch([
          _record([
            [(0, 'كِتَاب'), (1, 'noun')],
            [(0, 'كَتَب'), (1, 'verb')],
            [(0, 'كِتَاب'), (1, 'noun')],
          ]),
          null,
          _record([]),
        ]),
        ..._scores([
          (2, [(0, 0.96), (1, 0.04), (0, 0.96)]),
          (1, []),
          (1, []),
        ]),
      ]);
      final readings = decoder.decodeReadings(buffer, 3);
      expect(readings[0].best.map((a) => a['pos']), ['noun', 'noun']);
      expect(readings[0].margin, closeTo(0.92, 1e-6));
      expect(readings[0].confident(0.9), hasLength(2));
      expect(readings[1].analyses, isEmpty);
      expect(readings[2].confident(0), isNull);
      // A plain compact decode refuses the trailing score section.
      expect(() => decoder.decode(buffer, 3), throwsFormatException);
    });

    test('malformed score sections are rejected', () {
      final decoder = CompactAnalysisDecoder(keys);
      final record = _record([
        [(0, 'a'), (1, 'noun')],
      ]);
      Uint8List buffer(List<(int, List<(int, double)>)> scores) =>
          Uint8List.fromList([
            ..._batch([record]),
            ..._scores(scores),
          ]);
      expect(
        decoder
            .decodeReadings(
              buffer([
                (1, [(0, 1.0)]),
              ]),
              1,
            )
            .single
            .bestScore,
        1.0,
      );
      for (final bad in [
        <(int, List<(int, double)>)>[(1, [])], // count mismatch
        [
          (1, [(1, 1.0)]),
        ], // rank beyond the candidates
        [
          (0, [(0, 1.0)]),
        ], // no candidate
        [
          (1, [(0, 2.0)]),
        ], // score above 1
      ]) {
        expect(
          () => decoder.decodeReadings(buffer(bad), 1),
          throwsFormatException,
        );
      }
      expect(
        () => decoder.decodeReadings(_batch([record]), 1),
        throwsFormatException,
      );
    });
  });

  group('CamelArabicMorphology', () {
    test('disambiguates with a loaded model, batches and caches', () async {
      final transport = _FakeTransport();
      final morphology = _morphology(transport, model: true);
      expect(morphology.canDisambiguate, isFalse);
      final readings = await morphology.disambiguate([
        ['a', 'b'],
        ['c'],
        ['a', 'b'],
      ]);
      expect(morphology.canDisambiguate, isTrue);
      expect(readings.map((s) => s.length), [2, 1, 2]);
      expect(readings[1].single.best.single['pos'], 'noun');
      // Distinct sentences in batches of about two words.
      expect(transport.sentences, [
        [
          ['a', 'b'],
        ],
        [
          ['c'],
        ],
      ]);
      await morphology.disambiguate([
        ['c'],
      ]);
      expect(transport.sentences, hasLength(2), reason: 'cached');
      expect(morphology.disambiguatorInfo, isNotNull);
    });

    test('a model can be loaded later; a failing one is optional', () async {
      final transport = _FakeTransport()..failModel = true;
      final morphology = _morphology(transport);
      await morphology.load();
      expect(morphology.canDisambiguate, isFalse);
      expect(
        await morphology.disambiguate([
          ['a'],
        ]),
        isEmpty,
      );
      const model = MorphDatabaseFiles(
        camelMorphMsaDisambig,
        manifestPath: 'unused-model',
      );
      await morphology.loadDisambiguator(model);
      expect(morphology.canDisambiguate, isFalse);
      expect(morphology.disambiguatorFailure, isNotNull);
      expect(morphology.isAvailable, isTrue, reason: 'analysis is unaffected');
      transport.failModel = false;
      await morphology.loadDisambiguator(model);
      expect(morphology.canDisambiguate, isTrue);
    });

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

    test('implements the engine interfaces', () {
      expect(_morphology(_FakeTransport()), isA<ArabicMorphology>());
      expect(_morphology(_FakeTransport()), isA<ArabicContextMorphology>());
    });
  });
}
