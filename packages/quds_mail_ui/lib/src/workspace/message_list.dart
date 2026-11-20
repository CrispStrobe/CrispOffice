import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.dateLabel,
    this.isRead,
    this.isFlagged,
  });

  final String id;
  final String subject;
  final String sender;
  final String? dateLabel;
  final bool? isRead;
  final bool? isFlagged;
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
  });

  final String searchLoaded;
  final String unread;
  final String flagged;
  final String noMessages;
  final String noMatches;
  final String loadMore;
  final String loading;
  final String loadedScope;
  final String Function(int shown, int loaded) count;
}

/// Shared, virtualized foreground message navigation for native/cloud hosts.
///
/// Search and the conjunctive unread/flagged filters only inspect [items]. They
/// never trigger a provider request. The host owns pagination, selection,
/// message reads, mutations and durable storage; this view cannot mark a message
/// read. Arrow/Home/End keys move a separate keyboard cursor, while Enter or an
/// explicit row activation invokes [onOpen]. Search editing owns its own keys.
///
/// Change [scopeId] (or the widget key) for a different account or mailbox.
/// That resets query, filters, keyboard focus and scroll position. Within one
/// scope the keyboard cursor follows the stable row ID through reordering.
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
  }) : items = List.unmodifiable(items) {
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

  @override
  State<MailMessageList> createState() => _MailMessageListState();
}

class _MailMessageListState extends State<MailMessageList> {
  final _query = TextEditingController();
  final _listFocus = FocusNode(debugLabel: 'Mail message list');
  final _scroll = ScrollController();
  bool _unread = false;
  bool _flagged = false;
  String? _activeId;
  double _itemExtent = 84;

  List<MailMessageListItem> get _visible {
    final query = _query.text.trim().toLowerCase();
    return [
      for (final item in widget.items)
        if ((!_unread || item.isRead == false) &&
            (!_flagged || item.isFlagged == true) &&
            (query.isEmpty ||
                item.subject.toLowerCase().contains(query) ||
                item.sender.toLowerCase().contains(query)))
          item,
    ];
  }

  bool get _filtered => _unread || _flagged || _query.text.trim().isNotEmpty;

  @override
  void didUpdateWidget(MailMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeId != widget.scopeId) {
      _query.clear();
      _unread = false;
      _flagged = false;
      _activeId = null;
      _listFocus.unfocus();
      _resetScroll();
    } else {
      _reconcileCursor(_visible);
      if (_listFocus.hasFocus) _revealCursor();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _listFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _reconcileCursor(List<MailMessageListItem> visible) {
    if (visible.any((item) => item.id == _activeId)) return;
    _activeId = visible.any((item) => item.id == widget.selectedId)
        ? widget.selectedId
        : visible.firstOrNull?.id;
  }

  void _resetScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _filterChanged(VoidCallback update) {
    setState(() {
      update();
      _reconcileCursor(_visible);
    });
    _resetScroll();
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

  void _open(String id) {
    if (widget.busy || !widget.items.any((item) => item.id == id)) return;
    setState(() => _activeId = id);
    _listFocus.requestFocus();
    widget.onOpen(id);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
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
    final strings = widget.strings;
    final scaler = MediaQuery.textScalerOf(context);
    _itemExtent = math.max(
      84.0,
      scaler.scale(14) * 1.3 +
          scaler.scale(12) * 1.3 +
          scaler.scale(11) * 1.3 +
          24,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: TextField(
            key: const ValueKey('mail-list-search'),
            controller: _query,
            onChanged: (_) => _filterChanged(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: strings.searchLoaded,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                key: const ValueKey('mail-list-unread'),
                label: Text(strings.unread),
                selected: _unread,
                onSelected: (value) => _filterChanged(() => _unread = value),
              ),
              FilterChip(
                key: const ValueKey('mail-list-flagged'),
                label: Text(strings.flagged),
                selected: _flagged,
                onSelected: (value) => _filterChanged(() => _flagged = value),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Text(
            '${strings.count(visible.length, widget.items.length)}\n'
            '${strings.loadedScope}',
            key: const ValueKey('mail-list-scope'),
            style: Theme.of(context).textTheme.bodySmall,
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
                    itemBuilder: (context, index) => _row(visible[index]),
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

  Widget _row(MailMessageListItem item) {
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
          onTap: widget.busy ? null : () => _open(item.id),
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
