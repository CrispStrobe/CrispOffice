import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import 'support.dart';

final class _Transport implements GectorTransport {
  _Transport(this.handler);
  final Future<GectorDecodedText> Function(GectorCheckRequest) handler;
  bool disposed = false;
  int calls = 0;
  @override
  Future<GectorDecodedText> check(GectorCheckRequest request) {
    calls++;
    return handler(request);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

// Select model proposals by the exact WordPiece IDs of a source word. This
// exercises real guarded decoding and source projection without model weights.
final class _MappedBackend implements GectorBackend {
  _MappedBackend(this.fixtures, Map<String, String> labels)
    : proposals = <({List<int> ids, String label})>[
        for (final entry in labels.entries)
          (
            ids: fixtures.bundle.tokenizer
                .encode(<String>[entry.key])
                .inputIds
                .skip(1)
                .takeWhile((id) => id != 103)
                .toList(),
            label: entry.value,
          ),
      ];

  final TestBundle fixtures;
  final List<({List<int> ids, String label})> proposals;
  int calls = 0;

  @override
  GectorBackendIdentity get identity => const GectorBackendIdentity(
    artifactSha256: 'test',
    sourceModelSha256: gectorSourceModelSha256,
  );

  @override
  Future<GectorLogits> forward(GectorPreparedInput input) {
    calls++;
    final starts = input.firstSubwordIndices;
    final labels = List<String>.filled(starts.length, r'$KEEP');
    for (var word = 1; word < starts.length; word++) {
      final end = word + 1 < starts.length
          ? starts[word + 1]
          : input.tokenCount - 1;
      for (final proposal in proposals) {
        if (end - starts[word] != proposal.ids.length) continue;
        var matches = true;
        for (var i = 0; i < proposal.ids.length; i++) {
          if (input.inputIds[starts[word] + i] != proposal.ids[i]) {
            matches = false;
            break;
          }
        }
        if (matches) labels[word] = proposal.label;
      }
    }
    return ScriptedBackend(fixtures.bundle.configuration, <List<String>>[
      labels,
    ]).forward(input);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late TestBundle fixtures;
  late GectorConfiguration config;
  setUpAll(() async {
    fixtures = await TestBundle.load();
    config = fixtures.bundle.configuration;
  });
  OfficeProofingRequest request(
    String text, {
    String language = 'de-DE',
    int offset = 0,
  }) => OfficeProofingRequest(
    documentId: 'doc',
    blockId: 'p',
    revision: 7,
    text: text,
    language: language,
    startOffset: offset,
  );
  GectorDecodedText result(
    String text,
    List<GectorEdit> edits, {
    bool guarded = true,
    GectorStopReason reason = GectorStopReason.stable,
  }) => GectorDecodedText(
    original: text,
    corrected: GectorSourceText(text, config).apply(edits),
    edits: edits,
    passes: const <GectorPass>[],
    stopReason: reason,
    guarded: guarded,
  );

  GectorDecoder segmented(GectorBackend backend, Iterable<String> knownWords) =>
      GectorDecoder.guarded(
        configuration: config,
        tokenizer: fixtures.bundle.tokenizer,
        backend: backend,
        guards: GectorGermanGuards.fromJson(
          fixtures.bundle.guardsJson,
          configuration: config,
          lexicon: GectorWordSetLexicon(knownWords),
        ),
        options: GectorDecodeOptions(
          segmentation: GectorSegmentationOptions(targetTokens: 6),
        ),
      );

  test(
    'result retains original request identity and adds UTF-16 base once',
    () async {
      const text = '😊 mude';
      final transport = _Transport(
        (r) async => result(r.text, const <GectorEdit>[
          GectorEdit(start: 3, end: 7, original: 'mude', replacement: 'müde'),
        ]),
      );
      final provider = GectorProofingProvider.withTransport(
        transport: transport,
        configuration: config,
      );
      final input = request(text, offset: 120);
      final report = await OfficeProofingService(
        providers: <OfficeProofingProvider>[provider],
      ).check(input);
      expect(report.complete, isTrue);
      expect(identical(report.results.single.request, input), isTrue);
      expect(report.findings.single.start, 123);
      expect(report.findings.single.end, 127);
      expect(report.findings.single.originalText, 'mude');
      expect(report.findings.single.replacements, <String>['müde']);
      await provider.dispose();
    },
  );

  test('de-AT and de-CH remain explicitly unsupported', () async {
    final transport = _Transport(
      (r) async => result(r.text, const <GectorEdit>[]),
    );
    final provider = GectorProofingProvider.withTransport(
      transport: transport,
      configuration: config,
    );
    expect(
      (await provider.check(request('Grüezi.', language: 'de-CH'))).status,
      OfficeProofingStatus.unsupported,
    );
    expect(
      (await provider.check(request('Servus.', language: 'de-AT'))).status,
      OfficeProofingStatus.unsupported,
    );
    expect(transport.calls, 0);
    expect(provider.supportsLanguage('de_DE'), isTrue);
    await provider.dispose();
  });

  test(
    'links, code, personal words and grapheme-interior edits are suppressed',
    () async {
      const text = 'https://mude.de `mude` Mude Mu\u0308de';
      final transport = _Transport(
        (r) async => result(r.text, const <GectorEdit>[
          GectorEdit(start: 8, end: 12, original: 'mude', replacement: 'müde'),
          GectorEdit(start: 17, end: 21, original: 'mude', replacement: 'müde'),
          GectorEdit(start: 23, end: 27, original: 'Mude', replacement: 'Müde'),
          GectorEdit(start: 28, end: 30, original: 'Mu', replacement: 'Mü'),
        ]),
      );
      final vocabulary = OfficeProofingVocabulary()..addWord('Mude');
      final provider = GectorProofingProvider.withTransport(
        transport: transport,
        configuration: config,
        vocabulary: vocabulary,
      );
      final checked = await provider.check(request(text));
      expect(checked.status, OfficeProofingStatus.success);
      expect(checked.findings, isEmpty);
      await provider.dispose();
    },
  );

  test('vocabulary changes during work invalidate the result', () async {
    final pending = Completer<GectorDecodedText>();
    final transport = _Transport((r) => pending.future);
    final vocabulary = OfficeProofingVocabulary();
    final provider = GectorProofingProvider.withTransport(
      transport: transport,
      configuration: config,
      vocabulary: vocabulary,
    );
    final checked = provider.check(request('mude'));
    vocabulary.addWord('mude');
    pending.complete(result('mude', const <GectorEdit>[]));
    expect((await checked).status, OfficeProofingStatus.failed);
    expect(provider.configurationRevision, vocabulary.revision);
    await provider.dispose();
  });

  test(
    'unguarded and incomplete outputs do not become successful empty reports',
    () async {
      for (final invalid in <GectorDecodedText>[
        result('mude', const <GectorEdit>[], guarded: false),
        result(
          'mude',
          const <GectorEdit>[],
          reason: GectorStopReason.passLimit,
        ),
        result('mude', const <GectorEdit>[], reason: GectorStopReason.cycle),
      ]) {
        final provider = GectorProofingProvider.withTransport(
          transport: _Transport((r) async => invalid),
          configuration: config,
        );
        final checked = await provider.check(request('mude'));
        expect(checked.status, OfficeProofingStatus.failed);
        expect(checked.findings, isEmpty);
        await provider.dispose();
      }
    },
  );

  test('deadline failure disposes worker and prevents later checks', () async {
    final transport = _Transport((r) => Completer<GectorDecodedText>().future);
    final provider = GectorProofingProvider.withTransport(
      transport: transport,
      configuration: config,
      timeout: const Duration(milliseconds: 10),
    );
    expect(
      (await provider.check(request('mude'))).status,
      OfficeProofingStatus.failed,
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.disposed, isTrue);
    expect(
      (await provider.check(request('mude'))).status,
      OfficeProofingStatus.unavailable,
    );
  });

  test(
    'transport edits must reproduce its corrected text before filtering',
    () async {
      final malformed = GectorDecodedText(
        original: 'Du ist hier.',
        corrected: 'Du bist hier.',
        edits: const <GectorEdit>[],
        passes: const <GectorPass>[],
        stopReason: GectorStopReason.stable,
        guarded: true,
      );
      final provider = GectorProofingProvider.withTransport(
        transport: _Transport((r) async => malformed),
        configuration: config,
      );
      expect(
        (await provider.check(request('Du ist hier.'))).status,
        OfficeProofingStatus.failed,
      );
      await provider.dispose();
    },
  );

  test(
    'real segmented edits preserve emoji and CRLF and add request offset once',
    () async {
      const text = '😊 Das ist gut.\r\nWir ist zufrieden.  ';
      final backend = _MappedBackend(fixtures, const <String, String>{
        'ist': r'$TRANSFORM_VERB_P3S_P3P',
      });
      final decoder = segmented(backend, const <String>['sind']);
      late GectorDecodedText decoded;
      final provider = GectorProofingProvider.withTransport(
        transport: _Transport((r) async {
          decoded = await decoder.correct(
            r.text,
            personalWords: r.personalWords,
          );
          return decoded;
        }),
        configuration: config,
      );
      addTearDown(provider.dispose);
      final input = request(text, offset: 120);
      final checked = await provider.check(input);
      expect(checked.status, OfficeProofingStatus.success);
      expect(identical(checked.request, input), isTrue);
      expect(decoded.segmentCount, 2);
      expect(decoded.corrected, '😊 Das ist gut.\r\nWir sind zufrieden.  ');
      final start = text.indexOf('ist', text.indexOf('Wir'));
      expect(checked.findings, hasLength(1));
      expect(checked.findings.single.start, 120 + start);
      expect(checked.findings.single.end, 120 + start + 3);
      expect(checked.findings.single.originalText, 'ist');
      expect(checked.findings.single.replacements, <String>['sind']);
      expect(decoded.edits.single.start, start);
      expect(decoded.passes.last.sourceStart, text.indexOf('Wir'));
    },
  );

  test(
    'later segmented proposals still respect protected text personal words and graphemes',
    () async {
      const text =
          'Das ist gut. Mude https://mude.de `mude` Mu\u0308de. Wir ist zufrieden.';
      final backend = _MappedBackend(fixtures, const <String, String>{
        'mude': r'$REPLACE_müde',
        'Mude': r'$REPLACE_müde',
        'Mu': r'$REPLACE_müde',
        'ist': r'$TRANSFORM_VERB_P3S_P3P',
      });
      final decoder = segmented(backend, const <String>['müde', 'sind']);
      late GectorDecodedText decoded;
      final provider = GectorProofingProvider.withTransport(
        transport: _Transport((r) async {
          decoded = await decoder.correct(
            r.text,
            personalWords: r.personalWords,
          );
          return decoded;
        }),
        configuration: config,
        vocabulary: OfficeProofingVocabulary()..addWord('Mude'),
      );
      addTearDown(provider.dispose);
      final checked = await provider.check(request(text, offset: 50));
      expect(checked.status, OfficeProofingStatus.success);
      expect(decoded.segmentCount, 3);
      expect(decoded.edits.length, greaterThan(1));
      final protected = OfficeProofingTextRanges(text);
      expect(
        decoded.edits.any((edit) => protected.overlaps(edit.start, edit.end)),
        isTrue,
      );
      final boundaries = GectorSourceText(text, config).graphemeBoundaries;
      expect(
        decoded.edits.any((edit) => !boundaries.contains(edit.end)),
        isTrue,
      );
      final personalStart = text.indexOf('Mude');
      expect(
        decoded.edits.any(
          (edit) => edit.start < personalStart + 4 && personalStart < edit.end,
        ),
        isFalse,
      );
      expect(checked.findings, hasLength(1));
      expect(checked.findings.single.start, 50 + text.lastIndexOf('ist'));
      expect(checked.findings.single.originalText, 'ist');
      expect(checked.findings.single.replacements, <String>['sind']);
    },
  );

  test('a later real segment cycle publishes no earlier correction', () async {
    const text = 'Wir ist zufrieden. Buch. Das ist gut.';
    final backend = _MappedBackend(fixtures, const <String, String>{
      'ist': r'$TRANSFORM_VERB_P3S_P3P',
      'Buch': r'$REPLACE_Haus',
      'Haus': r'$REPLACE_Buch',
    });
    final decoder = segmented(backend, const <String>['sind', 'Haus', 'Buch']);
    late GectorDecodedText decoded;
    final provider = GectorProofingProvider.withTransport(
      transport: _Transport((r) async {
        decoded = await decoder.correct(r.text, personalWords: r.personalWords);
        return decoded;
      }),
      configuration: config,
    );
    addTearDown(provider.dispose);
    final checked = await provider.check(request(text));
    expect(checked.status, OfficeProofingStatus.failed);
    expect(checked.findings, isEmpty);
    expect(decoded.stopReason, GectorStopReason.cycle);
    expect(decoded.corrected, text);
    expect(decoded.edits, isEmpty);
    expect(decoded.passes.first.editedWords, <String>[
      'Wir',
      'sind',
      'zufrieden',
    ]);
    expect(backend.calls, 4);
  });

  test('one provider deadline covers every segment and disposes late work', () {
    fakeAsync((clock) {
      final backend = ScriptedBackend(
        config,
        const <List<String>>[],
        delay: const Duration(milliseconds: 60),
      );
      final decoder = segmented(backend, const <String>[]);
      late _Transport transport;
      transport = _Transport(
        (r) => decoder.correct(r.text, isCancelled: () => transport.disposed),
      );
      final provider = GectorProofingProvider.withTransport(
        transport: transport,
        configuration: config,
        timeout: const Duration(milliseconds: 100),
      );
      OfficeProofingResult? checked;
      provider
          .check(request('Das ist gut. Das ist lang. Das ist fertig.'))
          .then((value) => checked = value);
      clock.elapse(const Duration(milliseconds: 60));
      expect(backend.calls, 2);
      expect(checked, isNull);
      clock.elapse(const Duration(milliseconds: 40));
      expect(checked!.status, OfficeProofingStatus.failed);
      expect(checked!.findings, isEmpty);
      expect(transport.disposed, isTrue);
      clock.elapse(const Duration(seconds: 1));
      expect(
        backend.calls,
        2,
        reason: 'No third segment starts after disposal.',
      );
      OfficeProofingResult? unavailable;
      provider
          .check(request('Das ist gut.'))
          .then((value) => unavailable = value);
      clock.flushMicrotasks();
      expect(unavailable!.status, OfficeProofingStatus.unavailable);
    });
  });
}
