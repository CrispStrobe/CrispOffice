import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:quds_office_studio/studio_mail_schedule_dialog.dart';
import 'package:quds_office_studio/studio_mail_schedule_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);

final class _Picker {
  DateTime now = DateTime.utc(2026, 11, 21, 12);
  DateTime? result;
  bool completed = false;
  bool current = true;

  Future<void> show(
    WidgetTester tester, {
    StudioStrings strings = _strings,
    Size size = const Size(1000, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Directionality(
          textDirection: strings.language == StudioLanguage.ar
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<DateTime>(
                  context: context,
                  builder: (_) => StudioMailScheduleDialog(
                    strings: strings,
                    isCurrent: () => current,
                    clock: () => now,
                  ),
                );
                completed = true;
              },
              child: const Text('Choose schedule'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose schedule'));
    await tester.pumpAndSettle();
  }
}

Finder _key(String suffix) =>
    find.byKey(ValueKey('studio-mail-schedule-$suffix'));

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('cancel returns no schedule', (tester) async {
    final picker = _Picker();
    await picker.show(tester);
    await tester.tap(find.text(_strings.cancel));
    await tester.pumpAndSettle();
    expect(picker.completed, isTrue);
    expect(picker.result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a selected time that becomes past requires a fresh future choice',
    (tester) async {
      final picker = _Picker();
      await picker.show(tester);
      picker.now = picker.now.add(const Duration(hours: 2));
      await tester.tap(_key('confirm'));
      await tester.pumpAndSettle();
      expect(picker.completed, isFalse);
      expect(find.text(_strings.mailScheduleChooseFuture), findsOneWidget);
      await tester.tap(_key('hour'));
      await tester.pumpAndSettle();
      await tester.tap(_key('confirm'));
      await tester.pumpAndSettle();
      expect(picker.completed, isTrue);
      expect(picker.result, picker.now.add(const Duration(hours: 1)));
      expect(picker.result!.isUtc, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account invalidation prevents schedule confirmation', (
    tester,
  ) async {
    final picker = _Picker();
    await picker.show(tester);
    picker.current = false;
    await tester.tap(_key('confirm'));
    await tester.pumpAndSettle();
    expect(picker.completed, isFalse);
    expect(picker.result, isNull);
    await tester.tap(find.text(_strings.cancel));
    await tester.pumpAndSettle();
    expect(picker.completed, isTrue);
    expect(picker.result, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final language in StudioLanguage.values) {
    testWidgets('future picker remains usable in narrow ${language.name}', (
      tester,
    ) async {
      final strings = StudioStrings(language);
      final picker = _Picker();
      await picker.show(tester, strings: strings, size: const Size(390, 780));
      expect(find.text(strings.mailScheduleExplanation), findsOneWidget);
      await tester.ensureVisible(_key('hour'));
      await tester.tap(_key('hour'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('confirm'));
      await tester.tap(_key('confirm'));
      await tester.pumpAndSettle();
      expect(picker.completed, isTrue);
      expect(picker.result, picker.now.add(const Duration(hours: 1)));
      expect(tester.takeException(), isNull);
    });
  }
}
