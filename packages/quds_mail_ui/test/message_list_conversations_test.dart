import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  TextDirection direction = TextDirection.ltr,
  double width = 460,
  double textScale = 1,
  bool busy = false,
}) => MaterialApp(
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Directionality(
        textDirection: direction,
        child: SizedBox(
          width: width,
          height: 680,
          child: MailMessageList(
            items: rows,
            strings: _labels,
            scopeId: scope,
            onOpen: onOpen ?? (_) {},
            onBulkAction: onBulk,
            busy: busy,
          ),
        ),
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

Finder _disclosure(String id) =>
    find.byKey(ValueKey('mail-list-conversation-toggle-$id'));

Future<void> _collapse(WidgetTester tester, [String id = 'parent']) async {
  await tester.tap(_disclosure(id));
  await tester.pumpAndSettle();
}

Future<void> _sort(WidgetTester tester, MailMessageListSort sort) async {
  await tester.tap(find.byKey(const ValueKey('mail-list-sort')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('mail-list-sort-${sort.name}')));
  await tester.pumpAndSettle();
}

final _observedRows = [
  MailMessageListItem(
    id: 'parent',
    subject: 'Plan',
    sender: 'alice',
    date: DateTime(2026, 1, 1),
    accountId: 'account-1',
    messageId: '<parent@threads.test>',
    isRead: false,
    isFlagged: true,
  ),
  MailMessageListItem(
    id: 'known',
    subject: 'Re: Plan',
    sender: 'bob',
    date: DateTime(2026, 1, 2),
    accountId: 'account-1',
    inReplyTo: '<parent@threads.test>',
    isRead: true,
    isFlagged: false,
  ),
  MailMessageListItem(
    id: 'reply',
    subject: 'Re: Plan',
    sender: 'carol',
    date: DateTime(2026, 1, 3),
    accountId: 'account-1',
    inReplyTo: '<parent@threads.test>',
  ),
];

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
    expect(find.byTooltip('2 loaded messages in conversation'), findsNothing);
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
      _app(
        onBulk: (value, ids) {
          action = value;
          selected = ids;
        },
      ),
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
      'subject:"Re: Plan"',
    );
    await tester.pump();
    expect(_row('parent'), findsNothing);
    expect(_row('reply'), findsOneWidget);
    expect(find.byTooltip('2 loaded messages in conversation'), findsNothing);
    expect(find.text('0 selected'), findsOneWidget);
  });

  testWidgets('persistent keys group cross-folder rows without references', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        rows: [
          const MailMessageListItem(
            id: 'inbox',
            subject: 'Plan',
            sender: 'alice',
            accountId: 'account-1',
            conversationId: 'thread-1',
            messageId: '<inbox-copy@threads.test>',
          ),
          const MailMessageListItem(
            id: 'unrelated',
            subject: 'Other',
            sender: 'bob',
            accountId: 'account-1',
            messageId: '<other@threads.test>',
          ),
          const MailMessageListItem(
            id: 'sent',
            subject: 'Re: Plan',
            sender: 'alice',
            accountId: 'account-1',
            conversationId: 'thread-1',
            messageId: '<sent-copy@threads.test>',
          ),
        ],
      ),
    );
    await _toggle(tester);
    expect(_order(tester, ['inbox', 'unrelated', 'sent']), [
      'inbox',
      'sent',
      'unrelated',
    ]);
    expect(find.byTooltip('2 loaded messages in conversation'), findsOneWidget);
  });

  testWidgets('account namespaces prevent false conversation grouping', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        rows: [
          _rows.first,
          const MailMessageListItem(
            id: 'foreign',
            subject: 'Foreign reply',
            sender: 'other',
            accountId: 'account-2',
            inReplyTo: '<parent@threads.test>',
          ),
          _rows.last,
        ],
      ),
    );
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
    await tester.pumpWidget(
      _app(
        rows: [
          const MailMessageListItem(
            id: 'no-metadata',
            subject: 'Hello',
            sender: 'sender',
          ),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('mail-list-conversations')), findsNothing);
  });

  testWidgets('changing account or folder scope resets the grouping choice', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _toggle(tester);
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('mail-list-conversations')),
          )
          .selected,
      isTrue,
    );
    await tester.pumpWidget(_app(scope: 'account-1/archive'));
    await tester.pump();
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('mail-list-conversations')),
          )
          .selected,
      isFalse,
    );
    expect(_order(tester, ['parent', 'unrelated', 'reply']), [
      'parent',
      'unrelated',
      'reply',
    ]);
  });

  testWidgets(
    'collapse prunes hidden selection and bulk uses shown identities',
    (tester) async {
      final opened = <String>[];
      final actions = <List<String>>[];
      await tester.pumpWidget(
        _app(onOpen: opened.add, onBulk: (_, ids) => actions.add(ids)),
      );
      await _toggle(tester);
      await tester.tap(find.byKey(const ValueKey('mail-list-select-shown')));
      await tester.pump();
      expect(find.text('3 selected'), findsOneWidget);
      await _collapse(tester);
      expect(_row('reply'), findsNothing);
      expect(_row('parent'), findsOneWidget);
      expect(_row('unrelated'), findsOneWidget);
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('2 shown · 3 loaded'), findsOneWidget);
      expect(opened, isEmpty);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mail-list-bulk-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mail-list-bulk-markRead')));
      await tester.pumpAndSettle();
      expect(actions, [
        ['parent', 'unrelated'],
      ]);
      await _collapse(tester);
      expect(_row('reply'), findsOneWidget);
      expect(find.text('0 selected'), findsOneWidget);
      expect(opened, isEmpty);
    },
  );

  testWidgets(
    'aggregate counts use observed filtered members even when collapsed',
    (tester) async {
      await tester.pumpWidget(_app(rows: _observedRows));
      await _toggle(tester);
      expect(find.text('3 loaded · 1 unread · 1 flagged'), findsOneWidget);
      expect(
        find.byTooltip('Read state unknown: 1 · Flag state unknown: 1'),
        findsOneWidget,
      );
      await _collapse(tester);
      expect(_row('reply'), findsNothing);
      expect(_row('known'), findsNothing);
      expect(find.text('3 loaded · 1 unread · 1 flagged'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('mail-list-search')),
        'NOT from:bob',
      );
      await tester.pumpAndSettle();
      expect(find.text('2 loaded · 1 unread · 1 flagged'), findsOneWidget);
      expect(_row('reply'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('mail-list-search')),
        'is:unread',
      );
      await tester.pumpAndSettle();
      expect(_row('parent'), findsOneWidget);
      expect(_disclosure('parent'), findsNothing);
      expect(_row('reply'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mail-list-clear-search')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Expand conversation'), findsOneWidget);
      expect(_row('reply'), findsNothing);
      expect(find.text('3 loaded · 1 unread · 1 flagged'), findsOneWidget);
    },
  );

  testWidgets('collapse follows stable members through sorting and growth', (
    tester,
  ) async {
    await tester.pumpWidget(_app(rows: _observedRows, onBulk: (_, _) {}));
    await _toggle(tester);
    await tester.tap(find.byKey(const ValueKey('mail-list-check-parent')));
    await tester.pump();
    await _collapse(tester);
    await _sort(tester, MailMessageListSort.newestFirst);
    expect(_row('reply'), findsOneWidget);
    expect(_row('parent'), findsNothing);
    expect(find.byTooltip('Expand conversation'), findsOneWidget);
    expect(find.text('0 selected'), findsOneWidget);

    final expandedRows = [
      ..._observedRows,
      MailMessageListItem(
        id: 'new',
        subject: 'New reply',
        sender: 'dave',
        date: DateTime(2026, 1, 4),
        accountId: 'account-1',
        inReplyTo: '<parent@threads.test>',
        isRead: false,
        isFlagged: false,
      ),
    ];
    await tester.pumpWidget(_app(rows: expandedRows, onBulk: (_, _) {}));
    await tester.pumpAndSettle();
    expect(_row('new'), findsOneWidget);
    expect(_row('reply'), findsNothing);
    expect(_row('parent'), findsNothing);
    expect(find.text('4 loaded · 2 unread · 1 flagged'), findsOneWidget);
    await tester.pumpWidget(
      _app(
        rows: expandedRows.where((item) => item.id != 'parent').toList(),
        onBulk: (_, _) {},
      ),
    );
    await tester.pumpAndSettle();
    expect(_row('new'), findsOneWidget);
    expect(_row('reply'), findsNothing);
    expect(find.text('3 loaded · 1 unread · 0 flagged'), findsOneWidget);
    await _collapse(tester, 'new');
    expect(_row('reply'), findsOneWidget);
    expect(_row('known'), findsOneWidget);
  });

  testWidgets(
    'expanded choice clears hidden members remembered before filtering',
    (tester) async {
      await tester.pumpWidget(_app(rows: _observedRows));
      await _toggle(tester);
      await _collapse(tester);
      await tester.enterText(
        find.byKey(const ValueKey('mail-list-search')),
        'NOT from:bob',
      );
      await tester.pumpAndSettle();
      await _collapse(tester);
      await tester.tap(find.byKey(const ValueKey('mail-list-clear-search')));
      await tester.pumpAndSettle();
      expect(_row('parent'), findsOneWidget);
      expect(_row('reply'), findsOneWidget);
      expect(_row('known'), findsOneWidget);
      expect(find.byTooltip('Collapse conversation'), findsOneWidget);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'keyboard disclosure follows $direction and keeps individual opening',
      (tester) async {
        final opened = <String>[];
        await tester.pumpWidget(_app(direction: direction, onOpen: opened.add));
        await _toggle(tester);
        await tester.tap(_row('parent'));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(
          direction == TextDirection.ltr
              ? LogicalKeyboardKey.arrowLeft
              : LogicalKeyboardKey.arrowRight,
        );
        await tester.pumpAndSettle();
        expect(_row('reply'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(opened, ['parent', 'parent']);
        await tester.sendKeyEvent(
          direction == TextDirection.ltr
              ? LogicalKeyboardKey.arrowRight
              : LogicalKeyboardKey.arrowLeft,
        );
        await tester.pumpAndSettle();
        expect(_row('reply'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(opened, ['parent', 'parent', 'reply']);
      },
    );
  }

  testWidgets(
    'collapse rejects old row callbacks and an already opened bulk menu',
    (tester) async {
      final opened = <String>[];
      final actions = <List<String>>[];
      await tester.pumpWidget(
        _app(onOpen: opened.add, onBulk: (_, ids) => actions.add(ids)),
      );
      await _toggle(tester);
      final staleOpen = tester
          .widget<InkWell>(
            find
                .descendant(of: _row('reply'), matching: find.byType(InkWell))
                .first,
          )
          .onTap!;
      await tester.tap(find.byKey(const ValueKey('mail-list-select-shown')));
      await tester.pump();
      final collapse = tester
          .widget<IconButton>(
            find.descendant(
              of: _disclosure('parent'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed!;
      await tester.tap(find.byKey(const ValueKey('mail-list-bulk-actions')));
      await tester.pumpAndSettle();
      collapse();
      await tester.pump();
      staleOpen();
      await tester.tap(find.byKey(const ValueKey('mail-list-bulk-markRead')));
      await tester.pumpAndSettle();
      expect(actions, isEmpty);
      expect(opened, isEmpty);
      expect(_row('reply'), findsNothing);
      expect(find.text('2 selected'), findsOneWidget);
    },
  );

  testWidgets('stale disclosure cannot change refreshed or replaced scope', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _toggle(tester);
    final stale = tester
        .widget<IconButton>(
          find.descendant(
            of: _disclosure('parent'),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!;
    await tester.pumpWidget(_app(rows: [..._rows]));
    await tester.pump();
    stale();
    await tester.pump();
    expect(_row('reply'), findsOneWidget);
    await _collapse(tester);
    await tester.pumpWidget(_app(scope: 'account-1/archive'));
    await _toggle(tester);
    expect(_row('reply'), findsOneWidget);
    expect(find.byTooltip('Collapse conversation'), findsOneWidget);
  });

  testWidgets(
    'same local IDs in another account do not inherit collapse state',
    (tester) async {
      await tester.pumpWidget(_app());
      await _toggle(tester);
      await _collapse(tester);
      await tester.pumpWidget(
        _app(
          rows: [
            for (final row in _rows)
              MailMessageListItem(
                id: row.id,
                subject: row.subject,
                sender: row.sender,
                accountId: 'account-2',
                messageId: row.messageId,
                inReplyTo: row.inReplyTo,
              ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(_row('reply'), findsOneWidget);
      expect(find.byTooltip('Collapse conversation'), findsOneWidget);
    },
  );

  testWidgets('busy state disables disclosure and does not prune selection', (
    tester,
  ) async {
    await tester.pumpWidget(_app(onBulk: (_, _) {}));
    await _toggle(tester);
    await tester.tap(find.byKey(const ValueKey('mail-list-select-shown')));
    await tester.pump();
    await tester.pumpWidget(_app(busy: true, onBulk: (_, _) {}));
    await tester.pump();
    final disclosure = tester.widget<IconButton>(
      find.descendant(
        of: _disclosure('parent'),
        matching: find.byType(IconButton),
      ),
    );
    expect(disclosure.onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_row('reply'), findsOneWidget);
    expect(find.text('3 selected'), findsOneWidget);
  });

  testWidgets('compact RTL with enlarged text keeps disclosure usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        rows: _observedRows,
        width: 240,
        textScale: 2,
        direction: TextDirection.rtl,
        onBulk: (_, _) {},
      ),
    );
    await _toggle(tester);
    expect(tester.takeException(), isNull);
    await _collapse(tester);
    expect(tester.takeException(), isNull);
    expect(_row('reply'), findsNothing);
    expect(find.byTooltip('Expand conversation'), findsOneWidget);
    await _collapse(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disclosure exposes the current accessible expansion action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    await _toggle(tester);
    expect(
      tester.getSemantics(_disclosure('parent')),
      isSemantics(
        isButton: true,
        isEnabled: true,
        hasExpandedState: true,
        isExpanded: true,
        label: 'Collapse conversation: 2 loaded messages in conversation',
      ),
    );
    final expanded = tester
        .getSemantics(_disclosure('parent'))
        .getSemanticsData();
    expect(expanded.hasAction(SemanticsAction.collapse), isTrue);
    expect(expanded.hasAction(SemanticsAction.expand), isFalse);
    await _collapse(tester);
    expect(
      tester.getSemantics(_disclosure('parent')),
      isSemantics(
        isButton: true,
        hasExpandedState: true,
        isExpanded: false,
        label: 'Expand conversation: 2 loaded messages in conversation',
      ),
    );
    final collapsed = tester
        .getSemantics(_disclosure('parent'))
        .getSemanticsData();
    expect(collapsed.hasAction(SemanticsAction.collapse), isFalse);
    expect(collapsed.hasAction(SemanticsAction.expand), isTrue);
    semantics.dispose();
  });

  testWidgets('observed metadata refresh updates a collapsed aggregate', (
    tester,
  ) async {
    await tester.pumpWidget(_app(rows: _observedRows));
    await _toggle(tester);
    await _collapse(tester);
    await tester.pumpWidget(
      _app(
        rows: [
          for (final item in _observedRows)
            MailMessageListItem(
              id: item.id,
              subject: item.subject,
              sender: item.sender,
              date: item.date,
              accountId: item.accountId,
              messageId: item.messageId,
              inReplyTo: item.inReplyTo,
              isRead: true,
              isFlagged: false,
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(_row('reply'), findsNothing);
    expect(find.text('3 loaded · 0 unread · 0 flagged'), findsOneWidget);
    expect(
      find.byIcon(Icons.help_outline),
      findsOneWidget,
    ); // Search help only.
    expect(find.byTooltip('Expand conversation'), findsOneWidget);
  });
}
