import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_studio/studio_chrome.dart';

class _CommentProofing extends OfficeProofingProvider {
  _CommentProofing({this.gates = const {}});

  final Map<String, Completer<void>> gates;
  final requests = <OfficeProofingRequest>[];

  @override
  String get id => 'comment-review-test';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    await gates[request.text]?.future;
    return OfficeProofingResult(
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

  void release() {
    for (final gate in gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
  }
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
  // An in-flight check yields between paragraphs. Let its already scheduled
  // continuation observe disposal rather than leaving a fake timer behind.
  await tester.pump(const Duration(milliseconds: 1));
  expect(tester.takeException(), isNull);
}

Future<void> _checkComments(
  WidgetTester tester,
  WordEditorController controller, {
  _CommentProofing? provider,
}) async {
  controller.proofing.configure(
    OfficeProofingService(providers: [provider ?? _CommentProofing()]),
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

WordCanvas _commentCanvas(WidgetTester tester, int id) =>
    tester.widget<WordCanvas>(
      find.byKey(ValueKey<String>('studio-comment-canvas-$id')),
    );

OfficeContextHit _commentHit(
  WidgetTester tester,
  WordEditorController controller,
  int id,
) => OfficeContextHit(
  kind: OfficeContextKind.comment,
  globalPosition:
      tester.getTopLeft(
        find.byKey(ValueKey<String>('studio-comment-canvas-$id')),
      ) +
      const Offset(16, 12),
  commentId: id,
  paragraph: WordComment.byId(controller.document, id)!.paragraphs.first,
  proofingOffset: 1,
);

Future<void> _openCommentMenu(
  WidgetTester tester,
  WordEditorController controller, {
  int id = 1,
  bool primary = false,
}) async {
  controller.beginCommentEdit(id);
  await _pump(tester);
  final canvas = _commentCanvas(tester, id);
  final hit = _commentHit(tester, controller, id);
  if (primary) {
    canvas.onReviewTap!(hit);
    await tester.pump(kDoubleTapTimeout);
  } else {
    canvas.onContextMenu!(hit);
  }
  await _pump(tester);
}

GestureDetector _menuAction(WidgetTester tester, String label) =>
    tester.widget<GestureDetector>(
      find
          .ancestor(
            of: find.descendant(
              of: find.byKey(const Key('office-context-menu')),
              matching: find.text(label),
            ),
            matching: find.byType(GestureDetector),
          )
          .first,
    );

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

  testWidgets('comment writing marks offer focused inline corrections', (
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
    await _pump(tester);
    final render = tester.renderObject<RenderWordCanvas>(
      find.byKey(const ValueKey('studio-comment-canvas-1')),
    );
    final line = controller.commentLaidOut!.pages
        .expand((page) => page.lines)
        .firstWhere(
          (line) => line.paragraphIndex == 0 && line.glyphs.isNotEmpty,
        );
    final glyph = line.glyphs.firstWhere(
      (glyph) => glyph.glyph.logicalIndex <= 1 && 1 < glyph.logicalEnd,
    );
    final point = render.localToGlobal(
      render.windowForPagePoint(
        line.pageIndex,
        Offset(glyph.x + glyph.advance * .35, line.y + line.height * .5),
      ),
    );
    canvas.onReviewTap!(
      OfficeContextHit(
        kind: OfficeContextKind.comment,
        globalPosition: point,
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
    final local = render.globalToLocal(point);
    expect(render.compact, isTrue);
    expect(
      controller.commentLaidOut!.pages.first.headerBand.contains(
        local.dx,
        local.dy,
      ),
      isTrue,
    );
    expect(line.sourceParagraph, same(paragraph));
    expect(render.proofingFindings[paragraph], hasLength(1));
    final forward = render.onReviewTap!;
    var pointed = false;
    render.onReviewTap = (hit) {
      pointed = true;
      forward(hit);
    };
    final repeated = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await repeated.up();
    expect(
      pointed,
      isTrue,
      reason: 'The rendered marked word must report its source.',
    );
    await tester.pump(kDoubleTapTimeout);
    await _pump(tester);
    expect(controller.reviewPaneVisible, isFalse);
    expect(find.byKey(const Key('office-context-menu')), findsOneWidget);
    expect(find.text('Comment'), findsOneWidget);
    expect(find.text('Ignore once'), findsOneWidget);
    expect(find.text('Delete comment'), findsNothing);
    expect(controller.selectedProofingIssue!.paragraph, same(paragraph));
    expect(
      tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .focusNode!
          .hasPrimaryFocus,
      isTrue,
    );
    expect(controller.input.isAttached, isTrue);
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.text('Comment'));
    await _pump(tester);
    expect(comment.text, 'Comment one.');
    expect(controller.document.paragraphs.single.text, 'Alpha beta gamma.');
    controller.undo();
    expect(comment.text, 'Commet one.');
    await _close(tester);
  });

  testWidgets('comment marks follow the existing Writing pane', (tester) async {
    final controller = await _studio(tester);
    await _checkComments(tester, controller);
    controller.openReviewPane(tab: WordReviewPaneTab.changes);
    await _pump(tester);
    await _openCommentMenu(tester, controller, primary: true);
    expect(controller.reviewPaneVisible, isTrue);
    expect(controller.reviewPaneTab, WordReviewPaneTab.proofing);
    expect(
      controller.selectedProofingIssue!.paragraph,
      same(controller.document.comments.first.paragraphs.single),
    );
    expect(find.byKey(const Key('office-context-menu')), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    await _close(tester);
  });

  testWidgets('comment context menus combine corrections and thread actions', (
    tester,
  ) async {
    final controller = await _studio(tester);
    await _checkComments(tester, controller);
    await _openCommentMenu(tester, controller);
    expect(find.text('Comment'), findsOneWidget);
    expect(_menuAction(tester, 'Reply').onTap, isNotNull);
    expect(_menuAction(tester, 'Resolve').onTap, isNotNull);
    expect(_menuAction(tester, 'Delete comment').onTap, isNotNull);
    await tester.tap(find.text('Open writing pane'));
    await _pump(tester);
    expect(controller.reviewPaneVisible, isTrue);
    expect(controller.selectedProofingIssue!.story, 'Comment 1');
    expect(find.byKey(const Key('office-context-menu')), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    await _close(tester);
  });

  testWidgets(
    'comment context Cut owns the comment rather than a body selection',
    (tester) async {
      final controller = await _studio(tester);
      final clipboard = OfficeClipboard.instance;
      final useSystem = clipboard.useSystem;
      clipboard.useSystem = false;
      addTearDown(() {
        clipboard.useSystem = useSystem;
        clipboard.clear();
      });
      controller.documentCaret
        ..paragraphIndex = 0
        ..logicalIndex = 5
        ..selectionAnchorParagraph = 0
        ..selectionAnchor = 0;
      controller.commentCaret
        ..paragraphIndex = 0
        ..logicalIndex = 6
        ..selectionAnchorParagraph = 0
        ..selectionAnchor = 0;
      expect(controller.isEditingComment, isFalse);
      final originalBody = controller.document.paragraphs.single.text;
      _commentCanvas(tester, 1).onContextMenu!(
        _commentHit(tester, controller, 1),
      );
      await _pump(tester);
      expect(controller.isEditingComment, isTrue);
      expect(controller.selectedCommentId, 1);
      expect(controller.commentCaret.logicalIndex, 6);
      expect(controller.commentCaret.selectionAnchor, 0);
      expect(_menuAction(tester, 'Cut').onTap, isNotNull);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('office-context-menu')),
          matching: find.text('Cut'),
        ),
      );
      await _pump(tester);
      expect(clipboard.local?.plain, 'Commet');
      expect(controller.document.comments.first.text, ' one.');
      expect(controller.document.paragraphs.single.text, originalBody);
      controller.undo();
      expect(controller.document.comments.first.text, 'Commet one.');
      expect(controller.document.paragraphs.single.text, originalBody);
      await _close(tester);
    },
  );

  for (final action in ['Cut', 'Paste']) {
    for (final change in ['none', 'source', 'caret', 'document']) {
      testWidgets(
        'delayed comment $action validates its context after $change change',
        (tester) async {
          final controller = await _studio(tester);
          final clipboard = OfficeClipboard.instance;
          final useSystem = clipboard.useSystem;
          clipboard
            ..clear()
            ..useSystem = true;
          final pending = Completer<Object?>();
          final calls = <MethodCall>[];
          final method = action == 'Cut'
              ? 'Clipboard.setData'
              : 'Clipboard.getData';
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(SystemChannels.platform, (call) {
            if (call.method != method) return Future.value();
            calls.add(call);
            return pending.future;
          });
          addTearDown(() {
            if (!pending.isCompleted) pending.complete();
            messenger.setMockMethodCallHandler(SystemChannels.platform, null);
            clipboard
              ..useSystem = useSystem
              ..clear();
          });
          controller.beginCommentEdit(1);
          controller.commentCaret
            ..paragraphIndex = 0
            ..logicalIndex = 6
            ..selectionAnchorParagraph = 0
            ..selectionAnchor = 0;
          await _pump(tester);
          _commentCanvas(tester, 1).onContextMenu!(
            _commentHit(tester, controller, 1),
          );
          await _pump(tester);
          expect(_menuAction(tester, action).onTap, isNotNull);
          final originalDocument = controller.document;
          final originalComment = controller.document.comments.first;
          await tester.tap(
            find.descendant(
              of: find.byKey(const Key('office-context-menu')),
              matching: find.text(action),
            ),
          );
          await _pump(tester);
          expect(calls, hasLength(1));
          expect(originalComment.text, 'Commet one.');
          if (action == 'Cut') {
            expect(
              (calls.single.arguments as Map<Object?, Object?>)['text'],
              'Commet',
            );
          }
          switch (change) {
            case 'source':
              controller.updateComment(1, text: 'Updated note.');
            case 'caret':
              controller.commentCaret
                ..logicalIndex = 2
                ..collapseSelection();
              controller.refresh();
            case 'document':
              controller.document = _document();
              controller.refresh();
              controller.beginCommentEdit(1);
              controller.commentCaret
                ..logicalIndex = 6
                ..selectionAnchorParagraph = 0
                ..selectionAnchor = 0;
          }
          final revision = controller.contentRevision;
          final expectedComment = controller.document.comments.first.text;
          final expectedOriginal = originalComment.text;
          pending.complete(action == 'Paste' ? {'text': 'Pasted'} : null);
          await _pump(tester);
          if (change == 'none') {
            expect(
              originalComment.text,
              action == 'Cut' ? ' one.' : 'Pasted one.',
            );
            expect(controller.canUndo, isTrue);
            controller.undo();
            expect(originalComment.text, 'Commet one.');
          } else {
            expect(controller.contentRevision, revision);
            expect(controller.document.comments.first.text, expectedComment);
            expect(originalComment.text, expectedOriginal);
          }
          expect(
            controller.document.paragraphs.single.text,
            'Alpha beta gamma.',
          );
          expect(originalDocument.paragraphs.single.text, 'Alpha beta gamma.');
          await _close(tester);
        },
      );
    }
  }

  testWidgets('invalid clipboard guards stop before system clipboard access', (
    tester,
  ) async {
    final controller = await _studio(tester);
    final clipboard = OfficeClipboard.instance;
    final useSystem = clipboard.useSystem;
    clipboard
      ..clear()
      ..useSystem = true;
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      clipboard
        ..useSystem = useSystem
        ..clear();
    });
    controller.beginCommentEdit(1);
    controller.commentCaret
      ..logicalIndex = 6
      ..selectionAnchorParagraph = 0
      ..selectionAnchor = 0;
    expect(controller.canCut, isTrue);
    expect(controller.canPaste, isTrue);
    await controller.cutToClipboard(isCurrent: () => false);
    await controller.pasteFromClipboard(isCurrent: () => false);
    expect(calls, isEmpty);
    expect(clipboard.local, isNull);
    expect(controller.document.comments.first.text, 'Commet one.');
    expect(controller.canUndo, isFalse);
    await _close(tester);
  });

  for (final action in [
    'Ignore once',
    'Ignore this word',
    'Add to personal words',
  ]) {
    testWidgets('comment menu $action respects the current finding', (
      tester,
    ) async {
      final controller = await _studio(tester);
      controller.document.comments[1].text = 'Commet two.';
      controller.refresh();
      await _checkComments(tester, controller);
      expect(controller.proofing.summary.issues, hasLength(2));
      final revision = controller.contentRevision;
      await _openCommentMenu(tester, controller);
      await tester.tap(find.text(action));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(controller.document.comments.first.text, 'Commet one.');
      expect(
        controller.proofing.summary.issues,
        hasLength(action == 'Ignore once' ? 1 : 0),
      );
      if (action == 'Ignore once') {
        expect(
          controller.proofing.summary.issues.single.paragraph,
          same(controller.document.comments[1].paragraphs.single),
        );
      } else if (action == 'Ignore this word') {
        expect(
          controller.proofing.vocabulary.ignoredWordsFor('en-US'),
          contains('Commet'),
        );
      } else {
        expect(
          controller.proofing.vocabulary.wordsFor('en-US'),
          contains('Commet'),
        );
      }
      await _close(tester);
    });
  }

  testWidgets(
    'comment suggestions survive unrelated in-flight check progress',
    (tester) async {
      final controller = await _studio(tester);
      controller.document.comments.add(
        WmlComment(id: 3, text: 'Third note.', author: 'Chris'),
      );
      controller.refresh();
      final provider = _CommentProofing(
        gates: {
          'Second note.': Completer<void>(),
          'Third note.': Completer<void>(),
        },
      );
      addTearDown(provider.release);
      controller.proofing.configure(
        OfficeProofingService(providers: [provider]),
      );
      unawaited(controller.proofing.checkNow(includeManualProviders: false));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(controller.proofing.checking, isTrue);
      expect(controller.proofing.summary.issues, hasLength(1));
      final issue = controller.proofing.summary.issues.single;
      await _openCommentMenu(tester, controller, primary: true);
      expect(find.text('Comment'), findsOneWidget);
      provider.gates['Second note.']!.complete();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(controller.proofing.checking, isTrue);
      expect(provider.requests.last.text, 'Third note.');
      expect(controller.proofing.isCurrent(issue), isTrue);
      expect(find.byKey(const Key('office-context-menu')), findsOneWidget);
      await tester.tap(find.text('Comment'));
      await _pump(tester);
      expect(controller.document.comments.first.text, 'Comment one.');
      provider.release();
      await _pump(tester);
      expect(controller.document.comments.first.text, 'Comment one.');
      controller.undo();
      expect(controller.document.comments.first.text, 'Commet one.');
      await _close(tester);
    },
  );

  testWidgets(
    'stale comment menus cannot act on another document or reused ID',
    (tester) async {
      final controller = await _studio(tester);
      await _checkComments(tester, controller);
      await _openCommentMenu(tester, controller);
      final staleDelete = _menuAction(tester, 'Delete comment').onTap!;
      final staleResolve = _menuAction(tester, 'Resolve').onTap!;
      final staleApply = _menuAction(tester, 'Comment').onTap!;
      final previous = controller.document;
      controller.document = _document();
      controller.refresh();
      staleDelete();
      staleResolve();
      staleApply();
      await _pump(tester);
      expect(find.byKey(const Key('office-context-menu')), findsNothing);
      expect(controller.document.comments, hasLength(2));
      expect(controller.document.comments.first.resolved, isFalse);
      expect(controller.document.comments.first.text, 'Commet one.');
      expect(previous.comments, hasLength(2));
      expect(previous.comments.first.text, 'Commet one.');

      controller.selectComment(1);
      await _openCommentMenu(tester, controller);
      final reusedDelete = _menuAction(tester, 'Delete comment').onTap!;
      controller.document.comments[0] = WmlComment(
        id: 1,
        text: 'New identity.',
        author: 'Chris',
      );
      controller.selectComment(1);
      reusedDelete();
      await _pump(tester);
      expect(controller.document.comments, hasLength(2));
      expect(controller.document.comments.first.text, 'New identity.');
      expect(find.byKey(const Key('office-context-menu')), findsNothing);
      await _close(tester);
    },
  );

  testWidgets('comment menus dismiss on changed source or selected thread', (
    tester,
  ) async {
    final controller = await _studio(tester);
    await _checkComments(tester, controller);
    await _openCommentMenu(tester, controller);
    final staleApply = _menuAction(tester, 'Comment').onTap!;
    controller.updateComment(1, text: 'Rewritten comment.');
    staleApply();
    await _pump(tester);
    expect(controller.document.comments.first.text, 'Rewritten comment.');
    expect(find.byKey(const Key('office-context-menu')), findsNothing);
    await _openCommentMenu(tester, controller);
    final staleResolve = _menuAction(tester, 'Resolve').onTap!;
    controller.selectComment(2);
    staleResolve();
    await _pump(tester);
    expect(controller.document.comments.every((c) => !c.resolved), isTrue);
    expect(find.byKey(const Key('office-context-menu')), findsNothing);
    await _close(tester);
  });

  testWidgets('comment menus preserve IME and cannot act through a modal', (
    tester,
  ) async {
    final controller = await _studio(tester);
    await _checkComments(tester, controller);
    controller.beginCommentEdit(1);
    await _pump(tester);
    controller.input.composing = const TextRange(start: 0, end: 3);
    _commentCanvas(tester, 1).onContextMenu!(
      _commentHit(tester, controller, 1),
    );
    _commentCanvas(tester, 1).onReviewTap!(_commentHit(tester, controller, 1));
    await tester.pump(kDoubleTapTimeout);
    await _pump(tester);
    expect(find.byKey(const Key('office-context-menu')), findsNothing);
    expect(controller.input.composing, const TextRange(start: 0, end: 3));
    controller.input.composing = TextRange.empty;
    await _openCommentMenu(tester, controller);
    final staleApply = _menuAction(tester, 'Comment').onTap!;
    final context = tester.element(find.byType(QudsWordEditor));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Covering dialog')),
      ),
    );
    await _pump(tester);
    staleApply();
    await _pump(tester);
    expect(controller.document.comments.first.text, 'Commet one.');
    expect(controller.canUndo, isFalse);
    Navigator.of(context).pop();
    await _pump(tester);
    await _close(tester);
  });

  testWidgets('resolved reply context offers Reopen for its whole thread', (
    tester,
  ) async {
    final controller = await _studio(tester);
    controller.document.comments.add(
      WmlComment(id: 3, text: 'Reply text.', author: 'Chris', parentId: 1),
    );
    controller.document.comments.first.resolved = true;
    controller.refresh();
    await _openCommentMenu(tester, controller, id: 3);
    expect(find.text('Reopen'), findsOneWidget);
    expect(find.text('Resolve'), findsNothing);
    await tester.tap(find.text('Reopen'));
    await _pump(tester);
    expect(controller.document.comments.first.resolved, isFalse);
    controller.undo();
    expect(controller.document.comments.first.resolved, isTrue);
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

  testWidgets('comment menu mutations respect a later viewing-mode change', (
    tester,
  ) async {
    final controller = await _studio(tester);
    await _checkComments(tester, controller);
    await _openCommentMenu(tester, controller);
    final apply = _menuAction(tester, 'Comment').onTap!;
    final resolve = _menuAction(tester, 'Resolve').onTap!;
    final delete = _menuAction(tester, 'Delete comment').onTap!;
    await tester.tap(find.text('File').first);
    await _pump(tester);
    await _tapCommand(tester, 'View');
    expect(controller.config.allowsMutation, isFalse);
    apply();
    resolve();
    delete();
    await _pump(tester);
    expect(controller.document.comments, hasLength(2));
    expect(controller.document.comments.first.text, 'Commet one.');
    expect(controller.document.comments.first.resolved, isFalse);
    expect(controller.canUndo, isFalse);
    await _close(tester);
  });
}
