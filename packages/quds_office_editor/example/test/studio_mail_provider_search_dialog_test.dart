import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_provider_search.dart';
import 'package:quds_office_studio/studio_mail_server_search_dialog.dart';
import 'package:quds_office_studio/studio_strings.dart';

final _account = MailAccountId(
  'account',
  profile: MailProfileId('profile', hostId: 'studio'),
);
final _mailbox = MailMailboxId('inbox', account: _account);
final _header = MailHeaderRecord(
  id: MailMessageId('cloud-result'),
  remote: MailOpaqueIdentity(
    account: _account,
    provider: MailProviderKind.gmail,
    value: 'cloud-result',
  ),
  envelope: MailEnvelope(
    subject: 'Provider invoice',
    from: [const MailAddress('shop@example.test', displayName: 'Shop')],
  ),
);

Widget _host({
  required StudioMailProviderSearchRunner search,
  ValueChanged<MailHeaderRecord?>? onClosed,
}) => MaterialApp(
  home: Builder(
    builder: (context) => TextButton(
      onPressed: () async {
        final result = await showStudioMailProviderSearchDialog(
          context,
          strings: const StudioStrings(StudioLanguage.en),
          mailboxName: 'Inbox',
          fields: const {
            MailProviderSearchField.subject,
            MailProviderSearchField.from,
            MailProviderSearchField.to,
          },
          search: search,
        );
        onClosed?.call(result);
      },
      child: const Text('open'),
    ),
  ),
);

Future<void> _search(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('studio-mail-server-query')),
    'invoice',
  );
  await tester.tap(find.byKey(const ValueKey('studio-mail-server-run')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers only provider fields and labels estimates honestly', (
    tester,
  ) async {
    MailProviderSearchField? searchedField;
    MailHeaderRecord? opened;
    await tester.pumpWidget(
      _host(
        onClosed: (value) => opened = value,
        search: (field, range, query, cancellation) async {
          searchedField = field;
          return MailProviderSearchResult(
            mailbox: _mailbox,
            messages: [_header],
            hasMore: true,
            totalCount: 240,
            countPrecision: MailSearchCountPrecision.estimate,
          );
        },
      ),
    );
    await _search(tester);
    expect(searchedField, MailProviderSearchField.subject);
    expect(find.text('Folder: Inbox'), findsOneWidget);
    expect(find.textContaining('About 240 matches'), findsOneWidget);
    expect(
      find.textContaining('More matches may be available'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('studio-mail-server-field')));
    await tester.pumpAndSettle();
    expect(find.text('Message body'), findsNothing);
    await tester.tap(find.text('Subject').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('studio-mail-server-result-cloud-result')),
    );
    await tester.pumpAndSettle();
    expect(opened, same(_header));
  });

  testWidgets('unknown total does not invent an exact count', (tester) async {
    await tester.pumpWidget(
      _host(
        search: (field, range, query, cancellation) async =>
            MailProviderSearchResult(
              mailbox: _mailbox,
              messages: [_header],
              hasMore: false,
            ),
      ),
    );
    await _search(tester);
    expect(find.text('Showing 1 · total unavailable'), findsOneWidget);
    expect(find.textContaining('More matches'), findsNothing);
    expect(find.text('Provider invoice'), findsOneWidget);
  });

  testWidgets('unsupported query and authorization errors stay actionable', (
    tester,
  ) async {
    var failure = MailProblemCode.unsupported;
    await tester.pumpWidget(
      _host(
        search: (_, _, _, _) async =>
            throw StudioMailProviderSearchFailure(failure),
      ),
    );
    await _search(tester);
    expect(
      find.textContaining('without quotes and backslashes'),
      findsOneWidget,
    );
    failure = MailProblemCode.authenticationRequired;
    await tester.tap(find.byKey(const ValueKey('studio-mail-server-run')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reconnect the account'), findsOneWidget);
    expect(find.textContaining('without quotes and backslashes'), findsNothing);
  });
}
