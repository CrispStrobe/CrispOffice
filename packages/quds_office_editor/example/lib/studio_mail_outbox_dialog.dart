import 'dart:convert';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_outbox.dart';
import 'studio_mail_draft.dart';
import 'studio_mail_outbox_export.dart';
import 'studio_mail_outbox_review.dart';
import 'studio_mail_outbox_strings.dart';
import 'studio_strings.dart';

/// A local, account-scoped foreground queue. Opening or refreshing never sends.
class StudioMailOutboxDialog extends StatefulWidget {
  const StudioMailOutboxDialog({
    super.key,
    required this.strings,
    required this.store,
    required this.submit,
    required this.isCurrent,
    this.exporter = exportStudioMailOutboxFile,
  });

  final StudioStrings strings;
  final StudioMailOutboxStore store;
  final StudioMailOutboxSubmit submit;
  final bool Function() isCurrent;
  final StudioMailOutboxExporter exporter;

  @override
  State<StudioMailOutboxDialog> createState() => _StudioMailOutboxDialogState();
}

class _StudioMailOutboxDialogState extends State<StudioMailOutboxDialog> {
  List<MailOutboxEntry> _entries = const [];
  bool _busy = true;
  String? _error;

  StudioMailOutboxManagementStore? get _management => switch (widget.store) {
    StudioMailOutboxManagementStore value => value,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!widget.isCurrent()) {
      setState(() {
        _busy = false;
        _error = widget.strings.mailOutboxFailed;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entries = await widget.store.loadOutbox();
      if (mounted && widget.isCurrent()) {
        setState(() => _entries = entries.reversed.toList());
      }
    } on Object {
      if (mounted) setState(() => _error = widget.strings.mailOutboxFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(
    String title,
    String explanation, {
    bool acknowledge = false,
  }) async {
    var checked = false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(explanation),
                  if (acknowledge)
                    CheckboxListTile(
                      key: const ValueKey('studio-mail-outbox-acknowledge'),
                      value: checked,
                      onChanged: (value) =>
                          setDialogState(() => checked = value ?? false),
                      title: Text(widget.strings.mailOutboxAcknowledgement),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(widget.strings.cancel),
                ),
                FilledButton(
                  key: const ValueKey('studio-mail-outbox-confirm'),
                  onPressed: acknowledge && !checked
                      ? null
                      : () => Navigator.pop(context, true),
                  child: Text(title),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !widget.isCurrent()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) setState(() => _error = widget.strings.mailOutboxFailed);
    } finally {
      // A failed result commit is recovered conservatively on this refresh.
      if (mounted && widget.isCurrent()) {
        try {
          final entries = await widget.store.loadOutbox();
          if (mounted && widget.isCurrent()) {
            setState(() => _entries = entries.reversed.toList());
          }
        } on Object {
          if (mounted) setState(() => _error = widget.strings.mailOutboxFailed);
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(MailOutboxEntry entry) => _run(() async {
    final acknowledge = entry.canBeginAcknowledgedAttempt;
    if (acknowledge &&
        !await _confirm(
          widget.strings.mailOutboxCheckRetry,
          widget.strings.mailOutboxUncertainExplanation,
          acknowledge: true,
        )) {
      return;
    }
    if (!widget.isCurrent()) return;
    await submitStudioMailOutbox(
      store: widget.store,
      entry: entry,
      submit: widget.submit,
      isCurrent: widget.isCurrent,
      acknowledgeUncertain: acknowledge,
      onAttemptPersisted: (attempt) {
        if (mounted && widget.isCurrent()) {
          setState(
            () => _entries = [
              for (final item in _entries)
                if (item.id == attempt.id) attempt else item,
            ],
          );
        }
      },
    );
  });

  Future<void> _cancel(MailOutboxEntry entry) => _run(() async {
    if (await _confirm(
          widget.strings.mailOutboxCancel,
          widget.strings.mailOutboxCancelExplanation,
        ) &&
        widget.isCurrent()) {
      await widget.store.cancelOutbox(entry);
    }
  });

  Future<void> _remove(MailOutboxEntry entry) => _run(() async {
    if (await _confirm(
          widget.strings.mailOutboxRemove,
          entry.state == MailOutboxState.closedUncertain
              ? widget.strings.mailOutboxRemoveUnknownExplanation
              : widget.strings.mailOutboxRemoveExplanation,
        ) &&
        widget.isCurrent()) {
      await widget.store.removeOutbox(entry);
    }
  });

  Future<void> _review(MailOutboxEntry entry) => _run(() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StudioMailOutboxReviewDialog(
        entry: entry,
        strings: widget.strings,
        isCurrent: () => mounted && widget.isCurrent(),
        exporter: widget.exporter,
      ),
    );
  });

  Future<void> _edit(MailOutboxEntry entry) => _run(() async {
    final management = _management;
    if (management == null || !entry.canCancel) return;
    if (!await _confirm(
          widget.strings.mailOutboxEdit,
          widget.strings.mailOutboxEditExplanation,
        ) ||
        !mounted ||
        !widget.isCurrent()) {
      return;
    }
    final draft = await management.editOutboxAsDraft(entry);
    if (mounted && widget.isCurrent()) {
      // The same owner has selected the newly saved draft. Return that exact
      // snapshot so the host never reuses its previous selected-draft content.
      Navigator.pop<StudioMailDraft>(context, draft);
    }
  });

  Future<void> _closeUncertain(MailOutboxEntry entry) => _run(() async {
    final management = _management;
    if (management == null || !entry.canCloseUncertain) return;
    if (await _confirm(
          widget.strings.mailOutboxStopRetrying,
          widget.strings.mailOutboxStopRetryingExplanation,
        ) &&
        mounted &&
        widget.isCurrent()) {
      await management.closeUncertainOutbox(entry);
    }
  });

  // Only bounded local headers are decoded for the list. No body, attachment or
  // remote resource is rendered, and the envelope comes from frozen transport.
  String _subject(MailOutboxEntry entry) {
    final bytes = entry.prepared.wire.bytes;
    final limit = bytes.length < 65536 ? bytes.length : 65536;
    for (var i = 0; i + 3 < limit; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        try {
          final header = ascii.decode(bytes.sublist(0, i + 4));
          final subject = mail.MimeMessage.parseFromText(
            header,
          ).decodeSubject();
          if (subject != null && subject.isNotEmpty) return subject;
        } on Object {
          break;
        }
        break;
      }
    }
    return widget.strings.mailOutboxNoSubject;
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        child: SizedBox(
          width: 760,
          height: 620,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.mailOutbox,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: strings.refresh,
                      onPressed: _busy ? null : _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: strings.close,
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(strings.mailOutboxExplanation),
                const SizedBox(height: 12),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Expanded(
                  child: _entries.isEmpty
                      ? Center(
                          child: Text(_busy ? '' : strings.mailOutboxEmpty),
                        )
                      : ListView.builder(
                          itemCount: _entries.length,
                          itemBuilder: (context, index) {
                            final entry = _entries[index];
                            return Card(
                              key: ValueKey('studio-mail-outbox-${entry.id}'),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      _subject(entry),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(strings.mailOutboxState(entry.state)),
                                    Text(
                                      '${entry.prepared.envelope.sender} · ${strings.mailOutboxAttempt(entry.attemptNumber)}',
                                      textDirection: TextDirection.ltr,
                                    ),
                                    ExpansionTile(
                                      title: Text(strings.mailOutboxRecipients),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Text(
                                            entry.prepared.envelope.recipients
                                                .join(', '),
                                            textDirection: TextDirection.ltr,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (entry.state ==
                                        MailOutboxState.closedUncertain)
                                      Text(strings.mailOutboxClosedExplanation)
                                    else if (entry.priorSubmissionUncertain ||
                                        entry.state ==
                                            MailOutboxState.uncertain)
                                      Text(
                                        strings.mailOutboxUncertainExplanation,
                                      ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        TextButton.icon(
                                          key: ValueKey(
                                            'studio-mail-outbox-review-${entry.id}',
                                          ),
                                          onPressed: _busy
                                              ? null
                                              : () => _review(entry),
                                          icon: const Icon(
                                            Icons.preview_outlined,
                                          ),
                                          label: Text(
                                            strings.mailOutboxPreview,
                                          ),
                                        ),
                                        if (entry.canBeginAttempt ||
                                            entry.canBeginAcknowledgedAttempt)
                                          FilledButton.icon(
                                            key: ValueKey(
                                              'studio-mail-outbox-send-${entry.id}',
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () => _send(entry),
                                            icon: const Icon(
                                              Icons.send_outlined,
                                            ),
                                            label: Text(
                                              entry.canBeginAcknowledgedAttempt
                                                  ? strings.mailOutboxCheckRetry
                                                  : entry.attemptNumber == 0
                                                  ? strings.mailOutboxSend
                                                  : strings.mailOutboxRetry,
                                            ),
                                          ),
                                        if (entry.canCancel)
                                          TextButton(
                                            key: ValueKey(
                                              'studio-mail-outbox-cancel-${entry.id}',
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () => _cancel(entry),
                                            child: Text(
                                              strings.mailOutboxCancel,
                                            ),
                                          ),
                                        if (_management != null &&
                                            entry.canCancel)
                                          TextButton.icon(
                                            key: ValueKey(
                                              'studio-mail-outbox-edit-${entry.id}',
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () => _edit(entry),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                            label: Text(strings.mailOutboxEdit),
                                          ),
                                        if (_management != null &&
                                            entry.canCloseUncertain)
                                          TextButton(
                                            key: ValueKey(
                                              'studio-mail-outbox-stop-${entry.id}',
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () => _closeUncertain(entry),
                                            child: Text(
                                              strings.mailOutboxStopRetrying,
                                            ),
                                          ),
                                        if (entry.canRemove)
                                          TextButton(
                                            key: ValueKey(
                                              'studio-mail-outbox-remove-${entry.id}',
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () => _remove(entry),
                                            child: Text(
                                              strings.mailOutboxRemove,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
