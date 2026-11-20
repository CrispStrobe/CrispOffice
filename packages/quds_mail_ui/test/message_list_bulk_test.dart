import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

String _count(int shown, int loaded) => '$shown of $loaded loaded';
String _selectedDe(int count) => '$count ausgewählt';
String _selectedAr(int count) => '$count محددة';

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

const _items = [
  MailMessageListItem(
    id: 'z',
    subject: 'Zebra project',
    sender: 'sara@example.test',
    isRead: false,
    isFlagged: true,
  ),
  MailMessageListItem(
    id: 'a',
    subject: 'Alpha project',
    sender: 'alice@example.test',
    isRead: true,
    isFlagged: false,
  ),
  MailMessageListItem(
    id: 'b',
    subject: 'Beta update',
    sender: 'bob@example.test',
  ),
];

Widget _app(
  Widget child, {
  double width = 420,
  double height = 560,
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
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    ),
  ),
);

MailMessageList _list({
  List<MailMessageListItem> items = _items,
  MailMessageListStrings strings = _strings,
  void Function(String)? onOpen,
  void Function(MailBulkFlagAction, List<String>)? onBulkAction,
  String scope = 'a/inbox',
  Object? revision,
  bool busy = false,
  bool enabled = true,
  VoidCallback? onLoadMore,
  Widget? status,
}) => MailMessageList(
  items: items,
  strings: strings,
  scopeId: scope,
  selectionScopeId: revision,
  busy: busy,
  bulkActionsEnabled: enabled,
  onOpen: onOpen ?? (_) {},
  onBulkAction: onBulkAction,
  hasMore: onLoadMore != null,
  onLoadMore: onLoadMore,
  bulkStatus: status,
);

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _check(String id) => _key('mail-list-check-$id');

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _selectAll(WidgetTester tester) =>
    _tap(tester, _key('mail-list-select-shown'));

Future<void> _focusList(WidgetTester tester) async {
  tester.widget<Focus>(_key('mail-list-focus')).focusNode!.requestFocus();
  await tester.pump();
}

Future<void> _invoke(WidgetTester tester, MailBulkFlagAction action) async {
  await _tap(tester, _key('mail-list-bulk-actions'));
  await _tap(tester, _key('mail-list-bulk-${action.name}'));
}

// Exercise the same frozen popup value and callback delivered after a route
// closes, including cases where the host has replaced the underlying widget.
VoidCallback _freezeAction(WidgetTester tester, MailBulkFlagAction action) {
  final finder = _key('mail-list-bulk-actions');
  final menu = tester.widget<PopupMenuButton<dynamic>>(finder);
  final entries = menu.itemBuilder(tester.element(finder));
  final entry = entries.whereType<PopupMenuItem<dynamic>>().singleWhere(
    (entry) => entry.key == ValueKey('mail-list-bulk-${action.name}'),
  );
  final value = entry.value;
  // Preserve the actual private menu-value type. Reading onSelected through
  // PopupMenuButton<dynamic> would incorrectly widen its function parameter.
  // ignore: avoid_dynamic_calls
  final callback = (menu as dynamic).onSelected as Function;
  return () => Function.apply(callback, [value]);
}

void main() {
  testWidgets('cached hosts have no mutable bulk controls', (tester) async {
    await tester.pumpWidget(_app(_list()));
    expect(find.byType(Checkbox), findsNothing);
    expect(_key('mail-list-select-shown'), findsNothing);
    expect(_key('mail-list-bulk-actions'), findsNothing);
    expect(_key('mail-list-selected-count'), findsNothing);
  });

  testWidgets('checking rows and selecting visible never opens or loads mail', (
    tester,
  ) async {
    var opens = 0;
    var loads = 0;
    var actions = 0;
    await tester.pumpWidget(
      _app(
        _list(
          onOpen: (_) => opens++,
          onLoadMore: () => loads++,
          onBulkAction: (_, _) => actions++,
        ),
      ),
    );
    await _tap(tester, _check('z'));
    expect(find.text('1 selected'), findsOneWidget);
    await _selectAll(tester);
    expect(find.text('3 selected'), findsOneWidget);
    await _tap(tester, _key('mail-list-clear-selection'));
    expect(find.text('0 selected'), findsOneWidget);
    expect(opens, 0);
    expect(loads, 0);
    expect(actions, 0);
  });

  for (final action in MailBulkFlagAction.values) {
    testWidgets('$action freezes visible order and clears before callback', (
      tester,
    ) async {
      final calls = <(MailBulkFlagAction, List<String>)>[];
      VoidCallback? duplicate;
      await tester.pumpWidget(
        _app(
          _list(
            onBulkAction: (action, ids) {
              calls.add((action, ids));
              duplicate?.call();
            },
          ),
        ),
      );
      await _selectAll(tester);
      await _tap(tester, _key('mail-list-sort'));
      await _tap(tester, _key('mail-list-sort-subjectAscending'));
      duplicate = _freezeAction(tester, action);
      await _invoke(tester, action);
      expect(calls, hasLength(1));
      expect(calls.single.$1, action);
      expect(calls.single.$2, ['a', 'b', 'z']);
      expect(() => calls.single.$2.add('injected'), throwsUnsupportedError);
      expect(find.text('0 selected'), findsOneWidget);
    });
  }

  testWidgets('filtering prunes hidden rows and never restores their checks', (
    tester,
  ) async {
    final batches = <List<String>>[];
    await tester.pumpWidget(
      _app(_list(onBulkAction: (_, ids) => batches.add(ids))),
    );
    await _selectAll(tester);
    await tester.enterText(_key('mail-list-search'), 'subject:project');
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.enterText(_key('mail-list-search'), '');
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    expect(tester.widget<Checkbox>(_check('b')).value, isFalse);
    await _invoke(tester, MailBulkFlagAction.flag);
    expect(batches.single, ['z', 'a']);
  });

  testWidgets(
    'unread filters prune unknown flags and invalid search clears all',
    (tester) async {
      await tester.pumpWidget(_app(_list(onBulkAction: (_, _) {})));
      await _selectAll(tester);
      await _tap(tester, _key('mail-list-unread'));
      expect(find.text('1 selected'), findsOneWidget);
      await tester.enterText(_key('mail-list-search'), 'body:unsupported');
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      await tester.enterText(_key('mail-list-search'), '');
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
    },
  );

  testWidgets('removed rows are pruned and appended pages are not selected', (
    tester,
  ) async {
    final batches = <List<String>>[];
    void onBulk(MailBulkFlagAction _, List<String> ids) => batches.add(ids);
    await tester.pumpWidget(
      _app(_list(items: _items.take(2).toList(), onBulkAction: onBulk)),
    );
    await _selectAll(tester);
    await tester.pumpWidget(_app(_list(onBulkAction: onBulk)));
    expect(find.text('2 selected'), findsOneWidget);
    expect(tester.widget<Checkbox>(_check('b')).value, isFalse);
    await tester.pumpWidget(
      _app(_list(items: _items.skip(1).toList(), onBulkAction: onBulk)),
    );
    expect(find.text('1 selected'), findsOneWidget);
    await _invoke(tester, MailBulkFlagAction.markUnread);
    expect(batches.single, ['a']);
  });

  for (final transition in ['scope', 'revision']) {
    testWidgets(
      '$transition resets checks and rejects overlapping stale rows',
      (tester) async {
        var actions = 0;
        void onBulk(MailBulkFlagAction _, List<String> _) => actions++;
        Widget app(int version) => _app(
          _list(
            onBulkAction: onBulk,
            scope: transition == 'scope' ? '$version/inbox' : 'a/inbox',
            revision: transition == 'revision' ? version : null,
          ),
        );
        await tester.pumpWidget(app(0));
        await _selectAll(tester);
        final oldAction = _freezeAction(tester, MailBulkFlagAction.markRead);
        final oldCheckbox = tester.widget<Checkbox>(_check('z')).onChanged!;
        await tester.pumpWidget(app(1));
        oldAction();
        oldCheckbox(true);
        await tester.pumpAndSettle();
        expect(find.text('0 selected'), findsOneWidget);
        await tester.pumpWidget(app(0));
        oldAction();
        oldCheckbox(true);
        await tester.pumpAndSettle();
        expect(find.text('0 selected'), findsOneWidget);
        expect(actions, 0);
      },
    );
  }

  testWidgets(
    'refresh revision clears checks while preserving query and sort',
    (tester) async {
      Widget app(int revision) =>
          _app(_list(revision: revision, onBulkAction: (_, _) {}));
      await tester.pumpWidget(app(0));
      await tester.enterText(_key('mail-list-search'), 'project');
      await _tap(tester, _key('mail-list-sort'));
      await _tap(tester, _key('mail-list-sort-subjectAscending'));
      await _selectAll(tester);
      await tester.pumpWidget(app(1));
      expect(find.text('0 selected'), findsOneWidget);
      expect(
        tester.widget<TextField>(_key('mail-list-search')).controller!.text,
        'project',
      );
      expect(find.text('Subject (A–Z)'), findsOneWidget);
      expect(_check('b'), findsNothing);
    },
  );

  for (final change in ['filter', 'selection', 'sort', 'host']) {
    testWidgets('pending menu cannot survive a $change change', (tester) async {
      var actions = 0;
      Widget app() => _app(_list(onBulkAction: (_, _) => actions++));
      await tester.pumpWidget(app());
      await _selectAll(tester);
      final oldAction = _freezeAction(tester, MailBulkFlagAction.unflag);
      switch (change) {
        case 'filter':
          await tester.enterText(_key('mail-list-search'), 'project');
          await tester.enterText(_key('mail-list-search'), '');
        case 'selection':
          await _tap(tester, _check('z'));
          await _tap(tester, _check('z'));
        case 'sort':
          await _tap(tester, _key('mail-list-sort'));
          await _tap(tester, _key('mail-list-sort-subjectAscending'));
        case 'host':
          await tester.pumpWidget(app());
      }
      oldAction();
      await tester.pumpAndSettle();
      expect(actions, 0);
    });
  }

  for (final change in ['scope', 'filter', 'selection', 'sort', 'host']) {
    testWidgets('actual open popup rejects a $change change', (tester) async {
      var actions = 0;
      Widget app({String scope = 'a/inbox'}) =>
          _app(_list(scope: scope, onBulkAction: (_, _) => actions++));
      await tester.pumpWidget(app());
      await _selectAll(tester);
      await _tap(tester, _key('mail-list-bulk-actions'));
      switch (change) {
        case 'scope':
          await tester.pumpWidget(app(scope: 'b/inbox'));
          await tester.pumpWidget(app());
        case 'filter':
          final field = tester.widget<TextField>(_key('mail-list-search'));
          field.controller!.text = 'project';
          field.onChanged!('project');
        case 'selection':
          tester.widget<Checkbox>(_check('z')).onChanged!(false);
        case 'sort':
          tester
              .widget<PopupMenuButton<MailMessageListSort>>(
                _key('mail-list-sort'),
              )
              .onSelected!(MailMessageListSort.subjectAscending);
        case 'host':
          await tester.pumpWidget(app());
      }
      await tester.pumpAndSettle();
      expect(_key('mail-list-bulk-markRead'), findsOneWidget);
      await _tap(tester, _key('mail-list-bulk-markRead'));
      expect(actions, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('actual open popup is inert after host refresh', (tester) async {
    var actions = 0;
    Widget app(int revision) =>
        _app(_list(revision: revision, onBulkAction: (_, _) => actions++));
    await tester.pumpWidget(app(0));
    await _selectAll(tester);
    await _tap(tester, _key('mail-list-bulk-actions'));
    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();
    await _tap(tester, _key('mail-list-bulk-markRead'));
    expect(actions, 0);
    expect(find.text('0 selected'), findsOneWidget);
  });

  testWidgets(
    'stale select-visible and clear callbacks cannot change selection',
    (tester) async {
      await tester.pumpWidget(_app(_list(onBulkAction: (_, _) {})));
      final oldSelect = tester
          .widget<TextButton>(_key('mail-list-select-shown'))
          .onPressed!;
      await _selectAll(tester);
      final oldClear = tester
          .widget<TextButton>(_key('mail-list-clear-selection'))
          .onPressed!;
      await tester.enterText(_key('mail-list-search'), 'project');
      await tester.pumpAndSettle();
      oldSelect();
      oldClear();
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
    },
  );

  testWidgets(
    'busy and refresh-required hosts reject all selection and actions',
    (tester) async {
      var opens = 0;
      var actions = 0;
      Widget app({bool busy = false, bool enabled = true}) => _app(
        _list(
          busy: busy,
          enabled: enabled,
          onOpen: (_) => opens++,
          onBulkAction: (_, _) => actions++,
        ),
      );
      await tester.pumpWidget(app());
      await _selectAll(tester);
      final oldAction = _freezeAction(tester, MailBulkFlagAction.flag);
      await tester.pumpWidget(app(busy: true));
      expect(tester.widget<Checkbox>(_check('z')).onChanged, isNull);
      expect(
        tester.widget<TextButton>(_key('mail-list-select-shown')).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(_key('mail-list-clear-selection')).onPressed,
        isNull,
      );
      await _focusList(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      oldAction();
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
      await tester.pumpWidget(app(enabled: false));
      expect(find.text('0 selected'), findsOneWidget);
      expect(tester.widget<Checkbox>(_check('z')).onChanged, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      oldAction();
      await tester.pumpAndSettle();
      expect(actions, 0);
      expect(opens, 0);
    },
  );

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft,
  ]) {
    testWidgets('$modifier+A checks visible loaded rows; Enter still opens', (
      tester,
    ) async {
      final opened = <String>[];
      final batches = <List<String>>[];
      await tester.pumpWidget(
        _app(
          _list(onOpen: opened.add, onBulkAction: (_, ids) => batches.add(ids)),
        ),
      );
      await tester.enterText(_key('mail-list-search'), 'project');
      await _focusList(tester);
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(opened, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, ['z']);
      await _invoke(tester, MailBulkFlagAction.markRead);
      expect(batches.single, ['a']);
    });
  }

  testWidgets('search editing keeps Ctrl+A and Space without checking mail', (
    tester,
  ) async {
    var actions = 0;
    var opens = 0;
    await tester.pumpWidget(
      _app(_list(onOpen: (_) => opens++, onBulkAction: (_, _) => actions++)),
    );
    await tester.enterText(_key('mail-list-search'), 'project');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
    expect(actions, 0);
    expect(opens, 0);
  });

  testWidgets('disposed list ignores all captured bulk callbacks', (
    tester,
  ) async {
    var actions = 0;
    await tester.pumpWidget(_app(_list(onBulkAction: (_, _) => actions++)));
    await _selectAll(tester);
    final oldAction = _freezeAction(tester, MailBulkFlagAction.flag);
    final oldCheck = tester.widget<Checkbox>(_check('z')).onChanged!;
    final oldClear = tester
        .widget<TextButton>(_key('mail-list-clear-selection'))
        .onPressed!;
    await tester.pumpWidget(_app(const SizedBox.shrink()));
    oldAction();
    oldCheck(false);
    oldClear();
    expect(actions, 0);
    expect(tester.takeException(), isNull);
  });

  for (final (language, direction, strings) in const [
    (
      'de',
      TextDirection.ltr,
      MailMessageListStrings(
        searchLoaded: 'Geladene Nachrichtenköpfe durchsuchen',
        unread: 'Ungelesen',
        flagged: 'Gekennzeichnet',
        noMessages: 'Keine Nachrichten',
        noMatches: 'Keine Treffer',
        loadMore: 'Weitere Nachrichten laden',
        loading: 'Wird geladen',
        loadedScope: 'Nur geladene Nachrichtenköpfe dieses Ordners.',
        count: _count,
        providerOrder: 'Ordnerreihenfolge',
        selectMessage: 'Nachricht auswählen',
        selectShown: 'Sichtbare auswählen',
        clearSelection: 'Auswahl aufheben',
        selectedCount: _selectedDe,
        bulkActions: 'Ausgewählte Nachrichten',
        markRead: 'Als gelesen markieren',
        markUnread: 'Als ungelesen markieren',
        flag: 'Kennzeichnen',
        unflag: 'Kennzeichnung entfernen',
      ),
    ),
    (
      'ar',
      TextDirection.rtl,
      MailMessageListStrings(
        searchLoaded: 'البحث في الترويسات المحمّلة',
        unread: 'غير مقروءة',
        flagged: 'المعلّمة',
        noMessages: 'لا رسائل',
        noMatches: 'لا نتائج',
        loadMore: 'تحميل المزيد',
        loading: 'جارٍ التحميل',
        loadedScope: 'الترويسات المحمّلة في هذا المجلد فقط.',
        count: _count,
        providerOrder: 'ترتيب المجلد',
        selectMessage: 'تحديد الرسالة',
        selectShown: 'تحديد الظاهرة',
        clearSelection: 'مسح التحديد',
        selectedCount: _selectedAr,
        bulkActions: 'الرسائل المحددة',
        markRead: 'وضع كمقروءة',
        markUnread: 'وضع كغير مقروءة',
        flag: 'وضع علامة',
        unflag: 'إزالة العلامة',
      ),
    ),
  ]) {
    testWidgets(
      'compact $language controls and results remain usable at 1.4x',
      (tester) async {
        final batches = <List<String>>[];
        await tester.pumpWidget(
          _app(
            _list(
              strings: strings,
              onBulkAction: (_, ids) => batches.add(ids),
              status: const Text('2 confirmed · 1 unattempted'),
            ),
            width: 320,
            height: 360,
            scale: 1.4,
            direction: direction,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(_key('mail-list-rows')).height,
          greaterThanOrEqualTo(90),
        );
        await _selectAll(tester);
        await _invoke(tester, MailBulkFlagAction.unflag);
        expect(batches.single, ['z', 'a', 'b']);
        await tester.ensureVisible(find.text('2 confirmed · 1 unattempted'));
        await tester.pumpAndSettle();
        expect(
          find.text('2 confirmed · 1 unattempted').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
