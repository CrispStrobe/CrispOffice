import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_archive_action.dart';
import 'package:quds_office_studio/studio_mail_archive_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _origin = MailArchiveOrigin(
  source: 'Account A',
  folder: '/Inbox',
  sourceMessageId: 'uid:42',
);

MailMessage _message(int id) => MailMessage(
  raw: MailBytes(Uint8List.fromList([id, 13, 10])),
  envelope: MailEnvelope(subject: 'Message $id'),
);

MailResult<MailArchiveImportResult> _success(
  MailMessage message, {
  bool duplicate = false,
}) => MailSuccess(
  MailArchiveImportResult(
    entry: MailArchiveEntry(
      id: message.raw.sha256,
      envelope: message.envelope,
      archivedAt: DateTime.utc(2026, 11, 19),
      byteLength: message.raw.length,
      attachmentCount: 0,
      indexTruncated: false,
      attachmentTextIndexed: 0,
      attachmentTextSkipped: 0,
    ),
    duplicate: duplicate,
    originAdded: true,
  ),
);

Future<void> _render(
  WidgetTester tester, {
  required MailMessage? message,
  required StudioMailArchiveWriter writer,
  MailArchiveOrigin origin = _origin,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StudioArchiveMessageButton(
          key: const ValueKey('archive-action'),
          strings: _strings,
          message: message,
          origin: origin,
          writer: writer,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('archive-current-message')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

IconButton _button(WidgetTester tester) => tester.widget<IconButton>(
  find.byKey(const ValueKey('archive-current-message')),
);

void main() {
  testWidgets(
    'no selected original disables the action without opening storage',
    (tester) async {
      var calls = 0;
      await _render(
        tester,
        message: null,
        writer: (message, {required origin, cancellation}) async {
          calls++;
          return _success(message);
        },
      );
      expect(_button(tester).onPressed, isNull);
      expect(find.byTooltip(_strings.archiveCurrentMessage), findsOneWidget);
      expect(calls, 0);
    },
  );

  testWidgets(
    'pending action captures the original, prevents double submission and reports success',
    (tester) async {
      final original = _message(1);
      final done = Completer<MailResult<MailArchiveImportResult>>();
      MailMessage? received;
      MailArchiveOrigin? receivedOrigin;
      var calls = 0;
      await _render(
        tester,
        message: original,
        writer: (message, {required origin, cancellation}) {
          calls++;
          received = message;
          receivedOrigin = origin;
          return done.future;
        },
      );
      await _tap(tester);
      expect(received, same(original));
      expect(receivedOrigin, same(_origin));
      expect(_button(tester).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _tap(tester);
      expect(calls, 1);
      done.complete(_success(original));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_button(tester).onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_strings.archiveMessageStored), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a duplicate original has distinct accurate feedback', (
    tester,
  ) async {
    await _render(
      tester,
      message: _message(1),
      writer: (message, {required origin, cancellation}) async =>
          _success(message, duplicate: true),
    );
    await _tap(tester);
    expect(find.text(_strings.archiveMessageDuplicate), findsOneWidget);
    expect(find.text(_strings.archiveMessageStored), findsNothing);
  });

  testWidgets(
    'typed failures retain their useful status without leaking exception details',
    (tester) async {
      await _render(
        tester,
        message: _message(1),
        writer: (message, {required origin, cancellation}) async =>
            const MailFailure(MailProblem(MailProblemCode.permissionDenied)),
      );
      await _tap(tester);
      expect(
        find.text(_strings.archiveProblem(MailProblemCode.permissionDenied)),
        findsOneWidget,
      );
      expect(_button(tester).onPressed, isNotNull);
      expect(find.text(_strings.archiveMessageStored), findsNothing);
    },
  );

  testWidgets('throwing writers produce sanitized failure and allow retry', (
    tester,
  ) async {
    var calls = 0;
    await _render(
      tester,
      message: _message(1),
      writer: (message, {required origin, cancellation}) async {
        calls++;
        throw StateError('secret SQL password and path');
      },
    );
    await _tap(tester);
    expect(
      find.text(_strings.archiveProblem(MailProblemCode.storageFailure)),
      findsOneWidget,
    );
    expect(find.textContaining('secret SQL'), findsNothing);
    expect(_button(tester).onPressed, isNotNull);
    await _tap(tester);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal cancels the owned operation and ignores late success', (
    tester,
  ) async {
    final original = _message(1);
    final done = Completer<MailResult<MailArchiveImportResult>>();
    MailCancellationToken? token;
    await _render(
      tester,
      message: original,
      writer: (message, {required origin, cancellation}) {
        token = cancellation;
        return done.future;
      },
    );
    await _tap(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(token!.isCancelled, isTrue);
    expect(token!.reason, MailCancellationReason.disposed);
    done.complete(_success(original));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'replacement cancels the old message without overwriting new-operation feedback',
    (tester) async {
      final oldMessage = _message(1);
      final newMessage = _message(2);
      final oldDone = Completer<MailResult<MailArchiveImportResult>>();
      MailCancellationToken? oldToken;
      Future<MailResult<MailArchiveImportResult>> writer(
        MailMessage message, {
        required MailArchiveOrigin origin,
        MailCancellationToken? cancellation,
      }) async {
        if (identical(message, oldMessage)) {
          oldToken = cancellation;
          return oldDone.future;
        }
        return _success(message, duplicate: true);
      }

      await _render(tester, message: oldMessage, writer: writer);
      await _tap(tester);
      await _render(tester, message: newMessage, writer: writer);
      expect(oldToken!.isCancelled, isTrue);
      expect(oldToken!.reason, MailCancellationReason.accountChanged);
      expect(_button(tester).onPressed, isNotNull);
      await _tap(tester);
      oldDone.complete(_success(oldMessage));
      await tester.pump();
      expect(find.text(_strings.archiveMessageDuplicate), findsOneWidget);
      expect(find.text(_strings.archiveMessageStored), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing only provenance cancels a pending action', (
    tester,
  ) async {
    final original = _message(1);
    final done = Completer<MailResult<MailArchiveImportResult>>();
    MailCancellationToken? token;
    Future<MailResult<MailArchiveImportResult>> writer(
      MailMessage message, {
      required MailArchiveOrigin origin,
      MailCancellationToken? cancellation,
    }) {
      token = cancellation;
      return done.future;
    }

    await _render(tester, message: original, writer: writer);
    await _tap(tester);
    await _render(
      tester,
      message: original,
      origin: const MailArchiveOrigin(
        source: 'Account A',
        folder: '/Sent',
        sourceMessageId: 'uid:42',
      ),
      writer: writer,
    );
    expect(token!.isCancelled, isTrue);
    done.complete(
      const MailFailure(MailProblem(MailProblemCode.permissionDenied)),
    );
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    expect(_button(tester).onPressed, isNotNull);
  });

  testWidgets(
    'equivalent provenance in a parent rebuild preserves a pending write',
    (tester) async {
      final original = _message(1);
      final done = Completer<MailResult<MailArchiveImportResult>>();
      MailCancellationToken? token;
      Future<MailResult<MailArchiveImportResult>> writer(
        MailMessage message, {
        required MailArchiveOrigin origin,
        MailCancellationToken? cancellation,
      }) {
        token = cancellation;
        return done.future;
      }

      await _render(tester, message: original, writer: writer);
      await _tap(tester);
      await _render(
        tester,
        message: original,
        origin: MailArchiveOrigin(
          source: _origin.source,
          folder: _origin.folder,
          sourceMessageId: _origin.sourceMessageId,
        ),
        writer: writer,
      );
      expect(token!.isCancelled, isFalse);
      expect(_button(tester).onPressed, isNull);
      done.complete(_success(original));
      await tester.pump();
      expect(find.text(_strings.archiveMessageStored), findsOneWidget);
    },
  );

  testWidgets('an explicit cancellation exception has cancellation feedback', (
    tester,
  ) async {
    await _render(
      tester,
      message: _message(1),
      writer: (message, {required origin, cancellation}) async =>
          throw const MailCancelled(MailCancellationReason.user),
    );
    await _tap(tester);
    expect(
      find.text(_strings.archiveProblem(MailProblemCode.cancelled)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
