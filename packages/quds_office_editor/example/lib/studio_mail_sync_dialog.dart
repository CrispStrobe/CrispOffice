import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_mailbox_store.dart';
import 'studio_mail_sync_strings.dart';
import 'studio_mail_workspace_strings.dart';
import 'studio_strings.dart';
import 'studio_mail_reader_labels.dart';

typedef StudioMailSyncRun =
    Future<MailSyncRunReport> Function({
      required MailCancellationToken cancellation,
      required void Function(MailSyncRunProgress) onProgress,
    });

typedef StudioMailBodyDownloadRun =
    Future<MailBodyDownloadReport> Function({
      required List<MailHeaderRecord> headers,
      required MailCancellationToken cancellation,
      required void Function(MailBodyDownloadProgress) onProgress,
    });

/// An explicit foreground sync controller and repository-only offline reader.
/// The caller keeps ownership of both stores until this route has closed.
/// Normal close cancels and drains operations and subscriptions before popping.
class StudioMailSyncDialog extends StatefulWidget {
  const StudioMailSyncDialog({
    super.key,
    required this.strings,
    required this.mailboxStore,
    required this.syncStore,
    required this.isCurrent,
    this.mailbox,
    this.run,
    this.download,
  }) : assert((mailbox == null) == (run == null)),
       assert(download == null || run != null);

  final StudioStrings strings;
  final StudioMailMailboxStore mailboxStore;
  final StudioMailSyncStore syncStore;
  final bool Function() isCurrent;
  final MailMailbox? mailbox;
  final StudioMailSyncRun? run;
  final StudioMailBodyDownloadRun? download;

  @override
  State<StudioMailSyncDialog> createState() => _StudioMailSyncDialogState();
}

class _StudioMailSyncDialogState extends State<StudioMailSyncDialog> {
  static const _pageSize = 100;
  final _pending = <Future<void>>{};
  final GlobalKey _listKey = GlobalKey();
  StreamSubscription<MailResult<List<MailMailboxSyncSummary>>>?
  _catalogSubscription;
  StreamSubscription<MailResult<MailMailboxSyncSnapshot?>>? _viewSubscription;
  List<MailMailboxSyncSummary> _folders = const [];
  MailMailbox? _mailbox;
  MailMailboxSyncSnapshot? _view;
  MailHeaderRecord? _selected;
  MailReaderController? _reader;
  MailCancellationSource? _cancellation;
  MailSyncRunProgress? _progress;
  MailSyncRunReport? _report;
  MailCancellationSource? _downloadCancellation;
  MailBodyDownloadProgress? _downloadProgress;
  MailBodyDownloadReport? _downloadReport;
  List<MailHeaderRecord> _downloadHeaders = const [];
  bool _catalogBusy = true;
  bool _viewBusy = false;
  bool _bodyBusy = false;
  bool _missingBody = false;
  bool _showMessage = false;
  bool _stopping = false;
  bool _closing = false;
  bool _closeInProgress = false;
  bool _allowPop = false;
  bool _catalogFailed = false;
  bool _viewFailed = false;
  String? _error;
  int _viewGeneration = 0;
  int _bodyGeneration = 0;
  int _offset = 0;

  bool get _current => mounted && !_closing && widget.isCurrent();
  bool get _running => _cancellation != null;
  bool get _downloading => _downloadCancellation != null;
  bool get _working => _running || _downloading;
  bool get _connected => widget.run != null && widget.mailbox != null;

  @override
  void initState() {
    super.initState();
    unawaited(_work(_open));
  }

  @override
  void dispose() {
    _closing = true;
    _viewGeneration++;
    _bodyGeneration++;
    _cancellation?.cancel(MailCancellationReason.disposed);
    _downloadCancellation?.cancel(MailCancellationReason.disposed);
    _reader?.dispose();
    _reader = null;
    unawaited(_drain().catchError((Object _, StackTrace _) {}));
    super.dispose();
  }

  Future<void> _work(Future<void> Function() action) {
    late final Future<void> pending;
    pending = Future<void>.sync(action)
        .catchError((Object _, StackTrace _) {
          if (_current) {
            setState(() {
              _error = widget.strings.mailSyncReadFailed;
              _catalogBusy = false;
              _viewBusy = false;
            });
          }
        })
        .whenComplete(() => _pending.remove(pending));
    _pending.add(pending);
    return pending;
  }

  static Never _invalid() =>
      throw const StudioMailMailboxStoreException(MailProblemCode.conflict);

  Future<void> _open() async {
    if (!_current) return;
    final mailbox = widget.mailbox;
    if (widget.syncStore.account != widget.mailboxStore.account ||
        (mailbox != null &&
            mailbox.id.account != widget.mailboxStore.account)) {
      _invalid();
    }
    _catalogSubscription = widget.syncStore.watchSyncMailboxes().listen(
      _catalogChanged,
      onError: (Object _) => _catalogError(),
      onDone: _catalogError,
    );
    if (mailbox != null) await _selectMailbox(mailbox);
  }

  void _catalogError() {
    if (!_current) return;
    setState(() {
      _catalogBusy = false;
      _catalogFailed = true;
    });
  }

  void _catalogChanged(MailResult<List<MailMailboxSyncSummary>> result) {
    if (!_current) return;
    try {
      final folders = switch (result) {
        MailSuccess<List<MailMailboxSyncSummary>>(:final value) => value,
        MailFailure<List<MailMailboxSyncSummary>>() => _invalid(),
      };
      final ids = <MailMailboxId>{};
      if (folders.length > 1000) _invalid();
      for (final folder in folders) {
        _validateSummary(folder);
        if (!ids.add(folder.mailbox.id)) _invalid();
      }
      setState(() {
        _folders = List.unmodifiable(folders);
        _catalogBusy = false;
        _catalogFailed = false;
      });
      if (!_connected && (_mailbox == null || !ids.contains(_mailbox!.id))) {
        if (folders.isEmpty) {
          _clearSelection();
        } else {
          unawaited(_work(() => _selectMailbox(folders.first.mailbox)));
        }
      }
    } on Object {
      _catalogError();
    }
  }

  void _validateSummary(MailMailboxSyncSummary summary) {
    if (summary.mailbox.id.account != widget.mailboxStore.account ||
        summary.revision < 1 ||
        summary.headerCount < 0) {
      _invalid();
    }
  }

  void _clearSelection() {
    _downloadCancellation?.cancel(MailCancellationReason.accountChanged);
    _viewGeneration++;
    final subscription = _viewSubscription;
    if (subscription != null) {
      unawaited(
        _work(() async {
          await subscription.cancel();
          if (identical(_viewSubscription, subscription)) {
            _viewSubscription = null;
          }
        }),
      );
    }
    final previous = _reader;
    setState(() {
      _mailbox = null;
      _view = null;
      _offset = 0;
      _viewBusy = false;
      _clearMessage();
    });
    _retire(previous);
  }

  void _clearMessage() {
    _bodyGeneration++;
    _selected = null;
    _reader = null;
    _missingBody = false;
    _showMessage = false;
    _bodyBusy = false;
  }

  Future<void> _selectMailbox(MailMailbox mailbox) async {
    if (!_current) return;
    if (mailbox.id.account != widget.mailboxStore.account) _invalid();
    _downloadCancellation?.cancel(MailCancellationReason.accountChanged);
    final previous = _reader;
    setState(() {
      _mailbox = mailbox;
      _view = null;
      _offset = 0;
      _clearMessage();
    });
    _retire(previous);
    await _loadPage(0);
  }

  Future<void> _loadPage(int offset) async {
    final mailbox = _mailbox;
    if (!_current || mailbox == null) return;
    // Automatic pagination repair can run after a membership reset, even while
    // paging controls are disabled. Retire its body writes before any await.
    _downloadCancellation?.cancel(MailCancellationReason.accountChanged);
    final generation = ++_viewGeneration;
    setState(() {
      _viewBusy = true;
      _viewFailed = false;
      _error = null;
      _offset = offset;
      _downloadProgress = null;
      _downloadReport = null;
    });
    final previous = _viewSubscription;
    try {
      await previous?.cancel();
      if (identical(_viewSubscription, previous)) _viewSubscription = null;
      if (!_viewCurrent(mailbox.id, generation)) return;
      final initial = await widget.syncStore.loadSyncMailbox(
        mailbox.id,
        limit: _pageSize,
        offset: offset,
      );
      if (!_viewCurrent(mailbox.id, generation)) return;
      _viewChanged(initial, mailbox.id, generation, offset);
      if (!_viewCurrent(mailbox.id, generation)) return;
      _viewSubscription = widget.syncStore
          .watchSyncMailbox(mailbox.id, limit: _pageSize, offset: offset)
          .listen(
            (result) => _viewChanged(result, mailbox.id, generation, offset),
            onError: (Object _) => _viewError(mailbox.id, generation),
            onDone: () => _viewError(mailbox.id, generation),
          );
    } on Object {
      _viewError(mailbox.id, generation);
    } finally {
      if (_viewCurrent(mailbox.id, generation)) {
        setState(() => _viewBusy = false);
      }
    }
  }

  bool _viewCurrent(MailMailboxId mailbox, int generation) =>
      _current && _mailbox?.id == mailbox && _viewGeneration == generation;

  void _viewError(MailMailboxId mailbox, int generation) {
    if (!_viewCurrent(mailbox, generation)) return;
    _downloadCancellation?.cancel(MailCancellationReason.accountChanged);
    setState(() {
      _viewFailed = true;
      _viewBusy = false;
    });
  }

  void _viewChanged(
    MailResult<MailMailboxSyncSnapshot?> result,
    MailMailboxId mailbox,
    int generation,
    int offset,
  ) {
    if (!_viewCurrent(mailbox, generation)) return;
    try {
      final view = switch (result) {
        MailSuccess<MailMailboxSyncSnapshot?>(:final value) => value,
        MailFailure<MailMailboxSyncSnapshot?>() => _invalid(),
      };
      if (view != null) {
        _validateSummary(view.summary);
        if (view.mailbox.id != mailbox ||
            view.offset != offset ||
            view.headers.length > _pageSize) {
          _invalid();
        }
        final ids = <MailMessageId>{};
        for (final header in view.headers) {
          if (header.remote.account != widget.mailboxStore.account ||
              !ids.add(header.id)) {
            _invalid();
          }
          if (header.remote case MailImapIdentity(:final mailbox)) {
            if (mailbox != view.mailbox.id) _invalid();
          }
        }
      }
      if (offset > 0 && (view == null || view.headerCount <= offset)) {
        unawaited(_work(() => _loadPage(0)));
        return;
      }
      final selected = _selected;
      if (_downloading &&
          _downloadHeaders.any(
            (target) =>
                !(view?.headers.any(
                      (header) =>
                          header.id == target.id &&
                          header.remote == target.remote,
                    ) ??
                    false),
          )) {
        _downloadCancellation?.cancel(MailCancellationReason.accountChanged);
      }
      final retained = selected == null
          ? null
          : view?.headers
                .where(
                  (header) =>
                      header.id == selected.id &&
                      header.remote == selected.remote,
                )
                .firstOrNull;
      final previous = retained == null ? _reader : null;
      setState(() {
        _view = view;
        _viewFailed = false;
        _selected = retained;
        if (retained == null) _clearMessage();
      });
      _retire(previous);
    } on Object {
      _viewError(mailbox, generation);
    }
  }

  Future<void> _openMessage(String id) async {
    if (!_current || _viewBusy || _bodyBusy) return;
    final header = _view?.headers
        .where((value) => value.id.value == id)
        .firstOrNull;
    if (header == null) return;
    final mailbox = _mailbox?.id;
    final generation = ++_bodyGeneration;
    final previous = _reader;
    setState(() {
      _selected = header;
      _reader = null;
      _missingBody = false;
      _bodyBusy = true;
      _showMessage = true;
      _error = null;
    });
    _retire(previous);
    try {
      final message = await widget.mailboxStore.loadMessage(header);
      if (!_current ||
          generation != _bodyGeneration ||
          _mailbox?.id != mailbox ||
          _selected?.id != header.id ||
          _selected?.remote != header.remote) {
        return;
      }
      if (message == null) {
        setState(() => _missingBody = true);
      } else {
        if (message.localId != header.id ||
            message.remoteIdentity != header.remote) {
          _invalid();
        }
        final reader = MailReaderController(
          result: MailParseResult(
            status: MailParseStatus.complete,
            message: message,
          ),
          preferHtml: false,
          includeHeaders: false,
          labels: StudioMailReaderLabels(widget.strings.language),
        );
        setState(() => _reader = reader);
      }
    } on Object {
      if (_current && generation == _bodyGeneration) {
        setState(() => _error = widget.strings.mailSyncReadFailed);
      }
    } finally {
      if (_current && generation == _bodyGeneration) {
        setState(() => _bodyBusy = false);
      }
    }
  }

  Future<void> _start() async {
    final run = widget.run;
    if (!_current ||
        run == null ||
        _working ||
        _viewBusy ||
        _mailbox?.id != widget.mailbox?.id) {
      return;
    }
    final cancellation = MailCancellationSource();
    setState(() {
      _cancellation = cancellation;
      _progress = null;
      _report = null;
      _stopping = false;
      _error = null;
      _downloadProgress = null;
      _downloadReport = null;
    });
    try {
      final report = await run(
        cancellation: cancellation.token,
        onProgress: (progress) {
          if (!_current || !identical(_cancellation, cancellation)) return;
          if (progress.mailbox != _mailbox?.id) {
            cancellation.cancel(MailCancellationReason.accountChanged);
            setState(() => _error = widget.strings.mailSyncConflict);
            return;
          }
          setState(() => _progress = progress);
        },
      );
      if (!_current || !identical(_cancellation, cancellation)) return;
      if (report.progress.mailbox != _mailbox?.id) _invalid();
      setState(() {
        _report = report;
        _progress = report.progress;
      });
    } on Object {
      if (_current && identical(_cancellation, cancellation)) {
        setState(() => _error = widget.strings.mailSyncFailed);
      }
    } finally {
      if (identical(_cancellation, cancellation)) {
        _cancellation = null;
        if (_current) setState(() => _stopping = false);
      }
    }
  }

  void _stop() {
    if (!_current || !_working) return;
    _cancellation?.cancel();
    _downloadCancellation?.cancel();
    setState(() => _stopping = true);
  }

  bool _validDownloadProgress(
    MailBodyDownloadProgress progress,
    MailMailboxId mailbox,
    int total,
  ) =>
      progress.mailbox == mailbox &&
      progress.total == total &&
      progress.downloaded >= 0 &&
      progress.alreadyCached >= 0 &&
      progress.processed <= total &&
      progress.retainedBytes >= 0 &&
      progress.retainedBytes <= 64 * 1024 * 1024;

  Future<void> _download({bool selectedOnly = false}) async {
    final run = widget.download;
    final mailbox = _mailbox?.id;
    final view = _view;
    if (!_current ||
        !_connected ||
        run == null ||
        mailbox == null ||
        view == null ||
        _working ||
        _viewBusy ||
        _bodyBusy ||
        _viewFailed) {
      return;
    }
    final headers = List<MailHeaderRecord>.unmodifiable(
      selectedOnly
          ? view.headers.where(
              (header) =>
                  header.id == _selected?.id &&
                  header.remote == _selected?.remote,
            )
          : view.headers,
    );
    if (headers.isEmpty || headers.length > _pageSize) return;
    final cancellation = MailCancellationSource();
    final generation = _viewGeneration;
    final selectedId = _selected?.id.value;
    bool current() =>
        _viewCurrent(mailbox, generation) &&
        identical(_downloadCancellation, cancellation);
    setState(() {
      _downloadCancellation = cancellation;
      _downloadHeaders = headers;
      _downloadProgress = null;
      _downloadReport = null;
      _stopping = false;
      _error = null;
    });
    try {
      final report = await run(
        headers: headers,
        cancellation: cancellation.token,
        onProgress: (progress) {
          if (!current()) {
            cancellation.cancel(MailCancellationReason.accountChanged);
            return;
          }
          if (!_validDownloadProgress(progress, mailbox, headers.length)) {
            cancellation.cancel(MailCancellationReason.accountChanged);
            setState(() => _error = widget.strings.mailDownloadConflict);
            return;
          }
          setState(() => _downloadProgress = progress);
        },
      );
      if (!current()) return;
      if (!_validDownloadProgress(report.progress, mailbox, headers.length)) {
        _invalid();
      }
      setState(() {
        _downloadReport = report;
        _downloadProgress = report.progress;
      });
    } on Object {
      if (current()) {
        setState(() => _error = widget.strings.mailDownloadFailed);
      }
    } finally {
      if (identical(_downloadCancellation, cancellation)) {
        _downloadCancellation = null;
        _downloadHeaders = const [];
        if (_current) setState(() => _stopping = false);
      }
    }
    // Refresh only from the local cache. Selecting a message never downloads it.
    if (_viewCurrent(mailbox, generation) &&
        selectedId != null &&
        _selected?.id.value == selectedId) {
      await _openMessage(selectedId);
    }
  }

  Future<void> _drain() async {
    final catalog = _catalogSubscription;
    if (catalog != null) {
      await catalog.cancel();
      if (identical(_catalogSubscription, catalog)) {
        _catalogSubscription = null;
      }
    }
    final view = _viewSubscription;
    if (view != null) {
      await view.cancel();
      if (identical(_viewSubscription, view)) _viewSubscription = null;
    }
    while (_pending.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(_pending));
    }
  }

  Future<void> _close() async {
    if (_closeInProgress) return;
    _closing = true;
    _cancellation?.cancel();
    _downloadCancellation?.cancel();
    setState(() => _closeInProgress = true);
    try {
      await _drain();
    } on Object {
      if (mounted) {
        setState(() {
          _closeInProgress = false;
          _error = widget.strings.mailSyncCloseFailed;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  void _retire(MailReaderController? reader) {
    if (reader != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => reader.dispose());
    }
  }

  String _problemText(MailProblem? problem) => switch (problem?.code) {
    MailProblemCode.authenticationRequired ||
    MailProblemCode.permissionDenied => widget.strings.mailSyncAuthentication,
    MailProblemCode.conflict ||
    MailProblemCode.staleOperation => widget.strings.mailSyncConflict,
    MailProblemCode.quotaExceeded => widget.strings.mailSyncQuota,
    MailProblemCode.unsupported => widget.strings.mailSyncUnsupported,
    _ => widget.strings.mailSyncFailed,
  };

  String? get _reportText {
    final report = _report;
    if (report == null) return null;
    return switch (report.status) {
      MailSyncRunStatus.completed => widget.strings.mailSyncFinished,
      MailSyncRunStatus.paused => widget.strings.mailSyncPaused,
      MailSyncRunStatus.cancelled => widget.strings.mailSyncCancelled,
      MailSyncRunStatus.failed => _problemText(report.problem),
    };
  }

  String? get _downloadReportText {
    final report = _downloadReport;
    if (report == null) return null;
    return switch (report.status) {
      MailBodyDownloadStatus.completed => widget.strings.mailDownloadFinished,
      MailBodyDownloadStatus.paused => widget.strings.mailDownloadPaused,
      MailBodyDownloadStatus.cancelled =>
        report.problem?.code == MailProblemCode.staleOperation
            ? widget.strings.mailDownloadConflict
            : widget.strings.mailDownloadCancelled,
      MailBodyDownloadStatus.failed => switch (report.problem?.code) {
        MailProblemCode.authenticationRequired ||
        MailProblemCode.permissionDenied =>
          widget.strings.mailDownloadAuthentication,
        MailProblemCode.conflict ||
        MailProblemCode.staleOperation => widget.strings.mailDownloadConflict,
        MailProblemCode.quotaExceeded => widget.strings.mailDownloadQuota,
        MailProblemCode.unsupported => widget.strings.mailDownloadUnsupported,
        _ => widget.strings.mailDownloadFailed,
      },
    };
  }

  Widget _messages() => MailMessageList(
    key: _listKey,
    scopeId: '${_mailbox?.id.value}:$_offset',
    strings: widget.strings.mailMessageListStrings,
    selectedId: _selected?.id.value,
    busy: _viewBusy || _bodyBusy || _downloading || !_current,
    items: [
      for (final header in _view?.headers ?? const <MailHeaderRecord>[])
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
              .map((address) => address.displayName ?? address.address)
              .join(', '),
          to: header.envelope.to.map((address) => address.address).join(', '),
          cc: header.envelope.cc.map((address) => address.address).join(', '),
          date: header.envelope.sentAt,
          dateLabel: studioMailListDate(
            header.envelope.sentAt,
            widget.strings.language,
          ),
          isRead: header.flags?.isRead,
          isFlagged: header.flags?.isFlagged,
        ),
    ],
    onOpen: (id) => unawaited(_work(() => _openMessage(id))),
  );

  Widget _message() {
    if (_reader case final reader?) return MailMessageView(controller: reader);
    return Center(
      // This is host status/recovery chrome, not the document reader. Keep its
      // action reachable with long translations and enlarged system text.
      child: SingleChildScrollView(
        key: const ValueKey('studio-mail-sync-message-status-scroll'),
        primary: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _missingBody
                    ? widget.strings.mailSyncMissingBody
                    : _bodyBusy
                    ? widget.strings.mailMessageListStrings.loading
                    : _error ?? widget.strings.mailSyncChooseMessage,
                key: const ValueKey('studio-mail-sync-message-state'),
              ),
              if (_missingBody && widget.download != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('studio-mail-download-message'),
                  onPressed: !_current || _working || _bodyBusy || _viewFailed
                      ? null
                      : () => unawaited(
                          _work(() => _download(selectedOnly: true)),
                        ),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: Text(widget.strings.mailDownloadMessage),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _workspace(bool compact) {
    if (!compact) {
      return Row(
        children: [
          SizedBox(width: 340, child: _messages()),
          const VerticalDivider(width: 1),
          Expanded(child: _message()),
        ],
      );
    }
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
                  key: const ValueKey('studio-mail-sync-back'),
                  onPressed: _closing
                      ? null
                      : () => setState(() => _showMessage = false),
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

  Widget _status() {
    final view = _view;
    final progress = _progress;
    final reportText = _reportText;
    final downloadProgress = _downloadProgress;
    final downloadReportText = _downloadReportText;
    final error =
        _error ??
        (_catalogFailed || _viewFailed
            ? widget.strings.mailSyncReadFailed
            : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (view != null) ...[
          Text(widget.strings.mailSyncSaved(view.updatedAt, view.headerCount)),
          Text(
            view.hasMore
                ? widget.strings.mailSyncPartial
                : widget.strings.mailSyncComplete,
            key: const ValueKey('studio-mail-sync-checkpoint'),
          ),
        ] else if (_mailbox != null && !_viewBusy)
          Text(widget.strings.mailSyncNotStarted),
        if (progress != null)
          Text(
            widget.strings.mailSyncProgress(
              progress.committedPages,
              progress.upsertCount,
            ),
            key: const ValueKey('studio-mail-sync-progress'),
          ),
        if (reportText != null)
          Text(reportText, key: const ValueKey('studio-mail-sync-result')),
        if (downloadProgress != null)
          Text(
            widget.strings.mailDownloadProgress(
              downloadProgress.downloaded,
              downloadProgress.alreadyCached,
              downloadProgress.remaining,
            ),
            key: const ValueKey('studio-mail-download-progress'),
          ),
        if (downloadReportText != null)
          Text(
            downloadReportText,
            key: const ValueKey('studio-mail-download-result'),
          ),
        if (error != null)
          Text(
            error,
            key: const ValueKey('studio-mail-sync-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                        widget.strings.mailSync,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('studio-mail-sync-close'),
                      tooltip: _closeInProgress
                          ? widget.strings.mailSyncClosing
                          : widget.strings.close,
                      onPressed: _closeInProgress ? null : _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              // Only host chrome scrolls here. Message content remains in the
              // shared RenderBox reader, with room preserved at narrow widths.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.42,
                ),
                child: SingleChildScrollView(
                  key: const ValueKey('studio-mail-sync-details'),
                  primary: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _connected
                            ? Text(
                                widget.mailbox!.displayName,
                                style: Theme.of(context).textTheme.titleMedium,
                              )
                            : DropdownButton<MailMailboxId>(
                                key: const ValueKey('studio-mail-sync-folders'),
                                isExpanded: true,
                                value:
                                    _folders.any(
                                      (folder) =>
                                          folder.mailbox.id == _mailbox?.id,
                                    )
                                    ? _mailbox?.id
                                    : null,
                                hint: Text(widget.strings.mailSyncEmpty),
                                items: [
                                  for (final folder in _folders)
                                    DropdownMenuItem(
                                      value: folder.mailbox.id,
                                      child: Text(
                                        folder.mailbox.displayName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: !_current || _viewBusy || _bodyBusy
                                    ? null
                                    : (id) {
                                        final folder = _folders
                                            .where(
                                              (item) => item.mailbox.id == id,
                                            )
                                            .firstOrNull;
                                        if (folder != null) {
                                          unawaited(
                                            _work(
                                              () => _selectMailbox(
                                                folder.mailbox,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: _status(),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(widget.strings.mailSyncScope),
                      ),
                      if (widget.download != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text(widget.strings.mailDownloadScope),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          _connected
                              ? widget.strings.mailSyncForeground
                              : widget.strings.mailSyncOffline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_connected)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _working
                        ? OutlinedButton.icon(
                            key: const ValueKey('studio-mail-sync-stop'),
                            onPressed: !_current || _stopping ? null : _stop,
                            icon: const Icon(Icons.stop),
                            label: Text(
                              _stopping
                                  ? widget.strings.mailSyncStopping
                                  : widget.strings.mailSyncStop,
                            ),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                key: const ValueKey('studio-mail-sync-start'),
                                onPressed: !_current || _viewBusy
                                    ? null
                                    : () => unawaited(_work(_start)),
                                icon: const Icon(Icons.sync),
                                label: Text(
                                  _view == null
                                      ? widget.strings.mailSyncStart
                                      : _view!.hasMore
                                      ? widget.strings.mailSyncContinue
                                      : widget.strings.mailSyncCheckChanges,
                                ),
                              ),
                              if (widget.download != null)
                                OutlinedButton.icon(
                                  key: const ValueKey(
                                    'studio-mail-download-page',
                                  ),
                                  onPressed:
                                      !_current ||
                                          _viewBusy ||
                                          _bodyBusy ||
                                          _viewFailed ||
                                          (_view?.headers.isEmpty ?? true)
                                      ? null
                                      : () => unawaited(_work(_download)),
                                  icon: const Icon(
                                    Icons.download_for_offline_outlined,
                                  ),
                                  label: Text(widget.strings.mailDownloadPage),
                                ),
                            ],
                          ),
                  ),
                ),
              if (_catalogBusy || _viewBusy || _working || _closeInProgress)
                const LinearProgressIndicator(minHeight: 2)
              else
                const Divider(height: 2),
              Expanded(child: _workspace(constraints.maxWidth < 760)),
              if (_view case final view?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    children: [
                      IconButton(
                        key: const ValueKey('studio-mail-sync-previous'),
                        tooltip: widget.strings.mailSyncPrevious,
                        onPressed:
                            !_current || _viewBusy || _working || _offset == 0
                            ? null
                            : () => unawaited(
                                _work(
                                  () => _loadPage(
                                    (_offset - _pageSize).clamp(0, _offset),
                                  ),
                                ),
                              ),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          widget.strings.mailSyncPage(
                            view.headers.isEmpty ? 0 : view.offset + 1,
                            view.offset + view.headers.length,
                            view.headerCount,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('studio-mail-sync-next'),
                        tooltip: widget.strings.mailSyncNext,
                        onPressed:
                            !_current ||
                                _viewBusy ||
                                _working ||
                                !view.hasMoreHeaders
                            ? null
                            : () => unawaited(
                                _work(() => _loadPage(_offset + _pageSize)),
                              ),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
