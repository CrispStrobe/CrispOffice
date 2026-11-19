import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';
import 'package:quds_office_studio/studio_mail_threading.dart';
import 'package:quds_office_studio/studio_strings.dart';

const strings = StudioStrings(StudioLanguage.en);
const sender = 'writer@example.invalid';

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _open(
  WidgetTester tester,
  ValueChanged<StudioMailDraft?> result, {
  StudioMailDraft? initial,
  bool uncertain = false,
  Size size = const Size(1100, 850),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result(
              await showDialog<StudioMailDraft>(
                context: context,
                builder: (_) => StudioMailComposeDialog(
                  strings: strings,
                  from: sender,
                  initialDraft: initial,
                  previousSubmissionUncertain: uncertain,
                ),
              ),
            ),
            child: const Text('Compose fixture'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Compose fixture'));
  await _pump(tester);
}

void main() {
  for (final address in <String>[
    '',
    'a@example.invalid,,b@example.invalid',
    'Name <a@example.invalid>',
    'a@',
    '@example.invalid',
    'a..b@example.invalid',
    '.a@example.invalid',
    'a.@example.invalid',
    'a@-example.invalid',
    'a@exam ple.invalid',
    'a@example.invalid\r\nBcc: hidden@example.invalid',
    'مستخدم@example.invalid',
  ]) {
    test('rejects unsupported recipient ${jsonEncode(address)}', () {
      final draft = StudioMailDraft(
        to: address,
        subject: 'Subject',
        body: 'Body',
      );
      expect(draft.problem, StudioMailDraftProblem.recipient);
      expect(
        () => buildStudioMailMessage(draft, sender),
        throwsFormatException,
      );
    });
  }

  test(
    'accepts supported mailbox punctuation and rejects header injection',
    () {
      expect(
        StudioMailDraft.isSupportedAddress('first.last+tag@example.invalid'),
        isTrue,
      );
      const draft = StudioMailDraft(
        to: 'reader@example.invalid',
        subject: 'Normal\r\nBcc: hidden@example.invalid',
        body: 'Body',
      );
      expect(draft.problem, StudioMailDraftProblem.subject);
      expect(
        () => buildStudioMailMessage(draft, sender),
        throwsFormatException,
      );
    },
  );

  test('bounds encoded body size and rejects null characters', () {
    expect(
      const StudioMailDraft(to: sender, subject: '', body: 'a\u0000b').problem,
      StudioMailDraftProblem.body,
    );
    final boundary = 'ب' * (StudioMailDraft.maxBodyBytes ~/ 2);
    expect(
      StudioMailDraft(to: sender, subject: '', body: boundary).problem,
      isNull,
    );
    expect(
      StudioMailDraft(to: sender, subject: '', body: '$boundary\u0628').problem,
      StudioMailDraftProblem.body,
    );
  });

  test('Arabic subject and body produce ASCII-safe MIME with exact decoded content', () {
    const draft = StudioMailDraft(
      to: 'reader@example.invalid',
      subject: 'رسالة اختبار',
      body: 'مرحبًا <reader> & أهلًا',
    );
    final message = buildStudioMailMessage(draft, sender);
    expect(
      message.renderMessage().codeUnits.every((unit) => unit < 128),
      isTrue,
    );
    expect(message.decodeSubject(), draft.subject);
    expect(message.decodeTextPlainPart(), draft.body);
    expect(message.decodeTextHtmlPart(), contains('&lt;reader&gt; &amp;'));
    expect(message.to!.single.email, draft.to);
    expect(message.bcc, isEmpty);
    expect(
      () => buildStudioMailMessage(draft, '$sender\r\nX-Extra: bad'),
      throwsFormatException,
    );
  });

  testWidgets(
    'body uses the Word editor and snapshots undoable text before disposal',
    (tester) async {
      StudioMailDraft? snapshot;
      await _open(tester, (value) => snapshot = value);
      expect(find.byType(TextField), findsNWidgets(2));
      final body = tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .controller;
      await tester.enterText(_field(strings.to), 'reader@example.invalid');
      await tester.enterText(_field(strings.subject), 'Snapshot');
      body.insertText('Hello مرحبًا');
      body.undo();
      expect(body.document.paragraphs.single.text, isEmpty);
      body.redo();
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, strings.send));
      await _pump(tester);
      expect(snapshot?.body, 'Hello مرحبًا');
      expect(snapshot?.subject, 'Snapshot');
      expect(snapshot?.thread.inReplyTo, isNull);
      expect(snapshot?.thread.references, isNull);
      expect(body.isDisposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid recipient keeps the draft open with bounded feedback', (
    tester,
  ) async {
    StudioMailDraft? snapshot;
    await _open(tester, (value) => snapshot = value);
    await tester.enterText(_field(strings.to), 'not-an-address');
    await tester.tap(find.widgetWithText(FilledButton, strings.send));
    await tester.pump();
    expect(snapshot, isNull);
    expect(find.text(strings.mailInvalidRecipient), findsOneWidget);
    expect(find.byType(StudioMailComposeDialog), findsOneWidget);
    await tester.tap(find.text(strings.cancel));
    await _pump(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'uncertain draft is retained and requires explicit resend acknowledgement',
    (tester) async {
      final thread = StudioMailThread.replyTo(
        MailEnvelope(
          messageId: '<parent@example.invalid>',
          references: const ['<root@example.invalid>'],
        ),
      );
      final initial = StudioMailDraft(
        to: sender,
        cc: 'copy@example.invalid',
        bcc: 'hidden@example.invalid',
        subject: 'Retained',
        body: 'Do not lose this.',
        thread: thread,
      );
      StudioMailDraft? snapshot;
      await _open(
        tester,
        (value) => snapshot = value,
        initial: initial,
        uncertain: true,
      );
      final send = find.widgetWithText(FilledButton, strings.send);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(
        tester.widget<TextField>(_field(strings.to)).controller!.text,
        initial.to,
      );
      expect(
        tester.widget<TextField>(_field(strings.mailCc)).controller!.text,
        initial.cc,
      );
      expect(
        tester.widget<TextField>(_field(strings.mailBcc)).controller!.text,
        initial.bcc,
      );
      final body = tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .controller;
      expect(body.document.paragraphs.single.text, initial.body);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await _pump(tester);
      expect(snapshot?.body, initial.body);
      expect(snapshot?.cc, initial.cc);
      expect(snapshot?.bcc, initial.bcc);
      expect(snapshot?.thread, same(thread));
      final message = buildStudioMailMessage(snapshot!, sender);
      expect(message.getHeaderValue('in-reply-to'), '<parent@example.invalid>');
      expect(
        message.getHeaderValue('references'),
        '<root@example.invalid> <parent@example.invalid>',
      );
      expect(body.isDisposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing a reply preserves its immutable thread snapshot', (
    tester,
  ) async {
    final thread = StudioMailThread.replyTo(
      MailEnvelope(
        messageId: '<parent@example.invalid>',
        references: const ['<root@example.invalid>'],
      ),
    );
    final initial = StudioMailDraft(
      to: sender,
      cc: 'copy@example.invalid',
      bcc: 'hidden@example.invalid',
      subject: 'Re: Original subject',
      body: 'Initial body',
      thread: thread,
    );
    StudioMailDraft? snapshot;
    await _open(tester, (value) => snapshot = value, initial: initial);
    await tester.enterText(_field(strings.to), 'different@example.invalid');
    await tester.enterText(_field(strings.mailCc), 'new-copy@example.invalid');
    await tester.enterText(
      _field(strings.mailBcc),
      'new-hidden@example.invalid',
    );
    await tester.enterText(_field(strings.subject), 'Edited subject');
    final body = tester
        .widget<QudsWordEditor>(find.byType(QudsWordEditor))
        .controller;
    body.insertText('Added text ');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, strings.send));
    await tester.tap(find.widgetWithText(FilledButton, strings.send));
    await _pump(tester);
    expect(snapshot?.to, 'different@example.invalid');
    expect(snapshot?.cc, 'new-copy@example.invalid');
    expect(snapshot?.bcc, 'new-hidden@example.invalid');
    expect(snapshot?.subject, 'Edited subject');
    expect(snapshot?.body, contains('Added text '));
    expect(snapshot?.thread, same(thread));
    expect(initial.to, sender);
    expect(initial.cc, 'copy@example.invalid');
    expect(initial.bcc, 'hidden@example.invalid');
    expect(initial.subject, 'Re: Original subject');
    expect(initial.body, 'Initial body');
    expect(body.isDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'composer fits a narrow window without substituting a body text field',
    (tester) async {
      await _open(tester, (_) {}, size: const Size(390, 720));
      expect(find.byType(QudsWordEditor), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(strings.cancel));
      await _pump(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cc and Bcc remain editable and sendable in a narrow window', (
    tester,
  ) async {
    StudioMailDraft? snapshot;
    await _open(
      tester,
      (value) => snapshot = value,
      size: const Size(390, 720),
    );
    await tester.tap(find.text(strings.mailCopyRecipients));
    await _pump(tester);
    expect(find.byType(TextField), findsNWidgets(4));
    await tester.enterText(
      _field(strings.to),
      'one@example.invalid; two@example.invalid',
    );
    await tester.enterText(_field(strings.mailCc), 'copy@example.invalid');
    await tester.enterText(_field(strings.mailBcc), 'hidden@example.invalid');
    final body = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
    body.controller.insertText('Group message');
    final send = find.widgetWithText(FilledButton, strings.send);
    await tester.ensureVisible(send);
    await _pump(tester);
    await tester.tap(send);
    await _pump(tester);
    expect(snapshot?.recipients.envelope, [
      'one@example.invalid',
      'two@example.invalid',
      'copy@example.invalid',
      'hidden@example.invalid',
    ]);
    expect(snapshot?.body, 'Group message');
    expect(body.controller.isDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invalid hidden recipient blocks submission without losing input',
    (tester) async {
      StudioMailDraft? snapshot;
      await _open(tester, (value) => snapshot = value);
      await tester.tap(find.text(strings.mailCopyRecipients));
      await tester.pump();
      await tester.enterText(_field(strings.to), 'one@example.invalid');
      await tester.enterText(_field(strings.mailBcc), 'not-an-address');
      final send = find.widgetWithText(FilledButton, strings.send);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pump();
      expect(snapshot, isNull);
      expect(find.text(strings.mailInvalidRecipient), findsOneWidget);
      expect(
        tester.widget<TextField>(_field(strings.mailBcc)).controller!.text,
        'not-an-address',
      );
      await tester.enterText(_field(strings.mailBcc), 'hidden@example.invalid');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await _pump(tester);
      expect(snapshot?.bcc, 'hidden@example.invalid');
      expect(tester.takeException(), isNull);
    },
  );

  for (final keyboard in <bool>[false, true]) {
    testWidgets(
      'uncertain composer scrolls in a short ${keyboard ? 'keyboard' : 'landscape'} window',
      (tester) async {
        StudioMailDraft? snapshot;
        await _open(
          tester,
          (value) => snapshot = value,
          initial: const StudioMailDraft(
            to: sender,
            subject: 'Keep the draft',
            body: 'Retained in the short window.',
          ),
          uncertain: true,
          size: keyboard ? const Size(390, 320) : const Size(640, 360),
        );
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        if (keyboard) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 120);
          addTearDown(tester.view.resetViewInsets);
        }
        await _pump(tester);
        expect(tester.takeException(), isNull);
        final body = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
        expect(
          tester.getSize(find.byType(QudsWordEditor)).height,
          greaterThanOrEqualTo(180),
        );
        final acknowledgement = find.byType(CheckboxListTile);
        await tester.ensureVisible(acknowledgement);
        await _pump(tester);
        await tester.tap(acknowledgement);
        await _pump(tester);
        final send = find.widgetWithText(FilledButton, strings.send);
        await tester.ensureVisible(send);
        await _pump(tester);
        await tester.tap(send);
        await _pump(tester);
        expect(snapshot?.body, 'Retained in the short window.');
        expect(body.controller.isDisposed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
