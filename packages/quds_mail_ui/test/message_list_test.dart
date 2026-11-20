import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

String _count(int shown, int loaded) => '$shown shown · $loaded loaded';

const _strings = MailMessageListStrings(
  searchLoaded: 'Search loaded messages',
  unread: 'Unread',
  flagged: 'Flagged',
  noMessages: 'No messages loaded',
  noMatches: 'No loaded messages match',
  loadMore: 'Load more messages',
  loading: 'Loading messages',
  loadedScope: 'Search and filters apply to loaded messages.',
  count: _count,
);

const _items = [
  MailMessageListItem(
    id: 'one',
    subject: 'Alpha planning',
    sender: 'alice@example.test',
    dateLabel: '20 November',
    isRead: false,
    isFlagged: true,
  ),
  MailMessageListItem(
    id: 'two',
    subject: 'Beta planning',
    sender: 'bob@example.test',
    isRead: true,
    isFlagged: true,
  ),
  MailMessageListItem(
    id: 'three',
    subject: 'Gamma update',
    sender: 'alice@example.test',
    isRead: false,
    isFlagged: false,
  ),
  MailMessageListItem(
    id: 'unknown',
    subject: 'Unobserved flags',
    sender: 'unknown@example.test',
  ),
];

Widget _app(
  Widget child, {
  double width = 360,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ),
);

MailMessageList _list({
  List<MailMessageListItem> items = _items,
  void Function(String)? onOpen,
  String? selectedId,
  String scopeId = 'account-a/inbox',
  bool busy = false,
  bool hasMore = false,
  VoidCallback? onLoadMore,
  String? limitNotice,
  Key? loadMoreKey,
}) => MailMessageList(
  items: items,
  strings: _strings,
  onOpen: onOpen ?? (_) {},
  selectedId: selectedId,
  scopeId: scopeId,
  busy: busy,
  hasMore: hasMore,
  onLoadMore: onLoadMore,
  limitNotice: limitNotice,
  loadMoreKey: loadMoreKey,
);

Future<void> _focusList(WidgetTester tester) async {
  tester
      .widget<Focus>(find.byKey(const ValueKey('mail-list-focus')))
      .focusNode!
      .requestFocus();
  await tester.pump();
}

Finder _row(String id) => find.byKey(ValueKey(id));

void main() {
  test('row collection is immutable and identities cannot alias', () {
    final source = [..._items];
    final list = _list(items: source);
    source.clear();
    expect(list.items, hasLength(4));
    expect(() => list.items.clear(), throwsUnsupportedError);
    expect(
      () => _list(items: [_items.first, _items.first]),
      throwsArgumentError,
    );
    expect(
      () => _list(
        items: [const MailMessageListItem(id: '', subject: '', sender: '')],
      ),
      throwsArgumentError,
    );
  });

  testWidgets('shows honest loaded scope without opening or fetching', (
    tester,
  ) async {
    var opens = 0;
    var loads = 0;
    await tester.pumpWidget(
      _app(
        _list(onOpen: (_) => opens++, hasMore: true, onLoadMore: () => loads++),
      ),
    );
    expect(
      find.text('4 shown · 4 loaded\n${_strings.loadedScope}'),
      findsOneWidget,
    );
    expect(find.text('Load more messages'), findsOneWidget);
    expect(opens, 0);
    expect(loads, 0);
  });

  testWidgets('search matches subject and sender without network work', (
    tester,
  ) async {
    var opens = 0;
    var loads = 0;
    await tester.pumpWidget(
      _app(
        _list(onOpen: (_) => opens++, hasMore: true, onLoadMore: () => loads++),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('mail-list-search')),
      '  ALICE@EXAMPLE  ',
    );
    await tester.pump();
    expect(_row('one'), findsOneWidget);
    expect(_row('three'), findsOneWidget);
    expect(_row('two'), findsNothing);
    expect(_row('unknown'), findsNothing);
    expect(
      find.text('2 shown · 4 loaded\n${_strings.loadedScope}'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('mail-list-search')),
      'planning',
    );
    await tester.pump();
    expect(_row('one'), findsOneWidget);
    expect(_row('two'), findsOneWidget);
    expect(_row('three'), findsNothing);
    expect(opens, 0);
    expect(loads, 0);
  });

  testWidgets(
    'unread and flagged filters intersect and exclude unknown flags',
    (tester) async {
      await tester.pumpWidget(_app(_list()));
      await tester.tap(find.byKey(const ValueKey('mail-list-unread')));
      await tester.pump();
      expect(_row('one'), findsOneWidget);
      expect(_row('three'), findsOneWidget);
      expect(_row('unknown'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mail-list-flagged')));
      await tester.pump();
      expect(_row('one'), findsOneWidget);
      expect(_row('two'), findsNothing);
      expect(_row('three'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mail-list-unread')));
      await tester.pump();
      expect(_row('one'), findsOneWidget);
      expect(_row('two'), findsOneWidget);
      expect(_row('unknown'), findsNothing);
    },
  );

  testWidgets(
    'no matches retains explicit pagination even with no visible rows',
    (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        _app(_list(hasMore: true, onLoadMore: () => loads++)),
      );
      await tester.enterText(
        find.byKey(const ValueKey('mail-list-search')),
        'not-yet-loaded',
      );
      await tester.pump();
      expect(find.text('No loaded messages match'), findsOneWidget);
      expect(find.text('No messages loaded'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mail-list-load-more')));
      await tester.pump();
      expect(loads, 1);
    },
  );

  testWidgets('empty and loading states remain distinct', (tester) async {
    await tester.pumpWidget(_app(_list(items: const [])));
    expect(find.text('No messages loaded'), findsOneWidget);
    await tester.pumpWidget(_app(_list(items: const [], busy: true)));
    expect(find.text('Loading messages'), findsOneWidget);
    expect(find.text('No messages loaded'), findsNothing);
    await tester.pumpWidget(_app(_list(items: _items, busy: true)));
    expect(_row('one'), findsOneWidget);
  });

  testWidgets(
    'busy blocks opening and pagination while preserving local filters',
    (tester) async {
      final opened = <String>[];
      var loads = 0;
      await tester.pumpWidget(
        _app(
          _list(
            onOpen: opened.add,
            busy: true,
            hasMore: true,
            onLoadMore: () => loads++,
          ),
        ),
      );
      await tester.tap(_row('one'));
      await _focusList(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.tap(find.byKey(const ValueKey('mail-list-load-more')));
      await tester.tap(find.byKey(const ValueKey('mail-list-unread')));
      await tester.pump();
      expect(_row('two'), findsNothing);
      expect(opened, isEmpty);
      expect(loads, 0);
    },
  );

  testWidgets('host row activation uses stable id and explicit selection', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(_app(_list(selectedId: 'two', onOpen: opened.add)));
    await tester.tap(_row('one'));
    await tester.pump();
    expect(opened, ['one']);
    expect(tester.widget<Semantics>(_row('one')).properties.selected, isFalse);
    expect(tester.widget<Semantics>(_row('two')).properties.selected, isTrue);
  });

  testWidgets('arrows Home and End move focus without opening messages', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(_app(_list(onOpen: opened.add, selectedId: 'two')));
    await _focusList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tester.widget<Semantics>(_row('three')).properties.focused, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(tester.widget<Semantics>(_row('one')).properties.focused, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(opened, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, ['unknown']);
    expect(tester.widget<Semantics>(_row('two')).properties.selected, isTrue);
  });

  testWidgets('search owns editing keys and Enter does not open a row', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(_app(_list(onOpen: opened.add)));
    await tester.enterText(
      find.byKey(const ValueKey('mail-list-search')),
      'planning',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('mail-list-search')))
          .controller!
          .text,
      'planning',
    );
  });

  testWidgets('modifier navigation is not consumed as plain list movement', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_list()));
    await _focusList(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(tester.widget<Semantics>(_row('one')).properties.focused, isTrue);
  });

  testWidgets('keyboard cursor follows stable identity through a row reorder', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(_app(_list(onOpen: opened.add)));
    await _focusList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpWidget(
      _app(_list(items: _items.reversed.toList(), onOpen: opened.add)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, ['two']);
  });

  testWidgets('removed keyboard target falls back without opening stale data', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(_app(_list(onOpen: opened.add)));
    await _focusList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpWidget(
      _app(_list(items: [_items.first, _items[2]], onOpen: opened.add)),
    );
    expect(opened, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, ['one']);
  });

  testWidgets('new pages retain the current query and keyboard identity', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _app(_list(items: [_items.first], onOpen: opened.add)),
    );
    await tester.enterText(
      find.byKey(const ValueKey('mail-list-search')),
      'planning',
    );
    await _focusList(tester);
    await tester.pumpWidget(_app(_list(onOpen: opened.add)));
    expect(_row('three'), findsNothing);
    expect(_row('two'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, ['one']);
  });

  testWidgets(
    'account or mailbox scope change resets query filters and focus',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(_app(_list(onOpen: opened.add)));
      await tester.enterText(
        find.byKey(const ValueKey('mail-list-search')),
        'alice',
      );
      await tester.tap(find.byKey(const ValueKey('mail-list-unread')));
      await tester.tap(find.byKey(const ValueKey('mail-list-flagged')));
      await _focusList(tester);
      await tester.pumpWidget(
        _app(_list(scopeId: 'account-b/inbox', onOpen: opened.add)),
      );
      await tester.pump();
      expect(_row('two'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('mail-list-search')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<FilterChip>(find.byKey(const ValueKey('mail-list-unread')))
            .selected,
        isFalse,
      );
      expect(
        tester
            .widget<FilterChip>(find.byKey(const ValueKey('mail-list-flagged')))
            .selected,
        isFalse,
      );
      expect(
        tester
            .widget<Focus>(find.byKey(const ValueKey('mail-list-focus')))
            .focusNode!
            .hasFocus,
        isFalse,
      );
      expect(opened, isEmpty);
    },
  );

  testWidgets('End reveals the final virtualized row and Enter opens that id', (
    tester,
  ) async {
    final opened = <String>[];
    final rows = [
      for (var i = 0; i < 1000; i++)
        MailMessageListItem(
          id: 'row-$i',
          subject: 'Message $i',
          sender: 'sender@example.test',
        ),
    ];
    await tester.pumpWidget(_app(_list(items: rows, onOpen: opened.add)));
    expect(_row('row-999'), findsNothing);
    await _focusList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(_row('row-999'), findsOneWidget);
    expect(_row('row-0'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, ['row-999']);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(_row('row-0'), findsOneWidget);
  });

  testWidgets('host pagination key and limit explanation remain available', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      _app(
        _list(
          hasMore: true,
          onLoadMore: () => loads++,
          loadMoreKey: const ValueKey('provider-load-more'),
          limitNotice: 'The loaded-message limit has been reached.',
        ),
      ),
    );
    expect(
      find.text('The loaded-message limit has been reached.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('provider-load-more')));
    expect(loads, 1);
  });

  for (final direction in TextDirection.values) {
    testWidgets('narrow $direction and enlarged text stay within the list', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          _list(hasMore: true, onLoadMore: () {}),
          width: 280,
          scale: 1.8,
          direction: direction,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('mail-list-unread')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
