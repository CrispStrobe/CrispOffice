import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

enum StudioCalendarPeriod {
  day('Day', Icons.view_day_outlined),
  week('Week', Icons.view_week_outlined),
  month('Month', Icons.calendar_view_month);

  const StudioCalendarPeriod(this.label, this.icon);
  final String label;
  final IconData icon;

  DateTime start(DateTime anchor) => switch (this) {
    day => DateTime(anchor.year, anchor.month, anchor.day),
    week => DateTime(
      anchor.year,
      anchor.month,
      anchor.day - anchor.weekday + 1,
    ),
    month => DateTime(anchor.year, anchor.month),
  };

  DateTime advance(DateTime anchor, int count) => switch (this) {
    day => DateTime(anchor.year, anchor.month, anchor.day + count),
    week => DateTime(anchor.year, anchor.month, anchor.day + 7 * count),
    month => DateTime(anchor.year, anchor.month + count),
  };
}

/// Grid positions use civil clock fields. Only UTC values have enough
/// information here to convert to the device's timezone as an instant.
DateTime studioCalendarDisplayTime(CalDavDateValue value) =>
    switch (value.toTaskDate()) {
      TaskDate(:final year, :final month, :final day) => DateTime.utc(
        year,
        month,
        day,
      ),
      TaskDateTime(:final localDateTime) =>
        value.kind == CalDavDateKind.utc
            ? DateTime.parse('${localDateTime}Z').toLocal()
            : DateTime.parse('${localDateTime}Z'),
    };

typedef _GridEvent = CalendarEventData<CalDavEvent>;

final class StudioCalendarGrid extends StatefulWidget {
  const StudioCalendarGrid({
    super.key,
    required this.period,
    required this.start,
    required this.end,
    required this.events,
    required this.openEvent,
    required this.openDay,
    this.createEvent,
  });

  final StudioCalendarPeriod period;
  final DateTime start;
  final DateTime end;
  final List<CalDavEvent> events;
  final ValueChanged<CalDavEvent> openEvent;
  final ValueChanged<DateTime> openDay;
  final ValueChanged<DateTime>? createEvent;

  @override
  State<StudioCalendarGrid> createState() => _StudioCalendarGridState();
}

final class _StudioCalendarGridState extends State<StudioCalendarGrid> {
  final _controller = EventController<CalDavEvent>();
  final _unplaced = <CalDavEvent>{};

  @override
  void initState() {
    super.initState();
    _project();
  }

  @override
  void didUpdateWidget(StudioCalendarGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.events != widget.events ||
        oldWidget.start != widget.start ||
        oldWidget.end != widget.end) {
      _project();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _project() {
    final first = _civil(widget.start);
    final limit = _civil(widget.end);
    final tiles = <_GridEvent>[];
    final counts = <DateTime, int>{};
    _unplaced.clear();
    for (final event in widget.events) {
      final start = event.start;
      final end = event.end;
      if (start.kind == CalDavDateKind.zoned ||
          end?.kind == CalDavDateKind.zoned) {
        _unplaced.add(event);
        continue;
      }
      final allDay = start.kind == CalDavDateKind.date;
      final shownStart = studioCalendarDisplayTime(start);
      final from = _wall(shownStart);
      final to = end == null
          ? from.add(
              allDay ? const Duration(days: 1) : const Duration(minutes: 15),
            )
          : _wall(studioCalendarDisplayTime(end));
      // The 24-hour grid cannot place an interval that runs backwards in
      // local time during a fall-back transition.
      if (to.isBefore(from) ||
          (to == from && end != null && start.value != end.value)) {
        _unplaced.add(event);
        continue;
      }
      final until = from == to ? from.add(const Duration(minutes: 15)) : to;
      final firstDay = _civil(from);
      for (
        var day = firstDay.isBefore(first) ? first : firstDay;
        day.isBefore(limit) && day.isBefore(until);
        day = day.add(const Duration(days: 1))
      ) {
        // Bound the renderer's overlap arrangement and keep dense
        // schedules accessible through the agenda and overflow list.
        final count = counts[day] ?? 0;
        if (count == 64) {
          _unplaced.add(event);
          continue;
        }
        counts[day] = count + 1;
        final next = day.add(const Duration(days: 1));
        final segmentStart = day.isAfter(from) ? day : from;
        final segmentEnd = next.isBefore(until) ? next : until;
        final startMinute = segmentStart.difference(day).inMinutes;
        final endMinute = segmentEnd.difference(day).inMinutes;
        // The renderer uses 00:00 twice to denote an all-day event. Use
        // the last minute for a timed segment that fills an entire day.
        final displayEnd = startMinute == 0 && endMinute == 1440
            ? 1439
            : endMinute.clamp(startMinute + 1, 1440);
        tiles.add(
          CalendarEventData(
            title: _title(event),
            date: day,
            startTime: allDay ? null : day.add(Duration(minutes: startMinute)),
            endTime: allDay ? null : day.add(Duration(minutes: displayEnd)),
            event: event,
          ),
        );
      }
    }
    _controller
      ..clear()
      ..addAll(tiles);
  }

  static DateTime _civil(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static DateTime _wall(DateTime value) => DateTime.utc(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
  );

  static String _title(CalDavEvent event) =>
      event.title.isEmpty ? 'Untitled event' : event.title;

  Future<void> _showEvents(String heading, Iterable<CalDavEvent> events) async {
    final rows = events.toList(growable: false);
    final selected = await showDialog<CalDavEvent>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(heading),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final event = rows[index];
              return ListTile(
                title: Text(_title(event)),
                onTap: () => Navigator.pop(context, event),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (mounted && selected != null) widget.openEvent(selected);
  }

  String _clock(BuildContext context, DateTime value) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(value),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  Widget _tile(_GridEvent tile) {
    final scheme = Theme.of(context).colorScheme;
    final when = tile.isFullDayEvent
        ? 'All day'
        : '${_clock(context, tile.startTime!)} – ${_clock(context, tile.endTime!)}';
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2),
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: () => widget.openEvent(tile.event!),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  tile.title,
                  semanticsLabel: '${tile.title}, $when',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _eventStrip(List<_GridEvent> events, DateTime date) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final event in events.take(2))
        SizedBox(height: 22, child: _tile(event)),
      if (events.length > 2)
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 22),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () => _showEvents(
            MaterialLocalizations.of(context).formatFullDate(date),
            events.map((tile) => tile.event!),
          ),
          child: Text(
            '+${events.length - 2}',
            semanticsLabel:
                'Show all events for '
                '${MaterialLocalizations.of(context).formatFullDate(date)}',
          ),
        ),
    ],
  );

  Widget _monthCell(
    DateTime day,
    List<_GridEvent> events,
    bool today,
    bool inMonth,
  ) {
    if (!inMonth) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: today ? scheme.surfaceContainerHighest : scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(28, 24),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => widget.openDay(day),
                child: Text(
                  MaterialLocalizations.of(context).formatDecimal(day.day),
                  semanticsLabel: MaterialLocalizations.of(
                    context,
                  ).formatFullDate(day),
                ),
              ),
            ),
            _eventStrip(events, day),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = MaterialLocalizations.of(context);
    final start = widget.start;
    final end = DateTime(widget.end.year, widget.end.month, widget.end.day - 1);
    const paging = NeverScrollableScrollPhysics();
    const scale = 0.85;
    const morningOffset = 7 * 60 * scale;
    Widget eventTiles(
      DateTime day,
      List<_GridEvent> events,
      Rect bounds,
      DateTime from,
      DateTime to,
    ) => _tile(events.first);
    String clock(DateTime value, {DateTime? secondaryDate}) =>
        _clock(context, value);
    final grid = switch (widget.period) {
      StudioCalendarPeriod.day => DayView<CalDavEvent>(
        controller: _controller,
        initialDay: start,
        minDay: start,
        maxDay: end,
        pageViewPhysics: paging,
        dayTitleBuilder: (_) => const SizedBox.shrink(),
        backgroundColor: scheme.surface,
        heightPerMinute: scale,
        scrollOffset: morningOffset,
        timeStringBuilder: clock,
        timeLineWidth: 70,
        eventArranger: const SideEventArranger(),
        eventTileBuilder: eventTiles,
        onDateTap: widget.createEvent,
        fullDayEventBuilder: _eventStrip,
      ),
      StudioCalendarPeriod.week => WeekView<CalDavEvent>(
        controller: _controller,
        initialDay: start,
        minDay: start,
        maxDay: end,
        pageViewPhysics: paging,
        weekPageHeaderBuilder: (_, _) => const SizedBox.shrink(),
        backgroundColor: scheme.surface,
        heightPerMinute: scale,
        scrollOffset: morningOffset,
        timeLineStringBuilder: clock,
        timeLineWidth: 70,
        weekDayBuilder: (day) => Center(
          child: Text(
            locale.formatMediumDate(day),
            textAlign: TextAlign.center,
          ),
        ),
        fullDayHeaderTitle: 'All day',
        eventArranger: const SideEventArranger(),
        eventTileBuilder: eventTiles,
        onDateTap: widget.createEvent,
        fullDayEventBuilder: _eventStrip,
      ),
      StudioCalendarPeriod.month => LayoutBuilder(
        builder: (context, constraints) => MonthView<CalDavEvent>(
          controller: _controller,
          monthViewStyle: MonthViewStyle(
            initialMonth: start,
            minMonth: start,
            maxMonth: end,
            pageViewPhysics: paging,
            hideDaysNotInMonth: true,
            cellAspectRatio: constraints.maxWidth / (7 * 106),
            borderColor: scheme.outlineVariant,
          ),
          // MonthView 2.0 stores its builder as a raw generic internally.
          monthViewBuilders: MonthViewBuilders<Object?>(
            headerBuilder: (_) => const SizedBox.shrink(),
            weekDayBuilder: (index) => ColoredBox(
              color: scheme.surfaceContainer,
              child: SizedBox(
                height: 40,
                child: Center(
                  child: Text(
                    locale.narrowWeekdays[(index + 1) % 7],
                    style: TextStyle(color: scheme.onSurface),
                  ),
                ),
              ),
            ),
            cellBuilder: (day, events, today, inMonth, _) =>
                _monthCell(day, events.cast<_GridEvent>(), today, inMonth),
          ),
        ),
      ),
    };
    return Column(
      children: [
        if (_unplaced.isNotEmpty)
          TextButton(
            onPressed: () =>
                _showEvents('Events without a grid position', _unplaced),
            child: Text('Events without a grid position (${_unplaced.length})'),
          ),
        Expanded(child: grid),
      ],
    );
  }
}
