import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_plural.dart';
import 'studio_strings.dart';

bool _dateDataReady = false;

/// The intl locale of a Studio UI language; date data is loaded on first use
/// (it is compiled in, so this completes synchronously).
String studioIntlLocale(StudioLanguage language) {
  if (!_dateDataReady) {
    _dateDataReady = true;
    initializeDateFormatting();
  }
  return switch (language) {
    StudioLanguage.en => 'en',
    StudioLanguage.de => 'de',
    StudioLanguage.ar => 'ar',
  };
}

/// The date column of a message list in the UI language: the time for
/// today, "Yesterday", the weekday within the last week, then a short date
/// (with the year only when it differs from the current one).
String? studioMailListDate(
  DateTime? sent,
  StudioLanguage language, {
  DateTime? now,
}) {
  if (sent == null) return null;
  final locale = studioIntlLocale(language);
  final local = sent.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  // Compare local calendar dates in UTC so a 23- or 25-hour daylight-saving
  // day still counts as exactly one day, including dates in the future.
  final day = DateTime.utc(local.year, local.month, local.day);
  final current = DateTime.utc(today.year, today.month, today.day);
  final days = current.difference(day).inDays;
  if (days == 0) return DateFormat.Hm(locale).format(local);
  if (days == 1) {
    return switch (language) {
      StudioLanguage.en => 'Yesterday',
      StudioLanguage.de => 'Gestern',
      StudioLanguage.ar => 'أمس',
    };
  }
  if (days > 1 && days < 7) return DateFormat.EEEE(locale).format(local);
  if (local.year == today.year) return DateFormat.MMMd(locale).format(local);
  return DateFormat.yMMMd(locale).format(local);
}

/// Reader header labels and formatting in the Studio UI language.
class StudioMailReaderLabels extends MailReaderLabels {
  StudioMailReaderLabels(this.language);

  final StudioLanguage language;

  String _t(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  @override
  String get noSubject => _t('(No subject)', '(Kein Betreff)', '(بلا موضوع)');
  @override
  String get from => _t('From', 'Von', 'من');
  @override
  String get to => _t('To', 'An', 'إلى');
  @override
  String get cc => _t('Cc', 'Cc', 'نسخة');
  @override
  String get bcc => _t('Bcc', 'Bcc', 'نسخة مخفية');
  @override
  String get replyTo => _t('Reply-To', 'Antwort an', 'الرد إلى');
  @override
  String get date => _t('Date', 'Datum', 'التاريخ');
  @override
  String get attachments => _t('Attachments', 'Anhänge', 'المرفقات');
  @override
  String get noBody => _t(
    '(No supported message text)',
    '(Kein unterstützter Nachrichtentext)',
    '(لا يوجد نص رسالة مدعوم)',
  );

  /// Full weekday, date and time, e.g. "Thursday, November 19, 2026 09:42".
  @override
  String formatDate(DateTime date) {
    final locale = studioIntlLocale(language);
    return DateFormat.yMMMMEEEEd(locale).add_Hm().format(date.toLocal());
  }

  @override
  String formatSize(int bytes) {
    final locale = studioIntlLocale(language);
    if (bytes < 1024) {
      return studioPlural(
        language,
        bytes,
        enOne: (_) => '1 byte',
        en: (n) => '$n bytes',
        deOne: (_) => '1 Byte',
        de: (n) => '$n Byte',
        arOne: (_) => 'بايت واحد',
        arTwo: (_) => 'بايتان',
        arFew: (n) => '$n بايتات',
        ar: (n) => '$n بايت',
      );
    }
    if (bytes < 1024 * 1024) {
      final kb = NumberFormat.decimalPattern(
        locale,
      ).format((bytes / 1024).round());
      return _t('$kb KB', '$kb KB', '$kb ك.ب');
    }
    final mb = NumberFormat('0.0', locale).format(bytes / (1024 * 1024));
    return _t('$mb MB', '$mb MB', '$mb م.ب');
  }

  @override
  String status(MailParseStatus status) => switch (status) {
    MailParseStatus.complete => _t('Message', 'Nachricht', 'الرسالة'),
    MailParseStatus.partial => _t(
      'Part of this message could not be displayed',
      'Ein Teil dieser Nachricht kann nicht angezeigt werden',
      'تعذر عرض جزء من هذه الرسالة',
    ),
    MailParseStatus.rejected => _t(
      'This message was not opened',
      'Diese Nachricht wurde nicht geöffnet',
      'لم تُفتح هذه الرسالة',
    ),
    MailParseStatus.unsupported => _t(
      'This message format is not supported',
      'Dieses Nachrichtenformat wird nicht unterstützt',
      'صيغة هذه الرسالة غير مدعومة',
    ),
    MailParseStatus.failed => _t(
      'This message could not be read',
      'Diese Nachricht konnte nicht gelesen werden',
      'تعذرت قراءة هذه الرسالة',
    ),
    MailParseStatus.cancelled => _t(
      'Opening the message was cancelled',
      'Das Öffnen der Nachricht wurde abgebrochen',
      'أُلغي فتح الرسالة',
    ),
  };

  @override
  String get displayUnavailable => _t(
    'Message display unavailable',
    'Nachricht kann nicht angezeigt werden',
    'تعذر عرض الرسالة',
  );
  @override
  String get selectAll => _t('Select all', 'Alles auswählen', 'تحديد الكل');
  @override
  String get copySelection =>
      _t('Copy selection', 'Auswahl kopieren', 'نسخ التحديد');
  @override
  String get findInMessage =>
      _t('Find in message', 'In Nachricht suchen', 'البحث في الرسالة');
  @override
  String get findField => findInMessage;
  @override
  String get rawSource => _t('Raw source', 'Quelltext', 'المصدر الخام');
  @override
  String get hex => _t('Hex', 'Hex', 'ست عشري');
  @override
  String get inspectHeaders =>
      _t('Inspect headers', 'Kopfzeilen prüfen', 'فحص الرؤوس');
  @override
  String get headers =>
      _t('Message headers', 'Nachrichtenkopfzeilen', 'رؤوس الرسالة');
  @override
  String get copyHeaders =>
      _t('Copy headers', 'Kopfzeilen kopieren', 'نسخ الرؤوس');
  @override
  String get headersUnavailable => _t(
    'Raw headers are unavailable for this message.',
    'Die Rohkopfzeilen dieser Nachricht sind nicht verfügbar.',
    'الرؤوس الخام غير متاحة لهذه الرسالة.',
  );
  @override
  String get showPlainText =>
      _t('Show plain text', 'Als Text anzeigen', 'عرض النص العادي');
  @override
  String get showStaticHtml =>
      _t('Show formatted', 'Formatiert anzeigen', 'عرض المنسق');
  @override
  String matches(int count, {required bool more}) {
    final phrase = studioPlural(
      language,
      count,
      enOne: (_) => '1 match',
      en: (n) => '$n matches',
      deOne: (_) => '1 Treffer',
      de: (n) => '$n Treffer',
      arZero: (_) => 'لا توجد نتائج',
      arOne: (_) => 'نتيجة واحدة',
      arTwo: (_) => 'نتيجتان',
      arFew: (n) => '$n نتائج',
      ar: (n) => '$n نتيجة',
    );
    return more ? '$phrase+' : phrase;
  }

  @override
  String get previousMatch => _t(
    'Previous match (Shift+F3)',
    'Vorheriger Treffer (Umschalt+F3)',
    'النتيجة السابقة (Shift+F3)',
  );
  @override
  String get nextMatch =>
      _t('Next match (F3)', 'Nächster Treffer (F3)', 'النتيجة التالية (F3)');
  @override
  String get openReadOnly =>
      _t('Open read only', 'Schreibgeschützt öffnen', 'فتح للقراءة فقط');
}
