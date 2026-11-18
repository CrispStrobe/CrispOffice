import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_linguistic_analysis.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

const _identity = SpacyBackendIdentity(
  librarySha256:
      'ea89842ebf22c08508aff1cfbf18d78a107118af320523009616ff62b6e42977',
);

final class _Transport implements SpacyTransport {
  final requests = <LinguisticAnalysisRequest>[];
  final replies = <Completer<LinguisticAnalysisResult>>[];
  final cancellations = <String>[];
  var disposals = 0;
  @override
  SpacyBackendIdentity get identity => _identity;
  @override
  Future<LinguisticAnalysisResult> analyze(LinguisticAnalysisRequest request) {
    requests.add(request);
    final reply = Completer<LinguisticAnalysisResult>();
    replies.add(reply);
    return reply.future;
  }

  @override
  void cancel(String key) => cancellations.add(key);
  @override
  Future<void> dispose() async => disposals++;
}

WordEditorController _controller(String text) {
  final controller = WordEditorController(
    document: WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: text)]),
          ],
        ),
      ],
    )..proofingLanguage = 'de-DE',
    config: const OfficeSurfaceConfig(autofocus: false),
  );
  addTearDown(controller.dispose);
  return controller;
}

LinguisticAnalysisResult _result(LinguisticAnalysisRequest request) =>
    LinguisticAnalysisResult.success(
      request: request,
      identity: _identity,
      tokens: request.text.isEmpty
          ? []
          : [
              LinguisticToken(
                index: 0,
                text: request.text,
                byteStart: 0,
                byteEnd: utf8.encode(request.text).length,
                scalarStart: 0,
                scalarEnd: request.text.runes.length,
                start: 0,
                end: request.text.length,
                lemma: 'Katze',
                tag: 'NN',
                pos: 'NOUN',
                morphology: 'Case=Nom|Number=Sing',
                dependency: 'ROOT',
                head: 0,
                sentenceStart: true,
                sentenceEnd: true,
              ),
            ],
    );

Future<void> _dialog(
  WidgetTester tester,
  WordEditorController controller,
  Future<SpacyTransport> Function() factory, {
  String configuration = 'test-install-v1',
}) => tester.pumpWidget(
  MaterialApp(
    home: StudioLinguisticAnalysisDialog(
      controller: controller,
      transportFactory: factory,
      configurationId: configuration,
    ),
  ),
);

Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.text('Analyze text'));
  await tester.pump();
}

void main() {
  test('snapshot and navigation add the nonzero origin once', () {
    final controller = _controller('😀 Katze Katze');
    controller.documentCaret
      ..selectionAnchor = 9
      ..logicalIndex = 14;
    final snapshot = StudioAnalysisSnapshot.capture(
      controller,
      generation: 2,
      configurationId: 'installed-v1',
    );
    expect(snapshot.request.text, 'Katze');
    expect(snapshot.request.startOffset, 9);
    expect(snapshot.request.revision, controller.contentRevision);
    expect(snapshot.request.generation, 2);
    expect(snapshot.request.configurationId, 'installed-v1');
    controller.documentCaret
      ..selectionAnchor = 0
      ..logicalIndex = 0;
    final before = controller.document.paragraphs.first.text;
    expect(
      snapshot.revealToken(
        controller,
        'installed-v1',
        _result(snapshot.request).tokens.single,
      ),
      isTrue,
    );
    expect(controller.documentCaret.selectionAnchor, 9);
    expect(controller.documentCaret.logicalIndex, 14);
    expect(controller.document.paragraphs.first.text, before);
    expect(controller.canUndo, isFalse);
  });

  test('body table paragraphs preserve their flattened source mapping', () {
    final controller = _controller('First');
    final paragraph = WmlParagraph(inlines: [WmlRun(text: 'Katze')]);
    controller.document.sections.first.blocks.add(
      WmlTable(
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(blocks: [paragraph]),
            ],
          ),
        ],
      ),
    );
    controller.relayout();
    controller.documentCaret
      ..paragraphIndex = 1
      ..selectionAnchorParagraph = 1;
    final snapshot = StudioAnalysisSnapshot.capture(
      controller,
      generation: 0,
      configurationId: 'v1',
    );
    expect(identical(snapshot.paragraph, paragraph), isTrue);
    expect(snapshot.paragraphIndex, 1);
    expect(
      snapshot.revealToken(
        controller,
        'v1',
        _result(snapshot.request).tokens.single,
      ),
      isTrue,
    );
    expect(controller.documentCaret.paragraphIndex, 1);
    expect(controller.documentCaret.logicalIndex, 5);
  });

  test('cross-paragraph and split-Unicode selections are refused exactly', () {
    final controller = _controller('😀 e\u0301 Katze');
    controller.document.sections.first.blocks.add(
      WmlParagraph(inlines: [WmlRun(text: 'Second')]),
    );
    controller.documentCaret
      ..selectionAnchorParagraph = 0
      ..paragraphIndex = 1
      ..logicalIndex = 2;
    expect(
      () => StudioAnalysisSnapshot.capture(
        controller,
        generation: 0,
        configurationId: 'v1',
      ),
      throwsFormatException,
    );
    controller.documentCaret
      ..paragraphIndex = 0
      ..selectionAnchor = 1
      ..logicalIndex = 2;
    expect(
      () => StudioAnalysisSnapshot.capture(
        controller,
        generation: 0,
        configurationId: 'v1',
      ),
      throwsFormatException,
    );
    controller.documentCaret
      ..selectionAnchor = 3
      ..logicalIndex = 4;
    expect(
      () => StudioAnalysisSnapshot.capture(
        controller,
        generation: 0,
        configurationId: 'v1',
      ),
      throwsFormatException,
    );
  });

  test('mixed-language text is refused but a German subrange is supported', () {
    final controller = _controller('');
    controller.document.paragraphs.first.inlines = [
      WmlRun(
        text: 'Katze',
        properties: WmlRunProps(proofingLanguage: 'de-DE'),
      ),
      WmlRun(
        text: ' cat',
        properties: WmlRunProps(proofingLanguage: 'en-US'),
      ),
    ];
    expect(
      () => StudioAnalysisSnapshot.capture(
        controller,
        generation: 0,
        configurationId: 'v1',
      ),
      throwsFormatException,
    );
    controller.documentCaret
      ..selectionAnchor = 0
      ..logicalIndex = 5;
    expect(
      StudioAnalysisSnapshot.capture(
        controller,
        generation: 0,
        configurationId: 'v1',
      ).request.locale,
      'de-DE',
    );
    controller.document.paragraphs.first.inlines = [
      WmlRun(
        text: 'Katze',
        properties: WmlRunProps(proofingLanguage: 'de-CH'),
      ),
    ];
    expect(
      () => StudioAnalysisSnapshot.capture(
        controller,
        generation: 0,
        configurationId: 'v1',
      ),
      throwsFormatException,
    );
  });

  test(
    'silent source replacement, language and configuration invalidate identity',
    () {
      final controller = _controller('Katze');
      final snapshot = StudioAnalysisSnapshot.capture(
        controller,
        generation: 0,
        configurationId: 'v1',
      );
      expect(snapshot.isCurrent(controller, 'v2'), isFalse);
      controller.document.proofingLanguage = 'de-CH';
      expect(snapshot.isCurrent(controller, 'v1'), isFalse);
      controller.document.proofingLanguage = 'de-DE';
      controller.document.paragraphs.first.inlines = [WmlRun(text: 'Katzen')];
      expect(snapshot.isCurrent(controller, 'v1'), isFalse);
      controller.document.paragraphs.first.inlines = [WmlRun(text: 'Katze')];
      controller.document.sections.first.blocks[0] = WmlParagraph(
        inlines: [WmlRun(text: 'Katze')],
      );
      expect(snapshot.isCurrent(controller, 'v1'), isFalse);
    },
  );

  test(
    'comment and header editing never use the body caret as a substitute',
    () {
      final controller = _controller('Katze');
      controller.document.comments.add(
        WmlComment(
          id: 1,
          paragraphs: [
            WmlParagraph(inlines: [WmlRun(text: 'Comment')]),
          ],
        ),
      );
      controller.beginCommentEdit(1);
      expect(
        () => StudioAnalysisSnapshot.capture(
          controller,
          generation: 0,
          configurationId: 'v1',
        ),
        throwsFormatException,
      );
      controller.endCommentEdit();
      controller.document.sections.first.header.add(
        WmlParagraph(inlines: [WmlRun(text: 'Header')]),
      );
      controller.relayout();
      controller.beginHeaderFooterEdit(0, footer: false);
      expect(
        () => StudioAnalysisSnapshot.capture(
          controller,
          generation: 0,
          configurationId: 'v1',
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets('manual start shows annotations and navigates without editing', (
    tester,
  ) async {
    final controller = _controller('😀 Katze Katze');
    controller.documentCaret
      ..selectionAnchor = 9
      ..logicalIndex = 14;
    final transport = _Transport();
    var opens = 0;
    await _dialog(tester, controller, () async {
      opens++;
      return transport;
    });
    expect(opens, 0);
    expect(transport.requests, isEmpty);
    await _start(tester);
    expect(opens, 1);
    expect(transport.requests.single.startOffset, 9);
    transport.replies.single.complete(_result(transport.requests.single));
    await tester.pump();
    expect(
      find.text('1 token · 1 sentence · de_core_news_sm 3.8.0'),
      findsOneWidget,
    );
    expect(find.textContaining('Lemma: Katze'), findsOneWidget);
    controller.documentCaret
      ..selectionAnchor = 0
      ..logicalIndex = 0;
    await tester.tap(find.byTooltip('Select token in document'));
    await tester.pump();
    expect(controller.documentCaret.selectionAnchor, 9);
    expect(controller.documentCaret.logicalIndex, 14);
    expect(controller.document.paragraphs.first.text, '😀 Katze Katze');
    expect(controller.canUndo, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(transport.disposals, 1);
  });

  testWidgets(
    'cancel completes the view and discards a late successful reply',
    (tester) async {
      final controller = _controller('Katze');
      final transport = _Transport();
      await _dialog(tester, controller, () async => transport);
      await _start(tester);
      await tester.tap(find.text('Cancel analysis'));
      await tester.pump();
      expect(find.text('Analysis cancelled.'), findsOneWidget);
      expect(transport.cancellations, [transport.requests.single.key]);
      expect(transport.disposals, 0);
      transport.replies.single.complete(_result(transport.requests.single));
      await tester.pump();
      expect(find.byTooltip('Select token in document'), findsNothing);
      expect(find.text('Analysis cancelled.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final change in ['text', 'locale', 'document']) {
    testWidgets('$change changes clear results and cancel pending requests', (
      tester,
    ) async {
      final controller = _controller('Katze');
      final transport = _Transport();
      await _dialog(tester, controller, () async => transport);
      await _start(tester);
      switch (change) {
        case 'text':
          controller.insertText('neu');
        case 'locale':
          controller.document.proofingLanguage = 'de-CH';
          controller.refresh();
        case 'document':
          controller.document = WmlDocument.empty()..proofingLanguage = 'de-DE';
          controller.refresh();
      }
      await tester.pump();
      expect(
        find.text(
          'The text or language changed. Analyze again to see current results.',
        ),
        findsOneWidget,
      );
      expect(transport.cancellations, [transport.requests.single.key]);
      transport.replies.single.complete(_result(transport.requests.single));
      await tester.pump();
      expect(find.byTooltip('Select token in document'), findsNothing);
      expect(transport.requests.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('configuration replacement disposes the old worker once', (
    tester,
  ) async {
    final controller = _controller('Katze');
    final transport = _Transport();
    Future<SpacyTransport> factory() async => transport;
    await _dialog(tester, controller, factory);
    await _start(tester);
    await _dialog(
      tester,
      controller,
      factory,
      configuration: 'test-install-v2',
    );
    await tester.pump();
    expect(transport.cancellations.length, 1);
    expect(transport.disposals, 1);
    transport.replies.single.complete(_result(transport.requests.single));
    await tester.pump();
    expect(find.byTooltip('Select token in document'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(transport.disposals, 1);
  });

  testWidgets(
    'closing while loading disposes a late worker and never analyzes',
    (tester) async {
      final controller = _controller('Katze');
      final transport = _Transport();
      final opening = Completer<SpacyTransport>();
      await _dialog(tester, controller, () => opening.future);
      await _start(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      opening.complete(transport);
      await tester.pump();
      expect(transport.requests, isEmpty);
      expect(transport.disposals, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel during loading permits a later explicit retry safely', (
    tester,
  ) async {
    final controller = _controller('Katze');
    final transport = _Transport();
    final opening = Completer<SpacyTransport>();
    await _dialog(tester, controller, () => opening.future);
    await _start(tester);
    await tester.tap(find.text('Cancel analysis'));
    await tester.pump();
    await _start(tester);
    opening.complete(transport);
    await tester.pump();
    expect(transport.requests.length, 1);
    transport.replies.single.complete(_result(transport.requests.single));
    await tester.pump();
    expect(find.byTooltip('Select token in document'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(transport.disposals, 1);
  });

  testWidgets('startup failures stay actionable and never show empty success', (
    tester,
  ) async {
    final controller = _controller('Katze');
    await _dialog(tester, controller, () async {
      throw const SpacyUnavailableException(
        'Install the optional local German analysis bundle.',
      );
    });
    await _start(tester);
    expect(
      find.text('Install the optional local German analysis bundle.'),
      findsOneWidget,
    );
    expect(find.text('The input is empty.'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'operational failure and mismatched snapshot cannot publish tokens',
    (tester) async {
      final controller = _controller('Katze');
      final transport = _Transport();
      await _dialog(tester, controller, () async => transport);
      await _start(tester);
      transport.replies[0].complete(
        LinguisticAnalysisResult.failure(
          request: transport.requests[0],
          status: LinguisticAnalysisStatus.timeout,
          message: 'Timed out.',
          identity: _identity,
        ),
      );
      await tester.pump();
      expect(
        find.text('Analysis took too long. Try a shorter passage.'),
        findsOneWidget,
      );
      await _start(tester);
      final requested = transport.requests[1];
      transport.replies[1].complete(
        _result(
          LinguisticAnalysisRequest(
            text: requested.text,
            documentId: requested.documentId,
            blockId: requested.blockId,
            revision: requested.revision,
            generation: requested.generation + 1,
            configurationId: requested.configurationId,
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Select token in document'), findsNothing);
      expect(
        find.text(
          'Analysis could not finish. Check the local installation and try again.',
        ),
        findsOneWidget,
      );
      expect(transport.disposals, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('unsupported locale is rejected before loading the worker', (
    tester,
  ) async {
    final controller = _controller('cat')..document.proofingLanguage = 'en-US';
    var opened = false;
    await _dialog(tester, controller, () async {
      opened = true;
      return _Transport();
    });
    await _start(tester);
    expect(opened, isFalse);
    expect(
      find.text(
        'This analysis supports German (Germany). Choose text marked de-DE.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'editing after success removes all token navigation immediately',
    (tester) async {
      final controller = _controller('Katze');
      final transport = _Transport();
      await _dialog(tester, controller, () async => transport);
      await _start(tester);
      transport.replies.single.complete(_result(transport.requests.single));
      await tester.pump();
      expect(find.byTooltip('Select token in document'), findsOneWidget);
      controller.insertText('neu');
      await tester.pump();
      expect(find.byTooltip('Select token in document'), findsNothing);
      expect(
        find.text(
          'The text or language changed. Analyze again to see current results.',
        ),
        findsOneWidget,
      );
      expect(transport.requests.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'closing an active request disposes once and absorbs late failure',
    (tester) async {
      final controller = _controller('Katze');
      final transport = _Transport();
      await _dialog(tester, controller, () async => transport);
      await _start(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(transport.cancellations, [transport.requests.single.key]);
      expect(transport.disposals, 1);
      transport.replies.single.completeError(StateError('late worker failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(transport.disposals, 1);
    },
  );
  testWidgets('cancelled startup failure allows one fresh explicit retry', (
    tester,
  ) async {
    final controller = _controller('Katze');
    final first = Completer<SpacyTransport>();
    final transport = _Transport();
    var opens = 0;
    await _dialog(tester, controller, () {
      opens++;
      return opens == 1 ? first.future : Future.value(transport);
    });
    await _start(tester);
    await tester.tap(find.text('Cancel analysis'));
    await tester.pump();
    first.completeError(const SpacyUnavailableException('Startup failed.'));
    await tester.pump();
    expect(find.text('Analysis cancelled.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _start(tester);
    expect(opens, 2);
    expect(transport.requests.length, 1);
    transport.replies.single.complete(_result(transport.requests.single));
    await tester.pump();
    expect(find.byTooltip('Select token in document'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'unavailable worker is replaced only on the next explicit action',
    (tester) async {
      final controller = _controller('Katze');
      final first = _Transport();
      final next = _Transport();
      var opens = 0;
      await _dialog(
        tester,
        controller,
        () async => ++opens == 1 ? first : next,
      );
      await _start(tester);
      first.replies.single.complete(
        LinguisticAnalysisResult.failure(
          request: first.requests.single,
          status: LinguisticAnalysisStatus.unavailable,
          message: 'The worker exited.',
        ),
      );
      await tester.pump();
      expect(first.disposals, 1);
      expect(opens, 1);
      await _start(tester);
      expect(opens, 2);
      expect(next.requests.length, 1);
      next.replies.single.complete(_result(next.requests.single));
      await tester.pump();
      expect(find.byTooltip('Select token in document'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(first.disposals, 1);
      expect(next.disposals, 1);
    },
  );
  test('frame and generated TOC paragraphs cannot masquerade as body text', () {
    final controller = _controller('Katze');
    final body = controller.document.paragraphs.first;
    final snapshot = StudioAnalysisSnapshot.capture(
      controller,
      generation: 0,
      configurationId: 'v1',
    );
    controller.document.sections.first.blocks
      ..clear()
      ..addAll([
        WmlFrame(blocks: [body]),
        WmlToc(title: 'Inhalt'),
      ]);
    expect(controller.selectedFrame, isNull);
    expect(snapshot.isCurrent(controller, 'v1'), isFalse);
    for (
      var index = 0;
      index < controller.document.paragraphs.length;
      index++
    ) {
      controller.documentCaret
        ..paragraphIndex = index
        ..selectionAnchorParagraph = index
        ..selectionAnchor = 0
        ..logicalIndex = 0;
      expect(
        () => StudioAnalysisSnapshot.capture(
          controller,
          generation: 0,
          configurationId: 'v1',
        ),
        throwsFormatException,
      );
    }
  });
}
