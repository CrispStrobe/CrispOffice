import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_bulk_status.dart';
import 'studio_mail_flag_journal.dart';
import 'studio_mail_journal_strings.dart';
import 'studio_strings.dart';

/// Durable receipts with an optional explicit, read-only server status check.
/// Cached hosts omit recovery; opening history never contacts a provider.
class StudioMailJournalDialog extends StatefulWidget {
  const StudioMailJournalDialog({
    super.key,
    required this.strings,
    required this.store,
    required this.isCurrent,
    this.onReconcile,
  });

  final StudioStrings strings;
  final StudioMailFlagJournalStore store;
  final bool Function() isCurrent;
  final StudioMailReconcileFlagBatch? onReconcile;

  @override
  State<StudioMailJournalDialog> createState() =>
      _StudioMailJournalDialogState();
}

class _StudioMailJournalDialogState extends State<StudioMailJournalDialog> {
  List<MailStoredFlagBatchSummary> _batches = const [];
  MailStoredFlagBatch? _selected;
  int? _nextOffset;
  bool _busy = true;
  bool _checking = false;
  MailCancellationSource? _checkCancellation;
  String? _error;
  int _generation = 0;

  bool _current(int generation) =>
      mounted && generation == _generation && widget.isCurrent();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _checkCancellation?.cancel(MailCancellationReason.disposed);
    super.dispose();
  }

  void _close() {
    _checkCancellation?.cancel(MailCancellationReason.disposed);
    _generation++;
    Navigator.pop(context);
  }

  bool _validReceipt(MailStoredFlagBatch receipt, String id) =>
      receipt.summary.id == id &&
      receipt.report.plan.id == id &&
      receipt.summary.mailbox.account == widget.store.account &&
      receipt.report.plan.mailbox == receipt.summary.mailbox &&
      receipt.report.plan.provider == receipt.summary.provider &&
      receipt.subjects.length == receipt.report.items.length &&
      receipt.summary.reconciledCount == receipt.resolutions.length &&
      receipt.summary.unresolvedCount >= 0 &&
      receipt.resolutions
              .map((resolution) => resolution.index)
              .toSet()
              .length ==
          receipt.resolutions.length &&
      receipt.resolutions.every(
        (resolution) =>
            resolution.index >= 0 &&
            resolution.index < receipt.report.items.length &&
            receipt.report.items[resolution.index].outcome ==
                MailBulkFlagOutcome.uncertain,
      );

  void _acceptReceipt(MailStoredFlagBatch receipt) {
    _selected = receipt;
    _batches = [
      for (final batch in _batches)
        batch.id == receipt.summary.id ? receipt.summary : batch,
    ];
  }

  Future<void> _checkStatus() async {
    final selected = _selected;
    final reconcile = widget.onReconcile;
    if (_busy ||
        selected == null ||
        reconcile == null ||
        !selected.summary.complete ||
        selected.summary.unresolvedCount == 0 ||
        !widget.isCurrent()) {
      return;
    }
    final generation = ++_generation;
    final cancellation = MailCancellationSource();
    _checkCancellation = cancellation;
    setState(() {
      _busy = _checking = true;
      _error = null;
    });
    try {
      final receipt = await reconcile(
        selected,
        cancellation.token,
        () => _current(generation),
      );
      if (!_current(generation)) return;
      if (!_validReceipt(receipt, selected.summary.id)) {
        throw const StudioMailFlagJournalException(MailProblemCode.conflict);
      }
      setState(() => _acceptReceipt(receipt));
    } on Object catch (error) {
      if (!_current(generation)) return;
      // Earlier observations may have committed before a later check failed.
      // Reload only local history, without starting another provider request.
      try {
        final receipt = await widget.store.load(selected.summary.id);
        if (!_current(generation)) return;
        if (receipt != null && _validReceipt(receipt, selected.summary.id)) {
          setState(() => _acceptReceipt(receipt));
        }
      } on Object {
        // Preserve the last verified receipt and the original typed failure.
      }
      if (_current(generation)) {
        setState(() {
          _error = widget.strings.mailActivityCheckFailed(
            error is StudioMailFlagJournalException
                ? error.code
                : MailProblemCode.providerFailure,
          );
        });
      }
    } finally {
      if (_current(generation)) {
        setState(() {
          _busy = _checking = false;
          _checkCancellation = null;
        });
      }
    }
  }

  Future<void> _load({int offset = 0}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!widget.isCurrent()) throw StateError('Retired activity view');
      final page = await widget.store.list(limit: 20, offset: offset);
      if (!_current(generation)) return;
      if (page.batches.any(
        (item) => item.mailbox.account != widget.store.account,
      )) {
        throw StateError('Mismatched activity account');
      }
      setState(() {
        final combined = offset == 0
            ? page.batches
            : [..._batches, ...page.batches];
        // Concurrent appends can shift an offset; never show one receipt twice.
        _batches = {for (final item in combined) item.id: item}.values.toList();
        _nextOffset = page.nextOffset;
      });
    } on Object {
      if (_current(generation)) {
        setState(() => _error = widget.strings.mailActivityFailed);
      }
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  Future<void> _open(MailStoredFlagBatchSummary summary) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!widget.isCurrent()) throw StateError('Retired activity view');
      final receipt = await widget.store.load(summary.id);
      if (!_current(generation)) return;
      if (receipt == null || !_validReceipt(receipt, summary.id)) {
        throw StateError('Invalid activity receipt');
      }
      setState(() => _acceptReceipt(receipt));
    } on Object {
      if (_current(generation)) {
        setState(() => _error = widget.strings.mailActivityFailed);
      }
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(widget.strings.mailActivityClear),
          content: Text(widget.strings.mailActivityClearQuestion),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(widget.strings.cancel),
            ),
            FilledButton(
              key: const ValueKey('studio-mail-activity-confirm-clear'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.strings.mailActivityClear),
            ),
          ],
        ),
      );
      if (!_current(generation) || confirmed != true) return;
      await widget.store.clearCompleted();
      if (!_current(generation)) return;
      await _load();
    } on Object {
      if (_current(generation)) {
        setState(() => _error = widget.strings.mailActivityFailed);
      }
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  String _date(DateTime date) {
    final local = date.toLocal();
    final strings = MaterialLocalizations.of(context);
    return '${strings.formatShortDate(local)} ${strings.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _checkCancellation?.cancel(MailCancellationReason.disposed);
        }
      },
      child: Dialog(
        key: const ValueKey('studio-mail-activity-dialog'),
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 680,
          height: 600,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
                child: Row(
                  children: [
                    if (selected != null)
                      IconButton(
                        key: const ValueKey('studio-mail-activity-back'),
                        tooltip: widget.strings.mailActivityBack,
                        onPressed: _busy
                            ? null
                            : () => setState(() => _selected = null),
                        icon: const BackButtonIcon(),
                      ),
                    Expanded(
                      child: Text(
                        widget.strings.mailActivity,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('studio-mail-activity-close'),
                      tooltip: widget.strings.close,
                      onPressed: _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('studio-mail-activity-scroll'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(widget.strings.mailActivityScope),
                      ),
                      if (_error case final error?)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            error,
                            key: const ValueKey('studio-mail-activity-error'),
                          ),
                        ),
                      if (selected != null) ...[
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_date(selected.summary.createdAt)),
                        ),
                        if (selected.summary.interrupted ||
                            !selected.summary.complete)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              selected.summary.interrupted
                                  ? widget.strings.mailActivityInterrupted
                                  : widget.strings.mailActivityRunning,
                            ),
                          ),
                        StudioMailBulkStatus(
                          strings: widget.strings,
                          report: selected.report,
                          running: false,
                          showStop: false,
                          historical: true,
                          subjects: {
                            for (var i = 0; i < selected.subjects.length; i++)
                              selected.report.items[i].message:
                                  selected.subjects[i],
                          },
                        ),
                        if (selected.summary.complete &&
                            selected.summary.uncertainCount != 0)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  widget.strings.mailActivityObservationScope,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  widget.strings.mailActivityCheckedCounts(
                                    selected.summary,
                                  ),
                                  key: const ValueKey(
                                    'studio-mail-activity-checked-counts',
                                  ),
                                ),
                                for (final resolution in selected.resolutions)
                                  Card(
                                    key: ValueKey(
                                      'studio-mail-activity-observation-${resolution.index}',
                                    ),
                                    margin: const EdgeInsets.only(top: 12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            selected
                                                    .subjects[resolution.index]
                                                    .isEmpty
                                                ? widget
                                                      .strings
                                                      .mailActivityNoSubject
                                                : selected.subjects[resolution
                                                      .index],
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            widget.strings.mailActivityObserved(
                                              resolution.kind,
                                              selected.summary.action,
                                            ),
                                          ),
                                          Text(
                                            widget.strings
                                                .mailActivityCheckedAt(
                                                  _date(resolution.checkedAt),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (selected.summary.unresolvedCount > 0) ...[
                                  const SizedBox(height: 12),
                                  if (widget.onReconcile == null)
                                    Text(
                                      widget.strings.mailActivityReconnect,
                                      key: const ValueKey(
                                        'studio-mail-activity-reconnect',
                                      ),
                                    )
                                  else
                                    Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: FilledButton.icon(
                                        key: const ValueKey(
                                          'studio-mail-activity-check',
                                        ),
                                        onPressed: _busy || !widget.isCurrent()
                                            ? null
                                            : _checkStatus,
                                        icon: const Icon(
                                          Icons.fact_check_outlined,
                                        ),
                                        label: Text(
                                          widget.strings.mailActivityCheck,
                                        ),
                                      ),
                                    ),
                                ],
                                if (_checking)
                                  Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TextButton(
                                      key: const ValueKey(
                                        'studio-mail-activity-stop-check',
                                      ),
                                      onPressed: () {
                                        _checkCancellation?.cancel();
                                      },
                                      child: Text(
                                        widget.strings.mailActivityStopCheck,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ] else ...[
                        if (!_busy && _batches.isEmpty && _error == null)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(widget.strings.mailActivityEmpty),
                          ),
                        for (final batch in _batches)
                          ListTile(
                            key: ValueKey('studio-mail-activity-${batch.id}'),
                            leading: Icon(
                              batch.unresolvedCount > 0 || !batch.complete
                                  ? Icons.help_outline
                                  : Icons.receipt_long_outlined,
                            ),
                            title: Text(
                              widget.strings.mailActivityAction(batch.action),
                            ),
                            subtitle: Text(
                              '${_date(batch.createdAt)}\n${widget.strings.mailActivityCounts(batch)}',
                            ),
                            onTap: _busy || !widget.isCurrent()
                                ? null
                                : () => _open(batch),
                          ),
                        if (_nextOffset case final offset?)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: TextButton(
                              key: const ValueKey('studio-mail-activity-more'),
                              onPressed: _busy
                                  ? null
                                  : () => _load(offset: offset),
                              child: Text(widget.strings.mailActivityMore),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              if (selected == null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        key: const ValueKey('studio-mail-activity-refresh'),
                        onPressed: _busy || !widget.isCurrent()
                            ? null
                            : () => _load(),
                        child: Text(widget.strings.refresh),
                      ),
                      TextButton(
                        key: const ValueKey('studio-mail-activity-clear'),
                        onPressed:
                            _busy || _batches.isEmpty || !widget.isCurrent()
                            ? null
                            : _clear,
                        child: Text(widget.strings.mailActivityClear),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
