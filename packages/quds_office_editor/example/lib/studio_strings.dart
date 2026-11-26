import 'studio_de_strings.dart';

/// User-facing Studio chrome in English, German and Arabic.
enum StudioLanguage { en, de, ar }

final class StudioStrings {
  const StudioStrings(this.language);

  final StudioLanguage language;

  static String de(String english) => studioGerman[english] ?? english;

  String _t(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String productivity(String text) => switch (text) {
    'Tasks' => _t(text, 'Aufgaben', 'المهام'),
    'Accounts' => _t(text, 'Konten', 'الحسابات'),
    'Connections' => _t(text, 'Verbindungen', 'الاتصالات'),
    'All tasks' => _t(text, 'Alle Aufgaben', 'كل المهام'),
    'Search tasks' => _t(text, 'Aufgaben suchen', 'البحث في المهام'),
    'Open' => _t(text, 'Offen', 'مفتوحة'),
    'Due today' => _t(text, 'Heute fällig', 'مستحقة اليوم'),
    'Overdue' => _t(text, 'Überfällig', 'متأخرة'),
    'Completed' => _t(text, 'Erledigt', 'مكتملة'),
    'Add task' => _t(text, 'Aufgabe hinzufügen', 'إضافة مهمة'),
    'Task list' => _t(text, 'Aufgabenliste', 'قائمة المهام'),
    'Task account' => _t(text, 'Aufgabenkonto', 'حساب المهام'),
    'Sync now' => _t(text, 'Jetzt synchronisieren', 'المزامنة الآن'),
    'Disconnect' => _t(text, 'Verbindung trennen', 'قطع الاتصال'),
    'Add account' => _t(text, 'Konto hinzufügen', 'إضافة حساب'),
    'Connect account' => _t(text, 'Konto verbinden', 'ربط حساب'),
    'Read-only list' => _t(
      text,
      'Schreibgeschützte Liste',
      'قائمة للقراءة فقط',
    ),
    'New task' => _t(text, 'Neue Aufgabe', 'مهمة جديدة'),
    'Edit task' => _t(text, 'Aufgabe bearbeiten', 'تعديل المهمة'),
    'On this device' => _t(text, 'Auf diesem Gerät', 'على هذا الجهاز'),
    'Title' => _t(text, 'Titel', 'العنوان'),
    'Notes' => _t(text, 'Notizen', 'ملاحظات'),
    'Set due date' => _t(
      text,
      'Fälligkeitsdatum festlegen',
      'تعيين تاريخ الاستحقاق',
    ),
    'Clear due date' => _t(
      text,
      'Fälligkeitsdatum entfernen',
      'إزالة تاريخ الاستحقاق',
    ),
    'Cancel' => _t(text, 'Abbrechen', 'إلغاء'),
    'Save task' => _t(text, 'Aufgabe speichern', 'حفظ المهمة'),
    'No tasks in this list.' => _t(
      text,
      'Diese Liste enthält keine Aufgaben.',
      'لا توجد مهام في هذه القائمة.',
    ),
    'No tasks match this view.' => _t(
      text,
      'Keine Aufgaben für diese Ansicht.',
      'لا توجد مهام تطابق طريقة العرض هذه.',
    ),
    'Export automation snapshot' => _t(
      text,
      'Automatisierungsdaten exportieren',
      'تصدير لقطة الأتمتة',
    ),
    _ => text,
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
    'Product names are used only to describe file formats and compatibility.',
    'Produktnamen dienen ausschließlich zur Beschreibung von Dateiformaten und Kompatibilität.',
    'تُستخدم أسماء المنتجات فقط لوصف صيغ الملفات والتوافق.',
  );
  String get licenses => _t(
    'Open-source licences',
    'Open-Source-Lizenzen',
    'تراخيص المصادر المفتوحة',
  );
  String get mailTitle =>
      _t('CrispOffice Mail', 'CrispOffice Mail', 'بريد CrispOffice');
  String get savedMessages =>
      _t('Saved messages', 'Gespeicherte Nachrichten', 'الرسائل المحفوظة');
  String get mailAccounts =>
      _t('Mail accounts', 'E-Mail-Konten', 'حسابات البريد');
  String get mailAccountsUnavailable => _t(
    'Mail accounts require the desktop app. You can open saved messages here.',
    'Für E-Mail-Konten benötigen Sie die Desktop-App. Gespeicherte Nachrichten können Sie hier öffnen.',
    'تتطلب حسابات البريد تطبيق سطح المكتب. يمكنك فتح الرسائل المحفوظة هنا.',
  );
  String get backToMessages =>
      _t('Back to messages', 'Zurück zu Nachrichten', 'العودة إلى الرسائل');
  String get openMessage => _t('Open message', 'Nachricht öffnen', 'فتح رسالة');
  String get openMessageFailed => _t(
    'The message could not be opened.',
    'Die Nachricht konnte nicht geöffnet werden.',
    'تعذّر فتح الرسالة.',
  );
  String get fullView => _t('Full', 'Vollständig', 'كامل');
  String get compactView => _t('Compact', 'Kompakt', 'مختصر');
  String get noMessage => _t(
    'Select a message to read it here.',
    'Wählen Sie eine Nachricht aus, um sie hier zu lesen.',
    'اختر رسالة لقراءتها هنا.',
  );
  String get viewLicences =>
      _t('View licences', 'Lizenzen anzeigen', 'عرض التراخيص');
  String get aboutVersion => _t('Version', 'Version', 'الإصدار');
  String get aboutProduct => _t('Product', 'Produkt', 'المنتج');
  String get aboutLegal => _t('Legal', 'Rechtliches', 'قانوني');
  String get aboutSource =>
      _t('Source and attribution', 'Quelle und Zuordnung', 'المصدر والإسناد');
  String get aboutProductText => _t(
    'Documents, spreadsheets and presentations are edited locally by the independent CrispOffice engine. No Microsoft Office installation is required.',
    'Dokumente, Tabellen und Präsentationen werden lokal von der unabhängigen CrispOffice-Engine bearbeitet. Eine Microsoft-Office-Installation ist nicht erforderlich.',
    'تُحرَّر المستندات وجداول البيانات والعروض التقديمية محليًا بواسطة محرك CrispOffice المستقل. لا يلزم تثبيت Microsoft Office.',
  );
  String get aboutSourceText => _t(
    'CrispOffice began as a fork of the MIT-licensed Quds Office Suite by Mohammed Asaad Asaad. CrispStrobe continues development independently.',
    'CrispOffice entstand als Fork der MIT-lizenzierten Quds Office Suite von Mohammed Asaad Asaad. CrispStrobe entwickelt CrispOffice eigenständig weiter.',
    'بدأ CrispOffice كتفرّع من Quds Office Suite التي طوّرها Mohammed Asaad Asaad بترخيص MIT. وتواصل CrispStrobe تطوير CrispOffice بشكل مستقل.',
  );
  String get aboutSourceProject => _t(
    'Original Quds Office Suite',
    'Originalprojekt Quds Office Suite',
    'مشروع Quds Office Suite الأصلي',
  );
  String get serviceProvider =>
      _t('Service Provider', 'Dienstanbieter', 'مزوّد الخدمة');
  String get contact => _t('Contact', 'Kontakt', 'اتصل بنا');
  String get disclaimer =>
      _t('Disclaimer', 'Haftungsausschluss', 'إخلاء المسؤولية');
  String get disclaimerText => _t(
    'This software is provided "as is", without warranty of any kind. CrispOffice is independent software and is not affiliated with any office-suite or cloud provider.',
    'Diese Software wird "wie besehen" bereitgestellt, ohne jegliche Garantie. CrispOffice ist unabhängige Software und nicht mit einem Office- oder Cloud-Anbieter verbunden.',
    'يُقدَّم هذا البرنامج «كما هو» دون أي ضمان. CrispOffice برنامج مستقل وغير تابع لأي مزوّد مكتبي أو سحابي.',
  );
  String get sourceCode => _t(
    'Source Code (GitHub)',
    'Quellcode (GitHub)',
    'الشفرة المصدرية (GitHub)',
  );
  String get website => _t('Website', 'Webseite', 'الموقع الإلكتروني');
  String get privacyPolicy =>
      _t('Privacy Policy', 'Datenschutzerklärung', 'سياسة الخصوصية');

  /// The app's privacy policy on crispstro.be (German page for a German UI,
  /// English otherwise; there is no Arabic page).
  String get privacyPolicyUrl => _t(
    'https://www.crispstro.be/en/crispoffice-privacy/',
    'https://www.crispstro.be/de/crispoffice-datenschutz/',
    'https://www.crispstro.be/en/crispoffice-privacy/',
  );
  String get compose => _t('Compose', 'Verfassen', 'إنشاء');
  String get refresh => _t('Refresh', 'Aktualisieren', 'تحديث');
  String get disconnect => _t('Disconnect', 'Trennen', 'قطع الاتصال');
  String get connect => _t('Connect', 'Verbinden', 'اتصال');
  String get emailAddress =>
      _t('Email address', 'E-Mail-Adresse', 'عنوان البريد');
  String get password => _t('Password', 'Passwort', 'كلمة المرور');
  String get manualServers => _t(
    'Manual server settings',
    'Manuelle Servereinstellungen',
    'إعدادات الخادم اليدوية',
  );
  String get imapHost => _t('IMAP host', 'IMAP-Server', 'خادم IMAP');
  String get smtpHost => _t('SMTP host', 'SMTP-Server', 'خادم SMTP');
  String get mailSetupHelp => _t(
    'Connect an IMAP/SMTP account. Automatic discovery is used unless manual server settings are enabled.',
    'Verbinden Sie ein IMAP-/SMTP-Konto. Die automatische Erkennung wird verwendet, sofern keine manuellen Servereinstellungen aktiviert sind.',
    'اتصل بحساب IMAP/SMTP. يُستخدم الاكتشاف التلقائي ما لم يتم تفعيل إعدادات الخادم اليدوية.',
  );
  String get mailSessionNotice => _t(
    'With Remember enabled, the account and password are saved in the selected credential store after a successful connection. Messages and drafts remain in this session.',
    'Mit aktivierter Speicheroption werden Konto und Passwort nach erfolgreicher Verbindung im gewählten Zugangsdaten-Speicher gespeichert. Nachrichten und Entwürfe bleiben in dieser Sitzung.',
    'عند تفعيل الحفظ، يُحفظ الحساب وكلمة المرور في مخزن بيانات الاعتماد المحدد بعد اتصال ناجح. تبقى الرسائل والمسودات في هذه الجلسة.',
  );
  String get searchMail => _t('Search mail', 'E-Mail suchen', 'بحث في البريد');
  String get noMessages =>
      _t('No messages', 'Keine Nachrichten', 'لا توجد رسائل');
  String get to => _t('To', 'An', 'إلى');
  String get subject => _t('Subject', 'Betreff', 'الموضوع');
  String get messageBody => _t('Message', 'Nachricht', 'الرسالة');
  String get send => _t('Send', 'Senden', 'إرسال');
  String get sending => _t('Sending…', 'Wird gesendet …', 'جارٍ الإرسال…');
  String get messageSent =>
      _t('Message sent', 'Nachricht gesendet', 'تم إرسال الرسالة');
  String get sentCopyWarning => _t(
    'A copy could not be saved to Sent.',
    'Eine Kopie konnte nicht im Ordner „Gesendet“ gespeichert werden.',
    'تعذّر حفظ نسخة في مجلد «المرسلة».',
  );
  String get sentCleanupWarning => _t(
    'The outgoing connection could not close cleanly.',
    'Die ausgehende Verbindung konnte nicht sauber geschlossen werden.',
    'تعذّر إغلاق اتصال الإرسال بشكل سليم.',
  );
  String get cancel => _t('Cancel', 'Abbrechen', 'إلغاء');
}
