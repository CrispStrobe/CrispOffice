import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_cached_search.dart';
import 'studio_mail_cached_search_refresh.dart';
import 'studio_mail_cached_search_strings.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_draft_store_native.dart';
import 'studio_mail_local_accounts.dart';
import 'studio_mail_reader_labels.dart';
import 'studio_mail_saved_searches.dart';
import 'studio_mail_saved_search_strings.dart';
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
    this.savedSearchStore,
  });

  final StudioStrings strings;
  final StudioMailLocalAccountStore store;
  final bool Function() isCurrent;
  final MailProviderKind? provider;
  final StudioMailDraftStoreFactory? draftStoreFactory;
  final StudioMailSavedSearchStore? savedSearchStore;

  @override
  State<StudioMailCachedSearchDialog> createState() =>
      _StudioMailCachedSearchDialogState();
}

class _StudioMailCachedSearchDialogState
    extends State<StudioMailCachedSearchDialog>
    with WidgetsBindingObserver {
  final _query = TextEditingController();
  final _retired = <StudioMailCachedSearchSession>{};
  late final Future<void> _opening;
  late final StudioMailSavedSearchStore? _savedStore;
  Future<void>? _saving;
  Future<void>? _accountRefresh;
  Future<void>? _pending;
  Future<void>? _retiring;
  StudioMailCachedSearchSession? _session;
  StudioMailCachedSearchSession? _refreshSession;
  Timer? _refreshTimer;
  List<MailLocalAccountRecord> _accounts = const [];
  List<StudioMailCachedSearchHit> _hits = const [];
  List<StudioMailCachedSearchCoverage> _coverage = const [];
  String? _scope;
  List<String>? _fixedAccountIds;
  List<MailSavedHeaderSearch> _savedSearches = const [];
  MailSavedHeaderSearch? _savedSearch;
  String? _savedError;
  String? _savedNotice;
  bool _savedLoading = false;
  bool _savedBusy = false;
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
  bool _autoRefresh = false;
  bool _foreground = true;
  bool _refreshing = false;
  String? _refreshNotice;
  int _refreshEpoch = 0;
  int _epoch = 0;
  int _readEpoch = 0;

  bool get _current =>
      mounted && !_closeRequested && !_expired && widget.isCurrent();
  bool get _hasMore => _session?.hasMore ?? false;
  bool get _limited => _hits.length >= 1000 && _hasMore;
  bool _active(int epoch) => _current && epoch == _epoch;

  bool get _completeSearch =>
      _started &&
      _session != null &&
      !_hasMore &&
      _coverage.isNotEmpty &&
      _coverage.length == _scopeAccounts()?.length &&
      _coverage.every((entry) => entry.complete && entry.problem == null);

  bool get _canAutoRefresh =>
      _current &&
      _completeSearch &&
      !_busy &&
      !_savedBusy &&
      !_loading &&
      !_savedLoading &&
      _error == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _savedStore =
        widget.savedSearchStore ??
        switch (widget.store) {
          StudioMailSavedSearchStore store => store,
          _ => null,
        };
    _opening = Future.wait([_loadAccounts(), _loadSavedSearches()])
        .then((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    setState(() => _foreground = foreground);
    if (!foreground) {
      // Suspension revokes this attempt, including a pending provider-free
      // database page. Resume schedules a fresh interval, never a catch-up run.
      _cancelRefresh();
    } else {
      _scheduleRefresh();
    }
  }

  @override
  void didUpdateWidget(covariant StudioMailCachedSearchDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store) ||
        oldWidget.provider != widget.provider ||
        oldWidget.savedSearchStore != widget.savedSearchStore ||
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
    WidgetsBinding.instance.removeObserver(this);
    _closeRequested = true;
    _cancelRefresh(stopAutomatic: true);
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

  void _cancelRefresh({bool stopAutomatic = false}) {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshEpoch++;
    if (_refreshSession case final staged?) _retired.add(staged);
    _refreshSession = null;
    if (stopAutomatic) _autoRefresh = false;
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (!_autoRefresh || !_foreground || !_canAutoRefresh || _refreshing) {
      return;
    }
    _refreshTimer = Timer(const Duration(seconds: 30), () {
      _refreshTimer = null;
      if (!_current) {
        if (mounted && !_closeRequested) {
          _expired = true;
          _invalidate();
          setState(() => _error = widget.strings.mailCachedSearchExpired);
        }
        return;
      }
      if (_autoRefresh && _foreground && _canAutoRefresh) {
        unawaited(_refreshResults(automatic: true));
      }
    });
  }

  void _setAutoRefresh(bool enabled) {
    if (!_current || (enabled && !_canAutoRefresh)) return;
    setState(() {
      _autoRefresh = enabled;
      if (!enabled) _cancelRefresh(stopAutomatic: true);
    });
    _scheduleRefresh();
  }

  Future<void> _drainAfterDisposal() async {
    await _opening;
    await _pending;
    await _saving;
    await _accountRefresh;
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
        setState(() {
          _accounts = const [];
          _error = widget.strings.mailCachedSearchAccountsFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSavedSearches() async {
    final store = _savedStore;
    if (store == null || !_current) return;
    setState(() => _savedLoading = true);
    try {
      final searches = await store.loadSavedSearches();
      if (!_current) return;
      final ids = <String>{};
      final names = <String>{};
      if (searches.length > 100 ||
          searches.any(
            (search) =>
                !search.isValid ||
                search.revision < 1 ||
                !ids.add(search.id) ||
                !names.add(search.nameKey),
          )) {
        throw const StudioMailDraftStoreException(MailProblemCode.conflict);
      }
      setState(() {
        _savedSearches = List.unmodifiable(searches);
        // Do not rebase an open editor silently onto a newer revision. The
        // user must select the refreshed definition before replacing it.
        if (_savedSearch case final selected?) {
          if (!searches.any(
            (search) =>
                search.id == selected.id &&
                search.revision == selected.revision,
          )) {
            _savedSearch = null;
          }
        }
        _savedError = null;
      });
    } on Object {
      if (_current) {
        setState(() => _savedError = widget.strings.mailSavedSearchLoadFailed);
      }
    } finally {
      if (mounted) setState(() => _savedLoading = false);
      _scheduleRefresh();
    }
  }

  List<MailLocalAccountRecord>? _scopeAccounts() {
    final fixed = _fixedAccountIds;
    if (fixed != null) {
      final byId = {for (final account in _accounts) account.id: account};
      if (fixed.any((id) => !byId.containsKey(id))) return null;
      return [for (final id in fixed) byId[id]!];
    }
    final accounts = [
      for (final row in _accounts)
        if (_scope == null || row.id == _scope) row,
    ];
    return accounts.isEmpty ? null : accounts;
  }

  Future<void> _chooseSavedSearch(String? id) async {
    if (!_current || _loading || _busy || _savedBusy || _savedLoading) return;
    final search = _savedSearches.where((entry) => entry.id == id).firstOrNull;
    if (search == null) {
      setState(() {
        _savedSearch = null;
        _savedNotice = null;
      });
      return;
    }
    _invalidate();
    final epoch = _epoch;
    setState(() {
      _savedSearch = search;
      _query.text = search.query;
      _fixedAccountIds = search.accountIds;
      _scope = '@saved';
      _savedNotice = null;
      _savedError = null;
      _loading = true;
    });
    // Reopen against today's verified directory, rather than persisting old
    // directory revisions or silently widening a missing account to All.
    final refresh = _loadAccounts();
    _accountRefresh = refresh;
    await refresh;
    if (identical(_accountRefresh, refresh)) _accountRefresh = null;
    if (!_active(epoch) || !identical(_savedSearch, search) || _error != null) {
      return;
    }
    if (_scopeAccounts() == null) {
      setState(() => _error = widget.strings.mailSavedSearchMissingAccounts);
      return;
    }
    await _search();
  }

  Future<void> _saveSearch({required bool replace}) async {
    final store = _savedStore;
    final selected = replace ? _savedSearch : null;
    if (store == null ||
        !_current ||
        _loading ||
        _busy ||
        _savedBusy ||
        _savedLoading ||
        replace && selected == null) {
      return;
    }
    final accounts = _scopeAccounts();
    if (accounts == null) {
      setState(
        () => _savedError = widget.strings.mailSavedSearchMissingAccounts,
      );
      return;
    }
    final query = _query.text;
    try {
      MailHeaderSearchQuery.parse(query);
    } on MailHeaderSearchException {
      setState(() => _error = widget.strings.mailCachedSearchInvalid);
      return;
    }
    final epoch = _epoch;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _SavedSearchNameDialog(
        strings: widget.strings,
        initialName: selected?.name ?? '',
        replace: replace,
      ),
    );
    if (name == null || !_active(epoch)) return;
    final random = Random.secure();
    final search = MailSavedHeaderSearch(
      id:
          selected?.id ??
          'search-${base64Url.encode(List<int>.generate(16, (_) => random.nextInt(256))).replaceAll('=', '')}',
      name: name,
      query: query,
      accountIds: [for (final account in accounts) account.id],
      revision: selected?.revision ?? 0,
    );
    await _savedOperation(() async {
      final saved = await store.saveSavedSearch(
        search,
        expectedRevision: selected?.revision,
      );
      if (!_current || !_active(epoch)) return;
      if (!saved.isValid ||
          saved.id != search.id ||
          saved.revision <= search.revision ||
          saved.name != search.name ||
          saved.query != search.query ||
          saved.accountIds.length != search.accountIds.length ||
          !saved.accountIds.every(search.accountIds.contains)) {
        throw const StudioMailDraftStoreException(MailProblemCode.conflict);
      }
      setState(() {
        _savedSearches = [
          ..._savedSearches.where((entry) => entry.id != saved.id),
          saved,
        ]..sort((a, b) => a.nameKey.compareTo(b.nameKey));
        _savedSearch = saved;
        _savedNotice = widget.strings.mailSavedSearchSaved;
      });
    });
  }

  Future<void> _deleteSearch() async {
    final store = _savedStore;
    final selected = _savedSearch;
    if (store == null || selected == null || !_current || _savedBusy || _busy) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.mailSavedSearchDelete),
        content: Text(widget.strings.mailSavedSearchDeleteAbout(selected.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.strings.mailSavedSearchDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !_current || !identical(selected, _savedSearch)) {
      return;
    }
    await _savedOperation(() async {
      await store.deleteSavedSearch(
        selected.id,
        expectedRevision: selected.revision,
      );
      if (!_current) return;
      setState(() {
        _savedSearches = [
          for (final entry in _savedSearches)
            if (entry.id != selected.id) entry,
        ];
        _savedSearch = null;
        _savedNotice = widget.strings.mailSavedSearchDeleted;
      });
    });
  }

  Future<void> _savedOperation(Future<void> Function() action) async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    setState(() {
      _savedBusy = true;
      _savedError = null;
      _savedNotice = null;
    });
    final operation = Future<void>.sync(action);
    _saving = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      await operation;
    } on StudioMailDraftStoreException catch (error) {
      if (_current) {
        setState(
          () => _savedError = switch (error.code) {
            MailProblemCode.conflict => widget.strings.mailSavedSearchConflict,
            MailProblemCode.quotaExceeded =>
              widget.strings.mailSavedSearchLimit,
            _ => widget.strings.mailSavedSearchWriteFailed,
          },
        );
      }
    } on Object {
      if (_current) {
        setState(() => _savedError = widget.strings.mailSavedSearchWriteFailed);
      }
    } finally {
      if (mounted) setState(() => _savedBusy = false);
      _scheduleRefresh();
    }
  }

  void _retireReader(MailReaderController? reader) {
    if (reader == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => reader.dispose());
  }

  /// Invalidation is synchronous: pending reads cannot repopulate an edited
  /// query or scope. Releasing owners can then finish asynchronously.
  void _invalidate() {
    _cancelRefresh(stopAutomatic: true);
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
      _refreshNotice = null;
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
    _refreshTimer?.cancel();
    _refreshTimer = null;
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
      _scheduleRefresh();
    }
  }

  /// Stage a new bounded scan and replace the displayed result set once. The
  /// opened message remains a local reading snapshot; refreshing headers never
  /// downloads or reloads its body. Existing complete sessions own no store
  /// between operations and can be retained if the replacement is interrupted.
  Future<void> _refreshResults({bool automatic = false}) async {
    if (!_current ||
        !_foreground ||
        !_started ||
        _busy ||
        _savedBusy ||
        _loading ||
        (automatic && (!_autoRefresh || !_completeSearch))) {
      return;
    }
    final accounts = _scopeAccounts();
    if (accounts == null) {
      _invalidate();
      setState(() => _error = widget.strings.mailSavedSearchMissingAccounts);
      return;
    }
    final epoch = _epoch;
    final refreshEpoch = ++_refreshEpoch;
    final query = _query.text;
    bool current() =>
        _active(epoch) && _foreground && refreshEpoch == _refreshEpoch;
    StudioMailCachedSearchSession? staged;
    setState(() {
      _refreshing = true;
      _refreshNotice = null;
    });
    try {
      await _operate(epoch, () async {
        try {
          // An unfinished manual scan can still own an exclusive database
          // lease. Drain it before opening the replacement account profile.
          if (_session case final previous? when previous.hasMore) {
            _retired.add(previous);
            _session = null;
          }
          await _releaseRetired();
          if (!current()) return;
          final session = StudioMailCachedSearchSession(
            query: query,
            accounts: accounts,
            directory: widget.store,
            openStore: widget.draftStoreFactory ?? openStudioMailDraftStore,
            isCurrent: () => _active(epoch),
          );
          staged = session;
          _refreshSession = session;
          final batch = await refreshStudioMailCachedSearch(
            session,
            isCurrent: current,
          );
          if (!current()) return;
          final selected = _selected;
          final replacement = selected == null
              ? null
              : batch.hits
                    .where(
                      (hit) =>
                          hit.key == selected.key &&
                          hit.result.header.remote ==
                              selected.result.header.remote &&
                          hit.account.hasSameIdentity(selected.account) &&
                          hit.account.revision == selected.account.revision,
                    )
                    .firstOrNull;
          final retiredReader = replacement == null ? _reader : null;
          if (_session case final previous?) _retired.add(previous);
          _refreshSession = null;
          setState(() {
            _session = session;
            _hits = batch.hits;
            _coverage = batch.coverage;
            _selected = replacement;
            if (replacement == null) {
              _readEpoch++;
              _reader = null;
              _missingBody = false;
            }
            if (!batch.complete) _autoRefresh = false;
            _refreshNotice =
                batch.coverage.any((entry) => entry.problem != null)
                ? widget.strings.mailCachedSearchRefreshPartial
                : !batch.complete
                ? widget.strings.mailCachedSearchRefreshLimited
                : selected != null && replacement == null
                ? widget.strings.mailCachedSearchSelectionRemoved
                : widget.strings.mailCachedSearchRefreshed;
          });
          _retireReader(retiredReader);
        } on Object {
          if (current()) {
            setState(() => _autoRefresh = false);
          }
          rethrow;
        } finally {
          final candidate = staged;
          if (candidate != null && !identical(_session, candidate)) {
            _retired.add(candidate);
          }
          if (identical(_refreshSession, candidate)) _refreshSession = null;
          await _releaseRetired();
        }
      }, isOperationCurrent: current);
    } finally {
      if (mounted) setState(() => _refreshing = false);
      _scheduleRefresh();
    }
  }

  Future<void> _search() async {
    if (!_current || _busy || _savedBusy || _loading || _accounts.isEmpty) {
      return;
    }
    final accounts = _scopeAccounts();
    _invalidate();
    if (accounts == null) {
      setState(() => _error = widget.strings.mailSavedSearchMissingAccounts);
      return;
    }
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
        accounts: accounts,
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
    _cancelRefresh(stopAutomatic: true);
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
    await _saving;
    await _accountRefresh;
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

  Widget _savedControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: const ValueKey('studio-mail-saved-search-picker'),
              initialValue: _savedSearch?.id ?? '',
              isExpanded: true,
              decoration: InputDecoration(
                labelText: widget.strings.mailSavedSearches,
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(
                    widget.strings.mailSavedSearchChoose,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final search in _savedSearches)
                  DropdownMenuItem(
                    value: search.id,
                    child: Text(search.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged:
                  !_current || _loading || _busy || _savedBusy || _savedLoading
                  ? null
                  : (id) => unawaited(_chooseSavedSearch(id)),
            ),
          ),
          IconButton(
            key: const ValueKey('studio-mail-saved-search-reload'),
            tooltip: widget.strings.mailSavedSearchReload,
            onPressed: !_current || _savedBusy || _savedLoading
                ? null
                : _loadSavedSearches,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(widget.strings.mailSavedSearchAbout),
      if (_savedError case final error?)
        Text(error, key: const ValueKey('studio-mail-saved-search-error')),
      if (_savedNotice case final notice?)
        Semantics(
          liveRegion: true,
          child: Text(
            notice,
            key: const ValueKey('studio-mail-saved-search-notice'),
          ),
        ),
      const SizedBox(height: 12),
    ],
  );

  Widget _controls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(widget.strings.mailCachedSearchAbout),
      const SizedBox(height: 16),
      if (_savedStore != null) _savedControls(),
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
          if (_fixedAccountIds case final ids?)
            DropdownMenuItem(
              value: '@saved',
              child: Text(
                widget.strings.mailSavedSearchAccountCount(ids.length),
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
        onChanged: !_current || _loading || _savedBusy
            ? null
            : (value) {
                final next = value == null || value.isEmpty ? null : value;
                if (next == _scope) return;
                _scope = next;
                _fixedAccountIds = null;
                _savedNotice = null;
                _invalidate();
              },
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('studio-mail-cached-search-query'),
        controller: _query,
        enabled: _current && !_savedBusy,
        textDirection: TextDirection.ltr,
        maxLines: 3,
        minLines: 1,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: widget.strings.mailCachedSearchQuery,
        ),
        onChanged: (_) {
          _savedNotice = null;
          _invalidate();
        },
        onSubmitted: (_) => unawaited(_search()),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            key: const ValueKey('studio-mail-cached-search-start'),
            onPressed:
                !_current ||
                    _loading ||
                    _busy ||
                    _savedBusy ||
                    _accounts.isEmpty
                ? null
                : _search,
            icon: const Icon(Icons.search),
            label: Text(widget.strings.mailCachedSearchStart),
          ),
          if (_savedStore != null) ...[
            OutlinedButton.icon(
              key: const ValueKey('studio-mail-saved-search-save'),
              onPressed:
                  !_current ||
                      _loading ||
                      _busy ||
                      _savedBusy ||
                      _savedLoading ||
                      _accounts.isEmpty
                  ? null
                  : () => _saveSearch(replace: false),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(widget.strings.mailSavedSearchSaveAs),
            ),
            if (_savedSearch != null) ...[
              TextButton(
                key: const ValueKey('studio-mail-saved-search-update'),
                onPressed:
                    !_current ||
                        _loading ||
                        _busy ||
                        _savedBusy ||
                        _savedLoading
                    ? null
                    : () => _saveSearch(replace: true),
                child: Text(widget.strings.mailSavedSearchUpdate),
              ),
              TextButton(
                key: const ValueKey('studio-mail-saved-search-delete'),
                onPressed: !_current || _busy || _savedBusy || _savedLoading
                    ? null
                    : _deleteSearch,
                child: Text(widget.strings.mailSavedSearchDelete),
              ),
            ],
          ],
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

  Widget _refreshControls() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('studio-mail-cached-search-refresh'),
            onPressed:
                !_current || !_foreground || _busy || _savedBusy || _loading
                ? null
                : () => _refreshResults(),
            icon: const Icon(Icons.refresh),
            label: Text(widget.strings.mailCachedSearchRefresh),
          ),
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('studio-mail-cached-search-auto-refresh'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _autoRefresh,
          title: Text(widget.strings.mailCachedSearchAutoRefresh),
          subtitle: Text(
            _autoRefresh && !_foreground
                ? widget.strings.mailCachedSearchRefreshSuspended
                : !_completeSearch
                ? widget.strings.mailCachedSearchRefreshIncomplete
                : widget.strings.mailCachedSearchRefreshAbout,
          ),
          onChanged: _current && (_autoRefresh || _canAutoRefresh)
              ? _setAutoRefresh
              : null,
        ),
        if (_refreshNotice case final notice?)
          Semantics(
            liveRegion: true,
            child: Text(
              notice,
              key: const ValueKey('studio-mail-cached-search-refresh-notice'),
            ),
          ),
        if (_selected != null && _error != null) Text(_error!),
      ],
    ),
  );

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
            if (_loading || _busy || _closing || _savedLoading || _savedBusy)
              const LinearProgressIndicator(),
            if (_started && !_closeRequested && !_expired && widget.isCurrent())
              _refreshControls(),
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

class _SavedSearchNameDialog extends StatefulWidget {
  const _SavedSearchNameDialog({
    required this.strings,
    required this.initialName,
    required this.replace,
  });
  final StudioStrings strings;
  final String initialName;
  final bool replace;

  @override
  State<_SavedSearchNameDialog> createState() => _SavedSearchNameDialogState();
}

class _SavedSearchNameDialogState extends State<_SavedSearchNameDialog> {
  late final _name = TextEditingController(text: widget.initialName);

  bool get _valid => MailSavedHeaderSearch(
    id: 'name-check',
    name: _name.text.trim(),
    query: '',
    accountIds: const ['name-check'],
  ).isValid;

  void _submit() {
    if (_valid) Navigator.of(context).pop(_name.text.trim());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: widget.strings.language == StudioLanguage.ar
        ? TextDirection.rtl
        : TextDirection.ltr,
    child: AlertDialog(
      title: Text(
        widget.replace
            ? widget.strings.mailSavedSearchUpdate
            : widget.strings.mailSavedSearchSaveAs,
      ),
      content: SingleChildScrollView(
        child: TextField(
          key: const ValueKey('studio-mail-saved-search-name'),
          controller: _name,
          autofocus: true,
          maxLength: MailSavedHeaderSearch.maxNameCodeUnits,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: widget.strings.mailSavedSearchName,
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.strings.cancel),
        ),
        FilledButton(
          key: const ValueKey('studio-mail-saved-search-confirm'),
          onPressed: _valid ? _submit : null,
          child: Text(widget.strings.mailSavedSearchSave),
        ),
      ],
    ),
  );
}
