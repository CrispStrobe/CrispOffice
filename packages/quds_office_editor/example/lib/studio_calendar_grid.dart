import 'dart:math' as math;

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
typedef _DateSpan = ({
  CalDavEvent event,
  DateTime startTime,
  DateTime first,
  DateTime end,
});
typedef _WeekPlacement = ({CalDavEvent event, int first, int end, int lane});

const _eventHeight = 22.0;
const _monthDateHeight = 28.0;
const _weekTimelineWidth = 70.0;
// calendar_view 2.0 adds 5 logical pixels for its hour-line offset.
const _weekGutter = _weekTimelineWidth + 5;

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
    this.appearanceOf,
  });

  final StudioCalendarPeriod period;
  final DateTime start;
  final DateTime end;
  final List<CalDavEvent> events;
  final ValueChanged<CalDavEvent> openEvent;
  final ValueChanged<DateTime> openDay;
  final ValueChanged<DateTime>? createEvent;
  final ({String label, Color color})? Function(CalDavEvent)? appearanceOf;

  @override
  State<StudioCalendarGrid> createState() => _StudioCalendarGridState();
}

final class _StudioCalendarGridState extends State<StudioCalendarGrid> {
  final _controller = EventController<CalDavEvent>();
  final _unplaced = <CalDavEvent>{};
  final _spans = <_DateSpan>[];
  final _expandedWeeks = <DateTime>{};

  @override
  void initState() {
    super.initState();
    _project();
  }

  @override
  void didUpdateWidget(StudioCalendarGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period ||
        oldWidget.events != widget.events ||
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
    _spans.clear();
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
      final firstVisible = firstDay.isBefore(first) ? first : firstDay;
      if (!firstVisible.isBefore(limit) || !firstVisible.isBefore(until)) {
        continue;
      }
      if (widget.period == StudioCalendarPeriod.month ||
          (widget.period == StudioCalendarPeriod.week && allDay)) {
        final lastDay = _civil(until);
        final endDay = lastDay == until
            ? lastDay
            : lastDay.add(const Duration(days: 1));
        _spans.add((
          event: event,
          startTime: from,
          first: firstVisible,
          end: endDay.isAfter(limit) ? limit : endDay,
        ));
        continue;
      }
      for (
        var day = firstVisible;
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
                subtitle: switch (widget.appearanceOf?.call(event)) {
                  (:final label, color: _) => Text(label),
                  null => null,
                },
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

  Widget _tile(CalDavEvent event, {bool showStart = false}) {
    final scheme = Theme.of(context).colorScheme;
    final appearance = widget.appearanceOf?.call(event);
    final allDay = event.start.kind == CalDavDateKind.date;
    final start = allDay
        ? null
        : _clock(context, studioCalendarDisplayTime(event.start));
    final end = allDay || event.end == null
        ? null
        : _clock(context, studioCalendarDisplayTime(event.end!));
    final title = _title(event);
    return Material(
      color: appearance == null
          ? scheme.primaryContainer
          : Color.alphaBlend(
              appearance.color.withValues(alpha: 0.25),
              scheme.surface,
            ),
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: () => widget.openEvent(event),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text.rich(
                TextSpan(
                  children: [
                    if (showStart && start != null)
                      TextSpan(
                        text: '$start ',
                        style: const TextStyle(fontSize: 9),
                      ),
                    TextSpan(text: title),
                  ],
                ),
                semanticsLabel: [
                  title,
                  if (allDay)
                    'All day'
                  else if (end == null)
                    start!
                  else
                    '$start – $end',
                  ?appearance?.label,
                ].join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: appearance == null
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                  fontSize: 12,
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
        SizedBox(height: _eventHeight, child: _tile(event.event!)),
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

  Widget _monthCell(DateTime day, DateTime today) {
    final scheme = Theme.of(context).colorScheme;
    final locale = MaterialLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: day == today ? scheme.surfaceContainerHighest : scheme.surface,
        border: BorderDirectional(
          end: BorderSide(color: scheme.outlineVariant),
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: day.month != widget.start.month
          ? const SizedBox.expand()
          : Align(
              alignment: AlignmentDirectional.topStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 3, top: 2),
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(28, 24),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => widget.openDay(day),
                  child: Text(
                    locale.formatDecimal(day.day),
                    semanticsLabel: locale.formatFullDate(day),
                  ),
                ),
              ),
            ),
    );
  }

  List<_WeekPlacement> _placeSpans(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 7));
    final spans =
        _spans
            .where(
              (span) =>
                  span.first.isBefore(weekEnd) && span.end.isAfter(weekStart),
            )
            .toList()
          ..sort((a, b) {
            final first = a.first.compareTo(b.first);
            if (first != 0) return first;
            final end = b.end.compareTo(a.end);
            return end != 0 ? end : a.startTime.compareTo(b.startTime);
          });
    final occupancy = <int>[];
    final nextLane = List.filled(1 << 7, 0);
    final placements = <_WeekPlacement>[];
    for (final span in spans) {
      final first = span.first.difference(weekStart).inDays.clamp(0, 7);
      final end = span.end.difference(weekStart).inDays.clamp(0, 7);
      // One bit per day keeps the entire span in the same row.
      final days = ((1 << (end - first)) - 1) << first;
      var lane = nextLane[days];
      while (lane < occupancy.length && (occupancy[lane] & days) != 0) {
        lane++;
      }
      nextLane[days] = lane + 1;
      if (lane == occupancy.length) {
        occupancy.add(days);
      } else {
        occupancy[lane] |= days;
      }
      placements.add((event: span.event, first: first, end: end, lane: lane));
    }
    return placements;
  }

  int _laneCount(List<_WeekPlacement> placements) =>
      placements.fold(0, (count, item) => math.max(count, item.lane + 1));

  List<Widget> _positionSpans(
    DateTime weekStart,
    List<_WeekPlacement> placements, {
    required double columnWidth,
    required double top,
    required int collapsedSlots,
    required bool expanded,
  }) {
    final lanes = _laneCount(placements);
    final overflow = lanes > collapsedSlots;
    final visible = expanded || !overflow ? lanes : collapsedSlots - 1;
    final hiddenByDay = List.filled(7, 0);
    for (final item in placements.where(
      (item) => item.lane >= collapsedSlots - 1,
    )) {
      for (var day = item.first; day < item.end; day++) {
        hiddenByDay[day]++;
      }
    }
    final locale = MaterialLocalizations.of(context);
    return [
      for (final item in placements.where((item) => item.lane < visible))
        PositionedDirectional(
          start: item.first * columnWidth + 2,
          width: math.max(0, (item.end - item.first) * columnWidth - 4),
          top: top + item.lane * _eventHeight,
          height: _eventHeight - 1,
          child: _tile(
            item.event,
            showStart:
                _civil(studioCalendarDisplayTime(item.event.start)) ==
                weekStart.add(Duration(days: item.first)),
          ),
        ),
      if (overflow)
        for (var day = 0; day < 7; day++)
          if (hiddenByDay[day] > 0)
            PositionedDirectional(
              start: day * columnWidth + 2,
              width: math.max(0, columnWidth - 4),
              top: top + visible * _eventHeight,
              height: _eventHeight,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => setState(() {
                  if (expanded) {
                    _expandedWeeks.remove(weekStart);
                  } else {
                    _expandedWeeks.add(weekStart);
                  }
                }),
                child: Text(
                  expanded ? '−' : '+${locale.formatDecimal(hiddenByDay[day])}',
                  semanticsLabel: expanded ? 'Collapse week' : 'Expand week',
                ),
              ),
            ),
    ];
  }

  Widget _weekHeader(DateTime date) {
    final weekStart = _civil(date);
    final placements = _placeSpans(weekStart);
    final lanes = _laneCount(placements);
    const slots = 3;
    final expanded = _expandedWeeks.contains(weekStart);
    final shown = expanded && lanes > slots
        ? lanes + 1
        : math.min(lanes, slots);
    final scheme = Theme.of(context).colorScheme;
    final locale = MaterialLocalizations.of(context);
    final thursday = weekStart.add(const Duration(days: 3));
    final week =
        thursday.difference(DateTime.utc(thursday.year)).inDays ~/ 7 + 1;
    return Column(
      children: [
        ColoredBox(
          color: scheme.surfaceContainer,
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                SizedBox(
                  width: _weekGutter,
                  child: Center(child: Text(locale.formatDecimal(week))),
                ),
                for (var day = 0; day < 7; day++)
                  Expanded(
                    child: Center(
                      child: Text(
                        locale.formatMediumDate(
                          weekStart.add(Duration(days: day)),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (lanes > 0)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: _weekGutter,
                height: _eventHeight,
                child: Center(child: Text('All day')),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 132),
                    child: SingleChildScrollView(
                      primary: false,
                      child: SizedBox(
                        height: shown * _eventHeight,
                        child: Stack(
                          children: _positionSpans(
                            weekStart,
                            placements,
                            columnWidth: constraints.maxWidth / 7,
                            top: 0,
                            collapsedSlots: slots,
                            expanded: expanded,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _monthGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final scheme = Theme.of(context).colorScheme;
      final locale = MaterialLocalizations.of(context);
      final start = _civil(widget.start);
      final end = _civil(widget.end);
      final today = _civil(DateTime.now());
      final firstWeekday = locale.firstDayOfWeekIndex;
      final offset = (start.weekday % 7 - firstWeekday) % 7;
      final weekCount = (offset + end.difference(start).inDays + 6) ~/ 7;
      final first = start.subtract(Duration(days: offset));
      final rowHeight = math.max(
        _monthDateHeight + _eventHeight,
        (constraints.maxHeight - 30) / weekCount,
      );
      final slots = math.max(1, (rowHeight - _monthDateHeight) ~/ _eventHeight);
      return Column(
        children: [
          ColoredBox(
            color: scheme.surfaceContainer,
            child: SizedBox(
              height: 30,
              child: Row(
                children: [
                  for (var index = 0; index < 7; index++)
                    Expanded(
                      child: Center(
                        child: Text(
                          locale.narrowWeekdays[(firstWeekday + index) % 7],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: weekCount,
              itemBuilder: (context, week) {
                final weekStart = first.add(Duration(days: 7 * week));
                final days = List.generate(
                  7,
                  (index) => weekStart.add(Duration(days: index)),
                );
                final placements = _placeSpans(weekStart);
                final expanded = _expandedWeeks.contains(weekStart);
                final height = expanded
                    ? math.max(
                        rowHeight,
                        _monthDateHeight +
                            _eventHeight * (_laneCount(placements) + 1),
                      )
                    : rowHeight;
                return SizedBox(
                  height: height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final day in days)
                              Expanded(child: _monthCell(day, today)),
                          ],
                        ),
                      ),
                      ..._positionSpans(
                        weekStart,
                        placements,
                        columnWidth: constraints.maxWidth / 7,
                        top: _monthDateHeight,
                        collapsedSlots: slots,
                        expanded: expanded,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
    ) {
      final event = events.first.event!;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 2),
        child: _tile(
          event,
          showStart:
              _civil(studioCalendarDisplayTime(event.start)) == _civil(day),
        ),
      );
    }

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
        weekPageHeaderBuilder: (firstDay, _) => _weekHeader(firstDay),
        weekTitleHeight: 0,
        weekDayBuilder: (_) => const SizedBox.shrink(),
        weekNumberBuilder: (_) => const SizedBox.shrink(),
        backgroundColor: scheme.surface,
        heightPerMinute: scale,
        scrollOffset: morningOffset,
        timeLineStringBuilder: clock,
        timeLineWidth: _weekTimelineWidth,
        eventArranger: const SideEventArranger(),
        eventTileBuilder: eventTiles,
        onDateTap: widget.createEvent,
      ),
      StudioCalendarPeriod.month => _monthGrid(),
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
