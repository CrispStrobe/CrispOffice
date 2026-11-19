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

  String get appTitle => 'CrispOffice';
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
  String get about =>
      _t('About CrispOffice', 'Über CrispOffice', 'حول CrispOffice');
  String get mode => _t('Mode', 'Modus', 'الوضع');
  String get look => _t('Appearance', 'Darstellung', 'المظهر');
  String get measurement =>
      _t('Measurement units', 'Maßeinheiten', 'وحدات القياس');
  String get millimetres =>
      _t('Millimetres (mm)', 'Millimeter (mm)', 'ملليمتر (mm)');
  String get centimetres =>
      _t('Centimetres (cm)', 'Zentimeter (cm)', 'سنتيمتر (cm)');
  String get showOutline => _t(
    'Show document outline',
    'Dokumentgliederung anzeigen',
    'إظهار مخطط المستند',
  );
  String get showComments =>
      _t('Show comments', 'Kommentare anzeigen', 'إظهار التعليقات');
  String get showNotes =>
      _t('Show notes', 'Notizen anzeigen', 'إظهار الملاحظات');
  String get showRibbonLabels => _t(
    'Show ribbon section labels',
    'Beschriftungen der Multifunktionsleiste anzeigen',
    'إظهار تسميات أقسام الشريط',
  );
  String get aboutDescription => _t(
    'CrispOffice is an independent document, spreadsheet and presentation workspace.',
    'CrispOffice ist eine unabhängige Arbeitsumgebung für Dokumente, Tabellen und Präsentationen.',
    'CrispOffice مساحة عمل مستقلة للمستندات وجداول البيانات والعروض التقديمية.',
  );
  String get legalNotice => _t(
    'Microsoft, Word, Excel and PowerPoint are trademarks of the Microsoft group of companies. CrispOffice is not affiliated with or endorsed by Microsoft. Product names describe file formats and compatibility only.',
    'Microsoft, Word, Excel und PowerPoint sind Marken der Microsoft-Unternehmensgruppe. CrispOffice steht in keiner Verbindung zu Microsoft und wird nicht von Microsoft unterstützt. Produktnamen beschreiben ausschließlich Dateiformate und Kompatibilität.',
    'Microsoft وWord وExcel وPowerPoint علامات تجارية لمجموعة شركات Microsoft. CrispOffice غير تابع لشركة Microsoft وغير معتمد منها. تُستخدم أسماء المنتجات فقط لوصف صيغ الملفات والتوافق.',
  );
  String get licenses => _t(
    'Open-source licences',
    'Open-Source-Lizenzen',
    'تراخيص المصادر المفتوحة',
  );
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
