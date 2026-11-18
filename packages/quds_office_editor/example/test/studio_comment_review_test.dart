import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_studio/studio_chrome.dart';

class _CommentProofing extends OfficeProofingProvider {
  @override
  String get id => 'comment-review-test';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async =>
      OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: [
          for (final match in RegExp('Commet').allMatches(request.text))
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              ruleId: 'comment.spelling',
              start: match.start,
              end: match.end,
              message: 'Use Comment.',
              category: OfficeProofingCategory.spelling,
              replacements: const ['Comment'],
            ),
        ],
      );
}

WmlDocument _document() {
  final document = WmlDocument.empty(text: 'Alpha beta gamma.')
    ..proofingLanguage = 'en-US';
  document.comments.addAll([
    WmlComment(id: 1, text: 'Commet one.', author: 'Alice', initials: 'AL'),
    WmlComment(id: 2, text: 'Second note.', author: 'Bob', initials: 'BO'),
  ]);
  final paragraph = document.paragraphs.single;
  WordComment.applyRange(paragraph, 0, 5, 1);
  WordComment.applyRange(paragraph, 6, 10, 2);
  return document;
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<WordEditorController> _studio(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const QudsOfficeStudioApp());
  await _pump(tester);
  await tester.tap(find.byTooltip('English'));
  await _pump(tester);
  final controller = tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller;
  controller.proofing.enabled = false;
  controller.proofing.configure(OfficeProofingService(providers: []));
  controller.document = _document();
  controller.refresh();
  controller.selectComment(1);
  await _pump(tester);
  return controller;
}

Finder _field(int id) =>
    find.byKey(ValueKey<String>('studio-comment-reply-$id'));
Finder _post(int id) => find.byKey(ValueKey<String>('studio-comment-post-$id'));
Finder _command(String label) => find.byWidgetPredicate(
  (widget) => widget is StudioCmd && widget.label == label,
);

Future<void> _tapCommand(WidgetTester tester, String label) async {
  final finder = _command(label);
  final ribbon = find.descendant(
    of: find.byType(StudioRibbonStrip),
    matching: find.byType(Scrollable),
  );
  if (finder.evaluate().isEmpty) {
    tester.state<ScrollableState>(ribbon).position.jumpTo(0);
    await tester.pump();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 240, scrollable: ribbon);
    }
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _pump(tester);
}

Future<void> _enter(WidgetTester tester, int id, String text) async {
  await tester.ensureVisible(_field(id));
  await tester.enterText(_field(id), text);
  await _pump(tester);
}

String _draft(WidgetTester tester, int id) =>
    tester.widget<TextField>(_field(id)).controller!.text;

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('Reply focuses the inline draft without posting or a dialog', (
    tester,
  ) async {
    final controller = await _studio(tester);
    final revision = controller.contentRevision;
    await tester.tap(find.text('Review').first);
    await _pump(tester);
    await _tapCommand(tester, 'Reply');
    expect(find.byType(Dialog), findsNothing);
    expect(tester.widget<TextField>(_field(1)).focusNode!.hasFocus, isTrue);
    expect(find.text('Reply to Alice'), findsOneWidget);
    await _enter(tester, 1, 'Keep this draft.');
    await _tapCommand(tester, 'Reply');
    expect(_draft(tester, 1), 'Keep this draft.');
    expect(tester.widget<TextField>(_field(1)).focusNode!.hasFocus, isTrue);
    expect(controller.document.comments, hasLength(2));
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
    await _close(tester);
  });

  testWidgets(
    'thread drafts survive switching and explicit posts are undoable',
    (tester) async {
      final controller = await _studio(tester);
      await _enter(tester, 1, 'For Alice');
      final staleAlicePost = tester.widget<IconButton>(_post(1)).onPressed!;
      controller.selectComment(2);
      staleAlicePost();
      expect(controller.document.comments, hasLength(2));
      await _pump(tester);
      expect(_draft(tester, 2), isEmpty);
      await _enter(tester, 2, 'For Bob');
      controller.selectComment(1);
      await _pump(tester);
      expect(_draft(tester, 1), 'For Alice');
      await tester.ensureVisible(_post(1));
      await tester.tap(_post(1));
      await _pump(tester);
      expect(
        WordComment.repliesOf(controller.document, 1).single.text,
        'For Alice',
      );
      expect(WordComment.repliesOf(controller.document, 2), isEmpty);
      expect(_draft(tester, 1), isEmpty);
      controller.undo();
      await _pump(tester);
      expect(controller.document.comments, hasLength(2));
      controller.redo();
      await _pump(tester);
      expect(
        WordComment.repliesOf(controller.document, 1).single.text,
        'For Alice',
      );
      controller.selectComment(2);
      await _pump(tester);
      expect(_draft(tester, 2), 'For Bob');
      await tester.tap(_field(2));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _pump(tester);
      expect(
        WordComment.repliesOf(controller.document, 2).single.text,
        'For Bob',
      );
      expect(_draft(tester, 2), isEmpty);
      await _close(tester);
    },
  );

  testWidgets(
    'hiding comments preserves drafts and Reply restores inline focus',
    (tester) async {
      final controller = await _studio(tester);
      await _enter(tester, 1, 'Unposted draft');
      await tester.tap(find.text('Review').first);
      await _pump(tester);
      await _tapCommand(tester, 'Pane');
      expect(_field(1), findsNothing);
      await _tapCommand(tester, 'Reply');
      expect(_draft(tester, 1), 'Unposted draft');
      expect(tester.widget<TextField>(_field(1)).focusNode!.hasFocus, isTrue);
      expect(controller.document.comments, hasLength(2));
      expect(find.byType(Dialog), findsNothing);
      await _close(tester);
    },
  );

  testWidgets(
    'a replaced thread cannot inherit a draft through its reused ID',
    (tester) async {
      final controller = await _studio(tester);
      await _enter(tester, 1, 'Old thread only');
      controller.deleteComment(1);
      controller.document.comments.add(
        WmlComment(id: 1, text: 'Replacement thread.', author: 'Chris'),
      );
      controller.selectComment(1);
      controller.refresh();
      await _pump(tester);
      expect(_draft(tester, 1), isEmpty);
      expect(find.text('Reply to Chris'), findsOneWidget);
      expect(WordComment.repliesOf(controller.document, 1), isEmpty);
      await _close(tester);
    },
  );

  testWidgets('a stale post callback cannot send into another document', (
    tester,
  ) async {
    final controller = await _studio(tester);
    await _enter(tester, 1, 'From previous document');
    final stalePost = tester.widget<IconButton>(_post(1)).onPressed!;
    final previousDocument = controller.document;
    controller.document = _document();
    controller.refresh();
    stalePost();
    await _pump(tester);
    expect(controller.document.comments, hasLength(2));
    expect(previousDocument.comments, hasLength(2));
    expect(_draft(tester, 1), isEmpty);
    await _close(tester);
  });

  testWidgets('posting waits until IME composition is complete', (
    tester,
  ) async {
    final controller = await _studio(tester);
    await _enter(tester, 1, 'Composing');
    final field = tester.widget<TextField>(_field(1));
    field.controller!.value = field.controller!.value.copyWith(
      composing: const TextRange(start: 0, end: 9),
    );
    tester.widget<IconButton>(_post(1)).onPressed!();
    await _pump(tester);
    expect(controller.document.comments, hasLength(2));
    expect(_draft(tester, 1), 'Composing');
    field.controller!.value = field.controller!.value.copyWith(
      composing: TextRange.empty,
    );
    tester.widget<IconButton>(_post(1)).onPressed!();
    await _pump(tester);
    expect(
      WordComment.repliesOf(controller.document, 1).single.text,
      'Composing',
    );
    await _close(tester);
  });

  testWidgets(
    'viewing mode keeps comments inspectable without reply controls',
    (tester) async {
      final controller = await _studio(tester);
      await _enter(tester, 1, 'Kept while viewing');
      await tester.tap(find.text('File').first);
      await _pump(tester);
      await _tapCommand(tester, 'View');
      expect(_field(1), findsNothing);
      expect(find.byKey(const ValueKey('studio-comment-1')), findsOneWidget);
      expect(controller.document.comments, hasLength(2));
      await tester.tap(find.text('Review').first);
      await _pump(tester);
      await _tapCommand(tester, 'Pane');
      await _tapCommand(tester, 'Pane');
      expect(_field(1), findsNothing);
      expect(controller.document.comments, hasLength(2));
      await _close(tester);
    },
  );

  testWidgets('comment writing marks open the current finding in live review', (
    tester,
  ) async {
    final controller = await _studio(tester);
    controller.proofing.configure(
      OfficeProofingService(providers: [_CommentProofing()]),
    );
    final check = controller.proofing.checkNow(includeManualProviders: false);
    var done = false;
    unawaited(check.then((_) => done = true));
    for (var i = 0; i < 20 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(done, isTrue);
    await _pump(tester);
    final comment = controller.document.comments.first;
    final paragraph = comment.paragraphs.single;
    final canvas = tester.widget<WordCanvas>(
      find.byKey(const ValueKey('studio-comment-canvas-1')),
    );
    expect(canvas.proofingFindings[paragraph], hasLength(1));
    controller.beginCommentEdit(1);
    canvas.onReviewTap!(
      OfficeContextHit(
        kind: OfficeContextKind.comment,
        globalPosition: Offset.zero,
        commentId: 1,
        paragraph: paragraph,
        proofingOffset: 1,
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    canvas.onChanged!();
    await tester.pump(kDoubleTapTimeout);
    await _pump(tester);
    expect(controller.reviewPaneVisible, isFalse);
    expect(controller.proofing.summary.issues, hasLength(1));
    canvas.onReviewTap!(
      OfficeContextHit(
        kind: OfficeContextKind.comment,
        globalPosition: Offset.zero,
        commentId: 1,
        paragraph: paragraph,
        proofingOffset: 1,
      ),
    );
    await tester.pump(kDoubleTapTimeout);
    await _pump(tester);
    expect(controller.reviewPaneVisible, isTrue);
    expect(controller.reviewPaneTab, WordReviewPaneTab.proofing);
    expect(controller.selectedProofingIssue!.paragraph, same(paragraph));
    expect(find.byType(Dialog), findsNothing);
    final issue = controller.selectedProofingIssue!;
    expect(controller.applyProofingSuggestion(issue, 'Comment'), isTrue);
    expect(comment.text, 'Comment one.');
    expect(controller.document.paragraphs.single.text, 'Alpha beta gamma.');
    controller.undo();
    expect(comment.text, 'Commet one.');
    await _close(tester);
  });

  for (final arabic in [false, true]) {
    testWidgets(
      'narrow ${arabic ? 'Arabic' : 'English'} comments stay below the editor',
      (tester) async {
        final controller = await _studio(tester);
        await _enter(tester, 1, 'Draft across resize');
        await tester.binding.setSurfaceSize(const Size(900, 1000));
        await _pump(tester);
        if (arabic) {
          await tester.tap(find.byTooltip('العربية'));
          await _pump(tester);
        }
        final pane = tester.getRect(
          find.byKey(const ValueKey('studio-comments-pane')),
        );
        final editor = tester.getRect(find.byType(QudsWordEditor));
        expect(pane.top, greaterThanOrEqualTo(editor.bottom));
        expect(pane.width, 900);
        expect(_draft(tester, 1), 'Draft across resize');
        final reply = find.byKey(
          const ValueKey('studio-comment-reply-action-1'),
        );
        await tester.ensureVisible(reply);
        await tester.tap(reply);
        await _pump(tester);
        expect(tester.widget<TextField>(_field(1)).focusNode!.hasFocus, isTrue);
        expect(controller.document.comments, hasLength(2));
        expect(find.byType(Dialog), findsNothing);
        await _close(tester);
      },
    );
  }
}
