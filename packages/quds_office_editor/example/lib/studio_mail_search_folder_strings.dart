import 'studio_strings.dart';

extension StudioMailSearchFolderStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailSearchChooseFolders =>
      _text('Choose folders…', 'Ordner wählen…', 'اختيار المجلدات…');
  String get mailSearchFolderTitle =>
      _text('Search folders', 'Ordner durchsuchen', 'مجلدات البحث');
  String get mailSearchFolderAll => _text(
    'All folders in selected accounts',
    'Alle Ordner der gewählten Konten',
    'جميع المجلدات في الحسابات المحددة',
  );
  String get mailSearchFolderAbout => _text(
    'Choose folders known on this device. An explicit selection keeps the same folders when new ones appear. Only saved message headers are searched.',
    'Wählen Sie auf diesem Gerät bekannte Ordner. Eine feste Auswahl wird nicht um neu hinzukommende Ordner erweitert. Durchsucht werden nur gespeicherte Nachrichtenköpfe.',
    'اختر المجلدات المعروفة على هذا الجهاز. يظل الاختيار المحدد كما هو عند ظهور مجلدات جديدة. يشمل البحث رؤوس الرسائل المحفوظة فقط.',
  );
  String get mailSearchFolderApply =>
      _text('Use this selection', 'Auswahl übernehmen', 'استخدام هذا الاختيار');
  String get mailSearchFolderRequired => _text(
    'Choose at least one folder, or explicitly choose all folders.',
    'Wählen Sie mindestens einen Ordner oder ausdrücklich alle Ordner.',
    'اختر مجلدًا واحدًا على الأقل، أو اختر جميع المجلدات صراحةً.',
  );
  String get mailSearchFolderUnavailable => _text(
    'Unavailable in the local folder catalog',
    'Im lokalen Ordnerverzeichnis nicht verfügbar',
    'غير متاح في قائمة المجلدات المحلية',
  );
  String get mailSearchFolderUnchecked => _text(
    'Folder availability could not be checked.',
    'Die Verfügbarkeit der Ordner konnte nicht geprüft werden.',
    'تعذر التحقق من توفر المجلدات.',
  );
  String get mailSearchFolderNone => _text(
    'No local folders are available. Connect this account and browse or synchronize folders, then reopen this chooser.',
    'Keine lokalen Ordner verfügbar. Verbinden Sie dieses Konto und öffnen oder synchronisieren Sie Ordner. Öffnen Sie danach diese Auswahl erneut.',
    'لا توجد مجلدات محلية متاحة. اتصل بهذا الحساب وتصفح المجلدات أو زامنها، ثم أعد فتح هذه القائمة.',
  );
  String get mailSearchFolderMissing => _text(
    'Some selected folders are unavailable locally. Results stay within the remaining selected folders. Choose folders to repair the selection, or reconnect the account to restore its folders.',
    'Einige gewählte Ordner sind lokal nicht verfügbar. Ergebnisse bleiben auf die übrigen gewählten Ordner beschränkt. Korrigieren Sie die Auswahl oder verbinden Sie das Konto erneut, um seine Ordner wiederherzustellen.',
    'بعض المجلدات المحددة غير متاحة محليًا. تظل النتائج ضمن المجلدات المحددة المتبقية. صحّح الاختيار أو أعد الاتصال بالحساب لاستعادة مجلداته.',
  );
  String get mailSearchFolderRefreshMissing => _text(
    'Some selected folders are unavailable. Automatic updates are off. Review search coverage and choose folders to repair the selection.',
    'Einige gewählte Ordner sind nicht verfügbar. Automatische Aktualisierungen sind ausgeschaltet. Prüfen Sie den Suchumfang und korrigieren Sie die Ordnerauswahl.',
    'بعض المجلدات المحددة غير متاحة. التحديث التلقائي متوقف. راجع نطاق البحث وصحّح اختيار المجلدات.',
  );
  String get mailSearchFolderChanged => _text(
    'Folder selection changed. Update the saved search to keep this selection.',
    'Ordnerauswahl geändert. Aktualisieren Sie die gespeicherte Suche, um diese Auswahl zu behalten.',
    'تغير اختيار المجلدات. حدّث البحث المحفوظ للاحتفاظ بهذا الاختيار.',
  );
  String get mailSearchFolderNoCheckpoint => _text(
    'No retained folder checkpoint; server coverage is unknown.',
    'Kein gespeicherter Ordnerstand; der Serverumfang ist unbekannt.',
    'لا توجد نقطة حفظ للمجلد؛ نطاق البريد على الخادم غير معروف.',
  );
  String mailSearchFolderCount(int count) => _text(
    'Selected folders: $count',
    'Gewählte Ordner: $count',
    'المجلدات المحددة: $count',
  );
  String mailSearchFolderAccounts(int count) => _text(
    'Selected accounts ($count)',
    'Gewählte Konten ($count)',
    'الحسابات المحددة ($count)',
  );
  String mailSearchFolderLimit(int count) => _text(
    'Choose no more than $count folders.',
    'Wählen Sie höchstens $count Ordner.',
    'اختر ما لا يزيد عن $count مجلد.',
  );
  String mailSearchFolderBrowseCoverage(int count, String date) => _text(
    'Browsed headers: $count · Saved: $date',
    'Besuchte Nachrichtenköpfe: $count · Gespeichert: $date',
    'الرؤوس المتصفحة: $count · الحفظ: $date',
  );
  String mailSearchFolderSyncCoverage(int count, String date) => _text(
    'Synchronized headers: $count · Saved: $date',
    'Synchronisierte Nachrichtenköpfe: $count · Gespeichert: $date',
    'الرؤوس المتزامنة: $count · الحفظ: $date',
  );
}
