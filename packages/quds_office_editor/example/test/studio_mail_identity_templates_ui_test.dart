import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_compose_tools.dart';
import 'package:quds_office_studio/studio_mail_compose_tools_dialog.dart';
import 'package:quds_office_studio/studio_mail_identity_strings.dart';
import 'package:quds_office_studio/studio_mail_threading.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);
final _account = MailAccountId(
  'account',
  profile: MailProfileId('profile', hostId: 'studio'),
);
const _alias = MailSenderIdentity(
  id: 'alias',
  name: 'Work alias',
  address: 'alias@example.test',
  displayName: 'Team',
  replyTo: 'replies@example.test',
);
const _template = MailMessageTemplate(
  id: 'update',
  name: 'Weekly update',
  to: 'new@example.test',
  cc: 'copy@example.test',
  bcc: 'private@example.test',
  subject: 'New subject',
  body: 'New body\nSecond line',
  senderIdentityId: 'alias',
);
MailComposeSettings _settings() => MailComposeSettings(
  account: _account,
  revision: 2,
  senderIdentities: const [_alias],
  templates: const [_template],
);
Finder _key(String name) => find.byKey(ValueKey('studio-mail-$name'));

final class _Tools implements StudioMailComposeToolsStore {
  _Tools(this.settings);
  MailComposeSettings settings;
  int writes = 0;
  @override
  MailAccountId get account => settings.account;
  @override
  Future<MailComposeSettings> loadComposeSettings() async => settings;
  @override
  Future<MailComposeSettings> saveComposeSettings(
    MailComposeSettings value,
  ) async {
    expect(value.revision, settings.revision);
    expect(value.account, settings.account);
    expect(value.isValid, isTrue);
    writes++;
    return settings = value.copyWith(revision: value.revision + 1);
  }
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _pump(tester);
}

Future<void> _size(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(_key(key));
  await tester.enterText(_key(key), text);
  await tester.pump();
}

void main() {
  testWidgets(
    'identity and template management save one complete settings revision',
    (tester) async {
      await _size(tester);
      final writes = <MailComposeSettings>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => StudioMailComposeToolsDialog(
                    strings: _strings,
                    initialSettings: MailComposeSettings(account: _account),
                    isCurrent: () => true,
                    onSave: (settings) async {
                      writes.add(settings);
                      return settings.copyWith(revision: 1);
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await _tap(tester, find.text('Open'));
      await _tap(tester, _key('sender-identities'));
      await _tap(tester, _key('identity-add'));
      await _enter(tester, 'identity-name', 'Work');
      await _enter(tester, 'identity-address', 'alias@example.test');
      await _enter(tester, 'identity-display', 'Writer');
      await _enter(tester, 'identity-reply-to', 'replies@example.test');
      await _tap(tester, _key('identity-apply'));
      expect(writes, isEmpty);
      await _tap(tester, _key('message-templates'));
      await _tap(tester, _key('template-add'));
      await _enter(tester, 'template-name', 'Welcome');
      await _enter(tester, 'template-to', 'reader@example.test');
      await _enter(tester, 'template-subject', 'Hello');
      final body = tester
          .widget<QudsWordEditor>(_key('template-body'))
          .controller;
      expect(body.insertPlainText('Body from the Word editor'), isTrue);
      await _pump(tester);
      await _tap(tester, _key('template-apply'));
      expect(writes, isEmpty);
      await _tap(tester, _key('compose-tools-save'));
      expect(writes, hasLength(1));
      expect(
        writes.single.senderIdentities.single.address,
        'alias@example.test',
      );
      expect(
        writes.single.senderIdentities.single.replyTo,
        'replies@example.test',
      );
      expect(writes.single.templates.single.body, 'Body from the Word editor');
      expect(writes.single.templates.single.subject, 'Hello');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'template replacement needs confirmation and clears old recipients, files and threading',
    (tester) async {
      await _size(tester);
      final saved = <StudioMailDraft>[];
      final tools = _Tools(_settings());
      final initial = StudioMailDraft(
        to: 'old@example.test',
        cc: 'old-copy@example.test',
        subject: 'Old subject',
        body: 'Old body',
        attachments: StudioMailAttachments.from([
          StudioMailAttachment(
            name: 'old.txt',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ]),
        thread: StudioMailThread.replyTo(
          MailEnvelope(messageId: '<parent@example.test>'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioMailComposeDialog(
              strings: _strings,
              from: 'account@example.test',
              allowSenderAliases: true,
              initialDraft: initial,
              composeToolsStore: tools,
              onSaveDraft: (value) async => saved.add(value),
            ),
          ),
        ),
      );
      await _pump(tester);
      await _tap(tester, _key('use-template'));
      await _tap(tester, find.text('Weekly update').last);
      expect(
        find.text(_strings.mailMessageTemplateReplaceHelp),
        findsOneWidget,
      );
      await _tap(tester, find.widgetWithText(TextButton, _strings.cancel).last);
      final body = tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .controller;
      expect(
        body.document.paragraphs.map((p) => p.text).join('\n'),
        'Old body',
      );
      await _tap(tester, _key('use-template'));
      await _tap(tester, find.text('Weekly update').last);
      await _tap(tester, _key('template-replace-confirm'));
      await tester.pump(const Duration(milliseconds: 600));
      await _pump(tester);
      expect(saved.last.to, _template.to);
      expect(saved.last.cc, _template.cc);
      expect(saved.last.bcc, _template.bcc);
      expect(saved.last.body, _template.body);
      expect(saved.last.thread.inReplyTo, isNull);
      expect(saved.last.attachments.isEmpty, isTrue);
      expect(saved.last.sender, StudioMailSender.fromIdentity(_alias));
      expect(tools.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a cloud-restricted resumed alias is preserved and cannot queue until explicitly changed',
    (tester) async {
      await _size(tester);
      final queued = <StudioMailDraft>[];
      final tools = _Tools(_settings());
      final draft = StudioMailDraft(
        to: 'reader@example.test',
        subject: 'Saved',
        body: 'Body',
        sender: StudioMailSender.fromIdentity(_alias),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioMailComposeDialog(
              strings: _strings,
              from: 'account@example.test',
              initialDraft: draft,
              composeToolsStore: tools,
              onQueueDraft: (value) async => queued.add(value),
            ),
          ),
        ),
      );
      await _pump(tester);
      expect(find.text(_strings.mailSenderRestricted), findsOneWidget);
      final queue = tester.widget<TextButton>(_key('queue'));
      expect(queue.onPressed, isNull);
      expect(queued, isEmpty);
      expect(find.text('Work alias · alias@example.test'), findsOneWidget);
      final dropdown = find.byType(DropdownButtonFormField<int>);
      await _tap(tester, dropdown);
      await _tap(
        tester,
        find.text('Account address · account@example.test').last,
      );
      expect(find.text(_strings.mailSenderRestricted), findsNothing);
      expect(tester.widget<TextButton>(_key('queue')).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account retirement while template confirmation is open cannot replace the draft',
    (tester) async {
      await _size(tester);
      var current = true;
      final tools = _Tools(_settings());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioMailComposeDialog(
              strings: _strings,
              from: 'account@example.test',
              initialDraft: const StudioMailDraft(
                to: 'old@example.test',
                subject: 'Old',
                body: 'Old body',
              ),
              composeToolsStore: tools,
              isComposeToolsCurrent: () => current,
            ),
          ),
        ),
      );
      await _pump(tester);
      await _tap(tester, _key('use-template'));
      await _tap(tester, find.text('Weekly update').last);
      current = false;
      await _tap(tester, _key('template-replace-confirm'));
      expect(find.text(_strings.mailMessageTemplateChanged), findsOneWidget);
      final body = tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .controller;
      expect(
        body.document.paragraphs.map((p) => p.text).join('\n'),
        'Old body',
      );
      expect(tools.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
