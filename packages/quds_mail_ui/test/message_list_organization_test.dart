import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

const _flags = {
  MailBulkFlagAction.markRead,
  MailBulkFlagAction.markUnread,
  MailBulkFlagAction.flag,
  MailBulkFlagAction.unflag,
};

String _count(int shown, int loaded) => '$shown shown · $loaded loaded';

const _strings = MailMessageListStrings(
  searchLoaded: 'Search',
  unread: 'Unread',
  flagged: 'Flagged',
  noMessages: 'Empty',
  noMatches: 'No matches',
  loadMore: 'Load more',
  loading: 'Loading',
  loadedScope: 'Loaded headers only',
  count: _count,
);

const _rows = [
  MailMessageListItem(id: 'z', subject: 'Zebra project', sender: 'Zoe'),
  MailMessageListItem(id: 'a', subject: 'Alpha project', sender: 'Alice'),
  MailMessageListItem(id: 'b', subject: 'Beta notice', sender: 'Bob'),
];

const _threadRows = [
  MailMessageListItem(
    id: 'parent',
    subject: 'Plan',
    sender: 'Alice',
    accountId: 'account-1',
    messageId: '<plan@example.test>',
  ),
  MailMessageListItem(
    id: 'other',
    subject: 'Another plan',
    sender: 'Bob',
    accountId: 'account-1',
  ),
  MailMessageListItem(
    id: 'reply',
    subject: 'Re: Plan',
    sender: 'Carol',
    accountId: 'account-1',
    inReplyTo: '<plan@example.test>',
  ),
  MailMessageListItem(
    id: 'filtered',
    subject: 'Invoice',
    sender: 'David',
    accountId: 'account-1',
  ),
];

MailMessageList _list({
  List<MailMessageListItem> rows = _rows,
  Set<MailBulkFlagAction> actions = _flags,
  MailMessageListStrings strings = _strings,
  void Function(MailBulkFlagAction, List<String>)? onBulk,
  void Function(String)? onOpen,
  VoidCallback? onLoadMore,
}) => MailMessageList(
  items: rows,
  strings: strings,
  scopeId: 'account-1/inbox',
  supportedBulkActions: actions,
  onBulkAction: onBulk,
  onOpen: onOpen ?? (_) {},
  onLoadMore: onLoadMore,
  hasMore: onLoadMore != null,
);

Widget _app(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
}) => MaterialApp(
  builder: (context, navigator) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: Directionality(textDirection: direction, child: navigator!),
  ),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 440, height: 600, child: child),
    ),
  ),
);

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _tap(WidgetTester tester, String value) async {
  if (_key(value).evaluate().isEmpty) {
    final filters = find.byKey(const ValueKey('mail-list-filters'));
    if (filters.evaluate().isNotEmpty) {
      await tester.tap(filters);
      await tester.pumpAndSettle();
    }
  }
  final finder = _key(value);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _invoke(WidgetTester tester, MailBulkFlagAction action) async {
  await _tap(tester, 'mail-list-bulk-actions');
  await _tap(tester, 'mail-list-bulk-${action.name}');
}

void _expectSelected(WidgetTester tester, int count) {
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('mail-list-selected-count')))
        .data,
    '$count',
  );
}

void main() {
  test('default action snapshot remains the four immutable flag choices', () {
    final list = MailMessageList(
      items: _rows,
      strings: _strings,
      onOpen: (_) {},
    );
    expect(list.supportedBulkActions, _flags);
    expect(
      () => list.supportedBulkActions.add(MailBulkFlagAction.move),
      throwsUnsupportedError,
    );
    expect(_strings.move, 'Move…');
    expect(_strings.delete, 'Delete…');
  });

  test('host action set is defensively copied before it can change', () {
    final source = {MailBulkFlagAction.move};
    final list = _list(actions: source);
    source
      ..clear()
      ..add(MailBulkFlagAction.delete);
    expect(list.supportedBulkActions, {MailBulkFlagAction.move});
    expect(() => list.supportedBulkActions.clear(), throwsUnsupportedError);
  });

  testWidgets('legacy list menu does not acquire organization actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MailMessageList(
          items: _rows,
          strings: _strings,
          onOpen: (_) {},
          onBulkAction: (_, _) {},
        ),
      ),
    );
    await _tap(tester, 'mail-list-select-shown');
    await _tap(tester, 'mail-list-bulk-actions');
    for (final action in _flags) {
      expect(_key('mail-list-bulk-${action.name}'), findsOneWidget);
    }
    expect(_key('mail-list-bulk-move'), findsNothing);
    expect(_key('mail-list-bulk-delete'), findsNothing);
    expect(_key('mail-list-bulk-archive'), findsNothing);
  });

  for (final actions in [
    {MailBulkFlagAction.move},
    {MailBulkFlagAction.delete},
    {MailBulkFlagAction.archive},
    {..._flags, MailBulkFlagAction.move, MailBulkFlagAction.delete},
  ]) {
    testWidgets('menu exposes exactly the supported set $actions', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(_list(actions: actions, onBulk: (_, _) => calls++)),
      );
      await _tap(tester, 'mail-list-select-shown');
      await _tap(tester, 'mail-list-bulk-actions');
      for (final action in MailBulkFlagAction.values) {
        expect(
          _key('mail-list-bulk-${action.name}'),
          actions.contains(action) ? findsOneWidget : findsNothing,
        );
      }
      expect(calls, 0);
    });
  }

  testWidgets('cached host never shows actions even when a set is supplied', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _list(
          actions: {
            MailBulkFlagAction.move,
            MailBulkFlagAction.delete,
            MailBulkFlagAction.archive,
          },
        ),
      ),
    );
    expect(_key('mail-list-bulk-actions'), findsNothing);
    expect(_key('mail-list-select-shown'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('an empty supported set cannot select or invoke an action', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(_list(actions: const {}, onBulk: (_, _) => calls++)),
    );
    await _tap(tester, 'mail-list-select-shown');
    await _tap(tester, 'mail-list-bulk-actions');
    _expectSelected(tester, 0);
    expect(_key('mail-list-bulk-move'), findsNothing);
    expect(calls, 0);
    expect(
      tester.widget<Checkbox>(_key('mail-list-check-z')).onChanged,
      isNull,
    );
  });

  for (final action in [
    MailBulkFlagAction.move,
    MailBulkFlagAction.delete,
    MailBulkFlagAction.archive,
  ]) {
    testWidgets('$action receives immutable visible order without reads', (
      tester,
    ) async {
      final calls = <(MailBulkFlagAction, List<String>)>[];
      var opens = 0;
      var loads = 0;
      await tester.pumpWidget(
        _app(
          _list(
            actions: {action},
            onBulk: (action, ids) => calls.add((action, ids)),
            onOpen: (_) => opens++,
            onLoadMore: () => loads++,
          ),
        ),
      );
      await _tap(tester, 'mail-list-select-shown');
      await tester.enterText(_key('mail-list-search'), 'subject:project');
      await tester.pumpAndSettle();
      await _tap(tester, 'mail-list-sort');
      await _tap(tester, 'mail-list-sort-subjectAscending');
      await _invoke(tester, action);
      expect(calls, hasLength(1));
      expect(calls.single.$1, action);
      expect(calls.single.$2, ['a', 'z']);
      expect(() => calls.single.$2.add('injected'), throwsUnsupportedError);
      _expectSelected(tester, 0);
      expect(opens, 0);
      expect(loads, 0);
    });

    testWidgets('$action excludes collapsed and filtered checked members', (
      tester,
    ) async {
      final calls = <List<String>>[];
      await tester.pumpWidget(
        _app(
          _list(
            rows: _threadRows,
            actions: {action},
            onBulk: (_, ids) => calls.add(ids),
          ),
        ),
      );
      await _tap(tester, 'mail-list-conversations');
      await _tap(tester, 'mail-list-select-shown');
      _expectSelected(tester, 4);
      await _tap(tester, 'mail-list-conversation-toggle-parent');
      await tester.enterText(_key('mail-list-search'), 'subject:plan');
      await tester.pumpAndSettle();
      _expectSelected(tester, 2);
      await _invoke(tester, action);
      expect(calls.single, ['parent', 'other']);
    });
  }

  for (final replacement in [
    {MailBulkFlagAction.delete},
    {MailBulkFlagAction.move, MailBulkFlagAction.delete},
    <MailBulkFlagAction>{},
  ]) {
    testWidgets('open menu is retired when capabilities become $replacement', (
      tester,
    ) async {
      var supported = {MailBulkFlagAction.move};
      var calls = 0;
      late StateSetter updateHost;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return _list(actions: supported, onBulk: (_, _) => calls++);
            },
          ),
        ),
      );
      await _tap(tester, 'mail-list-select-shown');
      await _tap(tester, 'mail-list-bulk-actions');
      expect(_key('mail-list-bulk-move'), findsOneWidget);
      updateHost(() => supported = replacement);
      await tester.pump();
      await _tap(tester, 'mail-list-bulk-move');
      expect(calls, 0);
      if (replacement.isEmpty) {
        _expectSelected(tester, 0);
      } else {
        await _invoke(tester, replacement.first);
        expect(calls, 1);
      }
    });
  }

  testWidgets('mutating the caller set cannot alter an already opened menu', (
    tester,
  ) async {
    final source = {MailBulkFlagAction.move};
    final calls = <MailBulkFlagAction>[];
    await tester.pumpWidget(
      _app(_list(actions: source, onBulk: (action, _) => calls.add(action))),
    );
    await _tap(tester, 'mail-list-select-shown');
    await _tap(tester, 'mail-list-bulk-actions');
    source
      ..clear()
      ..add(MailBulkFlagAction.delete);
    await _tap(tester, 'mail-list-bulk-move');
    expect(calls, [MailBulkFlagAction.move]);
    await _tap(tester, 'mail-list-select-shown');
    await _tap(tester, 'mail-list-bulk-actions');
    expect(_key('mail-list-bulk-move'), findsOneWidget);
    expect(_key('mail-list-bulk-delete'), findsNothing);
  });

  for (final locale in ['de', 'ar']) {
    testWidgets('$locale organization labels fit narrow enlarged menus', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rtl = locale == 'ar';
      final labels = MailMessageListStrings(
        searchLoaded: rtl ? 'البحث في البريد' : 'E-Mails durchsuchen',
        unread: rtl ? 'غير مقروءة' : 'Ungelesen',
        flagged: rtl ? 'المعلّمة' : 'Gekennzeichnet',
        noMessages: 'Empty',
        noMatches: 'No matches',
        loadMore: 'More',
        loading: 'Loading',
        loadedScope: 'Loaded',
        count: _count,
        move: rtl
            ? 'نقل الرسائل المحددة إلى مجلد آخر…'
            : 'Ausgewählte Nachrichten in einen anderen Ordner verschieben…',
        delete: rtl
            ? 'حذف الرسائل المحددة بعد التأكيد…'
            : 'Ausgewählte Nachrichten nach Bestätigung löschen…',
      );
      final calls = <MailBulkFlagAction>[];
      await tester.pumpWidget(
        _app(
          _list(
            strings: labels,
            actions: {MailBulkFlagAction.move, MailBulkFlagAction.delete},
            onBulk: (action, _) => calls.add(action),
          ),
          direction: rtl ? TextDirection.rtl : TextDirection.ltr,
          scale: 1.7,
        ),
      );
      await _tap(tester, 'mail-list-select-shown');
      await _tap(tester, 'mail-list-bulk-actions');
      expect(find.text(labels.move), findsOneWidget);
      expect(find.text(labels.delete), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, 'mail-list-bulk-delete');
      expect(calls, [MailBulkFlagAction.delete]);
      expect(tester.takeException(), isNull);
    });
  }
}
