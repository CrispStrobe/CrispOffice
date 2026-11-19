import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';

import 'support/studio_test_settings.dart';

class _DraftProvider extends OfficeProofingProvider {
  _DraftProvider({
    this.gates = const {},
    this.status = OfficeProofingStatus.success,
    this.message,
    this.providerId = 'draft-test',
  });

  final Map<String, Completer<void>> gates;
  final OfficeProofingStatus status;
  final String? message;
  final String providerId;
  final requests = <OfficeProofingRequest>[];
  int activeDrafts = 0;
  int maximumActiveDrafts = 0;

  @override
  String get id => providerId;

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    final draft = request.text.startsWith('Draft');
    if (draft) {
      activeDrafts++;
      if (activeDrafts > maximumActiveDrafts) {
        maximumActiveDrafts = activeDrafts;
      }
    }
    try {
      await gates[request.text]?.future;
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: status,
        message: message,
        findings: status != OfficeProofingStatus.success
            ? const []
            : [
                for (final entry in const [
                  ('Commet', 'Comment', OfficeProofingCategory.spelling),
                  ('are is', 'is', OfficeProofingCategory.grammar),
                  ('very very', 'very', OfficeProofingCategory.style),
                ])
                  for (final match in RegExp(entry.$1).allMatches(request.text))
                    OfficeProofingFinding.forRequest(
                      request,
                      providerId: id,
                      ruleId: 'draft.${entry.$3.name}',
                      start: match.start,
                      end: match.end,
                      message: 'Use ${entry.$2}.',
                      category: entry.$3,
                      replacements: [entry.$2],
                    ),
              ],
      );
    } finally {
      if (draft) activeDrafts--;
    }
  }

  void release() {
    for (final gate in gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}

WmlDocument _document() {
  final document = WmlDocument.empty(text: 'Body unchanged.')
    ..proofingLanguage = 'en-US';
  document.comments.addAll([
    WmlComment(id: 1, text: 'Root one.', author: 'Alice', initials: 'AL'),
    WmlComment(id: 2, text: 'Root two.', author: 'Bob', initials: 'BO'),
  ]);
  WordComment.applyRange(document.paragraphs.single, 0, 4, 1);
  WordComment.applyRange(document.paragraphs.single, 5, 14, 2);
  return document;
}

Finder _field([int id = 1]) =>
    find.byKey(ValueKey<String>('studio-comment-reply-$id'));
Finder _suggestion([int id = 1]) =>
    find.byKey(ValueKey<String>('studio-comment-draft-replace-$id-0'));
Finder _status([int id = 1]) =>
    find.byKey(ValueKey<String>('studio-comment-draft-status-$id'));

TextEditingController _text(WidgetTester tester, [int id = 1]) =>
    tester.widget<TextField>(_field(id)).controller!;

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<WordEditorController> _studio(
  WidgetTester tester,
  _DraftProvider provider, {
  bool enabled = true,
  GlobalKey? captureKey,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    captureKey == null
        ? const QudsOfficeStudioApp()
        : RepaintBoundary(key: captureKey, child: const QudsOfficeStudioApp()),
  );
  await _pump(tester);
  await configureStudioForTest(tester, showComments: true);
  await _pump(tester);
  final controller = tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller;
  controller.proofing.enabled = false;
  controller.proofing.configure(OfficeProofingService(providers: [provider]));
  controller.document = _document();
  controller.refresh();
  controller.selectComment(1);
  controller.proofing.enabled = enabled;
  await _pump(tester);
  return controller;
}

Future<void> _enter(WidgetTester tester, String text, [int id = 1]) async {
  await tester.ensureVisible(_field(id));
  await tester.enterText(_field(id), text);
  await _pump(tester);
}

Future<void> _finishCheck(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 401));
  for (var index = 0; index < 10; index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _close(WidgetTester tester, _DraftProvider provider) async {
  provider.release();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  expect(tester.takeException(), isNull);
}

List<TextSpan> _spans(WidgetTester tester) {
  final root = _text(tester).buildTextSpan(
    context: tester.element(_field()),
    style: const TextStyle(),
    withComposing: true,
  );
  return root.children?.whereType<TextSpan>().toList() ?? [root];
}

void main() {
  testWidgets('draft checks after the pause and corrects without posting', (
    tester,
  ) async {
    final provider = _DraftProvider();
    final controller = await _studio(tester, provider);
    final revision = controller.contentRevision;
    final dirty = controller.isDirty;
    await _enter(tester, 'Draft Commet stays here.');
    await tester.pump(const Duration(milliseconds: 399));
    expect(provider.requests.where((r) => r.text.startsWith('Draft')), isEmpty);
    expect(find.text('Waiting for a pause…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2));
    await _pump(tester);
    expect(_suggestion(), findsOneWidget);
    final marked = _spans(tester).singleWhere((span) => span.text == 'Commet');
    expect(marked.style!.decoration, TextDecoration.underline);
    expect(marked.style!.decorationStyle, TextDecorationStyle.wavy);
    expect(marked.style!.decorationColor, const Color(0xFFC62828));
    await tester.ensureVisible(_suggestion());
    await tester.tap(_suggestion());
    await _pump(tester);
    expect(_text(tester).text, 'Draft Comment stays here.');
    expect(_text(tester).selection.extentOffset, 13);
    expect(tester.widget<TextField>(_field()).focusNode!.hasFocus, isTrue);
    expect(_suggestion(), findsNothing);
    expect(controller.contentRevision, revision);
    expect(controller.isDirty, dirty);
    expect(controller.canUndo, isFalse);
    expect(controller.document.comments, hasLength(2));
    await _finishCheck(tester);
    expect(find.text('No issues found in this reply.'), findsOneWidget);
    await _close(tester, provider);
  });

  testWidgets(
    'grammar and style marks stay distinct and suggestions navigate',
    (tester) async {
      final provider = _DraftProvider();
      await _studio(tester, provider);
      await _enter(tester, 'Draft are is very very useful.');
      await _finishCheck(tester);
      final spans = _spans(tester);
      expect(
        spans.singleWhere((s) => s.text == 'are is').style!.decorationColor,
        const Color(0xFF1565C0),
      );
      expect(
        spans.singleWhere((s) => s.text == 'very very').style!.decorationColor,
        const Color(0xFFAD6800),
      );
      expect(find.text('Use is.'), findsOneWidget);
      final next = find.byKey(const Key('studio-comment-draft-next-1'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await _pump(tester);
      expect(find.text('Use very.'), findsOneWidget);
      await tester.tap(_suggestion());
      await _pump(tester);
      expect(_text(tester).text, 'Draft are is very useful.');
      await _close(tester, provider);
    },
  );

  testWidgets(
    'typing invalidates underlines and captured correction handlers',
    (tester) async {
      final provider = _DraftProvider();
      await _studio(tester, provider);
      await _enter(tester, 'Draft Commet old.');
      await _finishCheck(tester);
      final stale = tester.widget<ActionChip>(_suggestion()).onPressed!;
      await _enter(tester, 'Draft newer text.');
      stale();
      await _pump(tester);
      expect(_text(tester).text, 'Draft newer text.');
      expect(_suggestion(), findsNothing);
      expect(_spans(tester).any((s) => s.style?.decoration != null), isFalse);
      await _close(tester, provider);
    },
  );

  testWidgets('slow requests coalesce and never publish obsolete draft text', (
    tester,
  ) async {
    final first = Completer<void>();
    final provider = _DraftProvider(gates: {'Draft Commet first.': first});
    await _studio(tester, provider);
    await _enter(tester, 'Draft Commet first.');
    await _finishCheck(tester);
    await _enter(tester, 'Draft Commet second.');
    await _finishCheck(tester);
    await _enter(tester, 'Draft Commet latest.');
    await _finishCheck(tester);
    expect(
      provider.requests.where((r) => r.text.startsWith('Draft')),
      hasLength(1),
    );
    expect(_suggestion(), findsNothing);
    first.complete();
    await _pump(tester);
    expect(
      provider.requests
          .where((r) => r.text.startsWith('Draft'))
          .map((r) => r.text),
      ['Draft Commet first.', 'Draft Commet latest.'],
    );
    expect(provider.maximumActiveDrafts, 1);
    expect(_suggestion(), findsOneWidget);
    await tester.ensureVisible(_suggestion());
    await tester.tap(_suggestion());
    await _pump(tester);
    expect(_text(tester).text, 'Draft Comment latest.');
    await _close(tester, provider);
  });

  testWidgets('composition pauses checks and resumes without a text change', (
    tester,
  ) async {
    final provider = _DraftProvider();
    await _studio(tester, provider);
    await _enter(tester, 'Draft Commet composing.');
    _text(tester).value = _text(
      tester,
    ).value.copyWith(composing: const TextRange(start: 6, end: 12));
    await _finishCheck(tester);
    expect(provider.requests.where((r) => r.text.startsWith('Draft')), isEmpty);
    expect(find.text('Finish typing to check this reply.'), findsOneWidget);
    _text(tester).value = _text(
      tester,
    ).value.copyWith(composing: TextRange.empty);
    await _finishCheck(tester);
    expect(_suggestion(), findsOneWidget);
    final stale = tester.widget<ActionChip>(_suggestion()).onPressed!;
    _text(tester).value = _text(
      tester,
    ).value.copyWith(composing: const TextRange(start: 6, end: 12));
    stale();
    await _pump(tester);
    expect(_text(tester).text, 'Draft Commet composing.');
    expect(_suggestion(), findsNothing);
    await _close(tester, provider);
  });

  testWidgets(
    'disabled checking stays paused and never invokes manual providers',
    (tester) async {
      final provider = _DraftProvider();
      final manual = _DraftProvider(providerId: 'manual-draft-test');
      final controller = await _studio(tester, provider, enabled: false);
      controller.proofing.configureManual(
        OfficeProofingService(providers: [manual]),
      );
      await _enter(tester, 'Draft Commet paused.');
      await _finishCheck(tester);
      expect(find.text('Reply checking paused.'), findsOneWidget);
      expect(provider.requests, isEmpty);
      expect(manual.requests, isEmpty);
      controller.proofing.enabled = true;
      await _finishCheck(tester);
      expect(_suggestion(), findsOneWidget);
      expect(manual.requests, isEmpty);
      controller.proofing.enabled = false;
      await _pump(tester);
      expect(_suggestion(), findsNothing);
      expect(find.text('Reply checking paused.'), findsOneWidget);
      await _close(tester, provider);
    },
  );

  testWidgets('language changes invalidate existing draft suggestions', (
    tester,
  ) async {
    final provider = _DraftProvider();
    final controller = await _studio(tester, provider);
    await _enter(tester, 'Draft Commet language.');
    await _finishCheck(tester);
    final stale = tester.widget<ActionChip>(_suggestion()).onPressed!;
    controller.setProofingLanguage('de-DE');
    stale();
    await _pump(tester);
    expect(_text(tester).text, 'Draft Commet language.');
    expect(_suggestion(), findsNothing);
    await _finishCheck(tester);
    expect(
      provider.requests.where((r) => r.text.startsWith('Draft')).last.language,
      'de-DE',
    );
    expect(_suggestion(), findsOneWidget);
    await _close(tester, provider);
  });

  testWidgets('thread switches preserve draft text and reject old actions', (
    tester,
  ) async {
    final provider = _DraftProvider();
    final controller = await _studio(tester, provider);
    await _enter(tester, 'Draft Commet Alice.');
    await _finishCheck(tester);
    final stale = tester.widget<ActionChip>(_suggestion()).onPressed!;
    controller.selectComment(2);
    stale();
    await _pump(tester);
    await _enter(tester, 'Draft Commet Bob.', 2);
    await _finishCheck(tester);
    expect(_suggestion(2), findsOneWidget);
    expect(_text(tester, 2).text, 'Draft Commet Bob.');
    controller.selectComment(1);
    await _pump(tester);
    expect(_text(tester).text, 'Draft Commet Alice.');
    await _finishCheck(tester);
    expect(_suggestion(), findsOneWidget);
    await _close(tester, provider);
  });

  testWidgets('replacement documents cannot receive late draft results', (
    tester,
  ) async {
    final gate = Completer<void>();
    final provider = _DraftProvider(gates: {'Draft Commet before.': gate});
    final controller = await _studio(tester, provider);
    await _enter(tester, 'Draft Commet before.');
    await _finishCheck(tester);
    controller.document = _document();
    controller.refresh();
    controller.selectComment(1);
    await _pump(tester);
    gate.complete();
    await _pump(tester);
    expect(_text(tester).text, isEmpty);
    expect(_suggestion(), findsNothing);
    expect(controller.document.comments, hasLength(2));
    await _close(tester, provider);
  });

  testWidgets('covering dialogs block captured draft correction and posting', (
    tester,
  ) async {
    final provider = _DraftProvider();
    final controller = await _studio(tester, provider);
    await _enter(tester, 'Draft Commet covered.');
    await _finishCheck(tester);
    final stale = tester.widget<ActionChip>(_suggestion()).onPressed!;
    final post = tester
        .widget<IconButton>(find.byKey(const Key('studio-comment-post-1')))
        .onPressed!;
    final context = tester.element(_field());
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Covering dialog')),
      ),
    );
    await _pump(tester);
    stale();
    post();
    expect(_text(tester).text, 'Draft Commet covered.');
    expect(controller.document.comments, hasLength(2));
    Navigator.of(context).pop();
    await _pump(tester);
    await _close(tester, provider);
  });

  for (final status in [
    OfficeProofingStatus.unavailable,
    OfficeProofingStatus.unsupported,
  ]) {
    testWidgets('$status is shown as incomplete rather than a clean reply', (
      tester,
    ) async {
      final provider = _DraftProvider(
        status: status,
        message: 'Checker unavailable for this language.',
      );
      await _studio(tester, provider);
      await _enter(tester, 'Draft Commet cannot check.');
      await _finishCheck(tester);
      expect(tester.widget<Text>(_status()).data, contains('incomplete'));
      expect(
        find.text('Checker unavailable for this language.'),
        findsOneWidget,
      );
      expect(find.text('No issues found in this reply.'), findsNothing);
      expect(_suggestion(), findsNothing);
      await _close(tester, provider);
    });
  }

  testWidgets('over-limit drafts explain the limit without provider work', (
    tester,
  ) async {
    final provider = _DraftProvider();
    await _studio(tester, provider);
    await _enter(tester, 'Draft ${'x' * WordProofingSession.maxDraftLength}');
    await _finishCheck(tester);
    expect(provider.requests.where((r) => r.text.startsWith('Draft')), isEmpty);
    expect(tester.widget<Text>(_status()).data, contains('incomplete'));
    expect(
      find.textContaining(
        'This reply exceeds the live checking limit '
        '(${WordProofingSession.maxDraftLength})',
      ),
      findsOneWidget,
    );
    await _close(tester, provider);
  });

  testWidgets('corrected draft posts explicitly as one undoable reply', (
    tester,
  ) async {
    final provider = _DraftProvider();
    final controller = await _studio(tester, provider);
    await _enter(tester, 'Draft Commet to post.');
    await _finishCheck(tester);
    await tester.ensureVisible(_suggestion());
    await tester.tap(_suggestion());
    await _pump(tester);
    expect(controller.canUndo, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await _pump(tester);
    expect(
      WordComment.repliesOf(controller.document, 1).single.text,
      'Draft Comment to post.',
    );
    expect(_text(tester).text, isEmpty);
    controller.undo();
    await _pump(tester);
    expect(controller.document.comments, hasLength(2));
    expect(controller.canUndo, isFalse);
    await _close(tester, provider);
  });

  testWidgets('narrow Arabic reply suggestions remain usable with larger text', (
    tester,
  ) async {
    final provider = _DraftProvider();
    const capture = bool.fromEnvironment('STUDIO_CAPTURE_DRAFT');
    final captureKey = capture ? GlobalKey() : null;
    if (capture) {
      await tester.runAsync(() async {
        await OfficeHostFonts.ensureRegistered();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
    }
    await _studio(tester, provider, captureKey: captureKey);
    await configureStudioForTest(tester, language: StudioLanguage.ar);
    await _pump(tester);
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester);
    expect(find.byTooltip('التنقل'), findsOneWidget);
    await tester.tap(find.byTooltip('التنقل'));
    await _pump(tester);
    // The editor caret keeps scheduling frames. Advance the modal transition
    // explicitly rather than waiting for an otherwise idle application.
    await tester.pump(const Duration(milliseconds: 350));
    await _pump(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 350));
    await _pump(tester);
    await _enter(tester, 'Draft Commet are is very very useful.');
    await _finishCheck(tester);
    await tester.ensureVisible(_suggestion());
    await _pump(tester);
    expect(_suggestion().hitTestable(), findsOneWidget);
    await tester.tap(_suggestion());
    await _pump(tester);
    expect(_text(tester).text, 'Draft Comment are is very very useful.');
    expect(tester.takeException(), isNull);
    if (capture) {
      await expectLater(
        find.byKey(captureKey!),
        matchesGoldenFile(
          '../../../../docs/validation/mail-reader-20261118/checks/late-studio-arabic-draft.png',
        ),
      );
    }
    await _close(tester, provider);
  });
}
