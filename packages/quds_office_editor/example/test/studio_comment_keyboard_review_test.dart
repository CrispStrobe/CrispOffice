import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';

import 'support/studio_document_mode.dart';
import 'support/studio_test_settings.dart';

class _Proofing extends OfficeProofingProvider {
  _Proofing({this.overlapping = false});

  final bool overlapping;

  @override
  String get id => 'comment-keyboard';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async =>
      OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: [
          for (final match in RegExp('Commet').allMatches(request.text)) ...[
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              ruleId: 'spelling',
              start: match.start,
              end: match.end,
              message: 'Use Comment.',
              category: OfficeProofingCategory.spelling,
              replacements: const ['Comment'],
            ),
            if (overlapping)
              OfficeProofingFinding.forRequest(
                request,
                providerId: id,
                ruleId: 'wording',
                start: match.start,
                end: match.end,
                message: 'Use Review.',
                category: OfficeProofingCategory.grammar,
                replacements: const ['Review'],
              ),
          ],
        ],
      );
}

WmlDocument _document() {
  final document = WmlDocument.empty(text: 'Preserve the document body.')
    ..proofingLanguage = 'en-US';
  document.comments.addAll([
    WmlComment(id: 1, text: 'Commet one.', author: 'Alice'),
    WmlComment(id: 2, text: 'Second note.', author: 'Bob'),
  ]);
  WordComment.applyRange(document.paragraphs.single, 0, 8, 1);
  WordComment.applyRange(document.paragraphs.single, 9, 12, 2);
  return document;
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

QudsWordEditor _editor(WidgetTester tester) =>
    tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));

Future<WordEditorController> _studio(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const QudsOfficeStudioApp());
  await _pump(tester);
  final controller = _editor(tester).controller;
  controller.proofing.enabled = false;
  controller.proofing.configure(OfficeProofingService(providers: []));
  // Settings advances animations beyond the initial proofing debounce.
  await configureStudioForTest(tester, showComments: true);
  await _pump(tester);
  controller.document = _document();
  controller.refresh();
  controller.beginCommentEdit(1);
  await _pump(tester);
  return controller;
}

Future<void> _check(
  WidgetTester tester,
  WordEditorController controller, {
  bool overlapping = false,
}) async {
  controller.proofing.configure(
    OfficeProofingService(providers: [_Proofing(overlapping: overlapping)]),
  );
  var done = false;
  unawaited(
    controller.proofing
        .checkNow(includeManualProviders: false)
        .then((_) => done = true),
  );
  for (var i = 0; i < 40 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(done, isTrue);
  await _pump(tester);
}

Future<void> _open(WidgetTester tester, {bool menuKey = false}) async {
  if (menuKey) {
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
  } else {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  await _pump(tester);
}

Finder get _menu => find.byKey(const Key('office-context-menu'));

GestureDetector _action(WidgetTester tester, String label) =>
    tester.widget<GestureDetector>(
      find
          .ancestor(
            of: find.descendant(of: _menu, matching: find.text(label)),
            matching: find.byType(GestureDetector),
          )
          .first,
    );

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  expect(tester.takeException(), isNull);
}

void main() {
  for (final key in [LogicalKeyboardKey.escape, LogicalKeyboardKey.tab]) {
    testWidgets(
      'comment Shift+F10 opens in place and ${key.keyLabel} restores focus',
      (tester) async {
        final controller = await _studio(tester);
        await _check(tester, controller);
        controller.commentCaret
          ..logicalIndex = 1
          ..collapseSelection();
        controller.refreshView();
        await _pump(tester);
        final revision = controller.contentRevision;
        final origin = controller.viewport.origin;
        await _open(tester);
        expect(_menu, findsOneWidget);
        expect(find.text('Comment'), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        expect(_editor(tester).focusNode!.hasPrimaryFocus, isFalse);
        expect(controller.commentCaret.logicalIndex, 1);
        expect(controller.commentCaret.isCollapsed, isTrue);
        expect(controller.viewport.origin, origin);
        expect(controller.contentRevision, revision);
        expect(controller.canUndo, isFalse);
        await tester.sendKeyEvent(key);
        await _pump(tester);
        expect(_menu, findsNothing);
        expect(_editor(tester).focusNode!.hasPrimaryFocus, isTrue);
        expect(controller.input.isAttached, isTrue);
        expect(controller.isEditingComment, isTrue);
        expect(controller.document.comments.first.text, 'Commet one.');
        expect(
          controller.document.paragraphs.single.text,
          'Preserve the document body.',
        );
        await _close(tester);
      },
    );
  }

  testWidgets(
    'Menu key keeps the explicitly selected overlapping comment finding',
    (tester) async {
      final controller = await _studio(tester);
      await _check(tester, controller, overlapping: true);
      final issue = controller.proofing.summary.issues.singleWhere(
        (issue) => issue.finding.ruleId == 'wording',
      );
      expect(controller.selectProofingIssue(issue), isTrue);
      _editor(tester).focusNode!.requestFocus();
      await _pump(tester);
      expect(controller.commentCaret.logicalIndex, issue.finding.end);
      expect(controller.commentCaret.selectionAnchor, issue.finding.start);
      final revision = controller.contentRevision;
      await _open(tester, menuKey: true);
      expect(_menu, findsOneWidget);
      expect(find.text('Use Review.'), findsOneWidget);
      expect(find.text('Use Comment.'), findsNothing);
      expect(controller.contentRevision, revision);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _pump(tester);
      expect(_menu, findsNothing);
      expect(controller.document.comments.first.text, 'Review one.');
      expect(
        controller.document.paragraphs.single.text,
        'Preserve the document body.',
      );
      expect(_editor(tester).focusNode!.hasPrimaryFocus, isTrue);
      controller.undo();
      expect(controller.document.comments.first.text, 'Commet one.');
      expect(controller.canUndo, isFalse);
      await _close(tester);
    },
  );

  testWidgets('keyboard context uses the selected comment paragraph', (
    tester,
  ) async {
    final controller = await _studio(tester);
    final comment = controller.document.comments.first;
    comment.paragraphs.add(
      WmlParagraph(inlines: [WmlRun(text: 'Commet again.')]),
    );
    controller.refresh();
    await _check(tester, controller);
    final issue = controller.proofing.summary.issues.singleWhere(
      (issue) => identical(issue.paragraph, comment.paragraphs.last),
    );
    controller.selectProofingIssue(issue);
    _editor(tester).focusNode!.requestFocus();
    await _pump(tester);
    await _open(tester);
    expect(_menu, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pump(tester);
    expect(comment.paragraphs.first.text, 'Commet one.');
    expect(comment.paragraphs.last.text, 'Comment again.');
    expect(controller.document.comments.last.text, 'Second note.');
    await _close(tester);
  });

  testWidgets(
    'Select mode offers keyboard Copy without enabling comment edits',
    (tester) async {
      final controller = await _studio(tester);
      final clipboard = OfficeClipboard.instance;
      final useSystem = clipboard.useSystem;
      clipboard
        ..clear()
        ..useSystem = false;
      addTearDown(() {
        clipboard
          ..useSystem = useSystem
          ..clear();
      });
      await selectStudioDocumentMode(tester, OfficeInteractionMode.selecting);
      controller.beginCommentEdit(1);
      controller.commentCaret
        ..logicalIndex = 6
        ..selectionAnchorParagraph = 0
        ..selectionAnchor = 0;
      controller.refreshView();
      await _pump(tester);
      final revision = controller.contentRevision;
      await _open(tester, menuKey: true);
      expect(_menu, findsOneWidget);
      expect(_action(tester, 'Copy').onTap, isNotNull);
      expect(_action(tester, 'Cut').onTap, isNull);
      expect(_action(tester, 'Paste').onTap, isNull);
      expect(_action(tester, 'Delete comment').onTap, isNull);
      // The first enabled item is Open writing pane; disabled Cut is skipped.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _pump(tester);
      expect(clipboard.local?.plain, 'Commet');
      expect(_editor(tester).focusNode!.hasPrimaryFocus, isTrue);
      expect(controller.input.isAttached, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(controller.document.comments.first.text, 'Commet one.');
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      await selectStudioDocumentMode(tester, OfficeInteractionMode.viewing);
      _editor(tester).onCommentContextMenuRequested!();
      await _pump(tester);
      expect(_menu, findsNothing);
      await _close(tester);
    },
  );

  testWidgets(
    'IME composition blocks keyboard comment menus without changing composition',
    (tester) async {
      final controller = await _studio(tester);
      await _check(tester, controller);
      controller.input.composing = const TextRange(start: 0, end: 3);
      await _open(tester);
      expect(_menu, findsNothing);
      _editor(tester).onCommentContextMenuRequested!();
      await _pump(tester);
      expect(_menu, findsNothing);
      expect(controller.input.composing, const TextRange(start: 0, end: 3));
      expect(controller.document.comments.first.text, 'Commet one.');
      expect(controller.canUndo, isFalse);
      controller.input.composing = TextRange.empty;
      await _close(tester);
    },
  );

  testWidgets('covered modal blocks a captured keyboard comment correction', (
    tester,
  ) async {
    final controller = await _studio(tester);
    await _check(tester, controller);
    await _open(tester);
    final apply = _action(tester, 'Comment').onTap!;
    final hostMenu = _editor(tester).onCommentContextMenuRequested!;
    final context = tester.element(find.byType(QudsWordEditor));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Covered editor')),
      ),
    );
    await _pump(tester);
    apply();
    hostMenu();
    await _pump(tester);
    expect(_menu, findsNothing);
    expect(controller.document.comments.first.text, 'Commet one.');
    expect(controller.canUndo, isFalse);
    expect(_editor(tester).focusNode!.hasPrimaryFocus, isFalse);
    Navigator.of(context).pop();
    await tester.pump(const Duration(milliseconds: 300));
    await _pump(tester);
    await _close(tester);
  });

  testWidgets(
    'stale keyboard comment menu cannot mutate a replaced document with reused ids',
    (tester) async {
      final controller = await _studio(tester);
      await _check(tester, controller);
      await _open(tester);
      final apply = _action(tester, 'Comment').onTap!;
      final remove = _action(tester, 'Delete comment').onTap!;
      final previous = controller.document;
      controller.document = _document();
      controller.refresh();
      apply();
      remove();
      await _pump(tester);
      expect(_menu, findsNothing);
      expect(previous.comments.first.text, 'Commet one.');
      expect(controller.document.comments, hasLength(2));
      expect(controller.document.comments.first.text, 'Commet one.');
      expect(controller.canUndo, isFalse);
      await _close(tester);
    },
  );

  testWidgets(
    'comment keyboard context rejects a canvas from the prior thread before rebuild',
    (tester) async {
      final controller = await _studio(tester);
      await _check(tester, controller);
      controller.beginCommentEdit(2);
      // The host still has the first thread's rendered canvas until the frame.
      _editor(tester).onCommentContextMenuRequested!();
      await _pump(tester);
      expect(_menu, findsNothing);
      expect(controller.document.comments.first.text, 'Commet one.');
      expect(controller.document.comments.last.text, 'Second note.');
      expect(controller.canUndo, isFalse);
      await _open(tester);
      expect(_menu, findsOneWidget);
      expect(find.text('Comment'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _pump(tester);
      await _close(tester);
    },
  );
}
