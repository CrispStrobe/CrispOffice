import 'package:intl/intl.dart';

import 'studio_strings.dart';

/// Plural-aware count phrases for the Studio UI languages.
///
/// English and German use one/other. Arabic uses zero/one/two/few/many/other
/// (CLDR), chosen by `Intl.plural`; each form builds the whole phrase so the
/// number can be omitted where Arabic expresses it with the noun (نتيجتان).
String studioPlural(
  StudioLanguage language,
  int count, {
  required String Function(int) en,
  required String Function(int) enOne,
  required String Function(int) de,
  required String Function(int) deOne,
  required String Function(int) ar,
  String Function(int)? arZero,
  String Function(int)? arOne,
  String Function(int)? arTwo,
  String Function(int)? arFew,
  String Function(int)? arMany,
}) => switch (language) {
  StudioLanguage.en => Intl.plural(
    count,
    one: enOne(count),
    other: en(count),
    locale: 'en',
  ),
  StudioLanguage.de => Intl.plural(
    count,
    one: deOne(count),
    other: de(count),
    locale: 'de',
  ),
  StudioLanguage.ar => Intl.plural(
    count,
    zero: (arZero ?? ar)(count),
    one: (arOne ?? ar)(count),
    two: (arTwo ?? ar)(count),
    few: (arFew ?? ar)(count),
    many: (arMany ?? ar)(count),
    other: ar(count),
    locale: 'ar',
  ),
};

/// "3 writing issues" / "3 Schreibhinweise" / "٣ ملاحظات".
String studioWritingIssues(StudioLanguage language, int count) => studioPlural(
  language,
  count,
  enOne: (_) => '1 writing issue',
  en: (n) => '$n writing issues',
  deOne: (_) => '1 Schreibhinweis',
  de: (n) => '$n Schreibhinweise',
  arZero: (_) => 'لا توجد ملاحظات',
  arOne: (_) => 'ملاحظة واحدة',
  arTwo: (_) => 'ملاحظتان',
  arFew: (n) => '$n ملاحظات',
  ar: (n) => '$n ملاحظة',
);

/// "3 issues" / "3 Hinweise" / "٣ ملاحظات".
String studioIssues(StudioLanguage language, int count) => studioPlural(
  language,
  count,
  enOne: (_) => '1 issue',
  en: (n) => '$n issues',
  deOne: (_) => '1 Hinweis',
  de: (n) => '$n Hinweise',
  arZero: (_) => 'لا توجد ملاحظات',
  arOne: (_) => 'ملاحظة واحدة',
  arTwo: (_) => 'ملاحظتان',
  arFew: (n) => '$n ملاحظات',
  ar: (n) => '$n ملاحظة',
);

/// "3 changes" / "3 Änderungen" / "٣ تغييرات".
String studioChanges(StudioLanguage language, int count) => studioPlural(
  language,
  count,
  enOne: (_) => '1 change',
  en: (n) => '$n changes',
  deOne: (_) => '1 Änderung',
  de: (n) => '$n Änderungen',
  arZero: (_) => 'لا توجد تغييرات',
  arOne: (_) => 'تغيير واحد',
  arTwo: (_) => 'تغييران',
  arFew: (n) => '$n تغييرات',
  arMany: (n) => '$n تغييرًا',
  ar: (n) => '$n تغيير',
);

/// "3 paragraphs" / "3 Absätze" / "٣ فقرات".
String studioParagraphs(StudioLanguage language, int count) => studioPlural(
  language,
  count,
  enOne: (_) => '1 paragraph',
  en: (n) => '$n paragraphs',
  deOne: (_) => '1 Absatz',
  de: (n) => '$n Absätze',
  arZero: (_) => 'لا توجد فقرات',
  arOne: (_) => 'فقرة واحدة',
  arTwo: (_) => 'فقرتان',
  arFew: (n) => '$n فقرات',
  ar: (n) => '$n فقرة',
);

/// "3 words" / "3 Wörter" / "٣ كلمات".
String studioWords(StudioLanguage language, int count) => studioPlural(
  language,
  count,
  enOne: (_) => '1 word',
  en: (n) => '$n words',
  deOne: (_) => '1 Wort',
  de: (n) => '$n Wörter',
  arZero: (_) => 'لا توجد كلمات',
  arOne: (_) => 'كلمة واحدة',
  arTwo: (_) => 'كلمتان',
  arFew: (n) => '$n كلمات',
  ar: (n) => '$n كلمة',
);

/// "3 comments" / "3 Kommentare" / "٣ تعليقات".
String studioComments(StudioLanguage language, int count) => studioPlural(
  language,
  count,
  enOne: (_) => '1 comment',
  en: (n) => '$n comments',
  deOne: (_) => '1 Kommentar',
  de: (n) => '$n Kommentare',
  arZero: (_) => 'لا توجد تعليقات',
  arOne: (_) => 'تعليق واحد',
  arTwo: (_) => 'تعليقان',
  arFew: (n) => '$n تعليقات',
  arMany: (n) => '$n تعليقًا',
  ar: (n) => '$n تعليق',
);

/// "3 sheets" / "3 Blätter" / "٣ أوراق".
String studioSheets(StudioLanguage language, int count) => studioPlural(
  language,
  count,
  enOne: (_) => '1 sheet',
  en: (n) => '$n sheets',
  deOne: (_) => '1 Blatt',
  de: (n) => '$n Blätter',
  arZero: (_) => 'لا توجد أوراق',
  arOne: (_) => 'ورقة واحدة',
  arTwo: (_) => 'ورقتان',
  arFew: (n) => '$n أوراق',
  ar: (n) => '$n ورقة',
);

/// "4 of 9 packages installed" / "4 von 9 Paketen installiert" /
/// "تم تثبيت ٤ من ٩ حزم"; the noun agrees with [total].
String studioPackagesInstalled(
  StudioLanguage language,
  int installed,
  int total,
) => studioPlural(
  language,
  total,
  enOne: (_) => '$installed of 1 package installed',
  en: (n) => '$installed of $n packages installed',
  deOne: (_) => '$installed von 1 Paket installiert',
  de: (n) => '$installed von $n Paketen installiert',
  arZero: (_) => 'لا توجد حزم',
  arOne: (_) => 'تم تثبيت $installed من حزمة واحدة',
  arTwo: (_) => 'تم تثبيت $installed من حزمتين',
  arFew: (n) => 'تم تثبيت $installed من $n حزم',
  ar: (n) => 'تم تثبيت $installed من $n حزمة',
);

/// "3 cells" / "3 Zellen" / "٣ خلايا".
String studioCells(StudioLanguage language, int count) => studioPlural(
  language,
  count,
  enOne: (_) => '1 cell',
  en: (n) => '$n cells',
  deOne: (_) => '1 Zelle',
  de: (n) => '$n Zellen',
  arZero: (_) => 'لا توجد خلايا',
  arOne: (_) => 'خلية واحدة',
  arTwo: (_) => 'خليتان',
  arFew: (n) => '$n خلايا',
  ar: (n) => '$n خلية',
);
