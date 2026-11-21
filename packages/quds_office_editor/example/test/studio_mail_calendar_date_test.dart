import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_reader_labels.dart';
import 'package:quds_office_studio/studio_strings.dart';

// Run with TZ=Europe/Berlin to exercise the actual 23- and 25-hour boundaries.
// The expected labels describe calendar dates and also hold in other zones.
void main() {
  group('mail list calendar dates', () {
    for (final (language, yesterday) in <(StudioLanguage, String)>[
      (StudioLanguage.en, 'Yesterday'),
      (StudioLanguage.de, 'Gestern'),
      (StudioLanguage.ar, 'أمس'),
    ]) {
      test('yesterday across spring clock change in ${language.name}', () {
        expect(
          studioMailListDate(
            DateTime(2026, 3, 29, 9, 42),
            language,
            now: DateTime(2026, 3, 30, 15, 30),
          ),
          yesterday,
        );
      });

      test('yesterday across autumn clock change in ${language.name}', () {
        expect(
          studioMailListDate(
            DateTime(2026, 10, 25, 9, 42),
            language,
            now: DateTime(2026, 10, 26, 15, 30),
          ),
          yesterday,
        );
      });
    }

    test('seven calendar days remain outside the recent weekday window', () {
      expect(
        studioMailListDate(
          DateTime(2026, 3, 23, 9, 42),
          StudioLanguage.en,
          now: DateTime(2026, 3, 30, 15, 30),
        ),
        'Mar 23',
      );
    });

    test('tomorrow across spring clock change is not labeled as today', () {
      expect(
        studioMailListDate(
          DateTime(2026, 3, 30, 9, 42),
          StudioLanguage.en,
          now: DateTime(2026, 3, 29, 15, 30),
        ),
        'Mar 30',
      );
    });

    test('UTC now uses the same local date as the message', () {
      final localNow = DateTime(2026, 11, 21, 0, 15);
      expect(
        studioMailListDate(
          DateTime(2026, 11, 21, 0, 5),
          StudioLanguage.en,
          now: localNow.toUtc(),
        ),
        '00:05',
      );
    });

    test('UTC message and now preserve yesterday across the year boundary', () {
      final localNow = DateTime(2027, 1, 1, 0, 15);
      expect(
        studioMailListDate(
          DateTime(2026, 12, 31, 23, 55).toUtc(),
          StudioLanguage.en,
          now: localNow.toUtc(),
        ),
        'Yesterday',
      );
    });
  });
}
