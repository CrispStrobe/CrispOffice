import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

String _count(int shown, int loaded) => '$shown shown · $loaded loaded';

const _labels = MailMessageListStrings(
  searchLoaded: 'Search loaded headers',
  unread: 'Unread',
  flagged: 'Flagged',
  noMessages: 'No mail',
  noMatches: 'No matches',
  loadMore: 'Load more',
  loading: 'Loading',
  loadedScope: 'Loaded headers only',
  count: _count,
  groupConversations: 'Conversations',
);

const _rows = [
  MailMessageListItem(
    id: 'parent',
    subject: 'Plan',
    sender: 'alice',
    accountId: 'account-1',
    messageId: '<parent@threads.test>',
  ),
  MailMessageListItem(
    id: 'unrelated',
    subject: 'Plan',
    sender: 'bob',
    accountId: 'account-1',
    messageId: '<unrelated@threads.test>',
  ),
  MailMessageListItem(
    id: 'reply',
    subject: 'Re: Plan',
    sender: 'carol',
    accountId: 'account-1',
    inReplyTo: '<parent@threads.test>',
  ),
];

Widget _app({
  List<MailMessageListItem> rows = _rows,
  String scope = 'account-1/inbox',
  void Function(String)? onOpen,
  void Function(MailBulkFlagAction, List<String>)? onBulk,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 460,
      height: 680,
      child: MailMessageList(
        items: rows,
        strings: _labels,
        scopeId: scope,
        onOpen: onOpen ?? (_) {},
        onBulkAction: onBulk,
      ),
    ),
  ),
);

Finder _row(String id) => find.byKey(ValueKey(id));

List<String> _order(WidgetTester tester, List<String> ids) => [...ids]
  ..sort(
    (a, b) =>
        tester.getTopLeft(_row(a)).dy.compareTo(tester.getTopLeft(_row(b)).dy),
  );

Future<void> _toggle(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('mail-list-conversations')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('groups explicit loaded threads without collapsing or fetching', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(_app(onOpen: opened.add));
    expect(_order(tester, ['parent', 'unrelated', 'reply']), [
      'parent',
      'unrelated',
      'reply',
    ]);
    expect(find.byIcon(Icons.forum_outlined), findsNothing);
    await _toggle(tester);
    expect(_order(tester, ['parent', 'unrelated', 'reply']), [
      'parent',
      'reply',
      'unrelated',
    ]);
    expect(find.byTooltip('2 loaded messages in conversation'), findsOneWidget);
    expect(_row('parent'), findsOneWidget);
    expect(_row('reply'), findsOneWidget);
    await tester.tap(_row('reply'));
    await tester.pump();
    expect(opened, ['reply']);
  });

  testWidgets('search and bulk operate only on actually visible rows', (
    tester,
  ) async {
    MailBulkFlagAction? action;
    List<String>? selected;
    await tester.pumpWidget(
      _app(onBulk: (value, ids) {
        action = value;
        selected = ids;
      }),
    );
    await _toggle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('mail-list-search')),
      'Plan',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mail-list-select-shown')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mail-list-bulk-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mail-list-bulk-markRead')));
    await tester.pumpAndSettle();
    expect(action, MailBulkFlagAction.markRead);
    expect(selected, ['parent', 'reply', 'unrelated']);

    await tester.enterText(
      find.byKey(const ValueKey('mail-list-search')),
      'Re: Plan',
    );
    await tester.pump();
    expect(_row('parent'), findsNothing);
    expect(_row('reply'), findsOneWidget);
    expect(find.byIcon(Icons.forum_outlined), findsNothing);
    expect(find.text('0 selected'), findsOneWidget);
  });

  testWidgets('account namespaces prevent false conversation grouping', (
    tester,
  ) async {
    await tester.pumpWidget(_app(rows: [
      _rows.first,
      const MailMessageListItem(
        id: 'foreign',
        subject: 'Foreign reply',
        sender: 'other',
        accountId: 'account-2',
        inReplyTo: '<parent@threads.test>',
      ),
      _rows.last,
    ]));
    await _toggle(tester);
    expect(_order(tester, ['parent', 'foreign', 'reply']), [
      'parent',
      'reply',
      'foreign',
    ]);
    expect(find.byTooltip('2 loaded messages in conversation'), findsOneWidget);
  });

  testWidgets('absent metadata does not offer a misleading grouping control', (
    tester,
  ) async {
    await tester.pumpWidget(_app(rows: [
      const MailMessageListItem(
        id: 'no-metadata',
        subject: 'Hello',
        sender: 'sender',
      ),
    ]));
    expect(find.byKey(const ValueKey('mail-list-conversations')), findsNothing);
  });

  testWidgets('changing account or folder scope resets the grouping choice', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _toggle(tester);
    expect(
      tester.widget<FilterChip>(
        find.byKey(const ValueKey('mail-list-conversations')),
      ).selected,
      isTrue,
    );
    await tester.pumpWidget(_app(scope: 'account-1/archive'));
    await tester.pump();
    expect(
      tester.widget<FilterChip>(
        find.byKey(const ValueKey('mail-list-conversations')),
      ).selected,
      isFalse,
    );
    expect(_order(tester, ['parent', 'unrelated', 'reply']), [
      'parent',
      'unrelated',
      'reply',
    ]);
  });
}
