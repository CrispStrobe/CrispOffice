import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
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
    to: 'Planning Team <team@example.test>',
    cc: 'review@example.test',
    dateLabel: '20 November',
    isRead: false,
    isFlagged: true,
  ),
  MailMessageListItem(
    id: 'two',
    subject: 'Beta planning',
    sender: 'bob@example.test',
    to: 'other@example.test',
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
  MailMessageListStrings strings = _strings,
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
  strings: strings,
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

Future<void> _sortBy(WidgetTester tester, MailMessageListSort sort) async {
  await tester.tap(find.byKey(const ValueKey('mail-list-sort')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('mail-list-sort-${sort.name}')));
  await tester.pumpAndSettle();
}

List<String> _rowOrder(WidgetTester tester, List<String> ids) => [...ids]
  ..sort(
    (a, b) =>
        tester.getTopLeft(_row(a)).dy.compareTo(tester.getTopLeft(_row(b)).dy),
  );

String _localizedSearchError(MailHeaderSearchError error) =>
    'Localized error: ${error.name}';

String _compactGermanError(MailHeaderSearchError _) =>
    'Trennen Sie Begriffe durch Leerzeichen. Boolesche Operatoren, Verneinung '
    'und Platzhalter werden nicht unterstützt; setzen Sie wörtlichen Text '
    'in Anführungszeichen.';

String _compactArabicError(MailHeaderSearchError _) =>
    'افصل العبارات بمسافات. لا تُدعم العوامل المنطقية أو النفي أو أحرف البدل؛ '
    'ضع النص الحرفي بين علامتي اقتباس.';

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

  testWidgets('a fully loaded folder hides the loaded-scope line', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_list()));
    expect(find.byKey(const ValueKey('mail-list-scope')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('mail-list-search')),
      'planning',
    );
    await tester.pump();
    // Filters hiding rows still show the count, without the loaded scope.
    expect(find.text('2 shown · 4 loaded'), findsOneWidget);
    expect(find.textContaining(_strings.loadedScope), findsNothing);
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

  testWidgets('structured header terms are conjunctive and use recipients', (
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
      'from:ALICE to:"Planning Team" cc:review subject:planning is:unread',
    );
    await tester.pump();
    expect(_row('one'), findsOneWidget);
    expect(_row('two'), findsNothing);
    expect(_row('three'), findsNothing);
    expect(_row('unknown'), findsNothing);
    expect(
      find.text('1 shown · 4 loaded\n${_strings.loadedScope}'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('mail-list-search')),
      'is:unflagged',
    );
    await tester.pump();
    expect(_row('three'), findsOneWidget);
    expect(_row('unknown'), findsNothing);
    expect(opens, 0);
    expect(loads, 0);
  });

  testWidgets('dates use timestamps rather than the localized display label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _list(
          items: [
            MailMessageListItem(
              id: 'date-match',
              subject: 'Local calendar day',
              sender: 'test@example.test',
              date: DateTime(2026, 11, 20, 23, 30),
              dateLabel: 'A host-provided date label',
            ),
            const MailMessageListItem(
              id: 'label-only',
              subject: 'No observed date',
              sender: 'test@example.test',
              dateLabel: '2026-11-20',
            ),
          ],
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('mail-list-search')),
      'after:2026-11-19 before:2026-11-21 on:2026-11-20',
    );
    await tester.pump();
    expect(_row('date-match'), findsOneWidget);
    expect(_row('label-only'), findsNothing);
  });

  testWidgets(
    'invalid query shows localized error, no rows, and explicit clear',
    (tester) async {
      const localized = MailMessageListStrings(
        searchLoaded: 'Local search',
        unread: 'Local unread',
        flagged: 'Local flagged',
        noMessages: 'Local empty',
        noMatches: 'Local no matches',
        loadMore: 'Local more',
        loading: 'Local loading',
        loadedScope: 'Local scope',
        count: _count,
        clearSearch: 'Local clear',
        searchError: _localizedSearchError,
      );
      var loads = 0;
      final opened = <String>[];
      await tester.pumpWidget(
        _app(
          _list(
            strings: localized,
            onOpen: opened.add,
            hasMore: true,
            onLoadMore: () => loads++,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('mail-list-search')),
        'subject:"unfinished',
      );
      await tester.pump();
      expect(find.text('Localized error: unclosedQuote'), findsOneWidget);
      expect(find.text('0 shown · 4 loaded\nLocal scope'), findsOneWidget);
      expect(find.text('Local no matches'), findsOneWidget);
      expect(find.byTooltip('Local clear'), findsOneWidget);
      expect(_row('one'), findsNothing);
      await _focusList(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, isEmpty);
      expect(loads, 0);
      await tester.tap(find.byKey(const ValueKey('mail-list-clear-search')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mail-list-search-error')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mail-list-clear-search')),
        findsNothing,
      );
      expect(find.text('4 shown · 4 loaded\nLocal scope'), findsOneWidget);
      expect(_row('one'), findsOneWidget);
      expect(opened, isEmpty);
      expect(loads, 0);
    },
  );

  testWidgets(
    'oversized search fails closed without discarding trailing predicates',
    (tester) async {
      var opens = 0;
      var loads = 0;
      await tester.pumpWidget(
        _app(
          _list(
            onOpen: (_) => opens++,
            hasMore: true,
            onLoadMore: () => loads++,
          ),
        ),
      );
      final search = find.byKey(const ValueKey('mail-list-search'));
      final query =
          '${'from:alice'.padRight(MailHeaderSearchQuery.maxCodeUnits)} is:unread';
      await tester.enterText(search, query);
      await tester.pump();
      final controller = tester.widget<TextField>(search).controller!;
      expect(controller.text, query);
      expect(find.text('The search is too long.'), findsOneWidget);
      expect(_row('one'), findsNothing);
      expect(_row('three'), findsNothing);
      expect(
        find.text('0 shown · 4 loaded\n${_strings.loadedScope}'),
        findsOneWidget,
      );
      await _focusList(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opens, 0);
      expect(loads, 0);
      await tester.enterText(search, 'from:alice is:unread');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mail-list-search-error')),
        findsNothing,
      );
      expect(_row('one'), findsOneWidget);
      expect(_row('three'), findsOneWidget);
    },
  );

  testWidgets('search preserves active IME text and composing ranges', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_list()));
    final search = find.byKey(const ValueKey('mail-list-search'));
    await tester.showKeyboard(search);
    const composing = TextEditingValue(
      text: 'subject:تخطيط',
      selection: TextSelection.collapsed(offset: 13),
      composing: TextRange(start: 8, end: 13),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    final controller = tester.widget<TextField>(search).controller!;
    expect(controller.value, composing);
    final oversized = TextEditingValue(
      text: 'ش' * (MailHeaderSearchQuery.maxCodeUnits + 1),
      selection: TextSelection.collapsed(
        offset: MailHeaderSearchQuery.maxCodeUnits + 1,
      ),
      composing: TextRange(
        start: 0,
        end: MailHeaderSearchQuery.maxCodeUnits + 1,
      ),
    );
    tester.testTextInput.updateEditingValue(oversized);
    await tester.pump();
    expect(controller.value, oversized);
    expect(find.text('The search is too long.'), findsOneWidget);
    expect(_row('one'), findsNothing);
    tester.testTextInput.updateEditingValue(
      oversized.copyWith(composing: TextRange.empty),
    );
    await tester.pump();
    expect(controller.text, oversized.text);
    expect(controller.value.composing, TextRange.empty);
    expect(find.text('The search is too long.'), findsOneWidget);
  });

  testWidgets(
    'stale row callbacks cannot open filtered or invalid-query rows',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(_app(_list(onOpen: opened.add)));
      final staleTap = tester
          .widget<InkWell>(
            find.descendant(of: _row('one'), matching: find.byType(InkWell)),
          )
          .onTap!;
      final search = find.byKey(const ValueKey('mail-list-search'));
      await tester.enterText(search, 'from:bob');
      staleTap();
      await tester.pump();
      expect(_row('one'), findsNothing);
      staleTap();
      expect(opened, isEmpty);
      await tester.enterText(search, 'body:private');
      staleTap();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mail-list-search-error')),
        findsOneWidget,
      );
      expect(opened, isEmpty);
    },
  );

  testWidgets(
    'stale callbacks cannot cross mailbox scopes with overlapping ids',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(_app(_list(onOpen: opened.add)));
      final staleTap = tester
          .widget<InkWell>(
            find.descendant(of: _row('one'), matching: find.byType(InkWell)),
          )
          .onTap!;
      await tester.pumpWidget(
        _app(_list(scopeId: 'account-b/inbox', onOpen: opened.add)),
      );
      staleTap();
      expect(opened, isEmpty);
      // Returning to the old scope must not revive an obsolete pointer callback.
      await tester.pumpWidget(_app(_list(onOpen: opened.add)));
      staleTap();
      expect(opened, isEmpty);
      await tester.tap(_row('one'));
      expect(opened, ['one']);
      await tester.pumpWidget(_app(const SizedBox.shrink()));
      staleTap();
      expect(opened, ['one']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date sorting is stable and unknown dates always follow known dates',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final items = [
        const MailMessageListItem(
          id: 'unknown-date',
          subject: 'Unknown',
          sender: 'a',
        ),
        MailMessageListItem(
          id: 'later-a',
          subject: 'A',
          sender: 'b',
          date: DateTime.utc(2026, 11, 20, 12),
        ),
        MailMessageListItem(
          id: 'earlier',
          subject: 'B',
          sender: 'c',
          date: DateTime.utc(2026, 11, 19, 12),
        ),
        MailMessageListItem(
          id: 'later-b',
          subject: 'C',
          sender: 'd',
          date: DateTime.utc(2026, 11, 20, 12),
        ),
      ];
      final ids = items.map((item) => item.id).toList();
      var opens = 0;
      var loads = 0;
      await tester.pumpWidget(
        _app(
          _list(
            items: items,
            onOpen: (_) => opens++,
            hasMore: true,
            onLoadMore: () => loads++,
          ),
        ),
      );
      expect(_rowOrder(tester, ids), ids);
      await _sortBy(tester, MailMessageListSort.newestFirst);
      expect(_rowOrder(tester, ids), [
        'later-a',
        'later-b',
        'earlier',
        'unknown-date',
      ]);
      await _sortBy(tester, MailMessageListSort.oldestFirst);
      expect(_rowOrder(tester, ids), [
        'earlier',
        'later-a',
        'later-b',
        'unknown-date',
      ]);
      await _sortBy(tester, MailMessageListSort.providerOrder);
      expect(_rowOrder(tester, ids), ids);
      expect(opens, 0);
      expect(loads, 0);
    },
  );

  testWidgets('sender and subject sorting preserve case-insensitive ties', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const items = [
      MailMessageListItem(id: 'z', subject: 'Zulu', sender: 'Zoe'),
      MailMessageListItem(id: 'tie-a', subject: 'alpha', sender: 'Alice'),
      MailMessageListItem(id: 'tie-b', subject: 'Alpha', sender: 'alice'),
      MailMessageListItem(id: 'b', subject: 'Beta', sender: 'Bob'),
    ];
    final ids = items.map((item) => item.id).toList();
    await tester.pumpWidget(_app(_list(items: items)));
    await _sortBy(tester, MailMessageListSort.senderAscending);
    expect(_rowOrder(tester, ids), ['tie-a', 'tie-b', 'b', 'z']);
    await _sortBy(tester, MailMessageListSort.subjectAscending);
    expect(_rowOrder(tester, ids), ['tie-a', 'tie-b', 'b', 'z']);
  });

  testWidgets(
    'keyboard identity survives local sorting without activating a row',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(_app(_list(onOpen: opened.add)));
      await _focusList(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await _sortBy(tester, MailMessageListSort.senderAscending);
      expect(opened, isEmpty);
      await _focusList(tester);
      expect(tester.widget<Semantics>(_row('two')).properties.focused, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, ['two']);
    },
  );

  testWidgets('scope change resets sort and clears a previous query error', (
    tester,
  ) async {
    final ids = _items.map((item) => item.id).toList();
    await tester.pumpWidget(_app(_list()));
    await _sortBy(tester, MailMessageListSort.senderAscending);
    await tester.enterText(
      find.byKey(const ValueKey('mail-list-search')),
      'body:private',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mail-list-search-error')),
      findsOneWidget,
    );
    await tester.pumpWidget(_app(_list(scopeId: 'account-b/inbox')));
    await tester.pump();
    expect(find.byKey(const ValueKey('mail-list-search-error')), findsNothing);
    expect(find.text('Provider order'), findsOneWidget);
    expect(_rowOrder(tester, ids), ids);
  });

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
      await _sortBy(tester, MailMessageListSort.subjectAscending);
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

  testWidgets(
    'RTL help preserves prose and displays exact query examples LTR',
    (tester) async {
      const prose = 'استخدم العبارات التالية للبحث.';
      const example = 'from:alice subject:"quarterly report"';
      const recipientExample = '  TO:team@example.test cc:manager';
      const closing = 'يشمل البحث الترويسات المحمّلة فقط.';
      const localized = MailMessageListStrings(
        searchLoaded: 'البحث',
        unread: 'غير مقروءة',
        flagged: 'معلّمة',
        noMessages: 'لا رسائل',
        noMatches: 'لا نتائج',
        loadMore: 'المزيد',
        loading: 'تحميل',
        loadedScope: 'الترويسات المحمّلة',
        count: _count,
        searchHelpTitle: 'مساعدة البحث',
        searchHelpText: '$prose\n\n$example\n$recipientExample\n\n$closing',
      );
      await tester.pumpWidget(
        _app(_list(strings: localized), direction: TextDirection.rtl),
      );
      await tester.tap(find.byKey(const ValueKey('mail-list-search-help')));
      await tester.pumpAndSettle();
      for (final text in [example, recipientExample]) {
        final rendered = tester.widget<Text>(find.text(text));
        expect(rendered.data, text);
        expect(rendered.textDirection, TextDirection.ltr);
      }
      for (final text in [prose, closing]) {
        expect(tester.widget<Text>(find.text(text)).textDirection, isNull);
        expect(
          Directionality.of(tester.element(find.text(text))),
          TextDirection.rtl,
        );
      }
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text(' ')),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final (language, direction, strings) in const [
    (
      'de',
      TextDirection.ltr,
      MailMessageListStrings(
        searchLoaded: 'Geladene Nachrichtenköpfe durchsuchen',
        unread: 'Ungelesen',
        flagged: 'Gekennzeichnet',
        noMessages: 'Keine Nachrichten',
        noMatches: 'Keine geladene Nachricht entspricht diesen Filtern.',
        loadMore: 'Weitere Nachrichten laden',
        loading: 'Wird geladen…',
        loadedScope:
            'Suche, Filter und Sortierung gelten nur für geladene '
            'Nachrichtenköpfe dieses Ordners.',
        count: _count,
        providerOrder: 'Ordnerreihenfolge',
        searchError: _compactGermanError,
      ),
    ),
    (
      'ar',
      TextDirection.rtl,
      MailMessageListStrings(
        searchLoaded: 'البحث في الترويسات المحمّلة',
        unread: 'غير مقروءة',
        flagged: 'المعلّمة',
        noMessages: 'لا توجد رسائل',
        noMatches: 'لا توجد رسائل محمّلة تطابق هذه المرشحات.',
        loadMore: 'تحميل المزيد من الرسائل',
        loading: 'جارٍ التحميل…',
        loadedScope:
            'ينطبق البحث والترشيح والترتيب على الترويسات المحمّلة '
            'في هذا المجلد فقط.',
        count: _count,
        providerOrder: 'ترتيب المجلد',
        searchError: _compactArabicError,
      ),
    ),
  ]) {
    testWidgets('compact $language header scrolls while rows remain usable', (
      tester,
    ) async {
      final opened = <String>[];
      var loads = 0;
      Widget compact({String scopeId = 'a'}) => _app(
        SizedBox(
          height: 260,
          child: _list(
            strings: strings,
            scopeId: scopeId,
            onOpen: opened.add,
            hasMore: true,
            onLoadMore: () => loads++,
          ),
        ),
        width: 320,
        scale: 1.4,
        direction: direction,
      );
      await tester.pumpWidget(compact());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('mail-list-rows'))).height,
        greaterThanOrEqualTo(70),
      );
      final header = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('mail-list-header-scroll')),
          )
          .controller!;
      expect(header.position.maxScrollExtent, greaterThan(0));
      await tester.ensureVisible(find.byKey(const ValueKey('mail-list-scope')));
      await tester.pumpAndSettle();
      expect(header.offset, greaterThan(0));
      expect(
        find.byKey(const ValueKey('mail-list-scope')).hitTestable(),
        findsOneWidget,
      );
      expect(opened, isEmpty);
      expect(loads, 0);

      await tester.pumpWidget(compact(scopeId: 'b'));
      await tester.pumpAndSettle();
      expect(header.offset, 0);
      await tester.enterText(
        find.byKey(const ValueKey('mail-list-search')),
        'from:alice OR report',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('mail-list-search-error')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('mail-list-search-error')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('mail-list-clear-search')),
      );
      await tester.tap(find.byKey(const ValueKey('mail-list-clear-search')));
      await tester.pumpAndSettle();
      await _focusList(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, ['unknown']);
      await tester.tap(find.byKey(const ValueKey('mail-list-load-more')));
      expect(loads, 1);
      expect(tester.takeException(), isNull);
    });
  }

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
      await tester.tap(find.byKey(const ValueKey('mail-list-search-help')));
      await tester.pumpAndSettle();
      expect(find.text(_strings.searchHelpTitle), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(_strings.searchHelpTitle))),
        direction,
      );
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.text(_strings.searchHelpTitle)),
        ).scale(10),
        18,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(_strings.close));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await _sortBy(tester, MailMessageListSort.newestFirst);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const ValueKey('mail-list-search')),
        'subject:"unfinished',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mail-list-search-error')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
