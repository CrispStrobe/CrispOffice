import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_outbox_review.dart';
import 'package:quds_office_studio/studio_mail_outbox_strings.dart';
import 'package:quds_office_studio/studio_mail_rich_preview.dart';
import 'package:quds_office_studio/studio_mail_rich_preview_data.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _sender = 'author@example.test';

Future<void> _show(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1000, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

MailComposeBody _rich() => MailComposeBody(
  paragraphs: [
    MailComposeParagraph(
      alignment: MailComposeAlignment.center,
      runs: [
        MailComposeRun(text: 'Bold', bold: true),
        MailComposeRun(text: 'Italic', italic: true),
        MailComposeRun(text: 'Both', underline: true, strike: true),
        MailComposeRun(text: 'Inert link', link: 'https://example.test/'),
      ],
    ),
    MailComposeParagraph(
      rightToLeft: true,
      alignment: MailComposeAlignment.right,
      runs: [MailComposeRun(text: 'مرحبا')],
    ),
  ],
);

MailOutboxEntry _entry(StudioMailDraft draft) => MailOutboxEntry.queued(
  id: 'preview',
  prepared: MailPreparedMessage(
    account: MailAccountId(
      'preview',
      profile: MailProfileId('test', hostId: 'studio'),
    ),
    draftId: 'draft',
    draftRevision: 0,
    wire: MailBytes(
      utf8.encode(buildStudioMailMessage(draft, _sender).renderMessage()),
    ),
    envelope: MailTransportEnvelope(
      sender: _sender,
      recipients: draft.recipients.envelope,
    ),
  ),
  now: DateTime.utc(2026, 11, 25),
);

void main() {
  testWidgets(
    'supported styles, alignment and RTL render as inert text spans',
    (tester) async {
      await _show(
        tester,
        StudioMailRichPreview(body: _rich(), truncationNotice: 'Shortened'),
      );
      final first = tester.widget<SelectableText>(
        find.byKey(const ValueKey('studio-mail-rich-preview-paragraph-0')),
      );
      expect(first.textAlign, TextAlign.center);
      final spans = first.textSpan!.children!.cast<TextSpan>();
      expect(spans[0].style!.fontWeight, FontWeight.bold);
      expect(spans[1].style!.fontStyle, FontStyle.italic);
      expect(
        spans[2].style!.decoration,
        TextDecoration.combine([
          TextDecoration.underline,
          TextDecoration.lineThrough,
        ]),
      );
      expect(spans.every((span) => span.recognizer == null), isTrue);
      final second = tester.widget<SelectableText>(
        find.byKey(const ValueKey('studio-mail-rich-preview-paragraph-1')),
      );
      expect(second.textAlign, TextAlign.right);
      expect(second.textDirection, TextDirection.rtl);
      expect(find.byType(Image), findsNothing);
      expect(
        find.byKey(const ValueKey('studio-mail-rich-preview-truncated')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('studio-mail-rich-preview-paragraph-0')),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bounded preview shows a truncation notice and no later rows', (
    tester,
  ) async {
    final body = MailComposeBody(
      paragraphs: [
        for (var i = 0; i <= StudioMailRichPreviewData.maxParagraphs; i++)
          MailComposeParagraph(
            runs: [MailComposeRun(text: 'Paragraph $i', bold: true)],
          ),
      ],
    );
    await _show(
      tester,
      SingleChildScrollView(
        child: StudioMailRichPreview(body: body, truncationNotice: 'Shortened'),
      ),
    );
    expect(
      find.byType(SelectableText),
      findsNWidgets(StudioMailRichPreviewData.maxParagraphs),
    );
    expect(
      find.byKey(const ValueKey('studio-mail-rich-preview-truncated')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-mail-rich-preview-paragraph-256')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in StudioLanguage.values) {
    testWidgets(
      '${language.name} Outbox shows formatted label and preserves exact export',
      (tester) async {
        final body = _rich();
        final entry = _entry(
          StudioMailDraft(
            to: 'reader@example.test',
            subject: 'Preview',
            body: body.plainText,
            richBody: body,
          ),
        );
        final strings = StudioStrings(language);
        MailBytes? exported;
        await _show(
          tester,
          StudioMailOutboxReviewDialog(
            entry: entry,
            strings: strings,
            isCurrent: () => true,
            exporter:
                (
                  name,
                  bytes, {
                  required cancellation,
                  required isCurrent,
                }) async {
                  exported = bytes;
                  return const MailSuccess(true);
                },
          ),
        );
        expect(find.text(strings.mailOutboxFormattedBody), findsOneWidget);
        expect(find.byType(StudioMailRichPreview), findsOneWidget);
        expect(find.text(strings.mailPlainTextBody), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('studio-mail-outbox-export-eml')),
        );
        await tester.pumpAndSettle();
        expect(exported!.bytes, entry.prepared.wire.bytes);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('legacy plain review remains literal and uses plain-body label', (
    tester,
  ) async {
    const strings = StudioStrings(StudioLanguage.en);
    const body = '<img src="https://tracker.test/pixel"> visible text';
    final entry = _entry(
      const StudioMailDraft(
        to: 'reader@example.test',
        subject: 'Plain',
        body: body,
      ),
    );
    await _show(
      tester,
      StudioMailOutboxReviewDialog(
        entry: entry,
        strings: strings,
        isCurrent: () => true,
      ),
    );
    expect(find.text(strings.mailPlainTextBody), findsOneWidget);
    expect(find.byType(StudioMailRichPreview), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == body,
      ),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
