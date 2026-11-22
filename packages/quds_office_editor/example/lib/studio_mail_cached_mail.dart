import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_cached_strings.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_flag_journal.dart';
import 'studio_mail_journal_dialog.dart';
import 'studio_mail_journal_strings.dart';
import 'studio_mail_draft_store_native.dart';
import 'studio_mail_mailbox_store.dart';
import 'studio_mail_mailbox_session.dart';
import 'studio_mail_retained_folders.dart';
import 'studio_mail_workspace_strings.dart';
import 'studio_mail_sync_dialog.dart';
import 'studio_mail_sync_strings.dart';
import 'studio_strings.dart';
import 'studio_mail_reader_labels.dart';

/// A local mailbox reader with explicit confirmed cleanup of expendable cache.
/// Opening it never constructs a provider, reads credentials, loads a draft,
/// or issues a server operation. The caller awaits its result before acquiring
/// another owner of the same profile.
class StudioMailCachedMailDialog extends StatefulWidget {
  const StudioMailCachedMailDialog({
    super.key,
    required this.strings,
    required this.identity,
    required this.isCurrent,
    this.draftStoreFactory,
  });

  final StudioStrings strings;
  final StudioMailDraftAccount identity;
  final bool Function() isCurrent;
  final StudioMailDraftStoreFactory? draftStoreFactory;

  @override
  State<StudioMailCachedMailDialog> createState() =>
      _StudioMailCachedMailDialogState();
}

class _StudioMailCachedMailDialogState
    extends State<StudioMailCachedMailDialog> {
  StudioMailDraftStore? _owner;
  StudioMailMailboxStore? _store;
  StudioMailMailboxSession? _mailboxSession;
  StreamSubscription<StudioMailMailboxSnapshot>? _viewSubscription;
  StreamSubscription<MailResult<List<MailCachedMailboxSummary>>>?
  _folderSubscription;
  StreamSubscription<MailResult<List<MailMailboxSyncSummary>>>?
  _syncFolderSubscription;
  late final Future<void> _opening;
  Future<void>? _reading;
  Future<void>? _storeClosing;
  List<MailCachedMailboxSummary> _browsingFolders = const [];
  List<MailMailboxSyncSummary> _synchronizedFolders = const [];
  List<StudioMailRetainedFolder> _folders = const [];
  StudioMailMailboxSnapshot? _view;
  MailMailboxId? _selectedMailbox;
  StudioMailMailboxSource _source = StudioMailMailboxSource.browse;
  MailHeaderRecord? _selected;
  MailReaderController? _reader;
  final GlobalKey _listKey = GlobalKey();
  bool _loaded = false;
  bool _busy = true;
  bool _showMessage = false;
  bool _missingBody = false;
  bool _confirmingCleanup = false;
  bool _historyOpen = false;
  bool _closeRequested = false;
  bool _closingNavigation = false;
  bool _allowPop = false;
  int _cleanupEpoch = 0;
  String? _error;
  bool _viewReadFailed = false;
  bool _catalogReadFailed = false;
  bool _browseCatalogReadFailed = false;
  bool _syncCatalogReadFailed = false;
  int _catalogEpoch = 0;
  int _bodyEpoch = 0;
  MailCacheCleanupReport? _cleanupReport;

  static const _pageSize = 100;
  bool get _hasView => _view?.view != null || _view?.synchronizedView != null;
  List<MailHeaderRecord> get _headers => _view?.headers ?? const [];
  StudioMailRetainedFolder? get _folder => _folders
      .where((folder) => folder.mailbox.id == _selectedMailbox)
      .firstOrNull;

  String? get _displayError {
    final streamError =
        _viewReadFailed ||
            _catalogReadFailed ||
            _browseCatalogReadFailed ||
            _syncCatalogReadFailed
        ? widget.strings.mailCacheReadFailed
        : null;
    final operationError = _error;
    if (operationError == null) return streamError;
    if (streamError == null || operationError == streamError) {
      return operationError;
    }
    return '$operationError\n$streamError';
  }

  bool get _current =>
      mounted &&
      !_closeRequested &&
      widget.isCurrent() &&
      _store?.account == widget.identity.account &&
      _owner != null;

  @override
  void initState() {
    super.initState();
    _opening = _openStore();
  }

  @override
  void dispose() {
    _closeRequested = true;
    _reader?.dispose();
    _reader = null;
    unawaited(_closeAfterDisposal());
    super.dispose();
  }

  Future<void> _closeAfterDisposal() async {
    await _opening;
    await _reading;
    try {
      await _releaseStore();
    } on Object {
      // A disposed route has no surface for a content-redacted close error.
    }
  }

  static Never _invalid() =>
      throw const StudioMailMailboxStoreException(MailProblemCode.conflict);

  void _replaceFolders({
    List<MailCachedMailboxSummary>? browsing,
    List<MailMailboxSyncSummary>? synchronized,
  }) {
    final browse = browsing ?? _browsingFolders;
    final sync = synchronized ?? _synchronizedFolders;
    final folders = studioMailRetainedFolders(
      account: _store!.account,
      browsing: browse,
      synchronized: sync,
    );
    final selected = folders
        .where((folder) => folder.mailbox.id == _selectedMailbox)
        .firstOrNull;
    final sourceMissing =
        _selectedMailbox != null &&
        (selected == null ||
            (_source == StudioMailMailboxSource.browse
                ? selected.browse == null
                : selected.synchronized == null));
    final previous = sourceMissing ? _reader : null;
    setState(() {
      _browsingFolders = List.unmodifiable(browse);
      _synchronizedFolders = List.unmodifiable(sync);
      _folders = folders;
      _catalogReadFailed = false;
      if (sourceMissing) {
        _bodyEpoch++;
        _view = null;
        _selected = null;
        _reader = null;
        _missingBody = false;
        _showMessage = false;
        if (selected == null) _selectedMailbox = null;
      }
    });
    if (sourceMissing) {
      unawaited(
        _mailboxSession?.clear().catchError((Object _) {
          if (_current) setState(() => _viewReadFailed = true);
        }),
      );
    }
    _retire(previous);
    _ensureSelection();
  }

  void _ensureSelection() {
    if (_current && !_busy && _selectedMailbox == null && _folders.isNotEmpty) {
      unawaited(_operate(() => _readFolder(_folders.first)));
    }
  }

  Future<void> _readCatalogs(StudioMailMailboxStore store) async {
    try {
      final browsing = await store.listViews();
      if (!_current || !identical(store, _store)) return;
      _replaceFolders(browsing: browsing);
      setState(() => _browseCatalogReadFailed = false);
    } on Object {
      if (_current) setState(() => _browseCatalogReadFailed = true);
    }
    if (!_current) return;
    if (store is StudioMailSyncStore) {
      try {
        final result = await (store as StudioMailSyncStore).listSyncMailboxes();
        if (!_current || !identical(store, _store)) return;
        switch (result) {
          case MailSuccess<List<MailMailboxSyncSummary>>(:final value):
            _replaceFolders(synchronized: value);
            setState(() => _syncCatalogReadFailed = false);
          case MailFailure<List<MailMailboxSyncSummary>>():
            _invalid();
        }
      } on Object {
        if (_current) setState(() => _syncCatalogReadFailed = true);
      }
    }
    if (_current) setState(() => _loaded = true);
  }

  Future<void> _stopCatalogs() async {
    _catalogEpoch++;
    final browsing = _folderSubscription;
    final synchronized = _syncFolderSubscription;
    await Future.wait<void>([
      if (browsing != null)
        Future<void>.sync(() async {
          await browsing.cancel();
          if (identical(_folderSubscription, browsing)) {
            _folderSubscription = null;
          }
        }),
      if (synchronized != null)
        Future<void>.sync(() async {
          await synchronized.cancel();
          if (identical(_syncFolderSubscription, synchronized)) {
            _syncFolderSubscription = null;
          }
        }),
    ]);
  }

  void _watchCatalogs(StudioMailMailboxStore store) {
    if (_folderSubscription != null || _syncFolderSubscription != null) {
      // A failed cancellation still owns its subscription. Do not replace
      // that handle with another observer or make a later Close skip it.
      if (_current) setState(() => _catalogReadFailed = true);
      return;
    }
    final epoch = ++_catalogEpoch;
    bool current() =>
        _current && epoch == _catalogEpoch && identical(store, _store);
    void failed({required bool synchronized}) {
      if (!current()) return;
      setState(() {
        if (synchronized) {
          _syncCatalogReadFailed = true;
        } else {
          _browseCatalogReadFailed = true;
        }
      });
    }

    if (store is StudioMailMailboxWatchStore) {
      try {
        _folderSubscription = (store as StudioMailMailboxWatchStore)
            .watchViews()
            .listen(
              (result) {
                if (!current()) return;
                try {
                  switch (result) {
                    case MailSuccess<List<MailCachedMailboxSummary>>(
                      :final value,
                    ):
                      _replaceFolders(browsing: value);
                      setState(() => _browseCatalogReadFailed = false);
                    case MailFailure<List<MailCachedMailboxSummary>>():
                      failed(synchronized: false);
                  }
                } on Object {
                  failed(synchronized: false);
                }
              },
              onError: (Object _) => failed(synchronized: false),
              onDone: () => failed(synchronized: false),
            );
      } on Object {
        failed(synchronized: false);
      }
    }
    if (store is StudioMailSyncStore) {
      try {
        _syncFolderSubscription = (store as StudioMailSyncStore)
            .watchSyncMailboxes()
            .listen(
              (result) {
                if (!current()) return;
                try {
                  switch (result) {
                    case MailSuccess<List<MailMailboxSyncSummary>>(
                      :final value,
                    ):
                      _replaceFolders(synchronized: value);
                      setState(() => _syncCatalogReadFailed = false);
                    case MailFailure<List<MailMailboxSyncSummary>>():
                      failed(synchronized: true);
                  }
                } on Object {
                  failed(synchronized: true);
                }
              },
              onError: (Object _) => failed(synchronized: true),
              onDone: () => failed(synchronized: true),
            );
      } on Object {
        failed(synchronized: true);
      }
    }
  }

  Future<void> _openStore() async {
    try {
      if (!widget.isCurrent()) _invalid();
      final owner =
          await (widget.draftStoreFactory ?? openStudioMailDraftStore)(
            widget.identity,
          );
      _owner = owner;
      final store = switch (owner) {
        StudioMailMailboxStoreOwner value => value.mailboxStore,
        _ => null,
      };
      if (store == null || store.account != widget.identity.account) _invalid();
      _store = store;
      if (!_current) {
        await _releaseStore();
        return;
      }
      final session = StudioMailMailboxSession(
        store: store,
        provider: widget.identity.provider,
      );
      _mailboxSession = session;
      _viewSubscription = session.changes.listen(_viewChanged);
      await _readCatalogs(store);
      if (_current && _folders.isNotEmpty) await _readFolder(_folders.first);
      if (_current) _watchCatalogs(store);
      if (!_current) await _releaseStore();
    } on Object {
      var closeFailed = false;
      // A valid owner remains available for local cleanup even when reading
      // an over-budget or corrupt catalog fails. Never retain a wrong owner.
      if (_store == null || !_current) {
        try {
          await _releaseStore();
        } on Object {
          closeFailed = true;
        }
      }
      if (mounted && !_closeRequested) {
        setState(
          () => _error = closeFailed
              ? widget.strings.mailCacheCloseFailed
              : widget.strings.mailCacheReadFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _ensureSelection();
    }
  }

  Future<void> _readFolder(
    StudioMailRetainedFolder folder, {
    StudioMailMailboxSource? source,
    int offset = 0,
  }) async {
    final session = _mailboxSession;
    if (!_current || session == null) return;
    final selectedSource =
        source ??
        (folder.synchronized != null
            ? StudioMailMailboxSource.synchronized
            : StudioMailMailboxSource.browse);
    if (selectedSource == StudioMailMailboxSource.browse
        ? folder.browse == null
        : folder.synchronized == null) {
      _invalid();
    }
    _bodyEpoch++;
    setState(() {
      _selectedMailbox = folder.mailbox.id;
      _source = selectedSource;
    });
    if (selectedSource == StudioMailMailboxSource.synchronized) {
      await session.selectSynchronized(
        folder.mailbox.id,
        offset: offset,
        limit: _pageSize,
      );
    } else {
      await session.select(folder.mailbox.id);
    }
  }

  void _viewChanged(StudioMailMailboxSnapshot snapshot) {
    if (!_current) return;
    if (snapshot.phase == StudioMailMailboxPhase.failed) {
      setState(() => _viewReadFailed = true);
      return;
    }
    if (snapshot.phase == StudioMailMailboxPhase.closed) {
      return;
    }
    final selected = _selected;
    final retained =
        snapshot.mailbox == _view?.mailbox &&
            snapshot.source == _view?.source &&
            snapshot.offset == _view?.offset &&
            selected != null
        ? snapshot.headers
              .where(
                (header) =>
                    header.id == selected.id &&
                    header.remote == selected.remote,
              )
              .firstOrNull
        : null;
    final previous = retained == null ? _reader : null;
    setState(() {
      _view = snapshot.phase == StudioMailMailboxPhase.idle ? null : snapshot;
      _selected = retained;
      if (retained == null) {
        _bodyEpoch++;
        _reader = null;
        _missingBody = false;
        _showMessage = false;
      }
      _viewReadFailed = false;
    });
    _retire(previous);
  }

  void _retire(MailReaderController? reader) {
    if (reader == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => reader.dispose());
  }

  Future<void> _operate(
    Future<void> Function() read, {
    String? failureMessage,
  }) async {
    if (!_current || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final pending = Future<void>.sync(read);
    // Keep the completion (including a handled failure) until close can await
    // it. Injected owners need the same ordering as the serialized native one.
    _reading = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      await pending;
    } on Object {
      if (_current) {
        setState(
          () => _error = failureMessage ?? widget.strings.mailCacheReadFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _ensureSelection();
    }
  }

  Future<void> _refreshLocal() => _operate(() async {
    final store = _store!;
    await _stopCatalogs();
    if (!_current) return;
    try {
      await _readCatalogs(store);
      if (!_current) return;
      final folder = _folder;
      if (folder != null &&
          (_source == StudioMailMailboxSource.browse
              ? folder.browse != null
              : folder.synchronized != null)) {
        await _readFolder(folder, source: _source, offset: _view?.offset ?? 0);
      }
    } finally {
      if (_current) _watchCatalogs(store);
    }
  });

  Future<void> _changePage(int offset) => _operate(() async {
    final folder = _folder;
    if (folder == null || _source != StudioMailMailboxSource.synchronized) {
      return;
    }
    await _readFolder(folder, source: _source, offset: offset);
  });

  Future<void> _openMessage(String id) => _operate(() async {
    final view = _view;
    final store = _store!;
    final header = view?.headers
        .where((item) => item.id.value == id)
        .firstOrNull;
    if (header == null) _invalid();
    final previous = _reader;
    final bodyEpoch = ++_bodyEpoch;
    setState(() {
      _selected = header;
      _reader = null;
      _missingBody = false;
      _showMessage = true;
    });
    _retire(previous);
    final message = await store.loadMessage(header);
    if (!_current ||
        bodyEpoch != _bodyEpoch ||
        view?.mailbox != _view?.mailbox ||
        view?.source != _view?.source ||
        view?.offset != _view?.offset ||
        _selected?.id != header.id ||
        _selected?.remote != header.remote ||
        !identical(store, _store)) {
      return;
    }
    if (message == null) {
      setState(() => _missingBody = true);
      return;
    }
    if (message.localId != header.id ||
        message.remoteIdentity != header.remote) {
      _invalid();
    }
    final reader = MailReaderController(
      result: MailParseResult(
        status: MailParseStatus.complete,
        message: message,
      ),
      labels: StudioMailReaderLabels(widget.strings.language),
    );
    setState(() => _reader = reader);
  });

  Future<void> _clearCache() async {
    if (!_current || _busy || _confirmingCleanup) return;
    setState(() => _confirmingCleanup = true);
    final direction = Directionality.of(context);
    var confirmed = false;
    try {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => Directionality(
              textDirection: direction,
              child: AlertDialog(
                title: Text(widget.strings.mailCacheClear),
                content: SingleChildScrollView(
                  child: Text(widget.strings.mailCacheClearHelp),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(widget.strings.cancel),
                  ),
                  FilledButton(
                    key: const ValueKey('studio-mail-cache-clear-confirm'),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(widget.strings.mailCacheClear),
                  ),
                ],
              ),
            ),
          ) ??
          false;
    } finally {
      if (mounted) setState(() => _confirmingCleanup = false);
    }
    if (!confirmed || !_current) return;
    await _operate(() async {
      final store = _store!;
      final report = await store.clearCache();
      if (!_current || !identical(store, _store)) return;
      final previous = _reader;
      setState(() {
        _cleanupEpoch++;
        _bodyEpoch++;
        _cleanupReport = report;
        _folders = const [];
        _browsingFolders = const [];
        _synchronizedFolders = const [];
        _selectedMailbox = null;
        _view = null;
        _reader = null;
        _selected = null;
        _missingBody = false;
        _showMessage = false;
        _viewReadFailed = false;
        _browseCatalogReadFailed = false;
        _syncCatalogReadFailed = false;
        _loaded = true;
      });
      _retire(previous);
      // Cleanup is already committed. A subsequent read failure is reported
      // separately; it must not restore a stale view of removed local content.
      try {
        // Revoke selected-view delivery before waiting on catalog shutdown.
        // A slow catalog cancellation cannot resurrect the cleared snapshot.
        await Future.wait<void>([
          if (_mailboxSession case final session?) session.clear(),
          _stopCatalogs(),
        ]);
        await _readCatalogs(store);
        if (!_current || !identical(store, _store)) return;
        if (_folders.isNotEmpty) await _readFolder(_folders.first);
      } on Object {
        if (_current) {
          setState(() => _error = widget.strings.mailCacheReadFailed);
        }
      } finally {
        if (_current) _watchCatalogs(store);
      }
    }, failureMessage: widget.strings.mailCacheClearFailed);
  }

  Future<void> _releaseStore() {
    if (_storeClosing case final pending?) return pending;
    final owner = _owner;
    if (owner == null) return Future<void>.value();
    final closing =
        Future<void>.sync(() async {
          final session = _mailboxSession;
          final viewSubscription = _viewSubscription;
          // Start every drain even if another cancellation fails. Keep each
          // owner handle until its drain succeeds, so Close can never skip an
          // unfinished observer on a later attempt.
          await Future.wait<void>([
            _stopCatalogs(),
            if (viewSubscription != null)
              Future<void>.sync(() async {
                await viewSubscription.cancel();
                if (identical(_viewSubscription, viewSubscription)) {
                  _viewSubscription = null;
                }
              }),
            if (session != null)
              Future<void>.sync(() async {
                await session.close();
                if (identical(_mailboxSession, session)) {
                  _mailboxSession = null;
                }
              }),
          ]);
          await owner.close();
        }).then((_) {
          if (identical(owner, _owner)) {
            _owner = null;
            _store = null;
          }
        });
    final result = closing.whenComplete(() => _storeClosing = null);
    _storeClosing = result;
    return result;
  }

  Future<void> _closeAndPop() async {
    if (_closingNavigation) return;
    _closeRequested = true;
    if (mounted) setState(() => _closingNavigation = true);
    await _opening;
    await _reading;
    try {
      await _releaseStore();
    } on Object {
      if (mounted) {
        setState(() {
          _closingNavigation = false;
          _error = widget.strings.mailCacheCloseFailed;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  Widget _messages() => MailMessageList(
    key: _listKey,
    scopeId:
        '$_cleanupEpoch:${_selectedMailbox?.value}:${_source.name}:${_view?.offset ?? 0}',
    strings: widget.strings.mailMessageListStrings,
    selectedId: _selected?.id.value,
    busy: _busy || !_current,
    items: [
      for (final header in _headers)
        MailMessageListItem(
          id: header.id.value,
          subject: header.envelope.subject,
          accountId: [
            header.remote.account.profile.hostId,
            header.remote.account.profile.value,
            header.remote.account.value,
          ].map(Uri.encodeComponent).join('/'),
          messageId: header.envelope.messageId,
          inReplyTo: header.envelope.inReplyTo,
          references: header.envelope.references,
          sender: header.envelope.from
              .map(
                (address) => address.displayName?.isNotEmpty == true
                    ? '${address.displayName} <${address.address}>'
                    : address.address,
              )
              .join(', '),
          to: header.envelope.to
              .map(
                (address) => address.displayName?.isNotEmpty == true
                    ? '${address.displayName} <${address.address}>'
                    : address.address,
              )
              .join(', '),
          cc: header.envelope.cc
              .map(
                (address) => address.displayName?.isNotEmpty == true
                    ? '${address.displayName} <${address.address}>'
                    : address.address,
              )
              .join(', '),
          date: header.envelope.sentAt,
          dateLabel: studioMailListDate(
            header.envelope.sentAt,
            widget.strings.language,
          ),
          isRead: header.flags?.isRead,
          isFlagged: header.flags?.isFlagged,
        ),
    ],
    onOpen: (id) => unawaited(_openMessage(id)),
  );

  Widget _message() {
    if (_reader case final reader?) return MailMessageView(controller: reader);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _missingBody
              ? widget.strings.mailCacheMissingBody
              : _busy
              ? widget.strings.mailMessageListStrings.loading
              : _displayError ?? widget.strings.mailCacheChooseMessage,
          key: const ValueKey('studio-mail-cache-message-state'),
        ),
      ),
    );
  }

  Widget _workspace(bool compact) {
    if (compact) {
      return IndexedStack(
        index: _showMessage ? 1 : 0,
        children: [
          ExcludeFocus(excluding: _showMessage, child: _messages()),
          ExcludeFocus(
            excluding: !_showMessage,
            child: Column(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('studio-mail-cache-back'),
                    onPressed: () => setState(() => _showMessage = false),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(widget.strings.backToMessages),
                  ),
                ),
                Expanded(child: _message()),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(width: 340, child: _messages()),
        const VerticalDivider(width: 1),
        Expanded(child: _message()),
      ],
    );
  }

  Future<void> _openFlagHistory() async {
    final owner = _owner;
    if (!_current ||
        _busy ||
        _confirmingCleanup ||
        _historyOpen ||
        owner is! StudioMailFlagJournalOwner) {
      return;
    }
    final store = (owner as StudioMailFlagJournalOwner).flagJournal;
    if (store.account != widget.identity.account) return;
    setState(() => _historyOpen = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => StudioMailJournalDialog(
          strings: widget.strings,
          store: store,
          isCurrent: () => _current && identical(owner, _owner),
        ),
      );
    } finally {
      if (mounted) setState(() => _historyOpen = false);
    }
  }

  Future<void> _openSynchronization() async {
    final store = _store;
    final owner = _owner;
    if (!_current ||
        _busy ||
        _confirmingCleanup ||
        _historyOpen ||
        store == null ||
        store is! StudioMailSyncStore) {
      return;
    }
    setState(() => _historyOpen = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StudioMailSyncDialog(
          strings: widget.strings,
          mailboxStore: store,
          syncStore: store as StudioMailSyncStore,
          isCurrent: () => _current && identical(owner, _owner),
        ),
      );
    } finally {
      if (mounted) setState(() => _historyOpen = false);
    }
  }

  Widget _sourceSelector(StudioMailRetainedFolder folder) {
    final showBrowse =
        folder.browse != null || _source == StudioMailMailboxSource.browse;
    final showSync =
        folder.synchronized != null ||
        _source == StudioMailMailboxSource.synchronized;
    String label(StudioMailMailboxSource source) =>
        source == StudioMailMailboxSource.browse
        ? widget.strings.mailCacheBrowseSource
        : widget.strings.mailCacheSyncSource;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: showBrowse && showSync
          ? Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final source in StudioMailMailboxSource.values)
                  ChoiceChip(
                    key: ValueKey(
                      source == StudioMailMailboxSource.browse
                          ? 'studio-mail-cache-source-browse'
                          : 'studio-mail-cache-source-sync',
                    ),
                    label: Text(label(source)),
                    selected: _source == source,
                    onSelected:
                        _busy ||
                            !_current ||
                            (source == StudioMailMailboxSource.browse
                                ? folder.browse == null
                                : folder.synchronized == null)
                        ? null
                        : (selected) {
                            if (selected && source != _source) {
                              unawaited(
                                _operate(
                                  () => _readFolder(folder, source: source),
                                ),
                              );
                            }
                          },
                  ),
              ],
            )
          : Text(
              label(_source),
              key: const ValueKey('studio-mail-cache-source'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
    );
  }

  Widget _pageControls(StudioMailMailboxSnapshot view) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          widget.strings.mailSyncPage(
            view.headers.isEmpty ? 0 : view.offset + 1,
            view.offset + view.headers.length,
            view.headerCount,
          ),
          key: const ValueKey('studio-mail-cache-page'),
        ),
        TextButton.icon(
          key: const ValueKey('studio-mail-cache-previous'),
          onPressed: _busy || !_current || view.offset == 0
              ? null
              : () => _changePage(
                  (view.offset - _pageSize).clamp(0, view.offset),
                ),
          icon: const Icon(Icons.navigate_before),
          label: Text(widget.strings.mailSyncPrevious),
        ),
        TextButton.icon(
          key: const ValueKey('studio-mail-cache-next'),
          onPressed: _busy || !_current || view.nextOffset == null
              ? null
              : () => _changePage(view.nextOffset!),
          icon: const Icon(Icons.navigate_next),
          label: Text(widget.strings.mailSyncNext),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_confirmingCleanup) unawaited(_closeAndPop());
    },
    child: Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 1120,
        height: 760,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.strings.mailCachedMail} · ${widget.identity.sender}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (_store != null)
                      IconButton(
                        key: const ValueKey('studio-mail-cache-refresh'),
                        tooltip: widget.strings.mailCacheRefresh,
                        icon: const Icon(Icons.refresh),
                        onPressed:
                            _busy ||
                                _confirmingCleanup ||
                                _historyOpen ||
                                !_current
                            ? null
                            : _refreshLocal,
                      ),
                    if (_store is StudioMailSyncStore)
                      IconButton(
                        key: const ValueKey('studio-mail-open-sync'),
                        tooltip: widget.strings.mailSync,
                        icon: const Icon(Icons.sync),
                        onPressed:
                            _busy ||
                                _confirmingCleanup ||
                                _historyOpen ||
                                !_current
                            ? null
                            : _openSynchronization,
                      ),
                    if (_owner is StudioMailFlagJournalOwner)
                      IconButton(
                        key: const ValueKey('studio-mail-open-activity'),
                        tooltip: widget.strings.mailActivity,
                        icon: const Icon(Icons.history),
                        onPressed:
                            _busy ||
                                _confirmingCleanup ||
                                _historyOpen ||
                                !_current
                            ? null
                            : _openFlagHistory,
                      ),
                    IconButton(
                      key: const ValueKey('studio-mail-cache-close'),
                      tooltip: widget.strings.close,
                      onPressed:
                          _closingNavigation ||
                              _confirmingCleanup ||
                              _historyOpen
                          ? null
                          : _closeAndPop,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (_store != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TextButton.icon(
                      key: const ValueKey('studio-mail-cache-clear'),
                      onPressed:
                          _busy ||
                              _confirmingCleanup ||
                              _historyOpen ||
                              !_current
                          ? null
                          : _clearCache,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text(widget.strings.mailCacheClear),
                    ),
                  ),
                ),
              if (_busy || _closingNavigation) const LinearProgressIndicator(),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.35,
                ),
                child: SingleChildScrollView(
                  key: const ValueKey('studio-mail-cache-metadata'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Text(
                          _store is StudioMailSyncStore
                              ? widget.strings.mailCacheRetainedScope
                              : widget.strings.mailCacheScope,
                        ),
                      ),
                      if (_displayError case final error?)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Text(
                            error,
                            key: const ValueKey('studio-mail-cache-error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (_cleanupReport case final report?)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                widget.strings.mailCacheCleared(
                                  report.removedViews,
                                  report.evictedBodies,
                                  report.removedHeaders,
                                ),
                                key: const ValueKey(
                                  'studio-mail-cache-cleared',
                                ),
                              ),
                              if (report.hasMore)
                                Text(widget.strings.mailCacheClearMore),
                              if (report.retainedBodies > 0)
                                Text(
                                  widget.strings.mailCacheProtected(
                                    report.retainedBodies,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (_folders.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: DropdownButton<MailMailboxId>(
                            key: const ValueKey('studio-mail-cache-folders'),
                            isExpanded: true,
                            value: _folder == null ? null : _selectedMailbox,
                            items: [
                              for (final folder in _folders)
                                DropdownMenuItem(
                                  value: folder.mailbox.id,
                                  child: Text(
                                    folder.mailbox.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy || !_current
                                ? null
                                : (id) {
                                    final folder = _folders
                                        .where(
                                          (folder) => folder.mailbox.id == id,
                                        )
                                        .firstOrNull;
                                    if (folder != null) {
                                      unawaited(
                                        _operate(() => _readFolder(folder)),
                                      );
                                    }
                                  },
                          ),
                        ),
                      if (_folder case final folder?) _sourceSelector(folder),
                      if (_hasView && _view != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Text(
                            _source == StudioMailMailboxSource.synchronized
                                ? widget.strings.mailSyncSaved(
                                    _view!.capturedAt!,
                                    _view!.headerCount,
                                  )
                                : widget.strings.mailCacheSnapshot(
                                    _view!.capturedAt!,
                                    _headers.length,
                                  ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Text(
                            widget.strings.mailCacheUnread(
                              _view!.unreadCount,
                              _view!.unknownReadCount,
                            ),
                            key: const ValueKey('studio-mail-cache-unread'),
                          ),
                        ),
                        if (_view!.hasMore ||
                            _source == StudioMailMailboxSource.synchronized)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Text(
                              _source == StudioMailMailboxSource.synchronized
                                  ? (_view!.hasMore
                                        ? widget.strings.mailSyncPartial
                                        : widget.strings.mailSyncComplete)
                                  : widget.strings.mailCachePartial,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_hasView && _source == StudioMailMailboxSource.synchronized)
                _pageControls(_view!),
              if (_hasView)
                Expanded(child: _workspace(constraints.maxWidth < 760))
              else
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _displayError ??
                            (_loaded && _folders.isEmpty
                                ? (_store is StudioMailSyncStore
                                      ? widget.strings.mailCacheRetainedEmpty
                                      : widget.strings.mailCacheEmpty)
                                : !_busy &&
                                      _selectedMailbox != null &&
                                      _view?.phase !=
                                          StudioMailMailboxPhase.loading
                                ? widget.strings.mailCacheSourceMissing
                                : widget
                                      .strings
                                      .mailMessageListStrings
                                      .loading),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
