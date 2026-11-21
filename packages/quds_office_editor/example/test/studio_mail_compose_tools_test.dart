import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_compose_tools.dart';
import 'package:quds_office_studio/studio_mail_compose_tools_dialog.dart';
import 'package:quds_office_studio/studio_mail_compose_tools_strings.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);

Finder _key(String suffix) => find.byKey(ValueKey('studio-mail-$suffix'));

MailComposeSettings _settings({
  String signature = 'Regards\r\nWriter',
  bool automatic = true,
}) => MailComposeSettings(
  account: MailAccountId(
    'writer',
    profile: MailProfileId('profile', hostId: 'studio'),
  ),
  revision: 3,
  signature: signature,
  signatureForNewMessages: automatic,
  signatureForReplies: automatic,
  quickTexts: const [
    MailQuickText(
      id: 'steps',
      name: 'Steps',
      text: 'First\r\nSecond\rThird',
    ),
  ],
);

StudioMailDraft _draft(String body) => StudioMailDraft(
  to: 'reader@example.test',
  subject: 'Working draft',
  body: body,
);

final class _Tools implements StudioMailComposeToolsStore {
  _Tools(this.settings);

  MailComposeSettings settings;
  int loads = 0;
  int saves = 0;
  bool failLoad = false;
  bool failAfterSave = false;
  Completer<MailComposeSettings>? loadGate;

  @override
  MailAccountId get account => settings.account;

  @override
  Future<MailComposeSettings> loadComposeSettings() async {
    loads++;
    if (failLoad) throw const StudioMailComposeToolsException();
    final gate = loadGate;
    if (gate != null) return gate.future;
    return settings;
  }

  @override
  Future<MailComposeSettings> saveComposeSettings(
    MailComposeSettings candidate,
  ) async {
    saves++;
    if (candidate.account != account ||
        candidate.revision != settings.revision ||
        !candidate.isValid) {
      throw const StudioMailComposeToolsException();
    }
    settings = candidate.copyWith(revision: candidate.revision + 1);
    if (failAfterSave) throw StateError('Lost save acknowledgement');
    return settings;
  }
}

final class _Host {
  _Host({this.tools, this.initial, this.autosave = true});

  final _Tools? tools;
  final StudioMailDraft? initial;
  final bool autosave;
  final drafts = <StudioMailDraft>[];
  final queued = <StudioMailDraft>[];
  bool current = true;
  bool returned = false;
  StudioMailDraft? result;
}

WordEditorController _body(WidgetTester tester) =>
    tester.widget<QudsWordEditor>(find.byType(QudsWordEditor)).controller;

String _text(WordEditorController body) =>
    body.document.paragraphs.map((paragraph) => paragraph.text).join('\n');

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _flush(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await _pump(tester);
}

Future<void> _open(WidgetTester tester, _Host host) async {
  await tester.binding.setSurfaceSize(const Size(1100, 850));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              host.result = await showDialog<StudioMailDraft>(
                context: context,
                barrierDismissible: false,
                builder: (_) => StudioMailComposeDialog(
                  strings: _strings,
                  from: 'writer@example.test',
                  initialDraft: host.initial,
                  composeToolsStore: host.tools,
                  isComposeToolsCurrent: () => host.current,
                  onSaveDraft: host.autosave
                      ? (draft) async => host.drafts.add(draft)
                      : null,
                  onQueueDraft: (draft) async => host.queued.add(draft),
                ),
              );
              host.returned = true;
            },
            child: const Text('Open writing-tools composer'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open writing-tools composer'));
  await _pump(tester);
}

Future<void> _close(WidgetTester tester, _Host host) async {
  await _tap(
    tester,
    find.widgetWithText(
      TextButton,
      host.autosave ? _strings.mailDraftSaveClose : _strings.cancel,
    ),
  );
  expect(host.returned, isTrue);
  expect(host.result, isNull);
  expect(host.queued, isEmpty);
  expect(find.byType(StudioMailComposeDialog), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _insertSteps(WidgetTester tester) async {
  await _tap(tester, _key('insert-quick-text'));
  await _tap(tester, find.text('Steps').last);
}

void main() {
  testWidgets('new message defaults leave the caret above the saved signature', (
    tester,
  ) async {
    final tools = _Tools(_settings());
    final host = _Host(tools: tools);
    await _open(tester, host);
    final body = _body(tester);
    expect(_text(body), '\n\n-- \nRegards\nWriter');
    expect(body.caret.paragraphIndex, 0);
    expect(body.caret.logicalIndex, 0);
    expect(tools.loads, 1);
    expect(tools.saves, 0);
    await _flush(tester);
    expect(host.drafts, hasLength(1));
    expect(host.drafts.single.body, '\n\n-- \nRegards\nWriter');
    expect(host.queued, isEmpty);
    expect(host.returned, isFalse);
    await _close(tester, host);
  });

  testWidgets('resuming saved mail never injects or replaces its signature', (
    tester,
  ) async {
    const original = 'Unfinished reply\n\n-- \nEarlier signature';
    const initial = StudioMailDraft(
      to: 'reader@example.test',
      cc: 'copy@example.test',
      bcc: 'private@example.test',
      subject: 'Saved reply',
      body: original,
    );
    final tools = _Tools(_settings(signature: 'Different current signature'));
    final host = _Host(tools: tools, initial: initial);
    await _open(tester, host);
    expect(_text(_body(tester)), original);
    await _flush(tester);
    expect(host.drafts.last.body, original);
    expect(host.drafts.last.to, initial.to);
    expect(host.drafts.last.cc, initial.cc);
    expect(host.drafts.last.bcc, initial.bcc);
    expect(tools.saves, 0);
    expect(host.returned, isFalse);
    await _close(tester, host);
  });

  testWidgets('multiline Quick Text replaces selection in one undoable edit', (
    tester,
  ) async {
    const original = 'Left selected right';
    const inserted = 'Left First\nSecond\nThird right';
    final tools = _Tools(_settings());
    final host = _Host(tools: tools, initial: _draft(original));
    await _open(tester, host);
    await _flush(tester);
    final body = _body(tester);
    body.caret
      ..selectionAnchorParagraph = 0
      ..selectionAnchor = 5
      ..paragraphIndex = 0
      ..logicalIndex = 13;

    await _insertSteps(tester);
    expect(_text(body), inserted);
    expect(
      body.document.paragraphs.map((paragraph) => paragraph.text),
      ['Left First', 'Second', 'Third right'],
    );
    await _flush(tester);
    expect(host.drafts.last.body, inserted);

    body.undo();
    expect(_text(body), original);
    await _flush(tester);
    expect(host.drafts.last.body, original);
    body.redo();
    expect(_text(body), inserted);
    await _flush(tester);
    expect(host.drafts.last.body, inserted);
    expect(tools.saves, 0);
    expect(host.queued, isEmpty);
    expect(host.returned, isFalse);
    await _close(tester, host);
  });

  testWidgets('manual signature insertion uses the current text selection', (
    tester,
  ) async {
    const original = 'Left old right';
    final tools = _Tools(_settings(signature: 'Writer', automatic: false));
    final host = _Host(tools: tools, initial: _draft(original));
    await _open(tester, host);
    final body = _body(tester);
    body.caret
      ..selectionAnchorParagraph = 0
      ..selectionAnchor = 5
      ..paragraphIndex = 0
      ..logicalIndex = 8;
    await _tap(tester, _key('insert-signature'));
    expect(_text(body), 'Left \n\n-- \nWriter right');
    body.undo();
    expect(_text(body), original);
    expect(tools.saves, 0);
    await _close(tester, host);
  });

  testWidgets('manager saves update tools without rewriting the live draft', (
    tester,
  ) async {
    const original = 'Keep this text';
    final tools = _Tools(_settings(signature: 'Old signature'));
    final host = _Host(tools: tools, initial: _draft(original));
    await _open(tester, host);
    final body = _body(tester);
    await _tap(tester, _key('compose-tools'));
    expect(find.byType(StudioMailComposeToolsDialog), findsOneWidget);
    await tester.enterText(_key('compose-signature'), 'New signature');
    await _tap(tester, _key('compose-tools-save'));

    expect(find.byType(StudioMailComposeToolsDialog), findsNothing);
    expect(tools.saves, 1);
    expect(tools.loads, 2);
    expect(tools.settings.signature, 'New signature');
    expect(_text(body), original);
    expect(host.queued, isEmpty);
    expect(host.returned, isFalse);

    body.caret
      ..paragraphIndex = 0
      ..logicalIndex = original.length
      ..collapseSelection();
    await _tap(tester, _key('insert-signature'));
    expect(_text(body), '$original\n\n-- \nNew signature');
    await _flush(tester);
    expect(host.drafts.last.body, '$original\n\n-- \nNew signature');
    await _close(tester, host);
  });

  testWidgets('retained tools callbacks cannot mutate a stale account', (
    tester,
  ) async {
    const original = 'Keep this draft';
    final tools = _Tools(_settings());
    final host = _Host(tools: tools, initial: _draft(original));
    await _open(tester, host);
    await _flush(tester);
    final body = _body(tester);
    final insertSignature = tester
        .widget<TextButton>(_key('insert-signature'))
        .onPressed!;
    final selectText = tester
        .widget<PopupMenuButton<MailQuickText>>(_key('insert-quick-text'))
        .onSelected!;
    final manage = tester
        .widget<TextButton>(_key('compose-tools'))
        .onPressed!;
    host.current = false;
    insertSignature();
    selectText(tools.settings.quickTexts.single);
    manage();
    await _pump(tester);
    expect(_text(body), original);
    expect(find.byType(StudioMailComposeToolsDialog), findsNothing);
    expect(host.drafts, hasLength(1));
    expect(tools.loads, 1);
    expect(tools.saves, 0);
    expect(host.queued, isEmpty);
    expect(host.returned, isFalse);
    await _close(tester, host);
  });

  testWidgets('a late tools load cannot sign a different active account', (
    tester,
  ) async {
    final tools = _Tools(_settings());
    final gate = Completer<MailComposeSettings>();
    tools.loadGate = gate;
    final host = _Host(tools: tools);
    await _open(tester, host);
    expect(find.text(_strings.mailComposeToolsLoading), findsOneWidget);
    expect(_text(_body(tester)), isEmpty);
    host.current = false;
    gate.complete(tools.settings);
    await _pump(tester);
    expect(_text(_body(tester)), isEmpty);
    expect(
      tester.widget<TextButton>(_key('insert-signature')).onPressed,
      isNull,
    );
    expect(host.drafts, isEmpty);
    expect(tools.saves, 0);
    await _close(tester, host);
  });

  testWidgets('an initially stale new composer is not trapped behind loading', (
    tester,
  ) async {
    final tools = _Tools(_settings());
    final host = _Host(tools: tools, autosave: false)..current = false;
    await _open(tester, host);
    expect(tools.loads, 0);
    expect(_text(_body(tester)), isEmpty);
    expect(find.text(_strings.mailComposeToolsLoading), findsNothing);
    expect(
      tester.widget<TextButton>(_key('insert-signature')).onPressed,
      isNull,
    );
    await _close(tester, host);
    expect(tools.saves, 0);
    expect(host.drafts, isEmpty);
  });

  testWidgets('reload after load failure leaves intervening body edits intact', (
    tester,
  ) async {
    final tools = _Tools(_settings())..failLoad = true;
    final host = _Host(tools: tools);
    await _open(tester, host);
    expect(find.text(_strings.mailComposeToolsLoadFailed), findsOneWidget);
    expect(_text(_body(tester)), isEmpty);
    _body(tester).insertText('Handwritten message');
    await tester.pump();
    tools.failLoad = false;
    await _tap(tester, _key('reload-compose-tools'));
    expect(find.text(_strings.mailComposeToolsLoadFailed), findsNothing);
    expect(_text(_body(tester)), 'Handwritten message');
    expect(tools.loads, 2);
    expect(
      tester.widget<TextButton>(_key('insert-signature')).onPressed,
      isNotNull,
    );
    await _flush(tester);
    expect(host.drafts.last.body, 'Handwritten message');
    expect(host.returned, isFalse);
    expect(tools.saves, 0);
    await _close(tester, host);
  });

  testWidgets('uncertain manager saves are reloaded before another edit', (
    tester,
  ) async {
    const original = 'My current draft';
    final tools = _Tools(_settings())..failAfterSave = true;
    final host = _Host(tools: tools, initial: _draft(original));
    await _open(tester, host);
    final body = _body(tester);
    await _tap(tester, _key('compose-tools'));
    await tester.enterText(_key('compose-signature'), 'Actually persisted');
    await _tap(tester, _key('compose-tools-save'));
    expect(find.text(_strings.mailComposeToolsSaveUnconfirmed), findsOneWidget);
    expect(tools.saves, 1);
    expect(find.byType(StudioMailComposeToolsDialog), findsOneWidget);
    expect(
      tester.widget<FilledButton>(_key('compose-tools-save')).onPressed,
      isNull,
    );
    await _tap(tester, _key('compose-tools-close'));
    expect(tools.loads, 2);
    expect(_text(body), original);

    tools.failAfterSave = false;
    await _tap(tester, _key('compose-tools'));
    expect(
      tester.widget<TextField>(_key('compose-signature')).controller!.text,
      'Actually persisted',
    );
    await tester.enterText(_key('compose-signature'), 'Reviewed revision');
    await _tap(tester, _key('compose-tools-save'));
    expect(tools.saves, 2);
    expect(tools.settings.revision, 5);
    expect(tools.settings.signature, 'Reviewed revision');
    expect(_text(body), original);
    expect(host.queued, isEmpty);
    expect(host.returned, isFalse);
    await _close(tester, host);
  });

  testWidgets(
    'partial cross-paragraph insertion refuses safely and whole-message selection works',
    (tester) async {
      final tools = _Tools(_settings());
      final host = _Host(tools: tools, initial: _draft(''));
      await _open(tester, host);
      final body = _body(tester);
      const original = 'First paragraph\nSecond paragraph';
      expect(body.insertPlainText(original), isTrue);
      await _flush(tester);
      final savedBefore = host.drafts.length;
      body.caret
        ..selectionAnchorParagraph = 0
        ..selectionAnchor = 5
        ..paragraphIndex = 1
        ..logicalIndex = 6;

      await _insertSteps(tester);
      expect(_text(body), original);
      expect(
        find.text(_strings.mailComposeToolsSelectionFailed),
        findsOneWidget,
      );
      await _flush(tester);
      expect(host.drafts, hasLength(savedBefore));

      body.selectAll();
      await _insertSteps(tester);
      expect(_text(body), 'First\nSecond\nThird');
      expect(
        find.text(_strings.mailComposeToolsSelectionFailed),
        findsNothing,
      );
      await _flush(tester);
      expect(host.drafts.last.body, 'First\nSecond\nThird');
      body.undo();
      expect(_text(body), original);
      expect(tools.saves, 0);
      expect(host.queued, isEmpty);
      expect(host.returned, isFalse);
      await _close(tester, host);
    },
  );

  testWidgets('legacy compose hosts retain editing without writing-tool UI', (
    tester,
  ) async {
    final host = _Host(initial: _draft('Legacy body'));
    await _open(tester, host);
    expect(_key('compose-tools'), findsNothing);
    expect(_key('insert-signature'), findsNothing);
    expect(_key('insert-quick-text'), findsNothing);
    expect(_key('reload-compose-tools'), findsNothing);
    final body = _body(tester);
    body.insertText('Edited ');
    await _flush(tester);
    expect(host.drafts.last.body, contains('Edited '));
    expect(host.drafts.last.body, contains('Legacy body'));
    expect(find.byType(QudsWordEditor), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(host.returned, isFalse);
    await _close(tester, host);
  });
}
