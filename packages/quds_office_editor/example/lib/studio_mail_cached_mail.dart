import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_cached_strings.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_draft_store_native.dart';
import 'studio_mail_mailbox_store.dart';
import 'studio_mail_workspace_strings.dart';
import 'studio_strings.dart';

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
  bool _closeRequested = false;
  bool _closingNavigation = false;
  bool _allowPop = false;
  int _cleanupEpoch = 0;
  String? _error;
  MailCacheCleanupReport? _cleanupReport;

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
    final ids = <MailMailboxId>{};
    for (final folder in folders) {
      if (folder.mailbox.id.account != store.account ||
          !ids.add(folder.mailbox.id) ||
          folder.revision < 0 ||
          folder.headerCount < 0) {
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
      if (folders.isNotEmpty) await _readFolder(folders.first);
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
    final store = _store;
    if (!_current || store == null) return;
    final view = await store.loadView(summary.mailbox.id);
    if (!_current || !identical(store, _store)) return;
    if (view == null ||
        view.mailbox.id != summary.mailbox.id ||
        view.revision != summary.revision ||
        view.capturedAt != summary.capturedAt ||
        view.headers.length != summary.headerCount ||
        view.hasMore != summary.hasMore) {
      _invalid();
    }
    final ids = <MailMessageId>{};
    for (final header in view.headers) {
      final wrongMailbox = switch (header.remote) {
        MailImapIdentity(:final mailbox) => mailbox != view.mailbox.id,
        _ => false,
      };
      if (header.remote.account != store.account ||
          header.remote.provider != widget.identity.provider ||
          !ids.add(header.id) ||
          wrongMailbox) {
        _invalid();
      }
    }
    final previous = _reader;
    setState(() {
      _view = view;
      _selected = null;
      _reader = null;
      _missingBody = false;
      _showMessage = false;
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
    if (!_current || !identical(view, _view) || !identical(store, _store)) {
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
    );
    setState(() => _reader = reader);
  });

  Future<void> _clearCache() async {
    if (!_current || _busy || _confirmingCleanup) return;
    setState(() => _confirmingCleanup = true);
    var confirmed = false;
    try {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
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
        _loaded = true;
      });
      _retire(previous);
      // Cleanup is already committed. A subsequent read failure is reported
      // separately; it must not restore a stale view of removed local content.
      try {
        final folders = await _listFolders(store);
        if (!_current || !identical(store, _store)) return;
        setState(() => _folders = folders);
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
    final closing = Future<void>.sync(owner.close).then((_) {
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
          dateLabel: header.envelope.sentAt?.toLocal().toString(),
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
              : _error ?? widget.strings.mailCacheChooseMessage,
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
                    IconButton(
                      key: const ValueKey('studio-mail-cache-close'),
                      tooltip: widget.strings.close,
                      onPressed: _closingNavigation || _confirmingCleanup
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
                      onPressed: _busy || _confirmingCleanup || !_current
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
                      if (_error case final error?)
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
                            : _error ??
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
