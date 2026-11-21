import 'dart:async';
import 'dart:convert';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_outbox.dart';
import 'studio_mail_draft.dart';
import 'studio_mail_outbox_export.dart';
import 'studio_mail_outbox_review.dart';
import 'studio_mail_outbox_strings.dart';
import 'studio_mail_outbox_schedule_session.dart';
import 'studio_mail_schedule_dialog.dart';
import 'studio_mail_schedule_strings.dart';
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
    this.clock,
    this.elapsed,
  });

  final StudioStrings strings;
  final StudioMailOutboxStore store;
  final StudioMailOutboxSubmit submit;
  final bool Function() isCurrent;
  final StudioMailOutboxExporter exporter;
  final DateTime Function()? clock;
  final Duration Function()? elapsed;

  @override
  State<StudioMailOutboxDialog> createState() => _StudioMailOutboxDialogState();
}

class _StudioMailOutboxDialogState extends State<StudioMailOutboxDialog>
    with WidgetsBindingObserver {
  List<MailOutboxEntry> _entries = const [];
  bool _busy = true;
  String? _error;
  final Stopwatch _stopwatch = Stopwatch();
  late final StudioMailOutboxScheduleSession _scheduleSession;
  Timer? _scheduleTimer;
  int _permissionGeneration = 0;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  StudioMailOutboxSchedulingStore? get _scheduling => switch (widget.store) {
    StudioMailOutboxSchedulingStore value => value,
    _ => null,
  };

  StudioMailOutboxManagementStore? get _management => switch (widget.store) {
    StudioMailOutboxManagementStore value => value,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _scheduleSession = StudioMailOutboxScheduleSession(
      clock: () => _now,
      elapsed: () => widget.elapsed?.call() ?? _stopwatch.elapsed,
    );
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseSchedules();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _pauseSchedules();
      if (mounted) setState(() {});
    }
  }

  @override
  void didUpdateWidget(StudioMailOutboxDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) _pauseSchedules();
  }

  void _pauseSchedules() {
    _permissionGeneration++;
    _scheduleSession.pauseAll();
    _scheduleTimer?.cancel();
  }

  bool get _foreground {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  void _arm(
    MailOutboxEntry entry, {
    required int permissionGeneration,
    Duration minimumWait = Duration.zero,
  }) {
    if (!mounted ||
        _busy ||
        _error != null ||
        !widget.isCurrent() ||
        !_foreground ||
        permissionGeneration != _permissionGeneration) {
      return;
    }
    _scheduleSession.arm(entry, minimumWait: minimumWait);
    _scheduleSession.reconcile(_entries);
    if (_scheduleSession.isEmpty) return;
    _scheduleTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tick(),
    );
    if (!_scheduleTimer!.isActive) {
      _scheduleTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _tick(),
      );
    }
    setState(() {});
  }

  void _tick() {
    if (!mounted) return;
    if (!widget.isCurrent() || !_foreground) _pauseSchedules();
    if (_scheduleSession.isEmpty) {
      _scheduleTimer?.cancel();
      setState(() {});
      return;
    }
    if (_busy) return;
    final due = _scheduleSession.takeDue(_entries);
    setState(() {});
    if (due != null) unawaited(_send(due, fromSchedule: true));
  }

  void _replaceEntries(List<MailOutboxEntry> entries) {
    _entries = entries.reversed.toList();
    _scheduleSession.reconcile(_entries);
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
        setState(() => _replaceEntries(entries));
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
            setState(() => _replaceEntries(entries));
          }
        } on Object {
          if (mounted) setState(() => _error = widget.strings.mailOutboxFailed);
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(MailOutboxEntry entry, {bool fromSchedule = false}) =>
      _run(() async {
        final permissionGeneration = _permissionGeneration;
        final owner = widget.store;
        final isCurrentOwner = widget.isCurrent;
        var ready = entry;
        if (!fromSchedule && entry.canSchedule && entry.sendNotBefore != null) {
          final scheduling = _scheduling;
          if (scheduling == null ||
              !await _confirm(
                widget.strings.mailOutboxSend,
                widget.strings.mailScheduleSendNowExplanation,
              ) ||
              !mounted ||
              !widget.isCurrent()) {
            return;
          }
          _scheduleSession.pause(entry);
          ready = await scheduling.scheduleOutbox(entry, sendNotBefore: null);
        }
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
          entry: ready,
          submit: widget.submit,
          isCurrent: () =>
              mounted &&
              identical(widget.store, owner) &&
              isCurrentOwner() &&
              (!fromSchedule ||
                  (_foreground &&
                      permissionGeneration == _permissionGeneration &&
                      ready.isDueAt(_now))),
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

  Future<void> _schedule(
    MailOutboxEntry entry, {
    bool undoWindow = false,
  }) async {
    final permissionGeneration = _permissionGeneration;
    MailOutboxEntry? saved;
    await _run(() async {
      final scheduling = _scheduling;
      if (scheduling == null || !entry.canSchedule) return;
      DateTime? deadline;
      if (undoWindow) {
        deadline = _now.add(const Duration(seconds: 10));
      } else {
        deadline = await showDialog<DateTime>(
          context: context,
          builder: (_) => StudioMailScheduleDialog(
            strings: widget.strings,
            isCurrent: () => mounted && widget.isCurrent(),
            initial: entry.sendNotBefore,
            clock: () => _now,
          ),
        );
      }
      if (deadline == null || !mounted || !widget.isCurrent()) return;
      _scheduleSession.pause(entry);
      saved = await scheduling.scheduleOutbox(entry, sendNotBefore: deadline);
    });
    // Start only after save AND readback finish, when Undo is usable. A slow
    // refresh cannot consume the advertised window, and a hide/resume cycle
    // during either await cannot silently restore foreground permission.
    if (saved case final entry?) {
      _arm(
        entry,
        permissionGeneration: permissionGeneration,
        minimumWait: undoWindow ? const Duration(seconds: 10) : Duration.zero,
      );
    }
  }

  Future<void> _resume(MailOutboxEntry entry) async {
    final permissionGeneration = _permissionGeneration;
    MailOutboxEntry? saved;
    await _run(() async {
      if (!await _confirm(
            widget.strings.mailScheduleResume,
            widget.strings.mailScheduleExplanation,
          ) ||
          !mounted ||
          !widget.isCurrent()) {
        return;
      }
      // A fresh read prevents resuming stale timing after another window edits it.
      final current = await widget.store.loadOutbox();
      for (final candidate in current) {
        if (candidate.id == entry.id &&
            candidate.prepared.account == entry.prepared.account &&
            candidate.scheduleRevision == entry.scheduleRevision &&
            candidate.sendNotBefore == entry.sendNotBefore &&
            candidate.canSchedule) {
          saved = candidate;
        }
      }
      if (saved == null) throw StateError('The saved schedule changed.');
    });
    if (saved case final entry?) {
      _arm(entry, permissionGeneration: permissionGeneration);
    }
  }

  Future<void> _undoSchedule(MailOutboxEntry entry) => _run(() async {
    final scheduling = _scheduling;
    if (scheduling == null) return;
    // Pause before storage: a failed cancellation cannot trigger a send while
    // the user is trying to stop it. The saved entry remains reviewable.
    _scheduleSession.pause(entry);
    await scheduling.scheduleOutbox(entry, sendNotBefore: null);
  });

  Widget _scheduleStatus(MailOutboxEntry entry) {
    final strings = widget.strings;
    final active = _scheduleSession.isArmed(entry);
    final remaining = _scheduleSession.remaining(entry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.mailScheduleAt(entry.sendNotBefore!)),
        if (entry.canSchedule)
          Text(
            active
                ? remaining <= const Duration(seconds: 60)
                      ? strings.mailScheduleCountdown(remaining)
                      : strings.mailScheduleActive
                : strings.mailSchedulePaused,
          ),
        if (active && remaining <= const Duration(seconds: 10))
          Text(strings.mailScheduleUndoExplanation),
      ],
    );
  }

  List<Widget> _scheduleActions(MailOutboxEntry entry) {
    if (_scheduling == null || !entry.canSchedule) return const [];
    final strings = widget.strings;
    final active = _scheduleSession.isArmed(entry);
    return [
      if (entry.sendNotBefore == null)
        OutlinedButton.icon(
          key: ValueKey('studio-mail-outbox-delay-${entry.id}'),
          onPressed: _busy ? null : () => _schedule(entry, undoWindow: true),
          icon: const Icon(Icons.undo),
          label: Text(strings.mailSendWithUndo),
        ),
      OutlinedButton.icon(
        key: ValueKey('studio-mail-outbox-schedule-${entry.id}'),
        onPressed: _busy ? null : () => _schedule(entry),
        icon: const Icon(Icons.schedule_send_outlined),
        label: Text(strings.mailSendLater),
      ),
      if (entry.sendNotBefore != null) ...[
        if (active)
          TextButton(
            key: ValueKey('studio-mail-outbox-pause-${entry.id}'),
            onPressed: _busy
                ? null
                : () => setState(() => _scheduleSession.pause(entry)),
            child: Text(strings.mailSchedulePause),
          )
        else
          OutlinedButton(
            key: ValueKey('studio-mail-outbox-resume-${entry.id}'),
            onPressed: _busy ? null : () => _resume(entry),
            child: Text(strings.mailScheduleResume),
          ),
        TextButton(
          key: ValueKey('studio-mail-outbox-undo-${entry.id}'),
          onPressed: _busy ? null : () => _undoSchedule(entry),
          child: Text(strings.mailScheduleUndo),
        ),
      ],
    ];
  }

  Future<void> _cancel(MailOutboxEntry entry) => _run(() async {
    if (await _confirm(
          widget.strings.mailOutboxCancel,
          widget.strings.mailOutboxCancelExplanation,
        ) &&
        widget.isCurrent()) {
      _scheduleSession.pause(entry);
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
    _scheduleSession.pause(entry);
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
                                    if (entry.sendNotBefore == null ||
                                        entry.state != MailOutboxState.queued)
                                      Text(
                                        strings.mailOutboxState(entry.state),
                                      ),
                                    if (entry.sendNotBefore != null)
                                      _scheduleStatus(entry),
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
                                            onPressed:
                                                _busy ||
                                                    (entry.sendNotBefore !=
                                                            null &&
                                                        entry.canSchedule &&
                                                        _scheduling == null)
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
                                        ..._scheduleActions(entry),
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
