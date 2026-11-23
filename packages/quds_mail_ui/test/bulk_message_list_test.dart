import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

const _flagActions = [
  MailBulkFlagAction.markRead,
  MailBulkFlagAction.markUnread,
  MailBulkFlagAction.flag,
  MailBulkFlagAction.unflag,
];

String _count(int shown, int loaded) => '$shown of $loaded';

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

const _items = [
  MailMessageListItem(
    id: 'one',
    subject: 'Cedar',
    sender: 'alice@example.test',
    isRead: false,
    isFlagged: true,
  ),
  MailMessageListItem(
    id: 'two',
    subject: 'Alpha',
    sender: 'bob@example.test',
    isRead: true,
    isFlagged: false,
  ),
  MailMessageListItem(
    id: 'three',
    subject: 'Birch',
    sender: 'alice@example.test',
  ),
];

typedef _Command = ({MailBulkFlagAction action, List<String> ids});

Future<void> _pump(
  WidgetTester tester, {
  List<MailMessageListItem> items = _items,
  MailMessageListStrings strings = _strings,
  String scope = 'account-a/inbox',
  String? selectionScope,
  bool busy = false,
  bool enabled = true,
  String? selectedId,
  void Function(MailBulkFlagAction, List<String>)? onAction,
  void Function(String)? onOpen,
  VoidCallback? onCancel,
  double width = 500,
  double height = 760,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: height,
                child: MailMessageList(
                  key: const ValueKey('list'),
                  items: items,
                  strings: strings,
                  onOpen: onOpen ?? (_) {},
                  selectedId: selectedId,
                  scopeId: scope,
                  selectionScopeId: selectionScope,
                  busy: busy,
                  bulkActionsEnabled: enabled,
                  onBulkAction: onAction,
                  onCancelBulk: onCancel,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _check(String id) => _key('mail-list-check-$id');

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final filters = find.byKey(const ValueKey('mail-list-filters'));
    if (filters.evaluate().isNotEmpty) {
      await tester.tap(filters);
      await tester.pumpAndSettle();
    }
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _action(WidgetTester tester, MailBulkFlagAction action) async {
  await _tap(tester, _key('mail-list-bulk-actions'));
  await _tap(tester, _key('mail-list-bulk-${action.name}'));
}

// Retain the menu values as well as its callback, matching an open route.
void Function(MailBulkFlagAction) _freezeMenu(WidgetTester tester) {
  final finder = _key('mail-list-bulk-actions');
  final menu = tester.widget<PopupMenuButton<Object>>(finder);
  final entries = menu.itemBuilder(tester.element(finder));
  final values = <MailBulkFlagAction, Object?>{
    for (final action in _flagActions)
      action: entries
          .whereType<PopupMenuItem<Object>>()
          .singleWhere(
            (entry) => entry.key == ValueKey('mail-list-bulk-${action.name}'),
          )
          .value,
  };
  // Keep the private choice parameter type when invoking the actual callback.
  // ignore: avoid_dynamic_calls
  final callback = (menu as dynamic).onSelected as Function;
  return (action) => Function.apply(callback, [values[action]]);
}

Future<void> _focusList(WidgetTester tester) async {
  tester.widget<Focus>(_key('mail-list-focus')).focusNode!.requestFocus();
  await tester.pump();
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
  testWidgets(
    'checkbox selection never opens a message and freezes exact IDs',
    (tester) async {
      final commands = <_Command>[];
      final opened = <String>[];
      await _pump(
        tester,
        selectedId: 'two',
        onOpen: opened.add,
        onAction: (action, ids) => commands.add((action: action, ids: ids)),
      );
      await _tap(tester, _check('one'));
      await _tap(tester, _check('three'));
      expect(opened, isEmpty);
      _expectSelected(tester, 2);
      await _action(tester, MailBulkFlagAction.markRead);
      expect(commands.single.action, MailBulkFlagAction.markRead);
      expect(commands.single.ids, ['one', 'three']);
      expect(() => commands.single.ids.clear(), throwsUnsupportedError);
      expect(opened, isEmpty);
      expect(tester.widget<Checkbox>(_check('two')).value, isFalse);
    },
  );

  for (final action in _flagActions) {
    testWidgets('explicit ${action.name} requests are not inferred toggles', (
      tester,
    ) async {
      final commands = <_Command>[];
      await _pump(
        tester,
        onAction: (value, ids) => commands.add((action: value, ids: ids)),
      );
      await _tap(tester, _check('three'));
      await _action(tester, action);
      expect(commands.single.action, action);
      expect(commands.single.ids, ['three']);
      expect(_items.last.isRead, isNull);
      expect(_items.last.isFlagged, isNull);
    });
  }

  testWidgets('generic checkbox menu offers only the four flag assignments', (
    tester,
  ) async {
    final commands = <_Command>[];
    await _pump(
      tester,
      onAction: (action, ids) => commands.add((action: action, ids: ids)),
    );
    await _tap(tester, _check('one'));
    await _tap(tester, _key('mail-list-bulk-actions'));
    for (final action in _flagActions) {
      expect(
        _key('mail-list-bulk-${action.name}').hitTestable(),
        findsOneWidget,
      );
    }
    expect(_key('mail-list-bulk-move'), findsNothing);
    expect(_key('mail-list-bulk-delete'), findsNothing);
    expect(
      find.byWidgetPredicate((widget) => widget is PopupMenuItem<Object>),
      findsNWidgets(4),
    );
    expect(commands, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(commands, isEmpty);
  });

  testWidgets('Select shown respects filters and never adds hidden rows', (
    tester,
  ) async {
    final commands = <_Command>[];
    await _pump(
      tester,
      onAction: (action, ids) => commands.add((action: action, ids: ids)),
    );
    await tester.enterText(_key('mail-list-search'), 'from:alice');
    await tester.pump();
    await _tap(tester, _key('mail-list-select-shown'));
    await _action(tester, MailBulkFlagAction.flag);
    expect(commands.single.ids, ['one', 'three']);
    _expectSelected(tester, 0);
  });

  testWidgets('filters prune hidden selection and invalid queries clear it', (
    tester,
  ) async {
    final commands = <_Command>[];
    await _pump(
      tester,
      onAction: (action, ids) => commands.add((action: action, ids: ids)),
    );
    await _tap(tester, _key('mail-list-select-shown'));
    _expectSelected(tester, 3);
    await _tap(tester, _key('mail-list-unread'));
    _expectSelected(tester, 1);
    await _action(tester, MailBulkFlagAction.markRead);
    expect(commands.single.ids, ['one']);
    await tester.enterText(_key('mail-list-search'), 'body:unsupported');
    await tester.pump();
    _expectSelected(tester, 0);
    expect(
      tester
          .widget<PopupMenuButton<Object>>(_key('mail-list-bulk-actions'))
          .enabled,
      isFalse,
    );
    await tester.enterText(_key('mail-list-search'), '');
    await tester.pump();
    _expectSelected(tester, 0);
  });

  testWidgets(
    'sorting preserves checkboxes and uses displayed selection order',
    (tester) async {
      final commands = <_Command>[];
      await _pump(
        tester,
        onAction: (action, ids) => commands.add((action: action, ids: ids)),
      );
      await _tap(tester, _key('mail-list-select-shown'));
      await _tap(tester, _key('mail-list-sort'));
      await _tap(tester, _key('mail-list-sort-subjectAscending'));
      _expectSelected(tester, 3);
      await _action(tester, MailBulkFlagAction.unflag);
      expect(commands.single.ids, ['two', 'three', 'one']);
    },
  );

  testWidgets('newly loaded rows stay unchecked and removed rows are pruned', (
    tester,
  ) async {
    void action(MailBulkFlagAction _, List<String> _) {}
    await _pump(tester, onAction: action);
    await _tap(tester, _key('mail-list-select-shown'));
    const fourth = MailMessageListItem(id: 'four', subject: 'Date', sender: '');
    await _pump(tester, items: [..._items, fourth], onAction: action);
    _expectSelected(tester, 3);
    expect(tester.widget<Checkbox>(_check('four')).value, isFalse);
    await _pump(tester, items: [_items[1], fourth], onAction: action);
    _expectSelected(tester, 1);
  });

  testWidgets('keyboard selection stays separate from opening a body', (
    tester,
  ) async {
    final opened = <String>[];
    await _pump(tester, onAction: (_, _) {}, onOpen: opened.add);
    await _focusList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    _expectSelected(tester, 1);
    expect(opened, isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    _expectSelected(tester, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, ['one']);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    _expectSelected(tester, 0);
  });

  testWidgets('A to B to A rejects old checkbox and action callbacks', (
    tester,
  ) async {
    final commands = <_Command>[];
    void action(MailBulkFlagAction action, List<String> ids) =>
        commands.add((action: action, ids: ids));
    await _pump(tester, onAction: action);
    await _tap(tester, _check('one'));
    final oldCheck = tester.widget<Checkbox>(_check('one')).onChanged!;
    final oldAction = _freezeMenu(tester);
    final oldSelect = tester
        .widget<TextButton>(_key('mail-list-select-shown'))
        .onPressed!;
    await _pump(tester, scope: 'account-b/inbox', onAction: action);
    await _pump(tester, scope: 'account-a/inbox', onAction: action);
    oldCheck(true);
    oldSelect();
    oldAction(MailBulkFlagAction.markRead);
    await tester.pump();
    _expectSelected(tester, 0);
    expect(commands, isEmpty);
  });

  testWidgets(
    'a popup opened for an older selection cannot command a new one',
    (tester) async {
      final commands = <_Command>[];
      await _pump(
        tester,
        onAction: (action, ids) => commands.add((action: action, ids: ids)),
      );
      await _tap(tester, _check('one'));
      final oldAction = _freezeMenu(tester);
      await _tap(tester, _check('two'));
      oldAction(MailBulkFlagAction.flag);
      expect(commands, isEmpty);
      await _action(tester, MailBulkFlagAction.flag);
      expect(commands.single.ids, ['one', 'two']);
    },
  );

  testWidgets(
    'refresh invalidates selection but preserves search and sorting',
    (tester) async {
      final commands = <_Command>[];
      void action(MailBulkFlagAction action, List<String> ids) =>
          commands.add((action: action, ids: ids));
      await _pump(tester, selectionScope: '1', onAction: action);
      await tester.enterText(_key('mail-list-search'), 'from:alice');
      await tester.pump();
      await _tap(tester, _key('mail-list-sort'));
      await _tap(tester, _key('mail-list-sort-subjectAscending'));
      await _tap(tester, _key('mail-list-select-shown'));
      final oldAction = _freezeMenu(tester);
      await _pump(tester, selectionScope: '2', onAction: action);
      _expectSelected(tester, 0);
      expect(
        tester.widget<TextField>(_key('mail-list-search')).controller!.text,
        'from:alice',
      );
      expect(
        tester
            .widget<PopupMenuButton<MailMessageListSort>>(
              _key('mail-list-sort'),
            )
            .initialValue,
        MailMessageListSort.subjectAscending,
      );
      oldAction(MailBulkFlagAction.markRead);
      expect(commands, isEmpty);
      await _tap(tester, _key('mail-list-select-shown'));
      await _action(tester, MailBulkFlagAction.markRead);
      expect(commands.single.ids, ['three', 'one']);
    },
  );

  testWidgets('busy state blocks new work but keeps stop available', (
    tester,
  ) async {
    var stops = 0;
    final commands = <_Command>[];
    void action(MailBulkFlagAction action, List<String> ids) =>
        commands.add((action: action, ids: ids));
    await _pump(tester, onAction: action);
    await _tap(tester, _check('one'));
    final oldAction = _freezeMenu(tester);
    await _pump(tester, onAction: action, busy: true, onCancel: () => stops++);
    expect(tester.widget<Checkbox>(_check('one')).onChanged, isNull);
    oldAction(MailBulkFlagAction.unflag);
    expect(commands, isEmpty);
    await _tap(tester, _key('mail-list-stop-bulk'));
    expect(stops, 1);
  });

  testWidgets('an accepted menu callback cannot be replayed after completion', (
    tester,
  ) async {
    var calls = 0;
    await _pump(tester, onAction: (_, _) => calls++);
    await _tap(tester, _check('one'));
    final action = _freezeMenu(tester);
    action(MailBulkFlagAction.flag);
    await tester.pump();
    action(MailBulkFlagAction.flag);
    expect(calls, 1);
    _expectSelected(tester, 0);
    await _tap(tester, _check('one'));
    await _action(tester, MailBulkFlagAction.flag);
    expect(calls, 2);
  });

  testWidgets(
    'refresh-required disables changes and clears the old selection',
    (tester) async {
      void action(MailBulkFlagAction _, List<String> _) {}
      await _pump(tester, onAction: action);
      await _tap(tester, _check('one'));
      await _pump(tester, onAction: action, enabled: false);
      expect(tester.widget<Checkbox>(_check('one')).onChanged, isNull);
      expect(
        tester
            .widget<PopupMenuButton<Object>>(_key('mail-list-bulk-actions'))
            .enabled,
        isFalse,
      );
      _expectSelected(tester, 0);
      expect(
        tester.widget<TextButton>(_key('mail-list-clear-selection')).onPressed,
        isNull,
      );
    },
  );

  testWidgets('read-only hosts expose no mutation selection or shortcuts', (
    tester,
  ) async {
    final opened = <String>[];
    await _pump(tester, onOpen: opened.add);
    expect(find.byType(Checkbox), findsNothing);
    expect(_key('mail-list-bulk-actions'), findsNothing);
    await _focusList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(opened, ['one']);
  });

  testWidgets('disposed callbacks cannot dispatch commands', (tester) async {
    var calls = 0;
    await _pump(tester, onAction: (_, _) => calls++);
    await _tap(tester, _check('one'));
    final check = tester.widget<Checkbox>(_check('one')).onChanged!;
    final action = _freezeMenu(tester);
    await tester.pumpWidget(const SizedBox());
    check(true);
    action(MailBulkFlagAction.markRead);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets(
      'compact enlarged selection controls remain usable $direction',
      (tester) async {
        await _pump(
          tester,
          width: 320,
          height: 260,
          scale: 1.4,
          direction: direction,
          onAction: (_, _) {},
        );
        expect(tester.takeException(), isNull);
        final list = tester.getRect(_key('mail-list-rows'));
        expect(list.height, greaterThanOrEqualTo(80));
        await _tap(tester, _key('mail-list-select-shown'));
        _expectSelected(tester, 3);
        await _tap(tester, _key('mail-list-bulk-actions'));
        final label = find.text(_strings.markRead);
        expect(Directionality.of(tester.element(label)), direction);
        expect(tester.widget<Text>(label).textScaler!.scale(10), 14);
        await _tap(tester, _key('mail-list-bulk-markRead'));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Boolean edits prune checks and reject an earlier bulk menu', (
    tester,
  ) async {
    final commands = <_Command>[];
    final opened = <String>[];
    await _pump(
      tester,
      onOpen: opened.add,
      onAction: (action, ids) => commands.add((action: action, ids: ids)),
    );
    await tester.enterText(_key('mail-list-search'), 'from:alice OR from:bob');
    await tester.pump();
    await _tap(tester, _key('mail-list-select-shown'));
    _expectSelected(tester, 3);
    final staleAction = _freezeMenu(tester);
    await tester.enterText(_key('mail-list-search'), 'NOT is:read');
    await tester.pump();
    _expectSelected(tester, 1);
    expect(_check('three'), findsNothing);
    staleAction(MailBulkFlagAction.flag);
    expect(commands, isEmpty);
    await tester.enterText(_key('mail-list-search'), '');
    await tester.pump();
    _expectSelected(tester, 1);
    await _action(tester, MailBulkFlagAction.flag);
    expect(commands.single.ids, ['one']);
    expect(opened, isEmpty);

    await _tap(tester, _key('mail-list-select-shown'));
    await tester.enterText(_key('mail-list-search'), 'from:alice OR');
    await tester.pump();
    _expectSelected(tester, 0);
    expect(_key('mail-list-search-error'), findsOneWidget);
    expect(commands, hasLength(1));
  });
}
