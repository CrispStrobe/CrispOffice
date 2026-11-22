import 'studio_strings.dart';

extension StudioMailTagStrings on StudioStrings {
  String _t(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailTags => _t('Tags', 'Tags', 'الوسوم');
  String get mailTagsHelp => _t(
    'Local tags help you group saved mail. They are not sent to the mail server and do not change folders or labels.',
    'Lokale Tags gruppieren gespeicherte E-Mails. Sie werden nicht an den Mailserver gesendet und ändern keine Ordner oder Labels.',
    'تساعد الوسوم المحلية على تجميع البريد المحفوظ. لا تُرسل إلى خادم البريد ولا تغيّر المجلدات أو التسميات.',
  );
  String get mailTagAdd => _t('Add tag', 'Tag hinzufügen', 'إضافة وسم');
  String get mailTagName => _t('Tag name', 'Tag-Name', 'اسم الوسم');
  String get mailTagKnown => _t(
    'Tags in this account',
    'Tags in diesem Konto',
    'الوسوم في هذا الحساب',
  );
  String get mailTagSelected => _t(
    'Selected for this message',
    'Für diese Nachricht ausgewählt',
    'المحددة لهذه الرسالة',
  );
  String get mailTagInvalid => _t(
    'Use 1–64 letters, numbers, spaces, dots, hyphens or underscores.',
    'Verwenden Sie 1–64 Buchstaben, Ziffern, Leerzeichen, Punkte, Bindestriche oder Unterstriche.',
    'استخدم من 1 إلى 64 حرفًا أو رقمًا أو مسافة أو نقطة أو شرطة أو شرطة سفلية.',
  );
  String get mailTagLoadFailed => _t(
    'Tags could not be loaded. Close and reopen this menu to retry.',
    'Tags konnten nicht geladen werden. Schließen und öffnen Sie das Menü erneut.',
    'تعذر تحميل الوسوم. أغلق القائمة وافتحها مجددًا للمحاولة.',
  );
  String get mailTagSaveFailed => _t(
    'Tags could not be saved. Your previous tags were retained.',
    'Tags konnten nicht gespeichert werden. Die bisherigen Tags bleiben erhalten.',
    'تعذر حفظ الوسوم. تم الاحتفاظ بالوسوم السابقة.',
  );
  String get mailTagSaved =>
      _t('Tags saved.', 'Tags gespeichert.', 'تم حفظ الوسوم.');
  String get mailTagRemove => _t('Remove tag', 'Tag entfernen', 'إزالة الوسم');
}
