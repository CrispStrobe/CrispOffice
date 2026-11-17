import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_aot/quds_proofing_aot.dart';
import 'package:test/test.dart';

import 'grammar_support.dart';

OfficeProofingRequest request(
  String text, {
  String language = 'de-DE',
  int startOffset = 0,
  Set<String> ignoredRuleIds = const <String>{},
}) => OfficeProofingRequest(
  documentId: 'document',
  blockId: 'paragraph',
  revision: 9,
  text: text,
  language: language,
  startOffset: startOffset,
  ignoredRuleIds: ignoredRuleIds,
);

GrammarAnalyzer analyzerFor(List<List<GrammarWord>> clauses) => GrammarAnalyzer(
  analyzeText: (text) async => grammarAnalysis(text, clauses),
);

void main() {
  test(
    'source-bound finding adds UTF-16 segment origin exactly once',
    () async {
      const text = '😊 Ich geht.';
      final analyzer = analyzerFor(<List<GrammarWord>>[
        <GrammarWord>[const GrammarWord('😊', '😊', '')],
        <GrammarWord>[ich, geht, punkt],
      ]);
      final provider = AotProofingProvider(analyzer: analyzer);
      final input = request(text, startOffset: 100);
      final report = await OfficeProofingService(
        providers: <OfficeProofingProvider>[provider],
      ).check(input);
      expect(report.complete, isTrue);
      expect(identical(report.results.single.request, input), isTrue);
      expect(report.findings.single.originalText, 'geht');
      expect(report.findings.single.start, 107);
      expect(report.findings.single.end, 111);
      expect(report.findings.single.replacements, <String>['gehe']);
      await provider.dispose();
      expect(analyzer.disposed, isTrue);
    },
  );

  test(
    'de-DE aliases work and other locales do not contact the analyzer',
    () async {
      final analyzer = analyzerFor(<List<GrammarWord>>[
        <GrammarWord>[ich, geht, punkt],
      ]);
      final provider = AotProofingProvider(analyzer: analyzer);
      expect(provider.supportsLanguage('de_DE'), isTrue);
      expect(provider.supportsLanguage('de'), isTrue);
      for (final language in <String>[
        'de-AT',
        'de-CH',
        'en-US',
        'ru-RU',
        'de-1901',
      ]) {
        final result = await provider.check(
          request('Ich geht.', language: language),
        );
        expect(result.status, OfficeProofingStatus.unsupported);
        expect(result.findings, isEmpty);
      }
      expect(analyzer.analyzeCalls, 0);
    },
  );

  test('rule ignores avoid correction and morphology requests', () async {
    final analyzer = analyzerFor(<List<GrammarWord>>[
      <GrammarWord>[ich, geht, punkt],
    ]);
    final provider = AotProofingProvider(analyzer: analyzer);
    final result = await provider.check(
      request(
        'Ich geht.',
        ignoredRuleIds: <String>{AotGermanGrammar.subjectVerbRule},
      ),
    );
    expect(result.status, OfficeProofingStatus.success);
    expect(result.findings, isEmpty);
    expect(analyzer.morphologyCalls, isEmpty);
  });

  test(
    'protected code and personal words suppress whole candidate context',
    () async {
      const text = '`mit den Hund` mit den Hund';
      final analyzer = analyzerFor(<List<GrammarWord>>[
        <GrammarWord>[
          const GrammarWord('`', '`', ''),
          mit,
          den,
          hund,
          const GrammarWord('`', '`', ''),
          mit,
          den,
          hund,
        ],
      ]);
      final provider = AotProofingProvider(analyzer: analyzer);
      final result = await provider.check(request(text));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings.single.start, 18);
      expect(result.findings.single.replacements, <String>['dem']);
      provider.vocabulary.addWord('Hund');
      final personal = await provider.check(request(text));
      expect(personal.findings, isEmpty);
      expect(provider.configurationRevision, provider.vocabulary.revision);
    },
  );

  test('morphology lookups are cached once per check', () async {
    final analyzer = analyzerFor(<List<GrammarWord>>[
      <GrammarWord>[mit, den, hund, punkt],
      <GrammarWord>[mit, den, hund, punkt],
    ]);
    final provider = AotProofingProvider(analyzer: analyzer);
    final result = await provider.check(request('mit den Hund. mit den Hund.'));
    expect(result.findings, hasLength(2));
    expect(analyzer.morphologyCalls, <String>['den', 'Hund']);
  });

  test(
    'request and lookup limits report failed without partial findings',
    () async {
      final analyzer = analyzerFor(<List<GrammarWord>>[
        <GrammarWord>[ich, geht, punkt],
      ]);
      final provider = AotProofingProvider(
        analyzer: analyzer,
        maximumMorphologyLookups: 1,
      );
      final result = await provider.check(request('Ich geht.'));
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.findings, isEmpty);
      expect(analyzer.morphologyCalls, <String>['Ich']);
      final short = AotProofingProvider(
        analyzer: analyzer,
        maximumTextCodeUnits: 2,
      );
      expect(
        (await short.check(request('Ich geht.'))).status,
        OfficeProofingStatus.failed,
      );
      expect(analyzer.analyzeCalls, 1);
    },
  );

  test('result limit does not silently truncate coverage', () async {
    final analyzer = analyzerFor(<List<GrammarWord>>[
      <GrammarWord>[mit, den, hund, punkt],
      <GrammarWord>[mit, den, hund, punkt],
    ]);
    final result = await AotProofingProvider(
      analyzer: analyzer,
      maximumFindings: 1,
    ).check(request('mit den Hund. mit den Hund.'));
    expect(result.status, OfficeProofingStatus.failed);
    expect(result.findings, isEmpty);
  });

  test('in-flight vocabulary changes invalidate the whole result', () async {
    final pending = Completer<AotAnalysis>();
    final analyzer = GrammarAnalyzer(analyzeText: (_) => pending.future);
    final vocabulary = OfficeProofingVocabulary();
    final provider = AotProofingProvider(
      analyzer: analyzer,
      vocabulary: vocabulary,
    );
    final checked = provider.check(request('Ich geht.'));
    vocabulary.addWord('geht');
    pending.complete(
      grammarAnalysis('Ich geht.', <List<GrammarWord>>[
        <GrammarWord>[ich, geht, punkt],
      ]),
    );
    final result = await checked;
    expect(result.status, OfficeProofingStatus.failed);
    expect(result.findings, isEmpty);
    expect(analyzer.morphologyCalls, isEmpty);
  });

  for (final code in AotErrorCode.values) {
    test('operational ${code.name} never becomes a clean success', () async {
      final analyzer = GrammarAnalyzer(
        analyzeText: (_) async => throw AotException(code, 'test failure'),
      );
      final result = await AotProofingProvider(
        analyzer: analyzer,
      ).check(request('Ich geht.'));
      expect(result.status, isNot(OfficeProofingStatus.success));
      expect(result.findings, isEmpty);
      if (code == AotErrorCode.unavailable || code == AotErrorCode.disposed) {
        expect(result.status, OfficeProofingStatus.unavailable);
      }
    });
  }

  test(
    'empty or unmapped nonempty analysis reports incomplete coverage',
    () async {
      for (final analysis in <AotAnalysis>[
        AotAnalysis(
          text: 'Ich geht.',
          language: AotLanguage.german,
          sentences: <AotSentence>[],
        ),
        grammarAnalysis('Ich geht.', <List<GrammarWord>>[
          <GrammarWord>[
            const GrammarWord('Du', 'SIE', 'PRO sin,2,nom,per,;'),
            geht,
            punkt,
          ],
        ]),
        grammarAnalysis('Ich geht.', <List<GrammarWord>>[
          <GrammarWord>[ich, geht],
        ]),
      ]) {
        final analyzer = GrammarAnalyzer(analyzeText: (_) async => analysis);
        final result = await AotProofingProvider(
          analyzer: analyzer,
        ).check(request('Ich geht.'));
        expect(result.status, OfficeProofingStatus.failed);
        expect(result.findings, isEmpty);
      }
    },
  );

  test('wrong source and grapheme-interior tokens are rejected', () async {
    final stale = GrammarAnalyzer(
      analyzeText: (_) async =>
          grammarAnalysis('Ich gehe.', <List<GrammarWord>>[
            <GrammarWord>[
              ich,
              const GrammarWord('gehe', 'GEHEN', 'VER sin,1,prae,;'),
              punkt,
            ],
          ]),
    );
    expect(
      (await AotProofingProvider(
        analyzer: stale,
      ).check(request('Ich geht.'))).status,
      OfficeProofingStatus.failed,
    );
    final split = GrammarAnalyzer(
      analyzeText: (text) async => grammarAnalysis(text, <List<GrammarWord>>[
        <GrammarWord>[
          const GrammarWord('a', 'A', 'SUB sin,neu,nom,;'),
          const GrammarWord('\u0308', '\u0308', ''),
        ],
      ]),
    );
    expect(
      (await AotProofingProvider(
        analyzer: split,
      ).check(request('a\u0308'))).status,
      OfficeProofingStatus.failed,
    );
  });

  test(
    'missing lexical variants do not fabricate successful empty grammar',
    () async {
      final analysis = AotAnalysis.fromJson(<Object?>[
        <Object?>[
          <String, Object?>{
            'words': <Object?>[
              <String, Object?>{
                'str': 'Hund',
                'homonyms': <String>['HUND'],
              },
            ],
            'variants': <Object?>[],
          },
        ],
      ], text: 'Hund');
      final analyzer = GrammarAnalyzer(analyzeText: (_) async => analysis);
      final result = await AotProofingProvider(
        analyzer: analyzer,
      ).check(request('Hund'));
      expect(result.status, OfficeProofingStatus.failed);
    },
  );

  test('shared analyzer is not disposed by the grammar service', () async {
    final analyzer = analyzerFor(<List<GrammarWord>>[
      <GrammarWord>[ich, geht, punkt],
    ]);
    final provider = AotProofingProvider(
      analyzer: analyzer,
      ownsAnalyzer: false,
    );
    await provider.dispose();
    expect(analyzer.disposed, isFalse);
    expect(
      (await provider.check(request('Ich geht.'))).status,
      OfficeProofingStatus.unavailable,
    );
    expect(analyzer.analyzeCalls, 0);
  });

  test('deadline cancels later lookups and disposes owned analyzer', () {
    fakeAsync((clock) {
      final pending = Completer<AotAnalysis>();
      final analyzer = GrammarAnalyzer(analyzeText: (_) => pending.future);
      final provider = AotProofingProvider(
        analyzer: analyzer,
        timeout: const Duration(seconds: 1),
      );
      OfficeProofingResult? result;
      unawaited(
        provider.check(request('Ich geht.')).then((value) => result = value),
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 2));
      clock.flushMicrotasks();
      expect(result?.status, OfficeProofingStatus.failed);
      expect(analyzer.disposed, isTrue);
      pending.complete(
        grammarAnalysis('Ich geht.', <List<GrammarWord>>[
          <GrammarWord>[ich, geht, punkt],
        ]),
      );
      clock.flushMicrotasks();
      expect(analyzer.morphologyCalls, isEmpty);
    });
  });

  test('blank input succeeds without opening a connection', () async {
    final analyzer = analyzerFor(<List<GrammarWord>>[]);
    final result = await AotProofingProvider(
      analyzer: analyzer,
    ).check(request(' \n\t'));
    expect(result.status, OfficeProofingStatus.success);
    expect(result.findings, isEmpty);
    expect(analyzer.analyzeCalls, 0);
  });
}
