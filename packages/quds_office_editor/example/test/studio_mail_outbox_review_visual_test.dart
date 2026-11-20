import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_outbox_dialog.dart';
import 'package:quds_office_studio/studio_mail_outbox_review.dart';
import 'package:quds_office_studio/studio_mail_outbox_strings.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_outbox_store.dart';

const _sender = 'author@example.test';
const _visible = 'visible@example.test';
const _hidden = 'private@example.test';
const _body =
    'Review this saved message. مرحبًا — Grüße. '
    '<img src="https://example.invalid/tracking.png"> is text here.';
const _captureKey = ValueKey('outbox-management-visual-capture');

StudioMailDraftAccount _identity() => StudioMailDraftAccount(
  provider: 'imap',
  endpoint: 'imaps://mail.example.test:993',
  login: _sender,
  sender: _sender,
);

StudioMailDraft _draft() => StudioMailDraft(
  to: _visible,
  cc: 'copy@example.test',
  bcc: _hidden,
  subject: 'Quarterly update · Quartalsbericht · تحديث ربع سنوي',
  body: _body,
  attachments: StudioMailAttachments.from([
    StudioMailAttachment(
      name: 'résumé-ملخص.txt',
      bytes: Uint8List.fromList(utf8.encode('Saved attachment bytes.')),
    ),
  ]),
);

MailOutboxEntry _entry() => MailOutboxEntry.queued(
  id: 'visual-message',
  prepared: MailPreparedMessage(
    account: _identity().account,
    draftId: 'visual-draft',
    draftRevision: 0,
    wire: MailBytes(
      utf8.encode(buildStudioMailMessage(_draft(), _sender).renderMessage()),
    ),
    envelope: MailTransportEnvelope(
      sender: _sender,
      recipients: _draft().recipients.envelope,
    ),
  ),
  now: DateTime.utc(2026, 11, 20, 12),
);

bool _fontsLoaded = false;

Future<void> _loadFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    await (FontLoader('OutboxManagementVisual')
          ..addFont(rootBundle.load('fonts/Tajawal-Regular.ttf'))
          ..addFont(rootBundle.load('fonts/Tajawal-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  _fontsLoaded = true;
}

Future<void> _show(
  WidgetTester tester, {
  required Widget dialog,
  required StudioStrings strings,
  required Size size,
}) async {
  await _loadFonts(tester);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'OutboxManagementVisual'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: Directionality(
            textDirection: strings.language == StudioLanguage.ar
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => dialog,
              ),
              child: const Text('Open review fixture'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open review fixture'));
  await pumpOutboxWidgets(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment['OUTBOX_MANAGEMENT_SCREENSHOT_DIR'];
  if (path == null || path.isEmpty) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final directory = await Directory(path).create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _expectLocale(
  WidgetTester tester,
  Finder surface,
  StudioLanguage language,
) {
  expect(
    Directionality.of(tester.element(surface)),
    language == StudioLanguage.ar ? TextDirection.rtl : TextDirection.ltr,
  );
  expect(MediaQuery.textScalerOf(tester.element(surface)).scale(10), 13);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final language in StudioLanguage.values) {
    testWidgets(
      'compact ${language.name} review keeps enlarged export controls usable and Bcc separate',
      (tester) async {
        final strings = StudioStrings(language);
        final entry = _entry();
        var exports = 0;
        await _show(
          tester,
          strings: strings,
          size: const Size(700, 720),
          dialog: StudioMailOutboxReviewDialog(
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
                  exports++;
                  expectSync(name, 'outbox-message.eml');
                  expectSync(bytes.bytes, entry.prepared.wire.bytes);
                  return const MailSuccess(true);
                },
          ),
        );
        _expectLocale(
          tester,
          find.byType(StudioMailOutboxReviewDialog),
          language,
        );
        final export = find.byKey(
          const ValueKey('studio-mail-outbox-export-eml'),
        );
        final privateExport = find.byKey(
          const ValueKey('studio-mail-outbox-export-envelope'),
        );
        expect(export.hitTestable(), findsOneWidget);
        expect(privateExport.hitTestable(), findsOneWidget);
        expect(find.text(strings.mailOutboxPreviewUnavailable), findsNothing);
        expect(find.byType(Image), findsNothing);
        await _capture(tester, 'outbox-review-${language.name}-top');

        await tester.ensureVisible(find.text(strings.mailBcc));
        await pumpOutboxWidgets(tester);
        expect(find.text(strings.mailBcc).hitTestable(), findsOneWidget);
        expect(find.text(_hidden), findsOneWidget);
        expect(find.text(_visible), findsOneWidget);
        expect(find.text(_body), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(export.hitTestable(), findsOneWidget);
        expect(privateExport.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, 'outbox-review-${language.name}-content');

        await tester.ensureVisible(find.text('résumé-ملخص.txt'));
        await pumpOutboxWidgets(tester);
        expect(find.text('résumé-ملخص.txt').hitTestable(), findsOneWidget);
        expect(exports, 0);
        await tester.tap(export);
        await pumpOutboxWidgets(tester);
        expect(exports, 1);
        expect(find.text(strings.mailOutboxExported), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'compact ${language.name} closed uncertain queue stays reviewable with enlarged text',
      (tester) async {
        final strings = StudioStrings(language);
        final fixture = await awaitOutboxOperation(
          tester,
          SqliteOutboxFixture.create(_identity()),
        );
        addTearDown(() => awaitOutboxOperation(tester, fixture.close()));
        final store = await awaitOutboxOperation(tester, fixture.openLoaded());
        final queued = await awaitOutboxOperation(
          tester,
          store.enqueueOutbox(_draft(), _sender),
        );
        final attempt = await awaitOutboxOperation(
          tester,
          store.beginOutboxAttempt(queued),
        );
        final uncertain = await awaitOutboxOperation(
          tester,
          store.completeOutboxAttempt(
            attempt,
            MailSubmissionResult(
              attemptId: attempt.attemptId!,
              outcome: MailSubmissionOutcome.uncertain,
            ),
          ),
        );
        final closed = await awaitOutboxOperation(
          tester,
          store.closeUncertainOutbox(uncertain),
        );
        var submissions = 0;
        await _show(
          tester,
          strings: strings,
          size: const Size(700, 660),
          dialog: StudioMailOutboxDialog(
            strings: strings,
            store: store,
            isCurrent: () => true,
            submit: (_, {required attemptId}) async {
              submissions++;
              throw StateError('Review must not submit a message.');
            },
          ),
        );
        _expectLocale(tester, find.byType(StudioMailOutboxDialog), language);
        expect(
          find.text(strings.mailOutboxState(MailOutboxState.closedUncertain)),
          findsOneWidget,
        );
        expect(find.text(strings.mailOutboxClosedExplanation), findsOneWidget);
        expect(
          find.byKey(ValueKey('studio-mail-outbox-send-${closed.id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('studio-mail-outbox-edit-${closed.id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('studio-mail-outbox-stop-${closed.id}')),
          findsNothing,
        );
        final review = find.byKey(
          ValueKey('studio-mail-outbox-review-${closed.id}'),
        );
        final remove = find.byKey(
          ValueKey('studio-mail-outbox-remove-${closed.id}'),
        );
        await tester.ensureVisible(remove);
        await pumpOutboxWidgets(tester);
        expect(review.hitTestable(), findsOneWidget);
        expect(remove.hitTestable(), findsOneWidget);
        expect(submissions, 0);
        expect(tester.takeException(), isNull);
        await _capture(tester, 'outbox-closed-${language.name}');
      },
    );
  }
}
