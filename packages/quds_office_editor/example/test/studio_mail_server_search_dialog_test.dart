import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_server_search.dart';
import 'package:quds_office_studio/studio_mail_server_search_dialog.dart';
import 'package:quds_office_studio/studio_strings.dart';

mail.MimeMessage _message(int uid) {
  final message = mail.MimeMessage.parseFromText(
    'Subject: Invoice $uid\r\n'
    'From: Shop <shop@example.test>\r\n'
    'Date: Sun, 22 Nov 2026 12:00:00 +0000\r\n\r\n'
    'Body',
  );
  message.uid = uid;
  return message;
}

Widget _host({
  required StudioMailServerSearchRunner search,
  void Function(mail.MimeMessage?)? onClosed,
}) => MaterialApp(
  home: Builder(
    builder: (context) => TextButton(
      onPressed: () async {
        final result = await showStudioMailServerSearchDialog(
          context,
          strings: const StudioStrings(StudioLanguage.en),
          mailboxName: 'Inbox',
          search: search,
        );
        onClosed?.call(result);
      },
      child: const Text('open'),
    ),
  ),
);

void main() {
  testWidgets('runs a body search, shows coverage and opens a result', (
    tester,
  ) async {
    final message = _message(42);
    StudioMailServerSearchField? observedField;
    StudioMailServerSearchRange? observedRange;
    String? observedQuery;
    mail.MimeMessage? returned;
    await tester.pumpWidget(
      _host(
        onClosed: (value) => returned = value,
        search: (field, range, query, cancellation) async {
          observedField = field;
          observedRange = range;
          observedQuery = query;
          return StudioMailServerSearchResult(
            field: field,
            range: range,
            query: query,
            mailboxName: 'Inbox',
            totalMatches: 3,
            messages: [message],
            truncated: true,
          );
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-mail-server-range')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 30 days').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('studio-mail-server-query')),
      'invoice',
    );
    await tester.tap(find.byKey(const ValueKey('studio-mail-server-run')));
    await tester.pumpAndSettle();
    expect(observedField, StudioMailServerSearchField.body);
    expect(observedRange, StudioMailServerSearchRange.last30Days);
    expect(observedQuery, 'invoice');
    expect(find.textContaining('3 matches'), findsOneWidget);
    expect(find.textContaining('More matches exist'), findsOneWidget);
    expect(find.text('Invoice 42'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('studio-mail-server-result-42')),
    );
    await tester.pumpAndSettle();
    expect(returned, same(message));
  });

  testWidgets('rejects an empty query without calling the provider', (
    tester,
  ) async {
    var called = false;
    await tester.pumpWidget(
      _host(
        search: (field, range, query, cancellation) async {
          called = true;
          throw StateError('unexpected');
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-mail-server-run')));
    await tester.pump();
    expect(called, isFalse);
    expect(
      find.byKey(const ValueKey('studio-mail-server-error')),
      findsOneWidget,
    );
  });

  testWidgets('stopping discards an in-flight result', (tester) async {
    final Completer<StudioMailServerSearchResult> pending = Completer();
    await tester.pumpWidget(
      _host(
        search: (field, range, query, cancellation) {
          cancellation.throwIfCancelled();
          return pending.future;
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('studio-mail-server-query')),
      'invoice',
    );
    await tester.tap(find.byKey(const ValueKey('studio-mail-server-run')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('studio-mail-server-progress')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('studio-mail-server-stop')));
    await tester.pump();
    pending.complete(
      StudioMailServerSearchResult(
        field: StudioMailServerSearchField.body,
        range: StudioMailServerSearchRange.anyTime,
        query: 'invoice',
        mailboxName: 'Inbox',
        totalMatches: 1,
        messages: [_message(1)],
        truncated: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('studio-mail-server-count')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('studio-mail-server-progress')),
      findsNothing,
    );
  });
}
