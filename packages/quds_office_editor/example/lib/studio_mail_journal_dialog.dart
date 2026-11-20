import 'package:flutter/material.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_bulk_status.dart';
import 'studio_mail_flag_journal.dart';
import 'studio_mail_journal_strings.dart';
import 'studio_strings.dart';

/// Read-only durable receipts. No provider, credentials, replay or body fetch.
class StudioMailJournalDialog extends StatefulWidget {
  const StudioMailJournalDialog({
    super.key,
    required this.strings,
    required this.store,
    required this.isCurrent,
  });

  final StudioStrings strings;
  final StudioMailFlagJournalStore store;
  final bool Function() isCurrent;

  @override
  State<StudioMailJournalDialog> createState() =>
      _StudioMailJournalDialogState();
}

class _StudioMailJournalDialogState extends State<StudioMailJournalDialog> {
  List<MailStoredFlagBatchSummary> _batches = const [];
  MailStoredFlagBatch? _selected;
  int? _nextOffset;
  bool _busy = true;
  String? _error;
  int _generation = 0;

  bool _current(int generation) =>
      mounted && generation == _generation && widget.isCurrent();

  @override
  void initState() {
    super.initState();
    _load();
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
      if (receipt == null ||
          receipt.summary.id != summary.id ||
          receipt.summary.mailbox.account != widget.store.account ||
          receipt.report.plan.mailbox.account != widget.store.account ||
          receipt.subjects.length != receipt.report.items.length) {
        throw StateError('Invalid activity receipt');
      }
      setState(() => _selected = receipt);
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
    return Dialog(
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
                    onPressed: () => Navigator.pop(context),
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
                        subjects: {
                          for (var i = 0; i < selected.subjects.length; i++)
                            selected.report.items[i].message:
                                selected.subjects[i],
                        },
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
                            batch.requiresRefresh || batch.interrupted
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
    );
  }
}
