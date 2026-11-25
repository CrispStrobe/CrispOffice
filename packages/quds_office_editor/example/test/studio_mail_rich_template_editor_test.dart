import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_compose_tools_strings.dart';
import 'package:quds_office_studio/studio_mail_identity_templates.dart';
import 'package:quds_office_studio/studio_mail_rich_body.dart';
import 'package:quds_office_studio/studio_mail_rich_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);
final _account = MailAccountId(
  'rich-template-account',
  profile: MailProfileId('rich-template-profile', hostId: 'studio'),
);

Finder _key(String name) => find.byKey(ValueKey('studio-mail-$name'));

WordEditorController _body(WidgetTester tester) =>
    tester.widget<QudsWordEditor>(_key('template-body')).controller;

MailComposeBody _rich() => MailComposeBody(
  paragraphs: [
    MailComposeParagraph(
      alignment: MailComposeAlignment.center,
      rightToLeft: false,
      runs: [
        MailComposeRun(text: 'Keep ', bold: true),
        MailComposeRun(
          text: 'this link',
          italic: true,
          underline: true,
          link: 'https://example.test/details?a=1&b=2',
        ),
      ],
    ),
    MailComposeParagraph(
      alignment: MailComposeAlignment.right,
      rightToLeft: true,
      runs: [MailComposeRun(text: 'مرحبا', strike: true)],
    ),
  ],
);

MailMessageTemplate _template(MailComposeBody body) => MailMessageTemplate(
  id: 'saved-rich-template',
  name: 'Saved rich template',
  to: 'reader@example.test',
  bcc: 'private@example.test',
  subject: 'Saved subject',
  body: body.plainText,
  richBody: body,
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _pump(tester);
}

Future<void> _open(
  WidgetTester tester, {
  required MailMessageTemplate initial,
  required ValueChanged<MailMessageTemplate?> onResult,
  bool Function()? isCurrent,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              onResult(
                await showStudioMailTemplateEditor(
                  context,
                  strings: _strings,
                  settings: MailComposeSettings(
                    account: _account,
                    templates: [initial],
                  ),
                  initial: initial,
                  isCurrent: isCurrent ?? () => true,
                ),
              );
            },
            child: const Text('Open rich template'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open rich template'));
}

void main() {
  testWidgets(
    'metadata edits preserve canonical formatting and reopening restores it',
    (tester) async {
      final rich = _rich();
      final original = _template(rich);
      MailMessageTemplate? saved;
      await _open(
        tester,
        initial: original,
        onResult: (value) => saved = value,
      );
      expect(
        studioMailRichBodyFromDocument(_body(tester).document).html,
        rich.html,
      );
      await tester.ensureVisible(_key('template-subject'));
      await tester.enterText(_key('template-subject'), 'Edited subject');
      await _tap(tester, _key('template-apply'));
      expect(saved, isNotNull);
      expect(saved!.id, original.id);
      expect(saved!.subject, 'Edited subject');
      expect(saved!.bcc, original.bcc);
      expect(saved!.body, rich.plainText);
      expect(saved!.richBody!.html, rich.html);
      expect(original.subject, 'Saved subject');

      final firstSave = saved!;
      await tester.pumpWidget(const SizedBox.shrink());
      await _open(
        tester,
        initial: firstSave,
        onResult: (value) => saved = value,
      );
      final paragraphs = _body(tester).document.paragraphs.toList();
      expect(paragraphs.first.properties.justification, WmlJustification.center);
      expect(paragraphs.first.properties.rightToLeft, isFalse);
      expect(paragraphs.last.properties.rightToLeft, isTrue);
      final runs = paragraphs.first.inlines.whereType<WmlRun>().toList();
      expect(runs.first.properties.bold, isTrue);
      expect(runs.last.hyperlink!.url, 'https://example.test/details?a=1&b=2');
      expect(runs.last.properties.underline, WmlUnderline.single);
      await _tap(tester, _key('template-apply'));
      expect(saved!.richBody!.html, rich.html);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing rich text retains its styles and the original snapshot', (
    tester,
  ) async {
    final rich = _rich();
    final originalHtml = rich.html;
    MailMessageTemplate? saved;
    await _open(
      tester,
      initial: _template(rich),
      onResult: (value) => saved = value,
    );
    final body = _body(tester);
    body.documentCaret
      ..paragraphIndex = 0
      ..logicalIndex = 2
      ..collapseSelection();
    body.insertText('NEW');
    await _pump(tester);
    final expected = studioMailRichBodyFromDocument(body.document);
    await _tap(tester, _key('template-apply'));
    expect(saved!.body, 'KeNEWep this link\nمرحبا');
    expect(saved!.richBody!.html, expected.html);
    expect(
      saved!.richBody!.paragraphs.first.runs.any(
        (run) => run.bold && run.text.contains('NEW'),
      ),
      isTrue,
    );
    expect(rich.html, originalHtml);
    expect(rich.plainText, 'Keep this link\nمرحبا');
    expect(tester.takeException(), isNull);
  });

  testWidgets('formatting-only template edits keep matching plain text', (
    tester,
  ) async {
    const original = MailMessageTemplate(
      id: 'plain',
      name: 'Plain',
      body: 'Unchanged text',
    );
    MailMessageTemplate? saved;
    await _open(
      tester,
      initial: original,
      onResult: (value) => saved = value,
    );
    final body = _body(tester);
    body.selectAll();
    body.applyRunFormat((props) => props.bold = true);
    await _pump(tester);
    await _tap(tester, _key('template-apply'));
    expect(saved!.body, original.body);
    expect(saved!.richBody!.paragraphs.single.runs.single.bold, isTrue);
    expect(original.richBody, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported formatting refuses replacement until Undo', (
    tester,
  ) async {
    final rich = _rich();
    MailMessageTemplate? saved;
    await _open(
      tester,
      initial: _template(rich),
      onResult: (value) => saved = value,
    );
    final body = _body(tester);
    body.selectAll();
    body.applyRunFormat((props) => props.color = 'FF0000');
    await _pump(tester);
    await _tap(tester, _key('template-apply'));
    expect(saved, isNull);
    expect(_key('template-rich-unsupported'), findsOneWidget);
    expect(find.text(_strings.mailRichUnsupported), findsOneWidget);
    expect(
      body.document.paragraphs.first.inlines
          .whereType<WmlRun>()
          .first
          .properties
          .color,
      'FF0000',
    );
    body.undo();
    await _pump(tester);
    await _tap(tester, _key('template-apply'));
    expect(saved!.richBody!.html, rich.html);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inconsistent initial alternatives remain recoverable without replacement',
    (tester) async {
      final rich = _rich();
      final original = _template(rich).copyWith(body: 'Saved plain text');
      var completed = false;
      MailMessageTemplate? saved;
      await _open(
        tester,
        initial: original,
        onResult: (value) {
          completed = true;
          saved = value;
        },
      );
      expect(
        _body(tester).document.paragraphs.map((p) => p.text).join('\n'),
        'Saved plain text',
      );
      expect(_key('template-rich-conflict'), findsOneWidget);
      expect(find.text(_strings.mailRichTemplateConflict), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_key('template-apply')).onPressed,
        isNull,
      );
      expect(completed, isFalse);
      await _tap(tester, find.widgetWithText(TextButton, _strings.cancel));
      expect(completed, isTrue);
      expect(saved, isNull);
      expect(original.body, 'Saved plain text');
      expect(original.richBody!.html, rich.html);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a retained Apply callback cannot return a retired owner edit', (
    tester,
  ) async {
    var current = true;
    var completed = false;
    final rich = _rich();
    await _open(
      tester,
      initial: _template(rich),
      onResult: (_) => completed = true,
      isCurrent: () => current,
    );
    final apply = tester.widget<FilledButton>(_key('template-apply')).onPressed!;
    current = false;
    apply();
    await _pump(tester);
    expect(completed, isFalse);
    expect(_key('template-body'), findsOneWidget);
    expect(find.text(_strings.mailComposeToolsStale), findsOneWidget);
    expect(
      tester.widget<FilledButton>(_key('template-apply')).onPressed,
      isNull,
    );
    expect(
      studioMailRichBodyFromDocument(_body(tester).document).html,
      rich.html,
    );
    await _tap(tester, find.widgetWithText(TextButton, _strings.cancel));
    expect(completed, isTrue);
    apply();
    await _pump(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large legacy plain templates do not acquire a rich HTML budget', (
    tester,
  ) async {
    final text = List.filled(MailMessageTemplate.maxBodyCodeUnits, '<').join();
    final original = MailMessageTemplate(
      id: 'long-plain',
      name: 'Long plain',
      body: text,
    );
    MailMessageTemplate? saved;
    await _open(
      tester,
      initial: original,
      onResult: (value) => saved = value,
    );
    await _tap(tester, _key('template-apply'));
    expect(saved!.body, text);
    expect(saved!.richBody, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a newer pending settings object retires an open template editor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final initial = MailComposeSettings(
      account: _account,
      revision: 7,
      templates: [_template(_rich())],
    );
    final pending = ValueNotifier(initial);
    addTearDown(pending.dispose);
    final changes = <MailComposeSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<MailComposeSettings>(
            valueListenable: pending,
            builder: (context, settings, child) => StudioMailIdentityTemplates(
              strings: _strings,
              settings: settings,
              isCurrent: () => true,
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await _tap(tester, _key('message-templates'));
    await _tap(tester, _key('template-edit-saved-rich-template'));
    final apply = tester.widget<FilledButton>(_key('template-apply')).onPressed!;
    pending.value = initial.copyWith(signature: 'New pending signature');
    await _pump(tester);
    expect(pending.value.revision, initial.revision);
    apply();
    await _pump(tester);
    expect(changes, isEmpty);
    expect(_key('template-body'), findsOneWidget);
    expect(find.text(_strings.mailComposeToolsStale), findsOneWidget);
    await _tap(tester, find.widgetWithText(TextButton, _strings.cancel));
    expect(changes, isEmpty);
    expect(pending.value.signature, 'New pending signature');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
