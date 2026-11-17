import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_aot.dart';
import 'package:quds_proofing_aot/quds_proofing_aot.dart';

final class _Analyzer implements AotAnalyzer {
  final syntaxRequests = <({String text, AotLanguage language})>[];
  final morphRequests =
      <({String word, AotLanguage language, bool paradigms})>[];
  Completer<AotAnalysis>? gate;
  Object? failure;
  int disposals = 0;

  @override
  Future<AotAnalysis> analyze(
    String text, {
    AotLanguage language = AotLanguage.german,
  }) async {
    syntaxRequests.add((text: text, language: language));
    if (failure case final Object error) throw error;
    if (gate != null) return gate!.future;
    return text == 'Schläft er?'
        ? _analysis()
        : AotAnalysis(text: text, language: language, sentences: const []);
  }

  @override
  Future<AotMorphology> morphology(
    String word, {
    AotLanguage language = AotLanguage.german,
    bool withParadigms = false,
  }) async {
    morphRequests.add((
      word: word,
      language: language,
      paradigms: withParadigms,
    ));
    return AotMorphology(
      word: word,
      language: language,
      readings: [
        AotMorphReading(
          found: true,
          lemma: 'SCHLAFEN',
          grammar: AotGrammar.parse('VER sg,3,präs'),
          commonGrammems: const [],
          paradigm: [
            AotParadigmPart(
              grammar: AotGrammar.parse('VER präs'),
              groups: [
                AotParadigmGroup(
                  features: const ['sg'],
                  forms: [
                    AotParadigmForm(text: 'schlafe', features: const ['1']),
                    AotParadigmForm(text: 'schläfst', features: const ['2']),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> dispose() async => disposals++;
}

AotAnalysis _analysis() => AotAnalysis.fromJson([
  [
    {
      'words': [
        {
          'str': 'Schläft',
          'homonyms': ['SCHLAFEN'],
        },
        {
          'str': 'er',
          'homonyms': ['ER'],
        },
        {
          'str': '?',
          'homonyms': ['?'],
        },
      ],
      'variants': [
        {
          'units': [
            {'homNo': 0, 'grm': 'VER sg,3,präs'},
            {'homNo': 0, 'grm': 'PRO sg,3,nom,mas'},
            {'homNo': 0, 'grm': 'PUN'},
          ],
          'groups': [
            {
              'start': 1,
              'last': 0,
              'isGroup': false,
              'isSubj': true,
              'descr': 'subject relation',
            },
          ],
        },
      ],
    },
  ],
], text: 'Schläft er?');

Future<void> _open(
  WidgetTester tester,
  WordEditorController controller,
  AotAnalyzer Function() factory,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => StudioAotAnalysisDialog(
                controller: controller,
                createAnalyzer: factory,
              ),
            ),
            child: const Text('Open AOT'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open AOT'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('captures body in document order without changing selection', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: 'Er schläft.')]),
            WmlFrame(
              blocks: [
                WmlParagraph(inlines: [WmlRun(text: 'Noch ein Satz.')]),
              ],
            ),
          ],
        ),
      ],
    );
    final controller = WordEditorController(document: document);
    addTearDown(controller.dispose);
    final source = StudioAotTextSnapshot.capture(controller);
    expect(source.text, 'Er schläft.\nNoch ein Satz.');
    expect(source.scope, 'Document body text');
    expect(source.isCurrent(controller), isTrue);
    expect(controller.caret.isCollapsed, isTrue);
  });

  test(
    'captures a reversed selection with Unicode and paragraph boundaries',
    () {
      final controller = WordEditorController(
        document: WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlParagraph(inlines: [WmlRun(text: '🙂 Der Hund')]),
                WmlParagraph(inlines: [WmlRun(text: 'schläft hier.')]),
              ],
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      controller.caret
        ..selectionAnchorParagraph = 1
        ..selectionAnchor = 7
        ..paragraphIndex = 0
        ..logicalIndex = 3;
      final source = StudioAotTextSnapshot.capture(controller);
      expect(source.text, 'Der Hund\nschläft');
      expect(source.scope, 'Selected body text');
      expect(controller.caret.selectionAnchorParagraph, 1);
      expect(controller.caret.logicalIndex, 3);
    },
  );

  test('rejects oversized input and permits a bounded selection', () {
    final controller = WordEditorController(
      document: WmlDocument.empty(text: 'a' * 32769),
    );
    addTearDown(controller.dispose);
    expect(() => StudioAotTextSnapshot.capture(controller), throwsStateError);
    controller.caret
      ..selectionAnchor = 0
      ..logicalIndex = 12;
    expect(StudioAotTextSnapshot.capture(controller).text, 'a' * 12);
  });

  test('document replacement makes a captured snapshot stale', () {
    final controller = WordEditorController(
      document: WmlDocument.empty(text: 'Alt.'),
    );
    addTearDown(controller.dispose);
    final source = StudioAotTextSnapshot.capture(controller);
    controller.document = WmlDocument.empty(text: 'Neu.');
    expect(source.isCurrent(controller), isFalse);
  });

  test('rejects a selection that splits a Unicode surrogate pair', () {
    final controller = WordEditorController(
      document: WmlDocument.empty(text: '🙂 Hund'),
    );
    addTearDown(controller.dispose);
    controller.caret
      ..selectionAnchor = 1
      ..logicalIndex = 4;
    expect(() => StudioAotTextSnapshot.capture(controller), throwsStateError);
  });

  testWidgets(
    'analysis is explicit and renders lemmas, grammar and directed relations',
    (tester) async {
      final controller = WordEditorController(
        document: WmlDocument.empty(text: 'Schläft er?'),
      );
      final analyzer = _Analyzer();
      var clients = 0;
      await _open(tester, controller, () {
        clients++;
        return analyzer;
      });
      expect(clients, 0);
      expect(analyzer.syntaxRequests, isEmpty);
      expect(find.textContaining('de-AT and de-CH'), findsOneWidget);
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      expect(analyzer.syntaxRequests.single.text, 'Schläft er?');
      expect(analyzer.syntaxRequests.single.language, AotLanguage.german);
      expect(find.text('SCHLAFEN'), findsOneWidget);
      expect(find.text('VER sg,3,präs'), findsOneWidget);
      expect(find.text('er → Schläft'), findsOneWidget);
      expect(analyzer.disposals, 1);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      controller.dispose();
    },
  );

  testWidgets(
    'token morphology requests paradigms only after explicit lookup',
    (tester) async {
      final controller = WordEditorController(
        document: WmlDocument.empty(text: 'Schläft er?'),
      );
      final analyzers = <_Analyzer>[];
      await _open(tester, controller, () {
        final analyzer = _Analyzer();
        analyzers.add(analyzer);
        return analyzer;
      });
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Schläft'));
      await tester.pumpAndSettle();
      expect(analyzers, hasLength(1));
      final lookup = find.text('Look up morphology and forms');
      await tester.ensureVisible(lookup);
      await tester.pumpAndSettle();
      await tester.tap(lookup);
      await tester.pumpAndSettle();
      expect(analyzers, hasLength(2));
      expect(analyzers.last.morphRequests.single, (
        word: 'Schläft',
        language: AotLanguage.german,
        paradigms: true,
      ));
      final dictionary = find.textContaining('Dictionary reading');
      await tester.ensureVisible(dictionary);
      await tester.pumpAndSettle();
      await tester.tap(dictionary);
      await tester.pumpAndSettle();
      expect(find.text('schlafe'), findsOneWidget);
      expect(find.text('schläfst'), findsOneWidget);
      expect(analyzers.last.disposals, 1);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      controller.dispose();
    },
  );

  testWidgets('cancel disposes the request and ignores a late result', (
    tester,
  ) async {
    final controller = WordEditorController(
      document: WmlDocument.empty(text: 'Schläft er?'),
    );
    final analyzer = _Analyzer()..gate = Completer<AotAnalysis>();
    await _open(tester, controller, () => analyzer);
    await tester.tap(find.text('Analyze'));
    await tester.pump();
    await tester.tap(find.text('Cancel analysis'));
    await tester.pump();
    expect(analyzer.disposals, 1);
    analyzer.gate!.complete(_analysis());
    await tester.pumpAndSettle();
    expect(find.text('SCHLAFEN'), findsNothing);
    expect(analyzer.disposals, 1);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    controller.dispose();
  });

  testWidgets(
    'closing cancels in-flight analysis without publishing afterward',
    (tester) async {
      final controller = WordEditorController(
        document: WmlDocument.empty(text: 'Schläft er?'),
      );
      final analyzer = _Analyzer()..gate = Completer<AotAnalysis>();
      await _open(tester, controller, () => analyzer);
      await tester.tap(find.text('Analyze'));
      await tester.pump();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(analyzer.disposals, 1);
      analyzer.gate!.complete(_analysis());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );

  testWidgets(
    'a document edit cancels analysis and requires a fresh snapshot',
    (tester) async {
      final controller = WordEditorController(
        document: WmlDocument.empty(text: 'Schläft er?'),
      );
      final first = _Analyzer()..gate = Completer<AotAnalysis>();
      final second = _Analyzer();
      var created = 0;
      await _open(tester, controller, () => created++ == 0 ? first : second);
      await tester.tap(find.text('Analyze'));
      await tester.pump();
      controller.document = WmlDocument.empty(text: 'Neuer Text.');
      controller.refresh();
      await tester.pump();
      expect(find.byKey(const ValueKey('aot-stale')), findsOneWidget);
      expect(first.disposals, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Analyze'))
            .onPressed,
        isNull,
      );
      first.gate!.complete(_analysis());
      await tester.pumpAndSettle();
      expect(find.text('SCHLAFEN'), findsNothing);
      await tester.tap(find.text('Reload text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      expect(second.syntaxRequests.single.text, 'Neuer Text.');
      expect(
        find.textContaining('AOT returned no syntactic analysis'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      controller.dispose();
    },
  );

  testWidgets(
    'operational failure is visible and never reported as clean analysis',
    (tester) async {
      final controller = WordEditorController(
        document: WmlDocument.empty(text: 'Schläft er?'),
      );
      final analyzer = _Analyzer()
        ..failure = const AotException(
          AotErrorCode.unavailable,
          'Local AOT daemon is unavailable.',
        );
      await _open(tester, controller, () => analyzer);
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Local AOT daemon is unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('0 sentences'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(analyzer.disposals, 1);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      controller.dispose();
    },
  );

  testWidgets(
    'oversized source disables analysis before constructing a client',
    (tester) async {
      final controller = WordEditorController(
        document: WmlDocument.empty(text: 'a' * 32769),
      );
      var clients = 0;
      await _open(tester, controller, () {
        clients++;
        return _Analyzer();
      });
      expect(find.textContaining('exceeds the analysis limit'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Analyze'))
            .onPressed,
        isNull,
      );
      expect(clients, 0);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      controller.dispose();
    },
  );
}
