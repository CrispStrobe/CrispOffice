import 'dart:io';

import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_calendar_grid.dart';
import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';

List<CalDavEvent> _events(List<String> definitions) => readCalDavAgenda(
  'BEGIN:VCALENDAR\nVERSION:2.0\n'
  '${definitions.indexed.map((item) => 'BEGIN:VEVENT\nUID:${item.$1}\n${item.$2}\nEND:VEVENT\n').join()}'
  'END:VCALENDAR',
).events;

Future<void> _show(
  WidgetTester tester,
  StudioCalendarPeriod period,
  DateTime date,
  List<CalDavEvent> events, {
  ValueChanged<CalDavEvent>? openEvent,
  ValueChanged<DateTime>? openDay,
}) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: StudioCalendarGrid(
        period: period,
        start: period.start(date),
        end: period.advance(period.start(date), 1),
        events: events,
        openEvent: openEvent ?? (_) {},
        openDay: openDay ?? (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('week places overlapping timed events in separate columns', (
    tester,
  ) async {
    final events = _events([
      'SUMMARY:First overlap\nDTSTART:20261125T090000\nDTEND:20261125T104500',
      'SUMMARY:Second overlap\nDTSTART:20261125T093000\nDTEND:20261125T110000',
    ]);
    CalDavEvent? selected;
    await _show(
      tester,
      StudioCalendarPeriod.week,
      DateTime(2026, 11, 25),
      events,
      openEvent: (event) => selected = event,
    );
    await tester.pumpAndSettle();

    Finder tile(String name) => find
        .ancestor(of: find.text(name), matching: find.byType(InkWell))
        .first;
    final first = tester.getRect(tile('First overlap'));
    final second = tester.getRect(tile('Second overlap'));
    expect(first.bottom, greaterThan(second.top));
    expect(first.overlaps(second), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, same(events.first));
  });

  testWidgets('month splits exclusive all-day and timed midnight boundaries', (
    tester,
  ) async {
    final events = _events([
      'SUMMARY:All-day span\nDTSTART;VALUE=DATE:20260328\nDTEND;VALUE=DATE:20260330',
      'SUMMARY:Overnight\nDTSTART:20260328T223000\nDTEND:20260330T000000',
      'SUMMARY:Floating gap\nDTSTART:20260329T023000\nDTEND:20260329T031500',
      'SUMMARY:Other zone\nDTSTART;TZID=America/New_York:20260329T110000\n'
          'DTEND;TZID=America/New_York:20260329T120000',
    ]);
    DateTime? selected;
    await _show(
      tester,
      StudioCalendarPeriod.month,
      DateTime(2026, 3, 29),
      events,
      openDay: (day) => selected = day,
    );
    await tester.pumpAndSettle();
    final controller = tester
        .widget<MonthView<CalDavEvent>>(find.byType(MonthView<CalDavEvent>))
        .controller!;
    expect(
      controller.getFullDayEvent(DateTime(2026, 3, 28)).single.event,
      same(events[0]),
    );
    expect(
      controller.getFullDayEvent(DateTime(2026, 3, 29)).single.event,
      same(events[0]),
    );
    expect(controller.getEventsOnDay(DateTime(2026, 3, 30)), isEmpty);

    final overnight = controller.allEvents.where(
      (tile) => tile.event == events[1],
    );
    expect(overnight.map((tile) => tile.date.day), [28, 29]);
    expect(overnight.every((tile) => !tile.isFullDayEvent), isTrue);
    final floating = controller.allEvents.singleWhere(
      (tile) => tile.event == events[2],
    );
    expect(floating.startTime?.hour, 2);
    expect(floating.startTime?.minute, 30);

    await tester.tap(find.text('Events without a grid position (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Other zone'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('29'),
      95,
      scrollable: find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('29'));
    expect(selected, DateTime(2026, 3, 29));
  });

  testWidgets('day projects UTC into local clock time across a DST change', (
    tester,
  ) async {
    final events = _events([
      'SUMMARY:UTC appointment\nDTSTART:20260329T003000Z\nDTEND:20260329T013000Z',
    ]);
    final before = DateTime.utc(2026, 3, 29, 0, 30).toLocal();
    final after = DateTime.utc(2026, 3, 29, 1, 30).toLocal();
    await _show(tester, StudioCalendarPeriod.day, before, events);
    await tester.pumpAndSettle();

    final tile = tester
        .widget<DayView<CalDavEvent>>(find.byType(DayView<CalDavEvent>))
        .controller!
        .allEvents
        .single;
    expect(tile.startTime?.hour, before.hour);
    final endsNextDay = after.day != before.day;
    expect(tile.endTime?.hour, endsNextDay ? 0 : after.hour);
    if (Platform.environment['TZ'] == 'Europe/Berlin') {
      expect(before.timeZoneOffset, const Duration(hours: 1));
      expect(after.timeZoneOffset, const Duration(hours: 2));
      expect(tile.startTime?.hour, 1);
      expect(tile.endTime?.hour, 3);
    }
  });

  testWidgets('fall-back intervals that reverse local time stay accessible', (
    tester,
  ) async {
    final events = _events([
      'SUMMARY:Repeated hour\nDTSTART:20261025T004500Z\nDTEND:20261025T011500Z',
    ]);
    final before = DateTime.utc(2026, 10, 25, 0, 45).toLocal();
    final after = DateTime.utc(2026, 10, 25, 1, 15).toLocal();
    if (Platform.environment['TZ'] == 'Europe/Berlin') {
      expect(before.timeZoneOffset, const Duration(hours: 2));
      expect(after.timeZoneOffset, const Duration(hours: 1));
    }
    await _show(tester, StudioCalendarPeriod.day, before, events);
    await tester.pumpAndSettle();
    final controller = tester
        .widget<DayView<CalDavEvent>>(find.byType(DayView<CalDavEvent>))
        .controller!;
    if (before.day == after.day && before.hour == after.hour) {
      expect(controller.allEvents, isEmpty);
      expect(find.text('Events without a grid position (1)'), findsOneWidget);
    } else {
      expect(controller.allEvents.single.event, same(events.single));
    }
  });
}
