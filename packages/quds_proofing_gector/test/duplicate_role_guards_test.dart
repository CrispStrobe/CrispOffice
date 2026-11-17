import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import 'support.dart';

String _key(GectorPreparedInput input) => jsonEncode(<Object>[
  input.inputIds,
  input.attentionMask,
  input.firstSubwordIndices,
]);

final class _DeletionBackend implements GectorDeterministicBackend {
  _DeletionBackend(this.fixtures, Map<String, List<int>> deletions)
    : proposals = <String, List<String>>{} {
    for (final entry in deletions.entries) {
      final source = GectorSourceText(entry.key, fixtures.bundle.configuration);
      final words = source.words(source.plain);
      final tags = List<String>.filled(words.length + 1, r'$KEEP');
      for (final index in entry.value) {
        tags[index + 1] = r'$DELETE';
      }
      proposals[_key(fixtures.bundle.tokenizer.encode(words))] = tags;
    }
  }

  final TestBundle fixtures;
  final Map<String, List<String>> proposals;
  int calls = 0;
  @override
  GectorBackendIdentity get identity => const GectorBackendIdentity(
    artifactSha256: 'test',
    sourceModelSha256: gectorSourceModelSha256,
  );
  @override
  Future<GectorLogits> forward(GectorPreparedInput input) {
    calls++;
    return ScriptedBackend(fixtures.bundle.configuration, <List<String>>[
      proposals[_key(input)] ??
          List<String>.filled(input.firstSubwordIndices.length, r'$KEEP'),
    ]).forward(input);
  }

  @override
  Future<void> dispose() async {}
}

final class _DecoderTransport implements GectorTransport {
  _DecoderTransport(this.decoder);
  final GectorDecoder decoder;
  GectorDecodedText? lastResult;
  @override
  Future<GectorDecodedText> check(GectorCheckRequest request) async =>
      lastResult = await decoder.correct(
        request.text,
        personalWords: request.personalWords,
      );
  @override
  Future<void> dispose() async {}
}

void main() {
  late TestBundle fixtures;
  late GectorGermanGuards guards;
  setUpAll(() async => fixtures = await TestBundle.load());
  setUp(() {
    guards = GectorGermanGuards.fromJson(
      fixtures.bundle.guardsJson,
      configuration: fixtures.bundle.configuration,
      lexicon: GectorWordSetLexicon(const <String>[
        'Haus',
        'haus',
        'ist',
        'gut',
      ]),
    );
  });

  Future<String> deletion(
    List<String> words,
    int index, {
    bool isSourceStart = true,
    Set<String> personal = const <String>{},
  }) => guards.apply(
    words: words,
    index: index,
    label: r'$DELETE',
    replacement: '',
    personalWords: personal,
    isSourceStart: isSourceStart,
  );

  for (final (String, List<String>, int) example
      in <(String, List<String>, int)>[
        ('subject and object sie', ['Wenn', 'sie', 'sie', 'sehen'], 1),
        ('subject and object es', ['Weil', 'es', 'es', 'weiß'], 1),
        ('subject and dative ihr', ['Weil', 'ihr', 'ihr', 'helft'], 1),
        (
          'dative and possessive ihr',
          ['Wir', 'geben', 'ihr', 'ihr', 'Buch'],
          2,
        ),
        (
          'dative and adjective complement mir',
          ['Sie', 'zeigt', 'mir', 'mir', 'unbekannte', 'Orte'],
          2,
        ),
        (
          'dative and adjective complement dir',
          ['Sie', 'zeigt', 'dir', 'dir', 'unbekannte', 'Orte'],
          2,
        ),
        (
          'dative and adjective complement ihm',
          ['Sie', 'zeigt', 'ihm', 'ihm', 'unbekannte', 'Orte'],
          2,
        ),
        (
          'dative and adjective complement ihnen',
          ['Sie', 'zeigt', 'ihnen', 'ihnen', 'unbekannte', 'Orte'],
          2,
        ),
        (
          'dative and adjective complement uns',
          ['Sie', 'zeigt', 'uns', 'uns', 'unbekannte', 'Orte'],
          2,
        ),
        (
          'dative and adjective complement euch',
          ['Sie', 'zeigt', 'euch', 'euch', 'unbekannte', 'Orte'],
          2,
        ),
        (
          'object and reflexive mich',
          ['Er', 'lässt', 'mich', 'mich', 'selbst', 'sehen'],
          2,
        ),
        (
          'object and reflexive dich',
          ['Er', 'lässt', 'dich', 'dich', 'selbst', 'sehen'],
          2,
        ),
        (
          'objects of different verbs ihn',
          ['Sie', 'lässt', 'ihn', 'ihn', 'selbst', 'zeichnen'],
          2,
        ),
        ('subject and predicate ich', ['Dass', 'ich', 'ich', 'bleibe'], 1),
        ('subject and predicate du', ['Weil', 'du', 'du', 'bist'], 1),
        (
          'subject and predicate wir',
          ['Damit', 'wir', 'wir', 'selbst', 'bleiben'],
          1,
        ),
        (
          'demonstrative and article das',
          ['Ob', 'das', 'das', 'richtige', 'Buch', 'ist'],
          1,
        ),
        (
          'demonstrative and article die',
          ['Wenn', 'die', 'die', 'Tür', 'öffnen'],
          1,
        ),
        (
          'demonstrative and article der',
          ['Ob', 'der', 'der', 'Frau', 'hilft'],
          1,
        ),
        (
          'relative and duration article den',
          ['Der', 'Mann', ',', 'den', 'den', 'ganzen', 'Tag', 'alle', 'loben'],
          3,
        ),
        (
          'relative and prepositional article dem',
          [
            'Der',
            'Mann',
            ',',
            'dem',
            'dem',
            'Gerücht',
            'zufolge',
            'alle',
            'helfen',
          ],
          3,
        ),
      ]) {
    test('preserve both possible roles: ${example.$1}', () async {
      for (final int index in <int>[example.$3, example.$3 + 1]) {
        for (final bool sourceStart in <bool>[true, false]) {
          expect(
            await deletion(example.$2, index, isSourceStart: sourceStart),
            example.$2[index],
          );
        }
      }
    });
  }

  test(
    'missing role evidence abstains even for a likely article typo',
    () async {
      for (final List<String> words in <List<String>>[
        ['Mach', 'bitte', 'die', 'die', 'Tür', 'zu'],
        ['sie', 'sie'],
        ['SIE', 'SIE'],
        ['sich', 'sich'],
        ['er', 'er'],
      ]) {
        final index = words.length == 2 ? 0 : 2;
        expect(await deletion(words, index), words[index]);
        expect(await deletion(words, index + 1), words[index + 1]);
      }
    },
  );

  test(
    'triples retain every potentially distinct role including mixed case',
    () async {
      for (final List<String> words in <List<String>>[
        ['Weil', 'ihr', 'ihr', 'ihr', 'Buch', 'gebt'],
        ['Sie', 'sie', 'sie'],
        ['Ihr', 'ihr', 'ihr'],
        ['das', 'das', 'das'],
      ]) {
        final start = words.first == 'Weil' ? 1 : 0;
        for (var index = start; index < start + 3; index++) {
          for (final bool sourceStart in <bool>[true, false]) {
            expect(
              await deletion(words, index, isSourceStart: sourceStart),
              words[index],
            );
          }
        }
      }
    },
  );

  test(
    'the existing original-start case-differing pair exception is preserved',
    () async {
      for (final List<String> words in <List<String>>[
        ['Haus', 'haus'],
        ['Sie', 'sie'],
        ['Das', 'das'],
      ]) {
        for (var index = 0; index < 2; index++) {
          expect(await deletion(words, index), '');
          expect(
            await deletion(words, index, isSourceStart: false),
            words[index],
          );
          final later = <String>['vorher', ...words];
          expect(await deletion(later, index + 1), words[index]);
        }
      }
    },
  );

  test('ordinary duplicate removal and personal veto still work', () async {
    const words = <String>['Das', 'ist', 'ist', 'gut'];
    for (var index = 1; index <= 2; index++) {
      expect(await deletion(words, index), '');
      expect(await deletion(words, index, isSourceStart: false), '');
      expect(await deletion(words, index, personal: {'ist'}), 'ist');
    }
    expect(await deletion(['Das', 'ist', 'wirklich', 'gut'], 2), 'wirklich');
  });

  test(
    'observed first-sie deletion is rejected only by guarded decoding',
    () async {
      const text = 'Wenn sie sie sehen, winken sie.';
      GectorBackend backend() => _DeletionBackend(fixtures, {
        text: [1],
      });
      final guarded = GectorDecoder.guarded(
        configuration: fixtures.bundle.configuration,
        tokenizer: fixtures.bundle.tokenizer,
        backend: backend(),
        guards: guards,
      );
      final result = await guarded.correct(text);
      expect(result.complete, isTrue);
      expect(result.corrected, text);
      expect(result.edits, isEmpty);
      expect(result.passes, hasLength(1));

      final reference = GectorDecoder.reference(
        configuration: fixtures.bundle.configuration,
        tokenizer: fixtures.bundle.tokenizer,
        backend: backend(),
      );
      expect(
        (await reference.correct(text)).corrected,
        'Wenn sie sehen, winken sie.',
      );
    },
  );

  for (final List<int> deletions in <List<int>>[
    [1],
    [2],
    [1, 2],
  ]) {
    test(
      'reused proposals independently retain both pronouns: $deletions',
      () async {
        const sentence = 'Wenn sie sie sehen.';
        const text = '$sentence $sentence';
        final backend = _DeletionBackend(fixtures, {sentence: deletions});
        final result = await GectorDecoder.guarded(
          configuration: fixtures.bundle.configuration,
          tokenizer: fixtures.bundle.tokenizer,
          backend: backend,
          guards: guards,
          options: GectorDecodeOptions(
            segmentation: GectorSegmentationOptions(
              targetTokens: 6,
              inferenceReuse: GectorInferenceReuseOptions(),
            ),
          ),
        ).correct(text);
        expect(result.corrected, text);
        expect(result.edits, isEmpty);
        expect(result.complete, isTrue);
        expect(result.segmentCount, 2);
        expect(result.forwardCount, 1);
        expect(result.reusedPassCount, 1);
        expect(backend.calls, 1);
      },
    );
  }

  test(
    'provider keeps ambiguous pronouns while rebasing an ordinary deletion',
    () async {
      const sentence = 'Wenn sie sie sehen.';
      const text = '$sentence Das ist ist gut. $sentence';
      final backend = _DeletionBackend(fixtures, {
        sentence: [1, 2],
        'Das ist ist gut.': [1, 2],
      });
      final transport = _DecoderTransport(
        GectorDecoder.guarded(
          configuration: fixtures.bundle.configuration,
          tokenizer: fixtures.bundle.tokenizer,
          backend: backend,
          guards: guards,
          options: GectorDecodeOptions(
            segmentation: GectorSegmentationOptions(
              targetTokens: 6,
              inferenceReuse: GectorInferenceReuseOptions(),
            ),
          ),
        ),
      );
      final provider = GectorProofingProvider.withTransport(
        transport: transport,
        configuration: fixtures.bundle.configuration,
      );
      addTearDown(provider.dispose);
      final result = await provider.check(
        OfficeProofingRequest(
          documentId: 'duplicate-roles',
          blockId: 'paragraph',
          revision: 1,
          text: text,
          language: 'de-DE',
          startOffset: 37,
        ),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, hasLength(1));
      final finding = result.findings.single;
      expect(finding.originalText.trim(), 'ist');
      expect(
        text.substring(finding.start - 37, finding.end - 37),
        finding.originalText,
      );
      expect(
        text.replaceRange(
          finding.start - 37,
          finding.end - 37,
          finding.replacements.single,
        ),
        '$sentence Das ist gut. $sentence',
      );
      expect(transport.lastResult!.reusedPassCount, 1);
    },
  );
}
