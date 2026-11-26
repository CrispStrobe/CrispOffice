import 'package:flutter/material.dart';
import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

import 'studio_calendar_grid.dart';

typedef StudioCalendarSaveFailure = ({String message, bool retryable});

final class StudioCalendarEditor extends StatefulWidget {
  const StudioCalendarEditor({
    super.key,
    required this.initial,
    required this.calendarName,
    required this.save,
    this.event,
  });

  final DateTime initial;
  final String calendarName;
  final Future<StudioCalendarSaveFailure?> Function(CalDavEventFields) save;
  final CalDavEvent? event;

  @override
  State<StudioCalendarEditor> createState() => _StudioCalendarEditorState();
}

final class _StudioCalendarEditorState extends State<StudioCalendarEditor> {
  late final _title = TextEditingController(text: widget.event?.title);
  late final _location = TextEditingController(text: widget.event?.location);
  late final _description = TextEditingController(
    text: widget.event?.description,
  );

  late bool _allDay = widget.event?.start.kind == CalDavDateKind.date;
  late bool _hasEnd = widget.event == null || widget.event!.end != null;
  late DateTime _startDay = _day(_initialStart);
  late TimeOfDay _startTime = TimeOfDay.fromDateTime(_initialStart);
  late DateTime _endDay = _day(
    _initialEnd,
    _allDay && widget.event?.end != null ? -1 : 0,
  );
  late TimeOfDay _endTime = TimeOfDay.fromDateTime(_initialEnd);
  DateTime get _initialStart => widget.event == null
      ? widget.initial
      : studioCalendarDisplayTime(widget.event!.start);
  DateTime get _initialEnd => widget.event?.end == null
      ? _initialStart.add(const Duration(hours: 1))
      : studioCalendarDisplayTime(widget.event!.end!);
  String? _error;
  bool _saving = false;
  bool _saveBlocked = false;

  static DateTime _day(DateTime date, [int offset = 0]) =>
      DateTime(date.year, date.month, date.day + offset);

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDay(bool start) async {
    final current = start ? _startDay : _endDay;
    final first = DateTime(1900);
    final last = DateTime(2200, 12, 31);
    final result = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first)
          ? first
          : current.isAfter(last)
          ? last
          : current,
      firstDate: first,
      lastDate: last,
    );
    if (!mounted || result == null) return;
    setState(() {
      if (start) {
        final shift = DateTime.utc(result.year, result.month, result.day)
            .difference(
              DateTime.utc(_startDay.year, _startDay.month, _startDay.day),
            )
            .inDays;
        _startDay = result;
        _endDay = _day(_endDay, shift);
      } else {
        _endDay = result;
      }
      if (!_saveBlocked) _error = null;
    });
  }

  Future<void> _pickTime(bool start) async {
    final result = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (!mounted || result == null) return;
    setState(() {
      if (start) {
        final minutes =
            result.hour * 60 +
            result.minute -
            (_startTime.hour * 60 + _startTime.minute);
        final shiftedEnd = DateTime.utc(
          _endDay.year,
          _endDay.month,
          _endDay.day,
          _endTime.hour,
          _endTime.minute + minutes,
        );
        _startTime = result;
        _endDay = _day(shiftedEnd);
        _endTime = TimeOfDay.fromDateTime(shiftedEnd);
      } else {
        _endTime = result;
      }
      if (!_saveBlocked) _error = null;
    });
  }

  CalDavDateValue _date(DateTime day, [int offset = 0]) {
    final civil = DateTime.utc(day.year, day.month, day.day + offset);
    return CalDavDateValue.fromTaskDate(
      TaskDate(civil.year, civil.month, civil.day),
    );
  }

  CalDavDateValue _timed(
    DateTime day,
    TimeOfDay time,
    CalDavDateValue? original,
  ) {
    bool matches(DateTime value) =>
        value.year == day.year &&
        value.month == day.month &&
        value.day == day.day &&
        value.hour == time.hour &&
        value.minute == time.minute;
    if (original?.kind == CalDavDateKind.utc &&
        matches(studioCalendarDisplayTime(original!))) {
      return original;
    }
    final chosen = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    if (!matches(chosen)) {
      throw const FormatException(
        'That local time is skipped when the clocks change.',
      );
    }
    final utc = chosen.toUtc();
    for (final offset in [-1, 1]) {
      final nearbyZone = utc
          .add(Duration(days: offset))
          .toLocal()
          .timeZoneOffset;
      final shift = chosen.timeZoneOffset - nearbyZone;
      if (shift != Duration.zero && matches(utc.add(shift).toLocal())) {
        throw const FormatException(
          'That local time occurs twice. Choose another time.',
        );
      }
    }
    return CalDavDateValue.fromTaskDate(
      TaskDateTime(utc.toIso8601String().split('.').first, timeZone: 'UTC'),
    );
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Enter an event title.');
      return;
    }
    final CalDavEventFields fields;
    try {
      final start = _allDay
          ? _date(_startDay)
          : _timed(_startDay, _startTime, widget.event?.start);
      final end = !_hasEnd
          ? null
          : _allDay
          ? _date(_endDay, 1)
          : _timed(_endDay, _endTime, widget.event?.end);
      if (end != null && end.value.compareTo(start.value) <= 0) {
        setState(
          () => _error = _allDay
              ? 'The last day must be on or after the first day.'
              : 'The end time must be after the start time.',
        );
        return;
      }
      String? optionalText(String draft, String? original) =>
          draft.isEmpty && original != '' ? null : draft;
      fields = CalDavEventFields(
        title: _title.text == widget.event?.title
            ? _title.text
            : _title.text.trim(),
        start: start,
        end: end,
        location: optionalText(_location.text, widget.event?.location),
        description: optionalText(_description.text, widget.event?.description),
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    } on ArgumentError {
      setState(() => _error = 'Choose a valid date and time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    StudioCalendarSaveFailure? result;
    try {
      result = await widget.save(fields);
    } on Exception {
      result = (
        message: 'Check the calendar for the change before trying again.',
        retryable: false,
      );
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = result?.message;
      _saveBlocked = result?.retryable == false;
    });
    if (result == null) Navigator.pop(context);
  }

  Widget _dateRow(bool start) {
    final locale = MaterialLocalizations.of(context);
    final title = start
        ? 'Starts'
        : _allDay
        ? 'Through'
        : 'Ends';
    final date = start ? _startDay : _endDay;
    final time = start ? _startTime : _endTime;
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(width: 58, child: Text(title)),
        Tooltip(
          message: start ? 'Start date' : 'End date',
          child: OutlinedButton(
            onPressed: _saving ? null : () => _pickDay(start),
            child: Text(locale.formatMediumDate(date)),
          ),
        ),
        if (!_allDay)
          OutlinedButton(
            onPressed: _saving ? null : () => _pickTime(start),
            child: Text(
              locale.formatTimeOfDay(
                time,
                alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                  context,
                ),
              ),
            ),
          ),
        if (!start)
          IconButton(
            tooltip: 'Remove end',
            icon: const Icon(Icons.clear),
            onPressed: _saving ? null : () => setState(() => _hasEnd = false),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.event == null ? 'New event' : 'Edit event'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.calendarName),
            if (_saving) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              controller: _title,
              readOnly: _saving,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('All day'),
              value: _allDay,
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _allDay = value;
                      if (!value &&
                          _startTime.hour == 0 &&
                          _startTime.minute == 0 &&
                          _startTime == _endTime) {
                        _startTime = const TimeOfDay(hour: 9, minute: 0);
                        _endTime = const TimeOfDay(hour: 10, minute: 0);
                      }
                      if (!_saveBlocked) _error = null;
                    }),
            ),
            _dateRow(true),
            const SizedBox(height: 8),
            if (_hasEnd)
              _dateRow(false)
            else
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _hasEnd = true;
                          if (!_saveBlocked) _error = null;
                        }),
                  child: const Text('Add end'),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _location,
              readOnly: _saving,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              readOnly: _saving,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(_saveBlocked ? 'Close' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _saving || _saveBlocked ? null : _submit,
          child: Text(_saving ? 'Saving…' : 'Save event'),
        ),
      ],
    ),
  );
}
