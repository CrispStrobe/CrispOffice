/// User-facing Studio chrome in English, German and Arabic.
enum StudioLanguage { en, de, ar }

final class StudioStrings {
  const StudioStrings(this.language);

  final StudioLanguage language;

  String _t(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get appTitle => 'CrispOffice Studio';
  String get documents => _t('Documents', 'Dokumente', 'المستندات');
  String get spreadsheets => _t('Spreadsheets', 'Tabellen', 'جداول البيانات');
  String get presentations =>
      _t('Presentations', 'Präsentationen', 'العروض التقديمية');
  String get pdf => 'PDF';
  String get mail => _t('Mail', 'E-Mail', 'البريد');
  String get settings => _t('Settings', 'Einstellungen', 'الإعدادات');
  String get account => _t('Account', 'Konto', 'الحساب');
  String get save => _t('Save', 'Speichern', 'حفظ');
  String get undo => _t('Undo', 'Rückgängig', 'تراجع');
  String get redo => _t('Redo', 'Wiederholen', 'إعادة');
  String get minimize => _t('Minimize', 'Minimieren', 'تصغير');
  String get maximize => _t('Maximize', 'Maximieren', 'تكبير');
  String get restore => _t('Restore', 'Wiederherstellen', 'استعادة');
  String get close => _t('Close', 'Schließen', 'إغلاق');
  String get languageLabel => _t('Language', 'Sprache', 'اللغة');
  String get mailTitle =>
      _t('CrispOffice Mail', 'CrispOffice Mail', 'بريد CrispOffice');
  String get openMessage => _t('Open message', 'Nachricht öffnen', 'فتح رسالة');
  String get fullView => _t('Full', 'Vollständig', 'كامل');
  String get compactView => _t('Compact', 'Kompakt', 'مختصر');
  String get noMessage => _t(
    'Open an .eml message to read it here.',
    'Öffnen Sie eine .eml-Nachricht, um sie hier zu lesen.',
    'افتح رسالة .eml لقراءتها هنا.',
  );
}
