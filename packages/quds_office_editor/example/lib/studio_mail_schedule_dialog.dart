import 'package:flutter/material.dart';

import 'studio_mail_schedule_strings.dart';
import 'studio_strings.dart';

/// Picks a local calendar time and returns one fixed UTC instant. The parent
/// persists it before arming any foreground timer.
class StudioMailScheduleDialog extends StatefulWidget {
  const StudioMailScheduleDialog({
    super.key,
    required this.strings,
    required this.isCurrent,
    this.initial,
    this.clock,
  });

  final StudioStrings strings;
  final bool Function() isCurrent;
  final DateTime? initial;
  final DateTime Function()? clock;

  @override
  State<StudioMailScheduleDialog> createState() =>
      _StudioMailScheduleDialogState();
}

class _StudioMailScheduleDialogState extends State<StudioMailScheduleDialog> {
  late DateTime _selected;
  bool _invalid = false;

  DateTime get _now => (widget.clock?.call() ?? DateTime.now()).toLocal();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _selected = initial != null && initial.isAfter(_now)
        ? initial.toLocal()
        : _now.add(const Duration(hours: 1));
  }

  void _select(DateTime value) {
    if (!mounted || !widget.isCurrent()) return;
    setState(() {
      _selected = value;
      _invalid = false;
    });
  }

  void _selectLocal(int year, int month, int day, int hour, int minute) {
    final selected = DateTime(year, month, day, hour, minute);
    // Dart normalizes nonexistent local times during a DST gap. Require the
    // actual chosen calendar fields rather than silently changing the request.
    if (selected.year != year ||
        selected.month != month ||
        selected.day != day ||
        selected.hour != hour ||
        selected.minute != minute) {
      if (mounted) setState(() => _invalid = true);
      return;
    }
    _select(selected);
  }

  Future<void> _date() async {
    final now = _now;
    final first = DateTime(now.year, now.month, now.day);
    final last = DateTime(now.year + 5, 12, 31);
    var initial = _selected;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: widget.strings.mailScheduleDate,
      cancelText: widget.strings.cancel,
      confirmText: widget.strings.mailScheduleDate,
    );
    if (picked == null || !mounted || !widget.isCurrent()) return;
    _selectLocal(
      picked.year,
      picked.month,
      picked.day,
      _selected.hour,
      _selected.minute,
    );
  }

  Future<void> _time() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selected),
      helpText: widget.strings.mailScheduleTime,
      cancelText: widget.strings.cancel,
      confirmText: widget.strings.mailScheduleTime,
    );
    if (picked == null || !mounted || !widget.isCurrent()) return;
    _selectLocal(
      _selected.year,
      _selected.month,
      _selected.day,
      picked.hour,
      picked.minute,
    );
  }

  void _confirm() {
    if (!widget.isCurrent()) return;
    if (_invalid || !_selected.isAfter(_now)) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, _selected.toUtc());
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      title: Text(strings.mailSendLater),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.mailScheduleExplanation),
            const SizedBox(height: 16),
            Text(strings.mailScheduleAt(_selected)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('studio-mail-schedule-date'),
                  onPressed: _date,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(strings.mailScheduleDate),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('studio-mail-schedule-time'),
                  onPressed: _time,
                  icon: const Icon(Icons.access_time),
                  label: Text(strings.mailScheduleTime),
                ),
                TextButton(
                  key: const ValueKey('studio-mail-schedule-hour'),
                  onPressed: () => _select(_now.add(const Duration(hours: 1))),
                  child: Text(strings.mailScheduleInOneHour),
                ),
                TextButton(
                  key: const ValueKey('studio-mail-schedule-tomorrow'),
                  onPressed: () {
                    final now = _now;
                    final tomorrow = DateTime(now.year, now.month, now.day + 1);
                    _selectLocal(
                      tomorrow.year,
                      tomorrow.month,
                      tomorrow.day,
                      9,
                      0,
                    );
                  },
                  child: Text(strings.mailScheduleTomorrow),
                ),
              ],
            ),
            if (_invalid)
              Text(
                strings.mailScheduleChooseFuture,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const ValueKey('studio-mail-schedule-confirm'),
          onPressed: _confirm,
          child: Text(strings.mailScheduleConfirm),
        ),
      ],
    );
  }
}
