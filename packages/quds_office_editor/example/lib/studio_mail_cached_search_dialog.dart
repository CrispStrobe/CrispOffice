import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_cached_search.dart';
import 'studio_mail_cached_search_strings.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_draft_store_native.dart';
import 'studio_mail_local_accounts.dart';
import 'studio_mail_reader_labels.dart';
import 'studio_strings.dart';

/// Explicit, read-only discovery across saved account/folder headers.
/// No provider or credential store is constructed by this route.
class StudioMailCachedSearchDialog extends StatefulWidget {
  const StudioMailCachedSearchDialog({
    super.key,
    required this.strings,
    required this.store,
    required this.isCurrent,
    this.provider,
    this.draftStoreFactory,
  });

  final StudioStrings strings;
  final StudioMailLocalAccountStore store;
  final bool Function() isCurrent;
  final MailProviderKind? provider;
  final StudioMailDraftStoreFactory? draftStoreFactory;

  @override
  State<StudioMailCachedSearchDialog> createState() =>
      _StudioMailCachedSearchDialogState();
}

class _StudioMailCachedSearchDialogState
    extends State<StudioMailCachedSearchDialog> {
  final _query = TextEditingController();
  final _retired = <StudioMailCachedSearchSession>{};
  late final Future<void> _opening;
  Future<void>? _pending;
  Future<void>? _retiring;
  StudioMailCachedSearchSession? _session;
  List<MailLocalAccountRecord> _accounts = const [];
  List<StudioMailCachedSearchHit> _hits = const [];
  List<StudioMailCachedSearchCoverage> _coverage = const [];
  String? _scope;
  String? _error;
  MailReaderController? _reader;
  StudioMailCachedSearchHit? _selected;
  bool _missingBody = false;
  bool _loading = true;
  bool _busy = false;
  bool _started = false;
  bool _closeRequested = false;
  bool _closing = false;
  bool _allowPop = false;
  bool _expired = false;
  int _epoch = 0;
  int _readEpoch = 0;

  bool get _current =>
      mounted && !_closeRequested && !_expired && widget.isCurrent();
  bool get _hasMore => _session?.hasMore ?? false;
  bool get _limited => _hits.length >= 1000 && _hasMore;
  bool _active(int epoch) => _current && epoch == _epoch;

  @override
  void initState() {
    super.initState();
    _opening = _loadAccounts();
  }

  @override
  void didUpdateWidget(covariant StudioMailCachedSearchDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store) ||
        oldWidget.provider != widget.provider ||
        oldWidget.draftStoreFactory != widget.draftStoreFactory ||
        !widget.isCurrent()) {
      _expired = true;
      _scope = null;
      _invalidate();
      _accounts = const [];
      _error = widget.strings.mailCachedSearchExpired;
    }
  }

  @override
  void dispose() {
    _closeRequested = true;
    _epoch++;
    _readEpoch++;
    if (_session case final session?) _retired.add(session);
    _session = null;
    _reader?.dispose();
    _reader = null;
    _query.dispose();
    unawaited(_drainAfterDisposal());
    super.dispose();
  }

  Future<void> _drainAfterDisposal() async {
    await _opening;
    await _pending;
    try {
      await _releaseRetired();
    } on Object {
      // A forced route disposal has no surface on which to report a failure.
    }
  }

  Future<void> _loadAccounts() async {
    final directory = widget.store;
    final provider = widget.provider;
    try {
      if (!_current) return;
      final rows = await directory.load();
      if (!_current ||
          !identical(widget.store, directory) ||
          widget.provider != provider) {
        return;
      }
      final ids = <String>{};
      if (rows.length > 100) {
        throw const StudioMailDraftStoreException(
          MailProblemCode.quotaExceeded,
        );
      }
      for (final row in rows) {
        studioMailLocalAccountIdentity(row);
        if (!ids.add(row.id)) {
          throw const StudioMailDraftStoreException(MailProblemCode.conflict);
        }
      }
      setState(
        () => _accounts = List.unmodifiable([
          for (final row in rows)
            if (widget.provider == null || widget.provider == row.provider) row,
        ]),
      );
    } on Object {
      if (_current) {
        setState(() => _error = widget.strings.mailCachedSearchAccountsFailed);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _retireReader(MailReaderController? reader) {
    if (reader == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => reader.dispose());
  }

  /// Invalidation is synchronous: pending reads cannot repopulate an edited
  /// query or scope. Releasing owners can then finish asynchronously.
  void _invalidate() {
    _epoch++;
    _readEpoch++;
    final previous = _reader;
    if (_session case final session?) _retired.add(session);
    setState(() {
      _session = null;
      _reader = null;
      _selected = null;
      _missingBody = false;
      _hits = const [];
      _coverage = const [];
      _started = false;
      _error = null;
    });
    _retireReader(previous);
    unawaited(
      _releaseRetired().then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (_current) {
            setState(() => _error = widget.strings.mailCachedSearchCloseFailed);
          }
        },
      ),
    );
  }

  Future<void> _releaseRetired() {
    if (_retiring case final pending?) return pending;
    final closing = Future<void>.sync(() async {
      while (_retired.isNotEmpty) {
        final session = _retired.first;
        await session.close();
        _retired.remove(session);
      }
    });
    late final Future<void> tracked;
    tracked = closing.whenComplete(() {
      if (identical(_retiring, tracked)) _retiring = null;
    });
    _retiring = tracked;
    return tracked;
  }

  Future<void> _operate(
    int epoch,
    Future<void> Function() action, {
    bool Function()? isOperationCurrent,
  }) async {
    if (!_active(epoch) || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final operation = Future<void>.sync(action);
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      await operation;
    } on Object {
      if (_active(epoch) && (isOperationCurrent?.call() ?? true)) {
        setState(() => _error = widget.strings.mailCachedSearchFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search() async {
    if (!_current || _busy || _loading || _accounts.isEmpty) return;
    _invalidate();
    final epoch = _epoch;
    final query = _query.text;
    try {
      MailHeaderSearchQuery.parse(query);
    } on MailHeaderSearchException {
      setState(() => _error = widget.strings.mailCachedSearchInvalid);
      return;
    }
    await _operate(epoch, () async {
      try {
        await _releaseRetired();
      } on Object {
        if (_active(epoch)) {
          setState(() => _error = widget.strings.mailCachedSearchCloseFailed);
        }
        return;
      }
      if (!_active(epoch)) return;
      final session = StudioMailCachedSearchSession(
        query: query,
        accounts: [
          for (final row in _accounts)
            if (_scope == null || row.id == _scope) row,
        ],
        directory: widget.store,
        openStore: widget.draftStoreFactory ?? openStudioMailDraftStore,
        isCurrent: () => _active(epoch),
      );
      setState(() {
        _session = session;
        _started = true;
      });
      await _readPage(epoch, session);
    });
  }

  Future<void> _readPage(
    int epoch,
    StudioMailCachedSearchSession session,
  ) async {
    final limit = (1000 - _hits.length).clamp(1, 100);
    final page = await session.nextPage(limit: limit, scanLimit: 500);
    if (!_active(epoch) || !identical(_session, session)) return;
    if (page.length > limit) {
      throw const StudioMailDraftStoreException(MailProblemCode.conflict);
    }
    final seen = _hits.map((hit) => hit.key).toSet();
    setState(() {
      _hits = [
        ..._hits,
        for (final hit in page)
          if (seen.add(hit.key)) hit,
      ];
      _coverage = List.unmodifiable(session.coverage);
    });
  }

  Future<void> _more() async {
    final session = _session;
    if (!_current || _busy || session == null || !_hasMore || _limited) return;
    final epoch = _epoch;
    await _operate(epoch, () => _readPage(epoch, session));
  }

  Future<void> _openMessage(StudioMailCachedSearchHit hit) async {
    final session = _session;
    if (!_current || _busy || session == null || !_hits.contains(hit)) return;
    final epoch = _epoch;
    final readEpoch = ++_readEpoch;
    final previous = _reader;
    setState(() {
      _selected = hit;
      _reader = null;
      _missingBody = false;
    });
    _retireReader(previous);
    await _operate(
      epoch,
      () async {
        final message = await session.loadMessage(hit);
        if (!_active(epoch) ||
            !identical(_session, session) ||
            readEpoch != _readEpoch ||
            _selected?.key != hit.key) {
          return;
        }
        if (message == null) {
          setState(() => _missingBody = true);
          return;
        }
        if (message.localId != hit.result.header.id ||
            message.remoteIdentity != hit.result.header.remote) {
          throw const StudioMailDraftStoreException(MailProblemCode.conflict);
        }
        final reader = MailReaderController(
          result: MailParseResult(
            status: MailParseStatus.complete,
            message: message,
          ),
          labels: StudioMailReaderLabels(widget.strings.language),
        );
        setState(() => _reader = reader);
      },
      isOperationCurrent: () =>
          readEpoch == _readEpoch && _selected?.key == hit.key,
    );
  }

  void _back() {
    _readEpoch++;
    final previous = _reader;
    setState(() {
      _selected = null;
      _reader = null;
      _missingBody = false;
      _error = null;
    });
    _retireReader(previous);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closeRequested = true;
    _epoch++;
    _readEpoch++;
    if (_session case final session?) _retired.add(session);
    _session = null;
    final previous = _reader;
    setState(() {
      _closing = true;
      _reader = null;
      _selected = null;
      _hits = const [];
      _coverage = const [];
      _error = null;
    });
    _retireReader(previous);
    await _opening;
    await _pending;
    try {
      await _releaseRetired();
    } on Object {
      if (mounted) {
        setState(() {
          _closing = false;
          _error = widget.strings.mailCachedSearchCloseFailed;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  String _accountLabel(MailLocalAccountRecord account) =>
      '${account.sender} · ${switch (account.provider) {
        MailProviderKind.imap => 'IMAP / SMTP',
        MailProviderKind.ews => 'Exchange',
        MailProviderKind.gmail => 'Gmail',
        MailProviderKind.graph => 'Microsoft 365',
        _ => account.provider.name,
      }} · ${account.endpoint}';

  String _folderLabel(StudioMailCachedSearchHit hit) {
    final folders = hit.result.folders;
    return [
      for (final folder in folders.take(3)) folder.displayName,
      if (folders.length > 3)
        widget.strings.mailCachedSearchOtherFolders(folders.length - 3),
    ].join(' · ');
  }

  Widget _controls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(widget.strings.mailCachedSearchAbout),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: const ValueKey('studio-mail-cached-search-scope'),
        initialValue: _scope ?? '',
        isExpanded: true,
        decoration: InputDecoration(
          labelText: widget.strings.mailCachedSearchScope,
        ),
        items: [
          DropdownMenuItem(
            value: '',
            child: Text(
              widget.strings.mailCachedSearchAll,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (final row in _accounts)
            DropdownMenuItem(
              value: row.id,
              child: Tooltip(
                message: _accountLabel(row),
                child: Text(
                  _accountLabel(row),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
        onChanged: !_current || _loading
            ? null
            : (value) {
                final next = value == null || value.isEmpty ? null : value;
                if (next == _scope) return;
                _scope = next;
                _invalidate();
              },
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('studio-mail-cached-search-query'),
        controller: _query,
        enabled: _current,
        textDirection: TextDirection.ltr,
        maxLines: 3,
        minLines: 1,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: widget.strings.mailCachedSearchQuery,
        ),
        onChanged: (_) => _invalidate(),
        onSubmitted: (_) => unawaited(_search()),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            key: const ValueKey('studio-mail-cached-search-start'),
            onPressed: !_current || _loading || _busy || _accounts.isEmpty
                ? null
                : _search,
            icon: const Icon(Icons.search),
            label: Text(widget.strings.mailCachedSearchStart),
          ),
          if (_busy && _session != null)
            TextButton(
              key: const ValueKey('studio-mail-cached-search-cancel'),
              onPressed: _current ? _invalidate : null,
              child: Text(widget.strings.mailCachedSearchStop),
            ),
        ],
      ),
      ExpansionTile(
        key: const ValueKey('studio-mail-cached-search-help'),
        tilePadding: EdgeInsets.zero,
        title: Text(widget.strings.mailCachedSearchHelp),
        children: [
          Text(widget.strings.mailCachedSearchGrammar),
          const SizedBox(height: 8),
          for (final example in const [
            '(from:alice OR from:bob) is:unread',
            'NOT(subject:alerts OR from:newsletter)',
          ])
            Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(example),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
      if (_error case final error?)
        Text(error, key: const ValueKey('studio-mail-cached-search-error')),
      if (!_loading && _accounts.isEmpty && _error == null)
        Text(widget.strings.mailCachedSearchNoAccounts),
      if (!_started && !_loading && _accounts.isNotEmpty && _error == null)
        Text(widget.strings.mailCachedSearchReady),
      if (_started) ...[
        Text(widget.strings.mailCachedSearchMatches(_hits.length)),
        for (final entry in _coverage.where((value) => value.problem != null))
          Text(
            '${entry.account.sender}: ${widget.strings.mailCachedSearchAccountFailed}',
          ),
        if (_hits.isEmpty && !_busy)
          Text(
            _hasMore
                ? widget.strings.mailCachedSearchEmptyMore
                : widget.strings.mailCachedSearchEmpty,
          ),
      ],
      const SizedBox(height: 8),
    ],
  );

  Widget _coverageView() => ExpansionTile(
    key: const ValueKey('studio-mail-cached-search-coverage'),
    tilePadding: EdgeInsets.zero,
    title: Text(widget.strings.mailCachedSearchCoverage),
    children: [for (final entry in _coverage) _accountCoverage(entry)],
  );

  Widget _accountCoverage(StudioMailCachedSearchCoverage entry) {
    final dates = [
      for (final folder in entry.browsed) folder.capturedAt,
      for (final folder in entry.synchronized) folder.updatedAt,
    ]..sort();
    final incomplete =
        entry.browsed.any((folder) => folder.hasMore) ||
        entry.synchronized.any((folder) => folder.hasMore);
    final labels = StudioMailReaderLabels(widget.strings.language);
    return Padding(
      key: ValueKey('studio-mail-cached-search-coverage-${entry.account.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _accountLabel(entry.account),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            widget.strings.mailCachedSearchProgress(
              entry.scannedCount,
              entry.totalCount,
            ),
          ),
          Text(
            widget.strings.mailCachedSearchFolders(
              entry.browsed.length,
              entry.synchronized.length,
            ),
          ),
          if (entry.problem != null)
            Text(widget.strings.mailCachedSearchAccountFailed),
          if (entry.problem == null && entry.complete)
            Text(widget.strings.mailCachedSearchLocalFinished),
          if (incomplete) Text(widget.strings.mailCachedSearchPartialFolders),
          if (dates.isEmpty)
            Text(widget.strings.mailCachedSearchUnknownCoverage)
          else
            Text(
              widget.strings.mailCachedSearchSavedBetween(
                labels.formatDate(dates.first),
                labels.formatDate(dates.last),
              ),
            ),
        ],
      ),
    );
  }

  Widget _results() => ListView.builder(
    key: const ValueKey('studio-mail-cached-search-results'),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    itemCount: _hits.length + 2,
    itemBuilder: (context, index) {
      if (index == 0) return _controls();
      if (index == _hits.length + 1) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_limited)
              Text(
                widget.strings.mailCachedSearchLimit,
                key: const ValueKey('studio-mail-cached-search-limit'),
              ),
            if (_hasMore && !_limited)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: const ValueKey('studio-mail-cached-search-more'),
                  onPressed: !_current || _busy ? null : _more,
                  icon: const Icon(Icons.search),
                  label: Text(widget.strings.mailCachedSearchMore),
                ),
              ),
            if (_coverage.isNotEmpty) _coverageView(),
          ],
        );
      }
      final hit = _hits[index - 1];
      final envelope = hit.result.header.envelope;
      final from = envelope.from
          .map(
            (address) => address.displayName?.isNotEmpty == true
                // Keep a name's natural direction while the complete address,
                // including brackets, remains a single left-to-right fragment.
                ? '\u2068${address.displayName}\u2069 '
                      '\u2066<${address.address}>\u2069'
                : '\u2066${address.address}\u2069',
          )
          .join(', ');
      return ListTile(
        key: ValueKey('studio-mail-cached-search-hit-${hit.key}'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          envelope.subject.isEmpty
              ? StudioMailReaderLabels(widget.strings.language).noSubject
              : envelope.subject,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (from.isNotEmpty)
              Text(
                from,
                key: ValueKey('studio-mail-cached-search-sender-${hit.key}'),
                textDirection: TextDirection.ltr,
                textAlign: Directionality.of(context) == TextDirection.rtl
                    ? TextAlign.right
                    : TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            Text(
              _accountLabel(hit.account),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _folderLabel(hit),
              key: ValueKey('studio-mail-cached-search-folders-${hit.key}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              hit.result.hasCachedBody
                  ? widget.strings.mailCachedSearchSavedBody
                  : widget.strings.mailCachedSearchHeaderOnly,
              key: ValueKey('studio-mail-cached-search-body-state-${hit.key}'),
            ),
          ],
        ),
        leading: Icon(
          hit.result.hasCachedBody
              ? Icons.offline_pin_outlined
              : Icons.mail_outline,
        ),
        onTap: !_current || _busy ? null : () => unawaited(_openMessage(hit)),
      );
    },
  );

  Widget _message() {
    final reader = _reader;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('studio-mail-cached-search-back'),
            onPressed: _current ? _back : null,
            icon: const Icon(Icons.arrow_back),
            label: Text(widget.strings.mailCachedSearchBack),
          ),
        ),
        Expanded(
          child: reader != null
              ? MailMessageView(controller: reader)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _missingBody
                        ? widget.strings.mailCachedSearchMissingBody
                        : _error ?? widget.strings.mailCachedSearchLoading,
                    key: const ValueKey(
                      'studio-mail-cached-search-message-state',
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 960,
        height: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.strings.mailCachedSearch,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('studio-mail-cached-search-close'),
                    tooltip: widget.strings.close,
                    onPressed: _closing ? null : _close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (_loading || _busy || _closing) const LinearProgressIndicator(),
            Expanded(
              child: _closeRequested
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error ?? widget.strings.mailCachedSearchLoading,
                      ),
                    )
                  : _expired || !widget.isCurrent()
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Text(widget.strings.mailCachedSearchExpired),
                    )
                  : _selected != null
                  ? _message()
                  : _results(),
            ),
          ],
        ),
      ),
    ),
  );
}
