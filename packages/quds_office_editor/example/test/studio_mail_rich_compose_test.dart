import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_compose_tools.dart';
import 'package:quds_office_studio/studio_mail_rich_strings.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_mail_threading.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _sender = 'writer@example.test';
const _plain = StudioMailDraft(
  to: 'reader@example.test',
  subject: 'Rich composition',
  body: 'Keep this text',
);

Finder _key(String suffix) => find.byKey(ValueKey('studio-mail-$suffix'));

WordEditorController _body(WidgetTester tester) =>
    tester.widget<QudsWordEditor>(_key('compose-body')).controller;

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
  StudioMailDraft initial = _plain,
  StudioLanguage language = StudioLanguage.en,
  Future<void> Function(StudioMailDraft)? save,
  ValueChanged<StudioMailDraft?>? finish,
  StudioMailComposeToolsStore? tools,
  Size size = const Size(1100, 900),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final value = await showDialog<StudioMailDraft>(
                context: context,
                builder: (_) => Directionality(
                  textDirection: language == StudioLanguage.ar
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: StudioMailComposeDialog(
                    strings: StudioStrings(language),
                    from: _sender,
                    initialDraft: initial,
                    onSaveDraft: save,
                    composeToolsStore: tools,
                  ),
                ),
              );
              finish?.call(value);
            },
            child: const Text('Open mail fixture'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open mail fixture'));
}

MailComposeBody _rich() => MailComposeBody(
  paragraphs: [
    MailComposeParagraph(
      alignment: MailComposeAlignment.center,
      runs: [
        MailComposeRun(text: 'Keep ', bold: true),
        MailComposeRun(
          text: 'this text',
          italic: true,
          link: 'https://example.test/details?a=1&b=2',
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets(
    'conflicting initial alternatives are displayed without overwriting the saved draft',
    (tester) async {
      final saved = <StudioMailDraft>[];
      StudioMailDraft? sent;
      await _open(
        tester,
        initial: StudioMailDraft(
          to: _plain.to,
          subject: _plain.subject,
          body: 'Original plain text',
          richBody: _rich(),
        ),
        save: (draft) async => saved.add(draft),
        finish: (value) => sent = value,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        _body(tester).document.paragraphs.single.text,
        'Original plain text',
      );
      expect(find.text(_strings.mailRichConflict), findsOneWidget);
      expect(saved, isEmpty);
      await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
      expect(sent, isNull);
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      expect(saved, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reopens and submits a rich body without changing either alternative',
    (tester) async {
      final rich = _rich();
      StudioMailDraft? sent;
      await _open(
        tester,
        initial: StudioMailDraft(
          to: _plain.to,
          subject: _plain.subject,
          body: rich.plainText,
          richBody: rich,
        ),
        finish: (value) => sent = value,
      );
      final paragraph = _body(tester).document.paragraphs.single;
      expect(paragraph.properties.justification, WmlJustification.center);
      final runs = paragraph.inlines.whereType<WmlRun>().toList();
      expect(runs.first.properties.bold, isTrue);
      expect(runs.last.hyperlink?.url, 'https://example.test/details?a=1&b=2');
      await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
      expect(sent?.body, rich.plainText);
      expect(sent?.richBody?.html, rich.html);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'format-only changes autosave and Undo restores the plain draft',
    (tester) async {
      final saved = <StudioMailDraft>[];
      await _open(tester, save: (draft) async => saved.add(draft));
      await tester.pump(const Duration(milliseconds: 600));
      expect(saved.last.richBody, isNull);
      _body(tester).selectAll();
      await _tap(tester, _key('bold'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(saved.last.body, _plain.body);
      expect(saved.last.richBody?.paragraphs.single.runs.single.bold, isTrue);
      await _tap(tester, _key('undo'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(saved.last.body, _plain.body);
      expect(saved.last.richBody, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary Enter keeps an unfinished draft plain and autosavable',
    (tester) async {
      final saved = <StudioMailDraft>[];
      await _open(tester, save: (draft) async => saved.add(draft));
      final controller = _body(tester);
      controller.caret.logicalIndex = _plain.body.length;
      controller.caret.collapseSelection();
      controller.insertText('\nNext paragraph');
      await _pump(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(saved.last.body, '${_plain.body}\nNext paragraph');
      expect(saved.last.richBody, isNull);
      expect(find.text(_strings.mailRichUnsupported), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty paragraph formatting supports Undo, Enter, reopen and continued typing',
    (tester) async {
      final saved = <StudioMailDraft>[];
      await _open(
        tester,
        initial: StudioMailDraft(
          to: _plain.to,
          subject: _plain.subject,
          body: '',
        ),
        save: (draft) async => saved.add(draft),
      );
      await _tap(tester, _key('bold'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_body(tester).activeRunProps.bold, isTrue);
      expect(saved.last.body, isEmpty);
      expect(saved.last.richBody?.paragraphs.single.runs.single.bold, isTrue);
      await _tap(tester, _key('undo'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_body(tester).activeRunProps.bold, isFalse);
      expect(saved.last.richBody, isNull);
      await _tap(tester, _key('bold'));
      _body(tester).insertText('First\n');
      await _pump(tester);
      await tester.pump(const Duration(milliseconds: 600));
      final reopened = saved.last;
      expect(reopened.body, 'First\n');
      expect(reopened.richBody!.paragraphs.last.runs.single.text, isEmpty);
      expect(reopened.richBody!.paragraphs.last.runs.single.bold, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());

      StudioMailDraft? sent;
      await _open(tester, initial: reopened, finish: (draft) => sent = draft);
      final controller = _body(tester);
      controller.caret.paragraphIndex = 1;
      controller.caret.logicalIndex = 0;
      controller.caret.collapseSelection();
      controller.insertText('Second');
      await _pump(tester);
      await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
      expect(sent?.body, 'First\nSecond');
      expect(
        sent!.richBody!.paragraphs.every(
          (paragraph) => paragraph.runs.every((run) => run.bold),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multiline typing after a link retains inherited appearance without linking the new paragraph',
    (tester) async {
      final rich = _rich();
      final saved = <StudioMailDraft>[];
      await _open(
        tester,
        initial: StudioMailDraft(
          to: _plain.to,
          subject: _plain.subject,
          body: rich.plainText,
          richBody: rich,
        ),
        save: (draft) async => saved.add(draft),
      );
      final controller = _body(tester);
      controller.caret.logicalIndex = rich.plainText.length;
      controller.caret.collapseSelection();
      controller.insertText('\nContinuation');
      await _pump(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(saved.last.body, '${rich.plainText}\nContinuation');
      final continuation = saved.last.richBody!.paragraphs.last.runs.single;
      expect(continuation.text, 'Continuation');
      expect(continuation.link, isNull);
      expect(continuation.linkBlue, isTrue);
      expect(continuation.italic, isTrue);
      expect(find.text(_strings.mailRichUnsupported), findsNothing);
      final reopened = saved.last;
      await tester.pumpWidget(const SizedBox.shrink());
      await _open(tester, initial: reopened);
      final run = _body(tester).document.paragraphs.last.inlines
          .whereType<WmlRun>()
          .single;
      expect(run.hyperlink, isNull);
      expect(run.properties.color, WordLink.color);
      expect(run.properties.italic, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a format edit during a pending save gets its own immutable revision',
    (tester) async {
      final firstWrite = Completer<void>();
      final saved = <StudioMailDraft>[];
      await _open(
        tester,
        save: (draft) async {
          saved.add(draft);
          if (saved.length == 1) await firstWrite.future;
        },
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(saved.length, 1);
      _body(tester).selectAll();
      await _tap(tester, _key('italic'));
      expect(saved.single.richBody, isNull);
      firstWrite.complete();
      await _pump(tester);
      expect(saved.length, 2);
      expect(saved.first.richBody, isNull);
      expect(saved.last.richBody?.paragraphs.single.runs.single.italic, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'toolbar styles and explicit paragraph direction survive submission',
    (tester) async {
      StudioMailDraft? sent;
      await _open(tester, finish: (value) => sent = value);
      _body(tester).selectAll();
      await _tap(tester, _key('underline'));
      await _tap(tester, _key('strike'));
      await _tap(tester, _key('paragraph-direction'));
      await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
      final paragraph = sent!.richBody!.paragraphs.single;
      expect(paragraph.rightToLeft, isTrue);
      expect(paragraph.runs.single.underline, isTrue);
      expect(paragraph.runs.single.strike, isTrue);
      expect(sent!.body, _plain.body);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'writing tools use live caret offsets after formatting a legacy CRLF draft',
    (tester) async {
      StudioMailDraft? sent;
      await _open(
        tester,
        initial: StudioMailDraft(
          to: _plain.to,
          subject: _plain.subject,
          body: 'A\r\nB',
        ),
        tools: _Tools(signature: 'Signer'),
        finish: (value) => sent = value,
      );
      final body = _body(tester);
      body.selectAll();
      await _tap(tester, _key('bold'));
      body.documentCaret
        ..paragraphIndex = 0
        ..logicalIndex = body.document.paragraphs.single.text.length
        ..collapseSelection();
      body.notifyListeners();
      await _tap(tester, _key('insert-signature'));
      await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
      expect(sent!.body, 'A\nB\n\n-- \nSigner');
      expect(sent!.richBody!.paragraphs.first.runs.first.bold, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'link dialog refuses active schemes and preserves selected text',
    (tester) async {
      StudioMailDraft? sent;
      await _open(tester, finish: (value) => sent = value);
      _body(tester).selectAll();
      await _tap(tester, _key('add-link'));
      expect(_key('link-label'), findsNothing);
      await tester.enterText(_key('link-address'), 'javascript:alert(1)');
      await _tap(tester, _key('link-confirm'));
      expect(find.text(_strings.mailRichLinkInvalid), findsOneWidget);
      expect(_body(tester).document.paragraphs.single.text, _plain.body);
      await tester.enterText(_key('link-address'), 'https://example.test/path');
      await _tap(tester, _key('link-confirm'));
      await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
      expect(sent!.body, _plain.body);
      expect(
        sent!.richBody!.paragraphs.single.runs.single.link,
        'https://example.test/path',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late link confirmation cannot modify a changed message', (
    tester,
  ) async {
    StudioMailDraft? sent;
    await _open(tester, finish: (value) => sent = value);
    final body = _body(tester);
    await _tap(tester, _key('add-link'));
    await tester.enterText(_key('link-address'), 'https://example.test/path');
    await tester.enterText(_key('link-label'), 'Read more');
    body.insertText(' changed');
    await tester.pump();
    await _tap(tester, _key('link-confirm'));
    expect(find.text(_strings.mailRichChanged), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
    expect(sent!.body, '${_plain.body} changed');
    expect(sent!.richBody, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a delayed paste cannot insert into a changed editor selection', (
    tester,
  ) async {
    final read = Completer<List<Object?>>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('crispoffice/mail_pasteboard');
    messenger.setMockMethodCallHandler(channel, (_) => read.future);
    var textReads = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        textReads++;
        return <String, Object?>{'text': ' late paste'};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _open(tester);
    final editor = tester.widget<QudsWordEditor>(_key('compose-body'));
    final paste = editor.onPasteOverride!(keepTextOnly: true);
    await tester.pump();
    expect(textReads, 0);
    editor.controller.insertText(' changed');
    read.complete(const []);
    await paste;
    await tester.pump();
    expect(textReads, 0);
    expect(
      editor.controller.document.paragraphs.single.text,
      '${_plain.body} changed',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'unsupported list blocks save, close and send until Undo restores the body',
    (tester) async {
      final saved = <StudioMailDraft>[];
      StudioMailDraft? sent;
      await _open(
        tester,
        save: (draft) async => saved.add(draft),
        finish: (value) => sent = value,
      );
      await tester.pump(const Duration(milliseconds: 600));
      final savedBeforeList = saved.length;
      _body(tester).toggleList(numbered: true);
      await tester.pump(const Duration(milliseconds: 600));
      expect(_key('rich-unsupported'), findsOneWidget);
      expect(saved.length, savedBeforeList);
      await _tap(
        tester,
        find.widgetWithText(TextButton, _strings.mailDraftSaveClose),
      );
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      expect(saved.length, savedBeforeList);
      await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
      expect(sent, isNull);
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      await _tap(tester, _key('undo'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_key('rich-unsupported'), findsNothing);
      expect(saved.last.body, _plain.body);
      await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
      expect(sent!.body, _plain.body);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving a rich template confirms plain text while preserving the live reply and attachment',
    (tester) async {
      final rich = _rich();
      final tools = _Tools();
      final thread = StudioMailThread.replyTo(
        MailEnvelope(messageId: '<parent@example.test>'),
      );
      final attachments = StudioMailAttachments.from([
        StudioMailAttachment(
          name: 'retained.txt',
          bytes: Uint8List.fromList([65, 66]),
        ),
      ]);
      StudioMailDraft? sent;
      await _open(
        tester,
        tools: tools,
        finish: (draft) => sent = draft,
        initial: StudioMailDraft(
          to: _plain.to,
          bcc: 'private@example.test',
          subject: _plain.subject,
          body: rich.plainText,
          richBody: rich,
          thread: thread,
          attachments: attachments,
        ),
      );
      await _tap(tester, _key('save-template'));
      expect(find.text(_strings.mailRichTemplateHelp), findsOneWidget);
      expect(tools.writes, 0);
      await _tap(tester, _key('template-plain-confirm'));
      await tester.enterText(_key('template-name'), 'Plain snapshot');
      await _tap(tester, _key('template-apply'));
      expect(tools.writes, 1);
      expect(tools.settings.templates.single.body, rich.plainText);
      expect(
        _body(tester).document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .first
            .properties
            .bold,
        isTrue,
      );
      await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
      expect(sent!.richBody!.html, rich.html);
      expect(sent!.thread, same(thread));
      expect(sent!.attachments, same(attachments));
      expect(sent!.bcc, 'private@example.test');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed template replacement clears old links and formatting',
    (tester) async {
      final rich = _rich();
      final tools = _Tools(
        templates: const [
          MailMessageTemplate(
            id: 'plain-template',
            name: 'Plain template',
            to: 'new@example.test',
            subject: 'Replacement',
            body: 'Replacement body',
          ),
        ],
      );
      StudioMailDraft? sent;
      await _open(
        tester,
        tools: tools,
        finish: (value) => sent = value,
        initial: StudioMailDraft(
          to: _plain.to,
          subject: _plain.subject,
          body: rich.plainText,
          richBody: rich,
        ),
      );
      await _tap(tester, _key('use-template'));
      await _tap(tester, find.text('Plain template'));
      await _tap(tester, _key('template-replace-confirm'));
      await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
      expect(sent!.body, 'Replacement body');
      expect(sent!.richBody, isNull);
      expect(sent!.to, 'new@example.test');
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in [StudioLanguage.de, StudioLanguage.ar]) {
    testWidgets('narrow enlarged ${language.name} formatting controls wrap', (
      tester,
    ) async {
      await _open(
        tester,
        language: language,
        size: const Size(420, 760),
        textScale: 1.4,
      );
      final strings = StudioStrings(language);
      await tester.ensureVisible(_key('bold'));
      await tester.pump();
      expect(
        tester.widget<IconButton>(_key('bold')).tooltip,
        strings.mailRichBold,
      );
      expect(
        tester.widget<IconButton>(_key('add-link')).tooltip,
        strings.mailRichLink,
      );
      expect(
        tester.getTopLeft(_key('redo')).dy,
        greaterThan(tester.getTopLeft(_key('bold')).dy),
      );
      expect(
        Directionality.of(tester.element(_key('compose-body'))),
        language == StudioLanguage.ar ? TextDirection.rtl : TextDirection.ltr,
      );
      await _tap(tester, _key('add-link'));
      expect(find.text(strings.mailRichLinkHelp), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

final class _Tools implements StudioMailComposeToolsStore {
  _Tools({
    List<MailMessageTemplate> templates = const [],
    String signature = '',
  }) : settings = MailComposeSettings(
         account: MailAccountId(
           'rich-account',
           profile: MailProfileId('rich-profile', hostId: 'studio'),
         ),
         templates: templates,
         signature: signature,
       );

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
    expect(value.account, account);
    expect(value.revision, settings.revision);
    writes++;
    return settings = value.copyWith(revision: value.revision + 1);
  }
}
