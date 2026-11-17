// Bounded review probe for calendar-relative date boundaries. Uses the actual
// resolver and an injected calendar clock; each process supplies its own TZ.
import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';

void main() {
  final now = DateTime(2026, 11, 17, 12);
  final epoch = DateTime.utc(1899, 12, 30);
  final cases = [
    (period: 'last7Days', day: 17, expected: true),
    (period: 'last7Days', day: 11, expected: true),
    (period: 'last7Days', day: 10, expected: false),
    (period: 'thisWeek', day: 15, expected: true),
    (period: 'thisWeek', day: 21, expected: true),
    (period: 'thisWeek', day: 22, expected: false),
    (period: 'lastWeek', day: 8, expected: true),
    (period: 'lastWeek', day: 14, expected: true),
    (period: 'lastWeek', day: 15, expected: false),
    (period: 'nextWeek', day: 22, expected: true),
    (period: 'nextWeek', day: 28, expected: true),
    (period: 'nextWeek', day: 29, expected: false),
  ];
  final rows = <Map<String, Object?>>[];
  for (final entry in cases) {
    final date = DateTime.utc(2026, 11, entry.day);
    final sheet = SmlWorksheet(name: 'Dates', sheetId: 1);
    sheet.cellA1('A1').value = date.difference(epoch).inDays;
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('A1'),
        kind: SmlConditionalKind.timePeriod,
        formula: entry.period,
        fillRgb: 'FF0000',
      ),
    );
    final resolver = SmlConditionalResolver(sheet: sheet, now: () => now);
    final actual = resolver.resolve(SmlCellRef.parse('A1')).fillRgb == 'FF0000';
    rows.add({
      'period': entry.period,
      'cell_calendar_date': date.toIso8601String().substring(0, 10),
      'expected': entry.expected,
      'actual': actual,
      'passed': actual == entry.expected,
    });
  }
  final failed = rows.where((row) => row['passed'] == false).length;
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'schema': 'quds.sheet.calendar_boundary_probe.v1',
      'timezone': Platform.environment['TZ'],
      'clock_local': now.toIso8601String(),
      'utc_offset_minutes': now.timeZoneOffset.inMinutes,
      'cases': rows,
      'passed': rows.length - failed,
      'failed': failed,
    }),
  );
  exitCode = failed == 0 ? 0 : 1;
}
