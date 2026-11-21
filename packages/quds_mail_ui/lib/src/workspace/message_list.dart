import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

/// An immutable, provider-neutral row for foreground mailbox navigation.
///
/// [id] must be unique in the loaded collection and stable across refreshes.
/// Hosts own its account/provider namespace and must never use an IMAP sequence
/// number or an RFC Message-ID as the row's mailbox identity. Null flag values
/// mean unobserved and do not match the unread or flagged filters.
final class MailMessageListItem {
  const MailMessageListItem({
    required this.id,
    required this.subject,
    required this.sender,
    this.to = '',
    this.cc = '',
    this.date,
    this.dateLabel,
    this.isRead,
    this.isFlagged,
    this.accountId,
    this.messageId,
    this.inReplyTo,
    this.references = const [],
  });

  final String id;
  final String subject;
  final String sender;

  /// Already loaded, visible recipient headers, never hidden recipients or body.
  final String to;
  final String cc;

  /// Actual message timestamp for search/sort; [dateLabel] is presentation only.
  final DateTime? date;
  final String? dateLabel;
  final bool? isRead;
  final bool? isFlagged;

  /// Account namespace; absent means conversation grouping is unavailable.
  final String? accountId;
  final String? messageId;
  final String? inReplyTo;
  final List<String> references;
}

/// Local ordering of the loaded rows. Equal values retain provider order.
enum MailMessageListSort {
  providerOrder,
  newestFirst,
  oldestFirst,
  senderAscending,
  subjectAscending,
}

/// Host-localized copy; the shared list has no application localization global.
final class MailMessageListStrings {
  const MailMessageListStrings({
    required this.searchLoaded,
    required this.unread,
    required this.flagged,
    required this.noMessages,
    required this.noMatches,
    required this.loadMore,
    required this.loading,
    required this.loadedScope,
    required this.count,
    this.clearSearch = 'Clear search',
    this.searchHelp = 'Search help',
    this.searchHelpTitle = 'Search loaded message headers',
    this.searchHelpText =
        'Separate terms or use AND to require every match. Use OR for '
        'alternatives and NOT or a leading - to exclude a match. '
        'NOT applies before AND, then OR; parentheses group conditions. '
        'Use from:, to:, cc:, subject:, is:read, is:unread, is:flagged '
        'or is:unflagged. Use before:YYYY-MM-DD, after:YYYY-MM-DD or '
        'on:YYYY-MM-DD for dates. Before and after exclude the named day. '
        'Unknown dates and flags remain unknown, including with NOT. '
        'Put phrases or literal operators in double quotes. '
        'Only loaded message headers are searched. '
        'Use at most 1,024 characters, 32 terms, 32 explicit operators '
        'and 8 nested groups. Body text, attachments and wildcards '
        'are not searched.',
    this.close = 'Close',
    this.sort = 'Sort loaded messages',
    this.providerOrder = 'Provider order',
    this.newestFirst = 'Newest first',
    this.oldestFirst = 'Oldest first',
    this.senderAscending = 'Sender (A–Z)',
    this.subjectAscending = 'Subject (A–Z)',
    this.searchError = _defaultSearchError,
    this.selectMessage = 'Select message',
    String? selectShown,
    String? selectVisible,
    this.clearSelection = 'Clear selection',
    this.selectedCount = _defaultSelectedCount,
    this.bulkActions = 'Selected messages',
    this.markRead = 'Mark as read',
    this.markUnread = 'Mark as unread',
    this.flag = 'Flag',
    this.unflag = 'Remove flag',
    this.stopBulk = 'Stop after current message',
    this.bulkWorking = 'Applying changes…',
    this.groupConversations = 'Conversations',
    this.conversationCount = _defaultConversationCount,
  }) : assert(
         selectShown == null ||
             selectVisible == null ||
             selectShown == selectVisible,
       ),
       selectShown = selectShown ?? selectVisible ?? 'Select shown';

  final String searchLoaded;
  final String unread;
  final String flagged;
  final String noMessages;
  final String noMatches;
  final String loadMore;
  final String loading;
  final String loadedScope;
  final String Function(int shown, int loaded) count;
  final String clearSearch;
  final String searchHelp;
  final String searchHelpTitle;
  final String searchHelpText;
  final String close;
  final String sort;
  final String providerOrder;
  final String newestFirst;
  final String oldestFirst;
  final String senderAscending;
  final String subjectAscending;
  final String Function(MailHeaderSearchError error) searchError;
  final String selectMessage;
  final String selectShown;
  String get selectVisible => selectShown;
  final String clearSelection;
  final String Function(int selected) selectedCount;
  final String bulkActions;
  final String markRead;
  final String markUnread;
  final String flag;
  final String unflag;
  final String stopBulk;
  final String bulkWorking;
  final String groupConversations;
  final String Function(int count) conversationCount;
}

String _defaultConversationCount(int count) =>
    '$count loaded messages in conversation';

String _defaultSelectedCount(int selected) => '$selected selected';

String _defaultSearchError(MailHeaderSearchError error) => switch (error) {
  MailHeaderSearchError.queryTooLong => 'The search is too long.',
  MailHeaderSearchError.tooManyTerms => 'Use fewer search terms.',
  MailHeaderSearchError.invalidCharacter =>
    'The search contains an unsupported character.',
  MailHeaderSearchError.unclosedQuote => 'Close the quoted search phrase.',
  MailHeaderSearchError.invalidEscape =>
    'Inside quotes, only a quote or backslash can be escaped.',
  MailHeaderSearchError.emptyTerm => 'Enter text inside the quoted phrase.',
  MailHeaderSearchError.missingValue => 'Enter a value after the search field.',
  MailHeaderSearchError.unknownField => 'This search field is not supported.',
  MailHeaderSearchError.invalidState =>
    'Use is:read, is:unread, is:flagged or is:unflagged.',
  MailHeaderSearchError.invalidDate => 'Enter a valid date as YYYY-MM-DD.',
  MailHeaderSearchError.unsupportedOperator =>
    'Wildcards, brackets and symbolic operators are not supported.',
  MailHeaderSearchError.invalidExpression =>
    'Complete each AND, OR or NOT expression and balance parentheses. '
        'Use at most 32 explicit operators.',
  MailHeaderSearchError.nestingTooDeep => 'Use no more than 8 nested groups.',
};

final _searchExampleLine = RegExp(
  r'^\s*(?:[-(]\s*|NOT\b\s*)*(?:from|subject|to|cc|is|before|after|on):',
  caseSensitive: false,
);

/// Shared, virtualized foreground message navigation for native/cloud hosts.
///
/// Structured header search, sorting and the conjunctive unread/flagged filters
/// only inspect [items]. They never trigger a provider request. The host owns
/// pagination, opened-message selection, reads, mutations and durable storage.
/// If [onBulkAction] is supplied, this view owns an independent checked set and
/// forwards only explicit actions over immutable visible-row snapshots. It
/// never calls a provider. Arrow/Home/End move a separate keyboard cursor;
/// Enter or explicit row activation invokes [onOpen]. Space checks the cursor
/// when bulk actions are available, and Ctrl/Cmd+A checks visible rows only
/// while the list owns focus. Search editing owns its own keys.
///
/// Change [scopeId] (or the widget key) for a different account or mailbox.
/// That resets query, filters, sort, keyboard focus and scroll position. Within
/// one scope the keyboard cursor follows the stable row ID through reordering.
class MailMessageList extends StatefulWidget {
  MailMessageList({
    super.key,
    required List<MailMessageListItem> items,
    required this.strings,
    required this.onOpen,
    this.selectedId,
    this.scopeId,
    this.busy = false,
    this.hasMore = false,
    this.onLoadMore,
    this.limitNotice,
    this.loadMoreKey,
    this.onBulkAction,
    Object? selectionScopeId,
    Object? selectionRevision,
    bool? bulkActionsEnabled,
    bool? bulkEnabled,
    this.bulkStatus,
    this.onCancelBulk,
  }) : items = List.unmodifiable(items),
       selectionScopeId = selectionScopeId ?? selectionRevision,
       bulkActionsEnabled = bulkActionsEnabled ?? bulkEnabled ?? true {
    if (selectionScopeId != null &&
        selectionRevision != null &&
        selectionScopeId != selectionRevision) {
      throw ArgumentError(
        'Selection revision aliases must identify one scope.',
      );
    }
    if (bulkActionsEnabled != null &&
        bulkEnabled != null &&
        bulkActionsEnabled != bulkEnabled) {
      throw ArgumentError('Bulk enabled aliases must agree.');
    }
    final identities = <String>{};
    for (final item in this.items) {
      if (item.id.isEmpty || !identities.add(item.id)) {
        throw ArgumentError('Message rows require unique nonempty identities.');
      }
    }
  }

  final List<MailMessageListItem> items;
  final MailMessageListStrings strings;
  final void Function(String id) onOpen;
  final String? selectedId;
  final String? scopeId;
  final bool busy;
  final bool hasMore;
  final VoidCallback? onLoadMore;
  final String? limitNotice;
  final Key? loadMoreKey;

  /// Omit for read-only/cached hosts. IDs arrive in the current visible order.
  /// The checked set is cleared before this explicit callback is invoked.
  final void Function(MailBulkFlagAction action, List<String> ids)?
  onBulkAction;

  /// Change after refresh or any host identity/session revision. This clears
  /// checked rows and invalidates already-open menus, even if row IDs overlap.
  final Object? selectionScopeId;
  Object? get selectionRevision => selectionScopeId;

  /// Keep controls visible but unavailable when the host requires a refresh.
  final bool bulkActionsEnabled;
  bool get bulkEnabled => bulkActionsEnabled;

  /// Optional host-owned progress/results, kept in the scrollable header.
  final Widget? bulkStatus;

  /// Present only during a batch; remains usable while busy blocks new work.
  final VoidCallback? onCancelBulk;

  @override
  State<MailMessageList> createState() => _MailMessageListState();
}

class _MailMessageListState extends State<MailMessageList> {
  final _query = TextEditingController();
  final _listFocus = FocusNode(debugLabel: 'Mail message list');
  final _headerScroll = ScrollController();
  final _scroll = ScrollController();
  bool _unread = false;
  bool _flagged = false;
  bool _conversations = false;
  MailHeaderSearchQuery? _compiledQuery = MailHeaderSearchQuery.parse('');
  MailHeaderSearchException? _queryError;
  MailMessageListSort _sort = MailMessageListSort.providerOrder;
  int _interactionGeneration = 0;
  final _checkedIds = <String>{};
  String? _activeId;
  double _itemExtent = 84;

  bool get _canGroupConversations => widget.items.any(
    (item) =>
        (item.accountId?.isNotEmpty ?? false) &&
        (item.messageId != null ||
            item.inReplyTo != null ||
            item.references.isNotEmpty),
  );

  List<MailConversationGroup> _conversationGroups(
    List<MailMessageListItem> items,
  ) => groupMailConversations([
    for (final item in items)
      MailConversationEntry(
        id: item.id,
        // Without an explicit account, refuse to group this row with others.
        accountId: item.accountId?.isNotEmpty == true
            ? item.accountId!
            : '\u0000unscoped:' + item.id,
        messageId: item.messageId,
        inReplyTo: item.inReplyTo,
        references: item.references,
      ),
  ]);

  List<MailMessageListItem> get _visible {
    final query = _compiledQuery;
    if (query == null) return const [];
    final rows = <({int index, MailMessageListItem item})>[];
    for (var index = 0; index < widget.items.length; index++) {
      final item = widget.items[index];
      if ((!_unread || item.isRead == false) &&
          (!_flagged || item.isFlagged == true) &&
          query.matches(
            MailHeaderSearchDocument(
              subject: item.subject,
              sender: item.sender,
              to: item.to,
              cc: item.cc,
              date: item.date,
              isRead: item.isRead,
              isFlagged: item.isFlagged,
            ),
          )) {
        rows.add((index: index, item: item));
      }
    }
    if (_sort != MailMessageListSort.providerOrder) {
      rows.sort((a, b) {
        final comparison = switch (_sort) {
          MailMessageListSort.providerOrder => 0,
          MailMessageListSort.newestFirst => _compareDates(
            a.item,
            b.item,
            true,
          ),
          MailMessageListSort.oldestFirst => _compareDates(
            a.item,
            b.item,
            false,
          ),
          MailMessageListSort.senderAscending =>
            a.item.sender.toLowerCase().compareTo(b.item.sender.toLowerCase()),
          MailMessageListSort.subjectAscending =>
            a.item.subject.toLowerCase().compareTo(
              b.item.subject.toLowerCase(),
            ),
        };
        return comparison == 0 ? a.index.compareTo(b.index) : comparison;
      });
    }
    final visible = [for (final row in rows) row.item];
    if (!_conversations || !_canGroupConversations) return visible;
    final byId = {for (final item in visible) item.id: item};
    return [
      for (final group in _conversationGroups(visible))
        for (final member in group.entries) byId[member.id]!,
    ];
  }

  int _compareDates(
    MailMessageListItem a,
    MailMessageListItem b,
    bool descending,
  ) {
    final left = a.date;
    final right = b.date;
    if (left == null) return right == null ? 0 : 1;
    if (right == null) return -1;
    return descending ? right.compareTo(left) : left.compareTo(right);
  }

  bool get _filtered => _unread || _flagged || _query.text.trim().isNotEmpty;
  bool get _canBulk =>
      widget.onBulkAction != null && widget.bulkActionsEnabled && !widget.busy;

  @override
  void didUpdateWidget(MailMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A host rebuild can replace a provider/session or header observations.
    // Keep compatible checked rows, but never reuse its old pointer/menu work.
    _interactionGeneration++;
    if (oldWidget.selectionScopeId != widget.selectionScopeId ||
        oldWidget.scopeId != widget.scopeId ||
        widget.onBulkAction == null ||
        !widget.bulkActionsEnabled) {
      _checkedIds.clear();
    }
    if (oldWidget.scopeId != widget.scopeId) {
      _query.clear();
      _compileQuery();
      _unread = false;
      _flagged = false;
      _conversations = false;
      _sort = MailMessageListSort.providerOrder;
      _activeId = null;
      _listFocus.unfocus();
      _resetScroll(header: true);
    } else {
      final visible = _visible;
      _pruneSelection(visible);
      _reconcileCursor(visible);
      if (_listFocus.hasFocus) _revealCursor();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _listFocus.dispose();
    _headerScroll.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _reconcileCursor(List<MailMessageListItem> visible) {
    if (visible.any((item) => item.id == _activeId)) return;
    _activeId = visible.any((item) => item.id == widget.selectedId)
        ? widget.selectedId
        : visible.firstOrNull?.id;
  }

  void _resetScroll({bool header = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      if (mounted && header && _headerScroll.hasClients) {
        _headerScroll.jumpTo(0);
      }
    });
  }

  void _filterChanged(VoidCallback update) {
    setState(() {
      _interactionGeneration++;
      update();
      final visible = _visible;
      _pruneSelection(visible);
      _reconcileCursor(visible);
    });
    _resetScroll();
  }

  void _compileQuery() {
    try {
      _compiledQuery = MailHeaderSearchQuery.parse(_query.text);
      _queryError = null;
    } on MailHeaderSearchException catch (error) {
      _compiledQuery = null;
      _queryError = error;
    }
  }

  String _sortLabel(MailMessageListSort sort) => switch (sort) {
    MailMessageListSort.providerOrder => widget.strings.providerOrder,
    MailMessageListSort.newestFirst => widget.strings.newestFirst,
    MailMessageListSort.oldestFirst => widget.strings.oldestFirst,
    MailMessageListSort.senderAscending => widget.strings.senderAscending,
    MailMessageListSort.subjectAscending => widget.strings.subjectAscending,
  };

  void _sortChanged(MailMessageListSort value) {
    setState(() {
      _interactionGeneration++;
      _sort = value;
      _reconcileCursor(_visible);
    });
    if (_listFocus.hasFocus) {
      _revealCursor();
    } else {
      _resetScroll();
    }
  }

  void _pruneSelection(List<MailMessageListItem> visible) {
    final ids = visible.map((item) => item.id).toSet();
    _checkedIds.removeWhere((id) => !ids.contains(id));
  }

  bool _acceptBulkCallback(int generation) =>
      mounted && _canBulk && generation == _interactionGeneration;

  void _checkRow(String id, bool checked, int generation) {
    if (!_acceptBulkCallback(generation) ||
        !_visible.any((item) => item.id == id)) {
      return;
    }
    setState(() {
      _interactionGeneration++;
      if (checked) {
        _checkedIds.add(id);
      } else {
        _checkedIds.remove(id);
      }
      _activeId = id;
    });
    _listFocus.requestFocus();
  }

  void _selectShown(int generation) {
    if (!_acceptBulkCallback(generation)) return;
    final visible = _visible;
    setState(() {
      _interactionGeneration++;
      _checkedIds
        ..clear()
        ..addAll(visible.map((item) => item.id));
      _reconcileCursor(visible);
    });
    _listFocus.requestFocus();
  }

  void _clearSelection(int generation) {
    if (!_acceptBulkCallback(generation)) return;
    setState(() {
      _interactionGeneration++;
      _checkedIds.clear();
    });
  }

  String _bulkLabel(MailBulkFlagAction action) => switch (action) {
    MailBulkFlagAction.markRead => widget.strings.markRead,
    MailBulkFlagAction.markUnread => widget.strings.markUnread,
    MailBulkFlagAction.flag => widget.strings.flag,
    MailBulkFlagAction.unflag => widget.strings.unflag,
  };

  void _runBulk(_BulkChoice choice) {
    if (!_acceptBulkCallback(choice.generation) || choice.ids.isEmpty) return;
    final current = [
      for (final row in _visible)
        if (_checkedIds.contains(row.id)) row.id,
    ];
    if (current.length != choice.ids.length) return;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != choice.ids[i]) return;
    }
    final callback = widget.onBulkAction!;
    setState(() {
      _interactionGeneration++;
      _checkedIds.clear();
    });
    callback(choice.action, choice.ids);
  }

  void _showSearchHelp() {
    final strings = widget.strings;
    final direction = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    showDialog<void>(
      context: context,
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: Directionality(
          textDirection: direction,
          child: AlertDialog(
            title: Text(strings.searchHelpTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in strings.searchHelpText.split('\n'))
                    Text(
                      line.isEmpty ? ' ' : line,
                      textDirection: _searchExampleLine.hasMatch(line)
                          ? TextDirection.ltr
                          : null,
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _revealCursor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final index = _visible.indexWhere((item) => item.id == _activeId);
      if (index < 0) return;
      final position = _scroll.position;
      final top = index * _itemExtent;
      final bottom = top + _itemExtent;
      final desired = top < position.pixels
          ? top
          : bottom > position.pixels + position.viewportDimension
          ? bottom - position.viewportDimension
          : position.pixels;
      _scroll.jumpTo(
        desired
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    });
  }

  void _open(String id, {int? interactionGeneration}) {
    if (!mounted ||
        interactionGeneration != null &&
            interactionGeneration != _interactionGeneration ||
        widget.busy ||
        !_visible.any((item) => item.id == id)) {
      return;
    }
    setState(() => _activeId = id);
    _listFocus.requestFocus();
    widget.onOpen(id);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final selectAll =
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        key == LogicalKeyboardKey.keyA;
    if (selectAll && widget.onBulkAction != null) {
      if (event is KeyDownEvent) _selectShown(_interactionGeneration);
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape &&
        widget.onBulkAction != null &&
        _checkedIds.isNotEmpty) {
      if (event is KeyDownEvent) _clearSelection(_interactionGeneration);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space && widget.onBulkAction != null) {
      if (event is KeyDownEvent) {
        if (_activeId case final id?) {
          _checkRow(id, !_checkedIds.contains(id), _interactionGeneration);
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        if (_activeId case final id?) _open(id);
      }
      return KeyEventResult.handled;
    }
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.home &&
        key != LogicalKeyboardKey.end) {
      return KeyEventResult.ignored;
    }
    final visible = _visible;
    if (visible.isEmpty) return KeyEventResult.handled;
    final current = visible.indexWhere((item) => item.id == _activeId);
    final index = switch (key) {
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => visible.length - 1,
      LogicalKeyboardKey.arrowUp => math.max(0, current - 1),
      _ => math.min(visible.length - 1, current + 1),
    };
    setState(() => _activeId = visible[index].id);
    _revealCursor();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final conversationCounts = <String, int>{};
    if (_conversations && _canGroupConversations) {
      for (final group in _conversationGroups(visible)) {
        if (group.length > 1) {
          conversationCounts[group.entries.first.id] = group.length;
        }
      }
    }
    final notAllLoaded = widget.hasMore || widget.limitNotice != null;
    final strings = widget.strings;
    final scaler = MediaQuery.textScalerOf(context);
    final generation = _interactionGeneration;
    final direction = Directionality.of(context);
    _itemExtent = math.max(
      84.0,
      scaler.scale(14) * 1.3 +
          scaler.scale(12) * 1.3 +
          scaler.scale(11) * 1.3 +
          24,
    );
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('mail-list-search'),
                  controller: _query,
                  onChanged: (_) => _filterChanged(_compileQuery),
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    hintText: strings.searchLoaded,
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey('mail-list-clear-search'),
                            tooltip: strings.clearSearch,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => _filterChanged(() {
                              _query.clear();
                              _compileQuery();
                            }),
                          ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('mail-list-search-help'),
                tooltip: strings.searchHelp,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.help_outline, size: 18),
                onPressed: _showSearchHelp,
              ),
            ],
          ),
        ),
        if (_queryError case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Semantics(
              liveRegion: true,
              child: Text(
                strings.searchError(error.code),
                key: const ValueKey('mail-list-search-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              Tooltip(
                message: strings.unread,
                child: FilterChip(
                  key: const ValueKey('mail-list-unread'),
                  label: const Icon(Icons.mark_email_unread_outlined, size: 18),
                  tooltip: strings.unread,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelPadding: EdgeInsets.zero,
                  padding: const EdgeInsets.all(6),
                  selected: _unread,
                  onSelected: (value) => _filterChanged(() => _unread = value),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: strings.flagged,
                child: FilterChip(
                  key: const ValueKey('mail-list-flagged'),
                  label: const Icon(Icons.outlined_flag, size: 18),
                  tooltip: strings.flagged,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelPadding: EdgeInsets.zero,
                  padding: const EdgeInsets.all(6),
                  selected: _flagged,
                  onSelected: (value) => _filterChanged(() => _flagged = value),
                ),
              ),
              if (_canGroupConversations) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: strings.groupConversations,
                  child: FilterChip(
                    key: const ValueKey('mail-list-conversations'),
                    label: const Icon(Icons.forum_outlined, size: 18),
                    tooltip: strings.groupConversations,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelPadding: EdgeInsets.zero,
                    padding: const EdgeInsets.all(6),
                    selected: _conversations,
                    onSelected: (value) =>
                        _filterChanged(() => _conversations = value),
                  ),
                ),
              ],
              const Spacer(),
              PopupMenuButton<MailMessageListSort>(
                key: const ValueKey('mail-list-sort'),
                tooltip: strings.sort,
                initialValue: _sort,
                onSelected: _sortChanged,
                itemBuilder: (context) => [
                  for (final sort in MailMessageListSort.values)
                    PopupMenuItem(
                      key: ValueKey('mail-list-sort-${sort.name}'),
                      value: sort,
                      child: Text(_sortLabel(sort), textScaler: scaler),
                    ),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.sort, size: 20),
                ),
              ),
            ],
          ),
        ),
        if (notAllLoaded || visible.length != widget.items.length)
          Tooltip(
            message: strings.loadedScope,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  strings.count(visible.length, widget.items.length),
                  key: const ValueKey('mail-list-scope'),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ),
        if (widget.onBulkAction != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Wrap(
              spacing: 4,
              runSpacing: 0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    strings.selectedCount(_checkedIds.length),
                    key: const ValueKey('mail-list-selected-count'),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                TextButton(
                  key: const ValueKey('mail-list-select-shown'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 30),
                  ),
                  onPressed: _canBulk && visible.isNotEmpty
                      ? () => _selectShown(generation)
                      : null,
                  child: Text(strings.selectShown),
                ),
                TextButton(
                  key: const ValueKey('mail-list-clear-selection'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 30),
                  ),
                  onPressed: _canBulk && _checkedIds.isNotEmpty
                      ? () => _clearSelection(generation)
                      : null,
                  child: Text(strings.clearSelection),
                ),
                PopupMenuButton<_BulkChoice>(
                  key: const ValueKey('mail-list-bulk-actions'),
                  tooltip: strings.bulkActions,
                  enabled: _canBulk && _checkedIds.isNotEmpty,
                  onSelected: _runBulk,
                  itemBuilder: (context) {
                    if (!_acceptBulkCallback(generation)) return [];
                    // Freeze when the menu opens, not when it later closes:
                    // PopupMenuButton may receive an updated onSelected.
                    final ids = List<String>.unmodifiable([
                      for (final row in _visible)
                        if (_checkedIds.contains(row.id)) row.id,
                    ]);
                    final menuGeneration = _interactionGeneration;
                    return [
                      for (final action in MailBulkFlagAction.values)
                        PopupMenuItem(
                          key: ValueKey('mail-list-bulk-${action.name}'),
                          value: _BulkChoice(action, ids, menuGeneration),
                          child: Directionality(
                            textDirection: direction,
                            child: Text(_bulkLabel(action), textScaler: scaler),
                          ),
                        ),
                    ];
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.checklist,
                      size: 20,
                      color: _canBulk && _checkedIds.isNotEmpty
                          ? null
                          : Theme.of(context).disabledColor,
                    ),
                  ),
                ),
                if (widget.onCancelBulk case final cancel?)
                  IconButton(
                    key: const ValueKey('mail-list-stop-bulk'),
                    tooltip: strings.stopBulk,
                    visualDensity: VisualDensity.compact,
                    onPressed: cancel,
                    icon: const Icon(Icons.stop_circle_outlined, size: 20),
                  ),
              ],
            ),
          ),
        if (widget.bulkStatus case final status?)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: status,
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Long translations and errors can outgrow a compact dialog.
                // Keep every control reachable without consuming the row area.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.min(
                      constraints.maxHeight * 0.65,
                      math.max(
                        constraints.maxHeight * 0.5,
                        constraints.maxHeight - _itemExtent,
                      ),
                    ),
                  ),
                  child: Scrollbar(
                    controller: _headerScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      key: const ValueKey('mail-list-header-scroll'),
                      controller: _headerScroll,
                      primary: false,
                      child: header,
                    ),
                  ),
                ),
                Expanded(
                  child: Focus(
                    key: const ValueKey('mail-list-focus'),
                    focusNode: _listFocus,
                    onKeyEvent: _onKey,
                    onFocusChange: (focused) {
                      if (!mounted) return;
                      setState(() {
                        if (focused) _reconcileCursor(_visible);
                      });
                      if (focused) _revealCursor();
                    },
                    child: visible.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                widget.busy && widget.items.isEmpty
                                    ? strings.loading
                                    : _filtered
                                    ? strings.noMatches
                                    : strings.noMessages,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            key: const ValueKey('mail-list-rows'),
                            controller: _scroll,
                            itemExtent: _itemExtent,
                            itemCount: visible.length,
                            itemBuilder: (context, index) => _row(
                              visible[index],
                              conversationSize:
                                  conversationCounts[visible[index].id] ?? 1,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.limitNotice case final notice?)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(notice, style: Theme.of(context).textTheme.bodySmall),
          ),
        if (widget.hasMore)
          TextButton.icon(
            key: widget.loadMoreKey ?? const ValueKey('mail-list-load-more'),
            onPressed: widget.busy ? null : widget.onLoadMore,
            icon: const Icon(Icons.expand_more),
            label: Text(widget.busy ? strings.loading : strings.loadMore),
          ),
      ],
    );
  }

  Widget _row(MailMessageListItem item, {int conversationSize = 1}) {
    final generation = _interactionGeneration;
    final colors = Theme.of(context).colorScheme;
    final active = _listFocus.hasFocus && item.id == _activeId;
    final selected = item.id == widget.selectedId;
    return Semantics(
      key: ValueKey(item.id),
      button: true,
      selected: selected,
      focused: active,
      enabled: !widget.busy,
      child: Material(
        color: selected
            ? colors.secondaryContainer
            : active
            ? colors.surfaceContainerHighest
            : Colors.transparent,
        child: InkWell(
          canRequestFocus: false,
          onTap: widget.busy
              ? null
              : () => _open(item.id, interactionGeneration: generation),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: active ? colors.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  if (widget.onBulkAction != null)
                    ExcludeFocus(
                      child: Checkbox(
                        key: ValueKey('mail-list-check-${item.id}'),
                        value: _checkedIds.contains(item.id),
                        semanticLabel:
                            '${widget.strings.selectMessage}: ${item.subject}, '
                            '${item.sender}',
                        onChanged: _canBulk
                            ? (value) =>
                                  _checkRow(item.id, value ?? false, generation)
                            : null,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          item.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: item.isRead == false
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        Text(
                          item.sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.3),
                        ),
                        if (item.dateLabel case final date?)
                          Text(
                            date,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, height: 1.3),
                          ),
                      ],
                    ),
                  ),
                  if (conversationSize > 1)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: Tooltip(
                        message: widget.strings.conversationCount(conversationSize),
                        child: Icon(
                          Icons.forum_outlined,
                          size: 18,
                          semanticLabel:
                              widget.strings.conversationCount(conversationSize),
                        ),
                      ),
                    ),
                  if (item.isRead == false)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: Icon(
                        Icons.circle,
                        size: 8,
                        semanticLabel: widget.strings.unread,
                      ),
                    ),
                  if (item.isFlagged == true)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: Icon(
                        Icons.flag,
                        size: 18,
                        semanticLabel: widget.strings.flagged,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _BulkChoice {
  const _BulkChoice(this.action, this.ids, this.generation);

  final MailBulkFlagAction action;
  final List<String> ids;
  final int generation;
}
