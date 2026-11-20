import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_mail_threading.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_attachment_picker.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _add = ValueKey('studio-mail-add-attachments');

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
  StudioStrings strings = _strings,
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
                builder: (_) => Directionality(
                  textDirection: strings.language == StudioLanguage.ar
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: StudioMailComposeDialog(
                    strings: strings,
                    from: 'writer@example.invalid',
                    initialDraft:
                        initial ??
                        const StudioMailDraft(
                          to: 'reader@example.invalid',
                          subject: 'Attachments',
                          body: 'Body',
                        ),
                    previousSubmissionUncertain: uncertain,
                  ),
                ),
              ),
            ),
            child: const Text('Open composer'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open composer'));
  await _pump(tester);
}

Future<void> _attach(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_add));
  await tester.tap(find.byKey(_add));
  await _pump(tester);
}

Future<void> _send(
  WidgetTester tester, [
  StudioStrings strings = _strings,
]) async {
  final send = find.widgetWithText(FilledButton, strings.send);
  await tester.ensureVisible(send);
  await tester.tap(send);
  await _pump(tester);
}

StudioMailAttachment _attachment(String name, List<int> bytes) =>
    StudioMailAttachment(name: name, bytes: Uint8List.fromList(bytes));

void main() {
  setUp(() => FilePicker.platform = FilePickerIO());
  tearDown(() => FilePicker.platform = FilePickerIO());

  testWidgets('picker snapshots exact bytes and preserves edited Word body', (
    tester,
  ) async {
    final bytes = Uint8List.fromList([0, 128, 255, 42]);
    final picker = MailAttachmentPickerFixture(
      () async => FilePickerResult([
        PlatformFile(name: 'Budget.xlsx', size: 4, bytes: bytes),
        PlatformFile(name: '研究.pdf', size: 0, bytes: Uint8List(0)),
      ]),
    );
    FilePicker.platform = picker;
    StudioMailDraft? result;
    await _open(tester, (value) => result = value);
    final body = tester
        .widget<QudsWordEditor>(find.byType(QudsWordEditor))
        .controller;
    body.insertText(' edited');
    await _attach(tester);
    expect(find.text('Budget.xlsx'), findsOneWidget);
    expect(find.text('研究.pdf'), findsOneWidget);
    expect(find.text(_strings.mailAttachmentSummary(2, 4)), findsOneWidget);
    bytes.fillRange(0, bytes.length, 9);
    await _send(tester);
    expect(picker.calls, 1);
    expect(result!.attachments.items.first.content.bytes, [0, 128, 255, 42]);
    expect(result!.attachments.items.last.length, 0);
    expect(result!.body, contains('edited'));
    expect(body.isDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removing one duplicate name leaves the other and original draft intact',
    (tester) async {
      final bundle = StudioMailAttachments.from([
        _attachment('same.docx', [1]),
        _attachment('same.docx', [2]),
      ]);
      final initial = StudioMailDraft(
        to: 'reader@example.invalid',
        subject: 'Duplicate names',
        body: '',
        attachments: bundle,
      );
      StudioMailDraft? result;
      await _open(tester, (value) => result = value, initial: initial);
      await tester.tap(
        find.byKey(const ValueKey('studio-mail-remove-attachment-0')),
      );
      await tester.pump();
      expect(find.text('same.docx'), findsOneWidget);
      await _send(tester);
      expect(result!.attachments.items.single.content.bytes, [2]);
      expect(initial.attachments.items, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed multi-file selection adds no partial files and gives redacted feedback',
    (tester) async {
      FilePicker.platform = MailAttachmentPickerFixture(
        () async => FilePickerResult([
          PlatformFile(
            name: 'new.pdf',
            size: 1,
            bytes: Uint8List.fromList([3]),
          ),
          PlatformFile(
            name: 'bad.pdf',
            size: 1,
            readStream: Stream.error(StateError('/private/credential-secret')),
          ),
        ]),
      );
      final initial = StudioMailDraft(
        to: 'reader@example.invalid',
        subject: 'Keep',
        body: '',
        attachments: StudioMailAttachments.from([
          _attachment('keep.docx', [7]),
        ]),
      );
      StudioMailDraft? result;
      await _open(tester, (value) => result = value, initial: initial);
      await _attach(tester);
      expect(find.text('keep.docx'), findsOneWidget);
      expect(find.text('new.pdf'), findsNothing);
      expect(find.text('bad.pdf'), findsNothing);
      expect(find.text(_strings.mailAttachmentFailed), findsOneWidget);
      expect(find.textContaining('credential-secret'), findsNothing);
      await _send(tester);
      expect(result!.attachments, same(initial.attachments));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled selection keeps attachments and allows sending', (
    tester,
  ) async {
    FilePicker.platform = MailAttachmentPickerFixture(() async => null);
    StudioMailDraft? result;
    await _open(tester, (value) => result = value);
    await _attach(tester);
    expect(find.text(_strings.mailAttachmentFailed), findsNothing);
    await _send(tester);
    expect(result!.attachments.isEmpty, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending picker blocks send and late selection cannot publish after close',
    (tester) async {
      final selection = Completer<FilePickerResult?>();
      FilePicker.platform = MailAttachmentPickerFixture(() => selection.future);
      var subscribed = false;
      final stream = StreamController<List<int>>(
        onListen: () => subscribed = true,
      );
      StudioMailDraft? result;
      await _open(tester, (value) => result = value);
      await _attach(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, _strings.send),
            )
            .onPressed,
        isNull,
      );
      expect(tester.widget<TextButton>(find.byKey(_add)).onPressed, isNull);
      await tester.ensureVisible(find.text(_strings.cancel));
      await tester.tap(find.text(_strings.cancel));
      await _pump(tester);
      selection.complete(
        FilePickerResult([
          PlatformFile(name: 'late.pdf', size: 1, readStream: stream.stream),
        ]),
      );
      await _pump(tester);
      expect(subscribed, isFalse);
      expect(result, isNull);
      expect(find.byType(StudioMailComposeDialog), findsNothing);
      expect(tester.takeException(), isNull);
      unawaited(stream.close());
    },
  );

  testWidgets('closing during file read cancels the active stream', (
    tester,
  ) async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    FilePicker.platform = MailAttachmentPickerFixture(
      () async => FilePickerResult([
        PlatformFile(name: 'loading.pptx', size: 1, readStream: stream.stream),
      ]),
    );
    await _open(tester, (_) {});
    await _attach(tester);
    expect(find.text(_strings.mailReadingAttachments), findsOneWidget);
    await tester.ensureVisible(find.text(_strings.cancel));
    await tester.tap(find.text(_strings.cancel));
    await _pump(tester);
    expect(cancelled, isTrue);
    expect(find.byType(StudioMailComposeDialog), findsNothing);
    expect(tester.takeException(), isNull);
    unawaited(stream.close());
    await tester.pump();
  });

  testWidgets(
    'uncertain retry keeps attachments and thread behind acknowledgement',
    (tester) async {
      final bundle = StudioMailAttachments.from([
        _attachment('retained.pptx', [0, 255]),
      ]);
      final thread = StudioMailThread.replyTo(
        MailEnvelope(messageId: '<parent@example.invalid>'),
      );
      final initial = StudioMailDraft(
        to: 'reader@example.invalid',
        cc: 'copy@example.invalid',
        bcc: 'hidden@example.invalid',
        subject: 'Retained',
        body: 'Do not duplicate.',
        thread: thread,
        attachments: bundle,
      );
      StudioMailDraft? result;
      await _open(
        tester,
        (value) => result = value,
        initial: initial,
        uncertain: true,
      );
      final send = find.widgetWithText(FilledButton, _strings.send);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(find.text('retained.pptx'), findsOneWidget);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await _send(tester);
      expect(result!.attachments, same(bundle));
      expect(result!.thread, same(thread));
      expect(result!.cc, initial.cc);
      expect(result!.bcc, initial.bcc);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow Arabic body stays visible and retains IME and undo through resize',
    (tester) async {
      await tester.runAsync(OfficeHostFonts.ensureRegistered);
      const strings = StudioStrings(StudioLanguage.ar);
      const original = 'مرحبًا بكم في مراجعة التقرير والميزانية.';
      const edited = '$original جديد';
      final initial = StudioMailDraft(
        to: 'reader@example.invalid',
        subject: 'مراجعة',
        body: original,
        attachments: StudioMailAttachments.from([
          _attachment('مراجعة 2026.pdf', [1, 2, 3]),
        ]),
      );
      StudioMailDraft? result;
      await _open(
        tester,
        (value) => result = value,
        initial: initial,
        strings: strings,
        size: const Size(390, 844),
      );
      final editor = find.byType(QudsWordEditor);
      await tester.ensureVisible(editor);
      await _pump(tester);
      final body = tester.widget<QudsWordEditor>(editor).controller;
      final document = body.document;
      final paragraph = document.paragraphs.single;
      expect(body.config.textDirection, TextDirection.rtl);
      expect(body.viewport.scale, 1);
      expect(
        tester.widget<Text>(find.text('مراجعة 2026.pdf')).textDirection,
        TextDirection.ltr,
      );
      expect(
        tester.widget<Text>(find.text('3 B')).textDirection,
        TextDirection.ltr,
      );

      void expectVisibleBody() {
        final canvas = tester.renderObject<RenderWordCanvas>(
          find.byType(WordCanvas),
        );
        final lines = body.documentLaidOut.pages.first.lines;
        expect(lines, isNotEmpty);
        for (final line in lines) {
          for (final glyph in line.glyphs) {
            final start = canvas.windowForPagePoint(0, Offset(glyph.x, line.y));
            final end = canvas.windowForPagePoint(
              0,
              Offset(glyph.x + glyph.advance, line.y + line.height),
            );
            expect(start.dx, greaterThanOrEqualTo(0));
            expect(end.dx, lessThan(canvas.size.width));
            expect(start.dy, greaterThanOrEqualTo(0));
            expect(end.dy, lessThan(canvas.size.height));
          }
        }
      }

      expectVisibleBody();
      final canvas = tester.renderObject<RenderWordCanvas>(
        find.byType(WordCanvas),
      );
      final firstLine = body.documentLaidOut.pages.first.lines.first;
      final glyph = firstLine.glyphs.firstWhere((glyph) => glyph.advance > 0);
      await tester.tapAt(
        canvas.localToGlobal(
          canvas.windowForPagePoint(
            0,
            Offset(
              glyph.x + glyph.advance / 2,
              firstLine.y + firstLine.height / 2,
            ),
          ),
        ),
      );
      await _pump(tester);
      expect(body.input.isAttached, isTrue);
      final composing = TextRange(
        start: original.length + 1,
        end: edited.length,
      );
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: edited,
          selection: const TextSelection.collapsed(offset: edited.length),
          composing: composing,
        ),
      );
      await _pump(tester);
      expect(paragraph.text, edited);
      expect(body.input.composing, composing);
      expectVisibleBody();

      for (final size in [const Size(1100, 850), const Size(390, 844)]) {
        await tester.binding.setSurfaceSize(size);
        await _pump(tester);
        expect(tester.widget<QudsWordEditor>(editor).controller, same(body));
        expect(body.document, same(document));
        expect(body.document.paragraphs.single, same(paragraph));
        expect(paragraph.text, edited);
        expect(body.input.composing, composing);
        expect(body.caret.logicalIndex, edited.length);
        expect(body.input.isAttached, isTrue);
        expectVisibleBody();
      }
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: edited,
          selection: TextSelection.collapsed(offset: edited.length),
        ),
      );
      await _pump(tester);
      expect(body.canUndo, isTrue);
      body.undo();
      expect(body.document.paragraphs.single.text, original);
      body.redo();
      await _pump(tester);
      expectVisibleBody();
      await _send(tester, strings);
      expect(result!.body, edited);
      expect(result!.attachments, same(initial.attachments));
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in StudioLanguage.values) {
    testWidgets('attachment controls fit narrow $language chrome', (
      tester,
    ) async {
      final strings = StudioStrings(language);
      final initial = StudioMailDraft(
        to: 'reader@example.invalid',
        subject: '',
        body: '',
        attachments: StudioMailAttachments.from(
          List.generate(
            10,
            (index) => _attachment('Long document name 研究 العربية $index.pdf', [
              index,
            ]),
          ),
        ),
      );
      StudioMailDraft? result;
      await _open(
        tester,
        (value) => result = value,
        initial: initial,
        strings: strings,
        size: const Size(390, 720),
      );
      expect(find.text(strings.mailAddAttachments), findsOneWidget);
      await _send(tester, strings);
      expect(result!.attachments.items, hasLength(10));
      expect(tester.takeException(), isNull);
    });
  }
}
