import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

String _count(int shown, int loaded) => '$shown of $loaded loaded';

const _strings = MailMessageListStrings(
  searchLoaded: 'Search loaded headers',
  unread: 'Unread',
  flagged: 'Flagged',
  noMessages: 'No messages',
  noMatches: 'No matches',
  loadMore: 'Load more',
  loading: 'Loading',
  loadedScope: 'Loaded headers in this folder only.',
  count: _count,
);

const _ids = ['a', 'b', 'c', 'd', 'e', 'f'];

// The provider order deliberately differs from alphabetical subject order.
const _items = [
  MailMessageListItem(
    id: 'a',
    subject: 'Delta keep',
    sender: 'alice@example.test',
    isRead: false,
    isFlagged: true,
  ),
  MailMessageListItem(
    id: 'b',
    subject: 'Bravo other',
    sender: 'bob@example.test',
    isRead: true,
    isFlagged: false,
  ),
  MailMessageListItem(
    id: 'c',
    subject: 'Foxtrot keep',
    sender: 'carol@example.test',
    isRead: false,
    isFlagged: true,
  ),
  MailMessageListItem(
    id: 'd',
    subject: 'Alpha keep',
    sender: 'dana@example.test',
    isRead: false,
    isFlagged: false,
  ),
  MailMessageListItem(
    id: 'e',
    subject: 'Echo other',
    sender: 'eli@example.test',
    isRead: true,
    isFlagged: true,
  ),
  MailMessageListItem(
    id: 'f',
    subject: 'Charlie keep',
    sender: 'fran@example.test',
    isRead: false,
    isFlagged: false,
  ),
];

const _threadItems = [
  MailMessageListItem(
    id: 'root',
    subject: 'Project',
    sender: 'alice@example.test',
    accountId: 'account-a',
    messageId: '<root@range.test>',
  ),
  MailMessageListItem(
    id: 'other',
    subject: 'Other',
    sender: 'bob@example.test',
    accountId: 'account-a',
    messageId: '<other@range.test>',
  ),
  MailMessageListItem(
    id: 'reply',
    subject: 'Re: Project',
    sender: 'carol@example.test',
    accountId: 'account-a',
    inReplyTo: '<root@range.test>',
  ),
  MailMessageListItem(
    id: 'tail',
    subject: 'Last',
    sender: 'dana@example.test',
    accountId: 'account-a',
    messageId: '<tail@range.test>',
  ),
];

void _ignoreBulk(MailBulkFlagAction action, List<String> ids) {}

MailMessageList _list({
  List<MailMessageListItem> items = _items,
  void Function(String)? onOpen,
  void Function(MailBulkFlagAction, List<String>)? onBulk = _ignoreBulk,
  String scope = 'account-a/inbox',
  Object? revision,
  bool busy = false,
  bool enabled = true,
  VoidCallback? onLoadMore,
}) => MailMessageList(
  items: items,
  strings: _strings,
  scopeId: scope,
  selectionRevision: revision,
  busy: busy,
  bulkEnabled: enabled,
  onOpen: onOpen ?? (_) {},
  onBulkAction: onBulk,
  hasMore: onLoadMore != null,
  onLoadMore: onLoadMore,
);

Widget _app(
  Widget child, {
  double height = 900,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 620, height: height, child: child),
      ),
    ),
  ),
);

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  double height = 900,
  TextDirection direction = TextDirection.ltr,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_app(child, height: height, direction: direction));
  await tester.pumpAndSettle();
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _row(String id) => _key(id);
Finder _check(String id) => _key('mail-list-check-$id');

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _focusList(WidgetTester tester) async {
  tester.widget<Focus>(_key('mail-list-focus')).focusNode!.requestFocus();
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _shift(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey modifier = LogicalKeyboardKey.shiftLeft,
}) async {
  await tester.sendKeyDownEvent(modifier);
  try {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  } finally {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pumpAndSettle();
}

Future<void> _shiftTap(WidgetTester tester, Finder finder) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  try {
    await _tap(tester, finder);
  } finally {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.pumpAndSettle();
}

Future<void> _cursorAtC(WidgetTester tester) async {
  await _focusList(tester);
  await _press(tester, LogicalKeyboardKey.home);
  await _press(tester, LogicalKeyboardKey.arrowDown);
  await _press(tester, LogicalKeyboardKey.arrowDown);
  _expectCursor(tester, 'c');
}

void _expectCursor(WidgetTester tester, String id) {
  expect(tester.widget<Semantics>(_row(id)).properties.focused, isTrue);
}

void _expectChecked(
  WidgetTester tester,
  List<String> expected, {
  List<String> visible = _ids,
}) {
  final count = expected.length;
  expect(find.text('$count selected'), findsOneWidget);
  for (final id in visible) {
    expect(
      tester.widget<Checkbox>(_check(id)).value,
      expected.contains(id),
      reason: 'Checkbox for $id',
    );
  }
}

Future<void> _sort(
  WidgetTester tester,
  MailMessageListSort value,
) async {
  await _tap(tester, _key('mail-list-sort'));
  final name = value.name;
  await _tap(tester, _key('mail-list-sort-$name'));
}

Future<void> _invoke(
  WidgetTester tester,
  MailBulkFlagAction action,
) async {
  await _tap(tester, _key('mail-list-bulk-actions'));
  final name = action.name;
  await _tap(tester, _key('mail-list-bulk-$name'));
}

VoidCallback _rowCallback(WidgetTester tester, String id) =>
    tester.widget<InkWell>(
      find.descendant(of: _row(id), matching: find.byType(InkWell)),
    ).onTap!;

void main() {
  for (final modifier in [
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  ]) {
    testWidgets(
      '$modifier ranges grow, shrink and reverse around the same anchor',
      (tester) async {
        final opened = <String>[];
        final batches = <List<String>>[];
        var loads = 0;
        await _mount(
          tester,
          _list(
            onOpen: opened.add,
            onBulk: (_, ids) => batches.add(ids),
            onLoadMore: () => loads++,
          ),
        );
        await _cursorAtC(tester);
        await _shift(tester, LogicalKeyboardKey.arrowDown, modifier: modifier);
        _expectChecked(tester, ['c', 'd']);
        await _shift(tester, LogicalKeyboardKey.arrowDown, modifier: modifier);
        _expectChecked(tester, ['c', 'd', 'e']);
        await _shift(tester, LogicalKeyboardKey.arrowUp, modifier: modifier);
        _expectChecked(tester, ['c', 'd']);
        await _shift(tester, LogicalKeyboardKey.arrowUp, modifier: modifier);
        _expectChecked(tester, ['c']);
        await _shift(tester, LogicalKeyboardKey.arrowUp, modifier: modifier);
        _expectChecked(tester, ['b', 'c']);
        await _shift(tester, LogicalKeyboardKey.arrowUp, modifier: modifier);
        _expectChecked(tester, ['a', 'b', 'c']);
        await _shift(tester, LogicalKeyboardKey.arrowDown, modifier: modifier);
        _expectChecked(tester, ['b', 'c']);
        _expectCursor(tester, 'b');
        expect(opened, isEmpty);
        expect(batches, isEmpty);
        expect(loads, 0);
      },
    );
  }

  testWidgets('Shift Home and End include endpoints and cross the anchor', (
    tester,
  ) async {
    await _mount(tester, _list());
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.end);
    _expectChecked(tester, ['c', 'd', 'e', 'f']);
    _expectCursor(tester, 'f');
    await _shift(tester, LogicalKeyboardKey.home);
    _expectChecked(tester, ['a', 'b', 'c']);
    _expectCursor(tester, 'a');
    await _shift(tester, LogicalKeyboardKey.end);
    await _shift(tester, LogicalKeyboardKey.arrowUp);
    _expectChecked(tester, ['c', 'd', 'e']);
  });

  testWidgets('the initial cursor anchors a range and endpoints are bounded', (
    tester,
  ) async {
    await _mount(tester, _list());
    await _focusList(tester);
    await _shift(tester, LogicalKeyboardKey.arrowUp);
    _expectChecked(tester, ['a']);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    _expectChecked(tester, ['a', 'b']);
    await _shift(tester, LogicalKeyboardKey.end);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    _expectChecked(tester, _ids);
    _expectCursor(tester, 'f');
  });

  testWidgets('range gestures are inert for an empty loaded view', (
    tester,
  ) async {
    final opened = <String>[];
    await _mount(tester, _list(items: const [], onOpen: opened.add));
    await _focusList(tester);
    for (final key in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.space,
    ]) {
      await _shift(tester, key);
    }
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(opened, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('separate checks survive contraction on both sides of a range', (
    tester,
  ) async {
    await _mount(tester, _list());
    await _tap(tester, _check('a'));
    await _tap(tester, _check('f'));
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    _expectChecked(tester, ['a', 'c', 'd', 'f']);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    _expectChecked(tester, ['a', 'c', 'd', 'e', 'f']);
    await _shift(tester, LogicalKeyboardKey.arrowUp);
    await _shift(tester, LogicalKeyboardKey.arrowUp);
    _expectChecked(tester, ['a', 'c', 'f']);
    await _shift(tester, LogicalKeyboardKey.arrowUp);
    _expectChecked(tester, ['a', 'b', 'c', 'f']);
  });

  testWidgets('Shift Space selects the cursor without toggling or opening', (
    tester,
  ) async {
    final opened = <String>[];
    var actions = 0;
    await _mount(
      tester,
      _list(onOpen: opened.add, onBulk: (_, _) => actions++),
    );
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.space);
    _expectChecked(tester, ['c']);
    await _shift(tester, LogicalKeyboardKey.space);
    _expectChecked(tester, ['c']);
    await _shift(tester, LogicalKeyboardKey.end);
    await _shift(tester, LogicalKeyboardKey.space);
    _expectChecked(tester, ['c', 'd', 'e', 'f']);
    expect(opened, isEmpty);
    expect(actions, 0);
  });

  for (final targetKind in ['row', 'checkbox']) {
    testWidgets(
      'Shift clicking a $targetKind extends and contracts without opening',
      (tester) async {
        final opened = <String>[];
        var actions = 0;
        await _mount(
          tester,
          _list(onOpen: opened.add, onBulk: (_, _) => actions++),
        );
        await _tap(tester, _check('b'));
        Finder target(String id) =>
            targetKind == 'row' ? _row(id) : _check(id);
        await _shiftTap(tester, target('e'));
        _expectChecked(tester, ['b', 'c', 'd', 'e']);
        _expectCursor(tester, 'e');
        await _shiftTap(tester, target('c'));
        _expectChecked(tester, ['b', 'c']);
        await _shiftTap(tester, target('a'));
        _expectChecked(tester, ['a', 'b']);
        expect(opened, isEmpty);
        expect(actions, 0);
      },
    );
  }

  testWidgets('plain navigation starts a new range without losing old checks', (
    tester,
  ) async {
    await _mount(tester, _list());
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    _expectChecked(tester, ['c', 'd']);
    await _press(tester, LogicalKeyboardKey.home);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    _expectChecked(tester, ['a', 'b', 'c', 'd']);
    await _shift(tester, LogicalKeyboardKey.arrowUp);
    _expectChecked(tester, ['a', 'c', 'd']);
  });

  testWidgets('plain Space unchecks the cursor and establishes a new anchor', (
    tester,
  ) async {
    await _mount(tester, _list());
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.space);
    _expectChecked(tester, ['c']);
    await _shift(tester, LogicalKeyboardKey.end);
    _expectChecked(tester, ['c', 'd', 'e', 'f']);
    await _shift(tester, LogicalKeyboardKey.home);
    _expectChecked(tester, ['a', 'b', 'c', 'd']);
  });

  testWidgets('ordinary row activation establishes the next pointer anchor', (
    tester,
  ) async {
    final opened = <String>[];
    await _mount(tester, _list(onOpen: opened.add));
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    await _tap(tester, _row('a'));
    expect(opened, ['a']);
    _expectChecked(tester, ['c', 'd']);
    await _shiftTap(tester, _row('b'));
    _expectChecked(tester, ['a', 'b', 'c', 'd']);
    expect(opened, ['a']);
  });

  testWidgets('Escape clears the old range and its anchor', (tester) async {
    await _mount(tester, _list());
    await _focusList(tester);
    await _shift(tester, LogicalKeyboardKey.end);
    await _press(tester, LogicalKeyboardKey.escape);
    _expectChecked(tester, []);
    await _shift(tester, LogicalKeyboardKey.arrowUp);
    _expectChecked(tester, ['e', 'f']);
  });

  testWidgets('Enter opens only the cursor and never submits its checked range', (
    tester,
  ) async {
    final opened = <String>[];
    var actions = 0;
    await _mount(
      tester,
      _list(onOpen: opened.add, onBulk: (_, _) => actions++),
    );
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.end);
    await _press(tester, LogicalKeyboardKey.enter);
    expect(opened, ['f']);
    _expectChecked(tester, ['c', 'd', 'e', 'f']);
    expect(actions, 0);
  });

  testWidgets('query changes prune hidden rows and restart range ownership', (
    tester,
  ) async {
    final batches = <List<String>>[];
    await _mount(tester, _list(onBulk: (_, ids) => batches.add(ids)));
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    await tester.enterText(_key('mail-list-search'), 'subject:keep');
    await tester.pumpAndSettle();
    expect(_check('b'), findsNothing);
    expect(_check('e'), findsNothing);
    await _focusList(tester);
    await _shift(tester, LogicalKeyboardKey.arrowUp);
    await _shift(tester, LogicalKeyboardKey.arrowUp);
    _expectChecked(tester, ['a', 'c', 'd'], visible: ['a', 'c', 'd', 'f']);
    await _shift(tester, LogicalKeyboardKey.end);
    _expectChecked(tester, ['c', 'd', 'f'], visible: ['a', 'c', 'd', 'f']);
    await _invoke(tester, MailBulkFlagAction.flag);
    expect(batches.single, ['c', 'd', 'f']);
  });

  testWidgets('invalid queries clear checks and cannot retain a hidden anchor', (
    tester,
  ) async {
    await _mount(tester, _list());
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.end);
    await tester.enterText(_key('mail-list-search'), 'body:unsupported');
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
    await _focusList(tester);
    await _shift(tester, LogicalKeyboardKey.end);
    expect(find.text('0 selected'), findsOneWidget);
    await tester.enterText(_key('mail-list-search'), 'keep');
    await tester.pumpAndSettle();
    await _focusList(tester);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    _expectChecked(tester, ['a', 'c'], visible: ['a', 'c', 'd', 'f']);
  });

  testWidgets('quick filters exclude hidden rows from keyboard ranges', (
    tester,
  ) async {
    final batches = <List<String>>[];
    await _mount(tester, _list(onBulk: (_, ids) => batches.add(ids)));
    await _focusList(tester);
    await _shift(tester, LogicalKeyboardKey.end);
    await _tap(tester, _key('mail-list-unread'));
    _expectChecked(
      tester,
      ['a', 'c', 'd', 'f'],
      visible: ['a', 'c', 'd', 'f'],
    );
    await _tap(tester, _key('mail-list-clear-selection'));
    await _focusList(tester);
    await _press(tester, LogicalKeyboardKey.home);
    await _shift(tester, LogicalKeyboardKey.end);
    await _invoke(tester, MailBulkFlagAction.markRead);
    expect(batches.single, ['a', 'c', 'd', 'f']);
  });

  testWidgets('sorting resets the anchor while preserving independent checks', (
    tester,
  ) async {
    final batches = <List<String>>[];
    await _mount(tester, _list(onBulk: (_, ids) => batches.add(ids)));
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    await _sort(tester, MailMessageListSort.subjectAscending);
    await _focusList(tester);
    _expectCursor(tester, 'd');
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    _expectChecked(tester, ['b', 'c', 'd']);
    await _shift(tester, LogicalKeyboardKey.arrowUp);
    _expectChecked(tester, ['c', 'd']);
    await _invoke(tester, MailBulkFlagAction.markUnread);
    expect(batches.single, ['d', 'c']);
  });

  testWidgets('folding removes hidden checks and re-expansion keeps them clear', (
    tester,
  ) async {
    final batches = <List<String>>[];
    await _mount(
      tester,
      _list(items: _threadItems, onBulk: (_, ids) => batches.add(ids)),
    );
    await _tap(tester, _key('mail-list-conversations'));
    await _focusList(tester);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    _expectChecked(
      tester,
      ['root', 'reply'],
      visible: ['root', 'reply', 'other', 'tail'],
    );
    await _tap(tester, _key('mail-list-conversation-toggle-root'));
    expect(_check('reply'), findsNothing);
    _expectChecked(tester, ['root'], visible: ['root', 'other', 'tail']);
    await _shift(tester, LogicalKeyboardKey.end);
    _expectChecked(
      tester,
      ['root', 'other', 'tail'],
      visible: ['root', 'other', 'tail'],
    );
    await _tap(tester, _key('mail-list-conversation-toggle-root'));
    _expectChecked(
      tester,
      ['root', 'other', 'tail'],
      visible: ['root', 'reply', 'other', 'tail'],
    );
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    await _shift(tester, LogicalKeyboardKey.arrowUp);
    _expectChecked(
      tester,
      ['root', 'other', 'tail'],
      visible: ['root', 'reply', 'other', 'tail'],
    );
    await _invoke(tester, MailBulkFlagAction.unflag);
    expect(batches.single, ['root', 'other', 'tail']);
  });

  for (final transition in ['refresh', 'revision', 'account']) {
    testWidgets('$transition ends the previous keyboard range', (tester) async {
      final opened = <String>[];
      Widget view({bool updated = false}) => _app(
        _list(
          onOpen: opened.add,
          revision: transition == 'revision' && updated ? 1 : 0,
          scope: transition == 'account' && updated
              ? 'account-b/inbox'
              : 'account-a/inbox',
        ),
      );
      await _mount(tester, _list(onOpen: opened.add, revision: 0));
      await _cursorAtC(tester);
      await _shift(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpWidget(view(updated: true));
      await tester.pumpAndSettle();
      await _focusList(tester);
      if (transition == 'account') {
        _expectChecked(tester, []);
        _expectCursor(tester, 'a');
        await _shift(tester, LogicalKeyboardKey.arrowDown);
        _expectChecked(tester, ['a', 'b']);
      } else {
        _expectChecked(tester, transition == 'revision' ? [] : ['c', 'd']);
        _expectCursor(tester, 'd');
        await _shift(tester, LogicalKeyboardKey.arrowUp);
        await _shift(tester, LogicalKeyboardKey.arrowUp);
        _expectChecked(tester, ['b', 'c', 'd']);
      }
      expect(opened, isEmpty);
    });
  }

  testWidgets('removed range members cannot reappear in a later extension', (
    tester,
  ) async {
    await _mount(tester, _list());
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    await tester.pumpWidget(
      _app(_list(items: _items.where((item) => item.id != 'c').toList())),
    );
    await tester.pumpAndSettle();
    await _focusList(tester);
    await _shift(tester, LogicalKeyboardKey.home);
    _expectChecked(tester, ['a', 'b', 'd'], visible: ['a', 'b', 'd', 'e', 'f']);
    expect(_check('c'), findsNothing);
  });

  for (final transition in [
    'selection',
    'query',
    'sort',
    'refresh',
    'revision',
    'account',
    'dispose',
  ]) {
    testWidgets(
      'captured row and checkbox callbacks cannot extend after $transition',
      (tester) async {
        final opened = <String>[];
        await _mount(tester, _list(onOpen: opened.add, revision: 0));
        await _tap(tester, _check('b'));
        final oldRow = _rowCallback(tester, 'd');
        final oldCheckbox = tester.widget<Checkbox>(_check('d')).onChanged!;
        switch (transition) {
          case 'selection':
            await _shiftTap(tester, _row('c'));
          case 'query':
            await tester.enterText(_key('mail-list-search'), 'keep');
            await tester.pumpAndSettle();
            await tester.enterText(_key('mail-list-search'), '');
            await tester.pumpAndSettle();
          case 'sort':
            await _sort(tester, MailMessageListSort.subjectAscending);
          case 'refresh':
            await tester.pumpWidget(
              _app(_list(onOpen: opened.add, revision: 0)),
            );
          case 'revision':
            await tester.pumpWidget(
              _app(_list(onOpen: opened.add, revision: 1)),
            );
          case 'account':
            await tester.pumpWidget(
              _app(_list(onOpen: opened.add, scope: 'account-b/inbox')),
            );
          case 'dispose':
            await tester.pumpWidget(_app(const SizedBox.shrink()));
        }
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        try {
          oldCheckbox(true);
          oldRow();
          await tester.pumpAndSettle();
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        if (transition != 'dispose') {
          _expectChecked(
            tester,
            switch (transition) {
              'selection' => ['b', 'c'],
              'sort' || 'refresh' => ['b'],
              _ => <String>[],
            },
          );
        }
        expect(opened, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('collapsed-child callbacks cannot select or open hidden mail', (
    tester,
  ) async {
    final opened = <String>[];
    await _mount(tester, _list(items: _threadItems, onOpen: opened.add));
    await _tap(tester, _key('mail-list-conversations'));
    final oldRow = _rowCallback(tester, 'reply');
    final oldCheckbox = tester.widget<Checkbox>(_check('reply')).onChanged!;
    await _tap(tester, _key('mail-list-conversation-toggle-root'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    try {
      oldRow();
      oldCheckbox(true);
      await tester.pumpAndSettle();
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    expect(_check('reply'), findsNothing);
    _expectChecked(tester, [], visible: ['root', 'other', 'tail']);
    expect(opened, isEmpty);
  });

  for (final unavailable in ['busy', 'disabled']) {
    testWidgets('$unavailable hosts refuse every range gesture', (
      tester,
    ) async {
      final opened = <String>[];
      var actions = 0;
      void bulk(MailBulkFlagAction action, List<String> ids) => actions++;
      await _mount(tester, _list(onOpen: opened.add, onBulk: bulk));
      await _cursorAtC(tester);
      await _shift(tester, LogicalKeyboardKey.arrowDown);
      final oldRow = _rowCallback(tester, 'e');
      final oldCheckbox = tester.widget<Checkbox>(_check('e')).onChanged!;
      await tester.pumpWidget(
        _app(
          _list(
            onOpen: opened.add,
            onBulk: bulk,
            busy: unavailable == 'busy',
            enabled: unavailable != 'disabled',
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final id in _ids) {
        expect(tester.widget<Checkbox>(_check(id)).onChanged, isNull);
      }
      await _focusList(tester);
      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.space,
      ]) {
        await _shift(tester, key);
      }
      await _shiftTap(tester, _row('f'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      try {
        oldRow();
        oldCheckbox(true);
        await tester.pumpAndSettle();
      } finally {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      _expectChecked(tester, unavailable == 'busy' ? ['c', 'd'] : []);
      expect(opened, isEmpty);
      expect(actions, 0);
    });
  }

  testWidgets('read-only hosts ignore range keys and retain ordinary opening', (
    tester,
  ) async {
    final opened = <String>[];
    await _mount(tester, _list(onOpen: opened.add, onBulk: null));
    expect(find.byType(Checkbox), findsNothing);
    expect(_key('mail-list-selected-count'), findsNothing);
    expect(_key('mail-list-selection-help'), findsNothing);
    await _focusList(tester);
    for (final key in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.space,
    ]) {
      await _shift(tester, key);
    }
    expect(opened, isEmpty);
    await _press(tester, LogicalKeyboardKey.enter);
    expect(opened, ['a']);
  });

  for (final extra in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.altLeft,
  ]) {
    testWidgets('Shift plus $extra does not acquire a selection gesture', (
      tester,
    ) async {
      final opened = <String>[];
      await _mount(tester, _list(onOpen: opened.add));
      await _focusList(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(extra);
      try {
        await _press(tester, LogicalKeyboardKey.arrowDown);
        await _press(tester, LogicalKeyboardKey.end);
        await _press(tester, LogicalKeyboardKey.space);
        await _tap(tester, _check('d'));
        await _tap(tester, _row('f'));
      } finally {
        await tester.sendKeyUpEvent(extra);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      _expectChecked(tester, []);
      expect(opened, isEmpty);
    });
  }

  testWidgets('held range arrows repeat but held Shift Space never toggles', (
    tester,
  ) async {
    final opened = <String>[];
    await _mount(tester, _list(onOpen: opened.add));
    await _focusList(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    try {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      _expectChecked(tester, ['a', 'b']);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      _expectChecked(tester, ['a', 'b', 'c']);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      _expectChecked(tester, ['a', 'b', 'c', 'd']);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.pumpAndSettle();
    _expectChecked(tester, ['a', 'b', 'c', 'd']);
    expect(opened, isEmpty);
  });

  testWidgets('search-field selection and IME editing never select messages', (
    tester,
  ) async {
    final opened = <String>[];
    var actions = 0;
    await _mount(
      tester,
      _list(onOpen: opened.add, onBulk: (_, _) => actions++),
    );
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    await tester.enterText(_key('mail-list-search'), 'keep');
    await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'keep',
        selection: TextSelection(baseOffset: 0, extentOffset: 4),
        composing: TextRange(start: 0, end: 4),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(_key('mail-list-search'));
    expect(field.controller!.value.composing, const TextRange(start: 0, end: 4));
    for (final key in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.space,
    ]) {
      await _shift(tester, key);
    }
    expect(
      tester.widget<Focus>(_key('mail-list-focus')).focusNode!.hasFocus,
      isFalse,
    );
    _expectChecked(tester, ['c', 'd'], visible: ['a', 'c', 'd', 'f']);
    expect(field.controller!.text, 'keep');
    expect(opened, isEmpty);
    expect(actions, 0);
  });

  testWidgets('range commands produce an immutable snapshot in visible order', (
    tester,
  ) async {
    final calls = <(MailBulkFlagAction, List<String>)>[];
    await _mount(
      tester,
      _list(onBulk: (action, ids) => calls.add((action, ids))),
    );
    await _sort(tester, MailMessageListSort.subjectAscending);
    await _focusList(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    _expectChecked(tester, ['a', 'b', 'f']);
    expect(calls, isEmpty);
    await _invoke(tester, MailBulkFlagAction.markRead);
    expect(calls, hasLength(1));
    expect(calls.single.$1, MailBulkFlagAction.markRead);
    expect(calls.single.$2, ['b', 'f', 'a']);
    expect(() => calls.single.$2.add('injected'), throwsUnsupportedError);
    _expectChecked(tester, []);
  });

  testWidgets('a pending bulk popup cannot outlive a new range selection', (
    tester,
  ) async {
    var actions = 0;
    await _mount(tester, _list(onBulk: (_, _) => actions++));
    await _focusList(tester);
    await _shift(tester, LogicalKeyboardKey.arrowDown);
    await _tap(tester, _key('mail-list-bulk-actions'));
    // Deliver a real row control callback while the popup route is open.
    // The menu choice remains frozen at the earlier selection.
    final checkbox = tester.widget<Checkbox>(_check('d')).onChanged!;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    try {
      checkbox(true);
      await tester.pumpAndSettle();
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    await _tap(tester, _key('mail-list-bulk-markRead'));
    expect(actions, 0);
    _expectChecked(tester, ['a', 'b', 'c', 'd']);
  });

  testWidgets('keyboard ranges include offscreen loaded rows without fetching', (
    tester,
  ) async {
    final rows = [
      for (var index = 0; index < 40; index++)
        MailMessageListItem(
          id: 'row-$index',
          subject: 'Message $index',
          sender: 'sender@example.test',
        ),
    ];
    final batches = <List<String>>[];
    var opens = 0;
    var loads = 0;
    await _mount(
      tester,
      _list(
        items: rows,
        onOpen: (_) => opens++,
        onBulk: (_, ids) => batches.add(ids),
        onLoadMore: () => loads++,
      ),
      height: 430,
    );
    expect(_check('row-39'), findsNothing);
    await _focusList(tester);
    await _shift(tester, LogicalKeyboardKey.end);
    expect(find.text('40 selected'), findsOneWidget);
    expect(_row('row-39').hitTestable(), findsOneWidget);
    _expectCursor(tester, 'row-39');
    await _invoke(tester, MailBulkFlagAction.flag);
    expect(batches.single, [for (var index = 0; index < 40; index++) 'row-$index']);
    expect(opens, 0);
    expect(loads, 0);
  });

  testWidgets('RTL preserves vertical range direction and row identities', (
    tester,
  ) async {
    final batches = <List<String>>[];
    await _mount(
      tester,
      _list(onBulk: (_, ids) => batches.add(ids)),
      direction: TextDirection.rtl,
    );
    await _cursorAtC(tester);
    await _shift(tester, LogicalKeyboardKey.arrowUp);
    _expectChecked(tester, ['b', 'c']);
    await _shiftTap(tester, _row('e'));
    _expectChecked(tester, ['c', 'd', 'e']);
    await _invoke(tester, MailBulkFlagAction.unflag);
    expect(batches.single, ['c', 'd', 'e']);
  });
}
