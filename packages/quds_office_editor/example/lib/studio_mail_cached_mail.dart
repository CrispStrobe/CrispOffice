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
  late final Future<void> _opening;
  Future<void>? _reading;
  Future<void>? _storeClosing;
  List<MailCachedMailboxSummary> _folders = const [];
  MailCachedMailboxView? _view;
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
  MailCacheCleanupReport? _cleanupReport;

  String? get _displayError {
    final streamError = _viewReadFailed || _catalogReadFailed
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

  Future<List<MailCachedMailboxSummary>> _listFolders(
    StudioMailMailboxStore store,
  ) async {
    final folders = await store.listViews();
    return _validateFolders(store, folders);
  }

  List<MailCachedMailboxSummary> _validateFolders(
    StudioMailMailboxStore store,
    List<MailCachedMailboxSummary> folders,
  ) {
    final ids = <MailMailboxId>{};
    if (folders.length > 1000) _invalid();
    for (final folder in folders) {
      if (folder.mailbox.id.account != store.account ||
          !ids.add(folder.mailbox.id) ||
          folder.revision < 1 ||
          folder.headerCount < 0 ||
          folder.headerCount > 1000) {
        _invalid();
      }
    }
    return List.unmodifiable(folders);
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
      final folders = await _listFolders(store);
      if (!_current) {
        await _releaseStore();
        return;
      }
      setState(() {
        _folders = folders;
        _loaded = true;
      });
      final session = StudioMailMailboxSession(
        store: store,
        provider: widget.identity.provider,
      );
      _mailboxSession = session;
      _viewSubscription = session.changes.listen(_viewChanged);
      if (folders.isNotEmpty) await _readFolder(folders.first);
      if (_current && store is StudioMailMailboxWatchStore) {
        _folderSubscription = (store as StudioMailMailboxWatchStore)
            .watchViews()
            .listen(
              (result) => _foldersChanged(store, result),
              onError: (Object _) => _foldersChanged(
                store,
                const MailFailure(MailProblem(MailProblemCode.storageFailure)),
              ),
              onDone: () => _foldersChanged(
                store,
                const MailFailure(MailProblem(MailProblemCode.unavailable)),
              ),
            );
      }
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
    }
  }

  Future<void> _readFolder(MailCachedMailboxSummary summary) async {
    final session = _mailboxSession;
    if (!_current || session == null) return;
    await session.select(summary.mailbox.id);
  }

  void _viewChanged(StudioMailMailboxSnapshot snapshot) {
    if (!_current) return;
    if (snapshot.phase == StudioMailMailboxPhase.failed) {
      setState(() => _viewReadFailed = true);
      return;
    }
    if (snapshot.phase == StudioMailMailboxPhase.closed ||
        snapshot.phase == StudioMailMailboxPhase.idle) {
      return;
    }
    final view = snapshot.view;
    final selected = _selected;
    final retained = view?.mailbox.id == _view?.mailbox.id && selected != null
        ? view?.headers
              .where(
                (header) =>
                    header.id == selected.id &&
                    header.remote == selected.remote,
              )
              .firstOrNull
        : null;
    final previous = retained == null ? _reader : null;
    setState(() {
      _view = view;
      _selected = retained;
      if (retained == null) {
        _reader = null;
        _missingBody = false;
        _showMessage = false;
      }
      _viewReadFailed = false;
    });
    _retire(previous);
  }

  void _foldersChanged(
    StudioMailMailboxStore store,
    MailResult<List<MailCachedMailboxSummary>> result,
  ) {
    if (!_current || !identical(store, _store)) return;
    try {
      final folders = switch (result) {
        MailSuccess<List<MailCachedMailboxSummary>>(:final value) =>
          _validateFolders(store, value),
        MailFailure<List<MailCachedMailboxSummary>>() => _invalid(),
      };
      final removed =
          _view != null &&
          !folders.any((folder) => folder.mailbox.id == _view!.mailbox.id);
      final previous = removed ? _reader : null;
      setState(() {
        _folders = folders;
        _catalogReadFailed = false;
        if (removed) {
          _view = null;
          _selected = null;
          _reader = null;
          _missingBody = false;
          _showMessage = false;
        }
      });
      _retire(previous);
      if (_view == null && folders.isNotEmpty && !_busy) {
        unawaited(_operate(() => _readFolder(folders.first)));
      }
    } on Object {
      setState(() => _catalogReadFailed = true);
    }
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
    }
  }

  Future<void> _openMessage(String id) => _operate(() async {
    final view = _view;
    final store = _store!;
    final header = view?.headers
        .where((item) => item.id.value == id)
        .firstOrNull;
    if (header == null) _invalid();
    final previous = _reader;
    setState(() {
      _selected = header;
      _reader = null;
      _missingBody = false;
      _showMessage = true;
    });
    _retire(previous);
    final message = await store.loadMessage(header);
    if (!_current ||
        view?.mailbox.id != _view?.mailbox.id ||
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
        _cleanupReport = report;
        _folders = const [];
        _view = null;
        _reader = null;
        _selected = null;
        _missingBody = false;
        _showMessage = false;
        _viewReadFailed = false;
        _loaded = true;
      });
      _retire(previous);
      // Cleanup is already committed. A subsequent read failure is reported
      // separately; it must not restore a stale view of removed local content.
      try {
        final folders = await _listFolders(store);
        if (!_current || !identical(store, _store)) return;
        setState(() {
          _folders = folders;
          _catalogReadFailed = false;
        });
        if (folders.isNotEmpty) await _readFolder(folders.first);
      } on Object {
        if (_current) {
          setState(() => _error = widget.strings.mailCacheReadFailed);
        }
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
          _mailboxSession = null;
          await _viewSubscription?.cancel();
          _viewSubscription = null;
          await _folderSubscription?.cancel();
          _folderSubscription = null;
          await session?.close();
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
    scopeId: '$_cleanupEpoch:${_view?.mailbox.id.value}',
    strings: widget.strings.mailMessageListStrings,
    selectedId: _selected?.id.value,
    busy: _busy || !_current,
    items: [
      for (final header in _view?.headers ?? const <MailHeaderRecord>[])
        MailMessageListItem(
          id: header.id.value,
          subject: header.envelope.subject,
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
                        child: Text(widget.strings.mailCacheScope),
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
                            value: _view?.mailbox.id,
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
                      if (_view case final view?) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Text(
                            widget.strings.mailCacheSnapshot(
                              view.capturedAt,
                              view.headers.length,
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
                              view.headers
                                  .where(
                                    (header) => header.flags?.isRead == false,
                                  )
                                  .length,
                              view.headers
                                  .where((header) => header.flags == null)
                                  .length,
                            ),
                            key: const ValueKey('studio-mail-cache-unread'),
                          ),
                        ),
                        if (view.hasMore)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Text(widget.strings.mailCachePartial),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_view != null)
                Expanded(child: _workspace(constraints.maxWidth < 760))
              else
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _loaded && _folders.isEmpty
                            ? widget.strings.mailCacheEmpty
                            : _displayError ??
                                  widget.strings.mailMessageListStrings.loading,
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
