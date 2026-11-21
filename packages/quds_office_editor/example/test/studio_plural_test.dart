import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_download_strings.dart';
import 'package:quds_office_studio/studio_mail_reader_labels.dart';
import 'package:quds_office_studio/studio_plural.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _en = StudioLanguage.en;
const _de = StudioLanguage.de;
const _ar = StudioLanguage.ar;

void main() {
  test('English and German use singular and plural forms', () {
    expect(studioWritingIssues(_en, 1), '1 writing issue');
    expect(studioWritingIssues(_en, 5), '5 writing issues');
    expect(studioWritingIssues(_de, 1), '1 Schreibhinweis');
    expect(studioWritingIssues(_de, 5), '5 Schreibhinweise');
    expect(studioChanges(_en, 0), '0 changes');
    expect(studioChanges(_en, 1), '1 change');
    expect(studioChanges(_de, 1), '1 Änderung');
    expect(studioParagraphs(_de, 1), '1 Absatz');
    expect(studioParagraphs(_de, 10), '10 Absätze');
    expect(studioWords(_en, 1), '1 word');
    expect(studioSheets(_de, 3), '3 Blätter');
  });

  test('Arabic uses all six CLDR plural categories', () {
    expect(studioChanges(_ar, 0), 'لا توجد تغييرات');
    expect(studioChanges(_ar, 1), 'تغيير واحد');
    expect(studioChanges(_ar, 2), 'تغييران');
    expect(studioChanges(_ar, 3), '3 تغييرات');
    expect(studioChanges(_ar, 10), '10 تغييرات');
    expect(studioChanges(_ar, 11), '11 تغييرًا');
    expect(studioChanges(_ar, 99), '99 تغييرًا');
    expect(studioChanges(_ar, 100), '100 تغيير');
    expect(studioWritingIssues(_ar, 2), 'ملاحظتان');
    expect(studioWritingIssues(_ar, 5), '5 ملاحظات');
    expect(studioWritingIssues(_ar, 12), '12 ملاحظة');
  });

  test('package summary agrees with the total in every language', () {
    expect(
      const StudioDownloadStrings(_en).summary(1, 1, '7 MB'),
      '1 of 1 package installed · 7 MB on this device',
    );
    expect(
      const StudioDownloadStrings(_en).summary(4, 9, '34.5 MB'),
      '4 of 9 packages installed · 34.5 MB on this device',
    );
    expect(
      const StudioDownloadStrings(_de).summary(4, 9, '34,5 MB'),
      '4 von 9 Paketen installiert · 34,5 MB auf diesem Gerät',
    );
    expect(
      const StudioDownloadStrings(_ar).summary(4, 9, '34.5 MB'),
      'تم تثبيت 4 من 9 حزم · 34.5 MB على هذا الجهاز',
    );
    expect(
      const StudioDownloadStrings(_ar).summary(4, 12, '34.5 MB'),
      'تم تثبيت 4 من 12 حزمة · 34.5 MB على هذا الجهاز',
    );
  });

  group('mail list dates', () {
    final now = DateTime(2026, 11, 19, 15, 30);

    test('show the time today, then yesterday, weekday and short date', () {
      expect(
        studioMailListDate(DateTime(2026, 11, 19, 9, 42), _en, now: now),
        '09:42',
      );
      expect(
        studioMailListDate(DateTime(2026, 11, 18, 23, 5), _en, now: now),
        'Yesterday',
      );
      expect(
        studioMailListDate(DateTime(2026, 11, 16, 8), _en, now: now),
        'Monday',
      );
      expect(
        studioMailListDate(DateTime(2026, 11, 2, 8), _en, now: now),
        'Nov 2',
      );
      expect(
        studioMailListDate(DateTime(2025, 11, 2, 8), _en, now: now),
        'Nov 2, 2025',
      );
      expect(studioMailListDate(null, _en, now: now), isNull);
    });

    test('follow the UI language', () {
      expect(
        studioMailListDate(DateTime(2026, 11, 18, 9), _de, now: now),
        'Gestern',
      );
      expect(
        studioMailListDate(DateTime(2026, 11, 16, 8), _de, now: now),
        'Montag',
      );
      expect(
        studioMailListDate(DateTime(2026, 11, 2, 8), _de, now: now),
        '2. Nov.',
      );
      expect(
        studioMailListDate(DateTime(2026, 11, 18, 9), _ar, now: now),
        'أمس',
      );
      expect(
        studioMailListDate(DateTime(2026, 11, 16, 8), _ar, now: now),
        isNot(contains('Monday')),
      );
    });
  });

  test('reader labels format the header date and size per language', () {
    final date = DateTime(2026, 11, 19, 9, 42);
    expect(
      StudioMailReaderLabels(_en).formatDate(date),
      'Thursday, November 19, 2026 09:42',
    );
    expect(
      StudioMailReaderLabels(_de).formatDate(date),
      'Donnerstag, 19. November 2026 09:42',
    );
    expect(StudioMailReaderLabels(_de).date, 'Datum');
    expect(StudioMailReaderLabels(_ar).attachments, 'المرفقات');
    expect(StudioMailReaderLabels(_en).formatSize(1), '1 byte');
    expect(StudioMailReaderLabels(_en).formatSize(245760), '240 KB');
    expect(
      StudioMailReaderLabels(_de).formatSize(3 * 1024 * 1024 ~/ 2),
      '1,5 MB',
    );
    expect(StudioMailReaderLabels(_en).matches(1, more: false), '1 match');
    expect(StudioMailReaderLabels(_de).matches(3, more: true), '3 Treffer+');
  });
}
