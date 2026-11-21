import 'studio_strings.dart';

extension StudioMailCachedSearchStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailCachedSearch => _text(
    'Search saved mail',
    'Gespeicherte E-Mails suchen',
    'البحث في البريد المحفوظ',
  );
  String get mailCachedSearchScope => _text(
    'Accounts to search',
    'Zu durchsuchende Konten',
    'الحسابات المراد البحث فيها',
  );
  String get mailCachedSearchAll => _text(
    'All listed accounts',
    'Alle aufgeführten Konten',
    'كل الحسابات المدرجة',
  );
  String get mailCachedSearchQuery =>
      _text('Search query', 'Suchabfrage', 'عبارة البحث');
  String get mailCachedSearchStart => _text('Search', 'Suchen', 'بحث');
  String get mailCachedSearchMore =>
      _text('Search more', 'Weitersuchen', 'متابعة البحث');
  String get mailCachedSearchStop =>
      _text('Cancel search', 'Suche abbrechen', 'إلغاء البحث');
  String get mailCachedSearchHelp => _text(
    'Search help and coverage',
    'Suchhilfe und Umfang',
    'مساعدة البحث ونطاقه',
  );
  String get mailCachedSearchAbout => _text(
    'Search message headers saved on this device across accounts and folders. Results depend on what has been saved; message text and attachments are not searched.',
    'Durchsuchen Sie auf diesem Gerät gespeicherte Nachrichtenköpfe über Konten und Ordner hinweg. Ergebnisse hängen vom gespeicherten Bestand ab; Nachrichtentext und Anhänge werden nicht durchsucht.',
    'ابحث في رؤوس الرسائل المحفوظة على هذا الجهاز عبر الحسابات والمجلدات. تعتمد النتائج على البريد المحفوظ؛ لا يشمل البحث نصوص الرسائل أو المرفقات.',
  );
  String get mailCachedSearchGrammar => _text(
    'Use spaces or AND to require both terms, OR for alternatives, and NOT or - to exclude a term. Parentheses group conditions. Search from:, to:, cc:, subject:, is:read, is:unread, is:flagged, is:unflagged, or before:, after:, on: with YYYY-MM-DD dates. Quote phrases. Missing dates and flags remain unknown when negated. Limits: 1,024 characters, 32 terms, 32 operators and 8 nested groups.',
    'Leerzeichen oder AND verlangen beide Begriffe, OR erlaubt Alternativen, NOT oder - schließt einen Begriff aus. Klammern gruppieren Bedingungen. Felder: from:, to:, cc:, subject:, is:read, is:unread, is:flagged, is:unflagged sowie before:, after:, on: mit Datum im Format YYYY-MM-DD. Wortgruppen in Anführungszeichen setzen. Fehlende Datums- und Statuswerte bleiben auch bei Verneinung unbekannt. Grenzen: 1.024 Zeichen, 32 Begriffe, 32 Operatoren und 8 Klammerebenen.',
    'تتطلب المسافات أو \u2066AND\u2069 تحقق المصطلحين؛ استخدم \u2066OR\u2069 للبدائل و\u2066NOT\u2069 أو \u2066-\u2069 للاستبعاد. تجمع الأقواس الشروط. الحقول: \u2066from:\u2069 و\u2066to:\u2069 و\u2066cc:\u2069 و\u2066subject:\u2069 و\u2066is:read\u2069 و\u2066is:unread\u2069 و\u2066is:flagged\u2069 و\u2066is:unflagged\u2069، أو \u2066before:\u2069 و\u2066after:\u2069 و\u2066on:\u2069 مع تاريخ بصيغة \u2066YYYY-MM-DD\u2069. ضع العبارات بين علامتي اقتباس. تظل التواريخ والحالات المفقودة مجهولة عند النفي. الحدود: 1024 حرفًا و32 مصطلحًا و32 عاملًا و8 مستويات من الأقواس.',
  );
  String get mailCachedSearchReady => _text(
    'Choose the accounts and start a search. An empty query lists saved headers.',
    'Wählen Sie die Konten und starten Sie die Suche. Eine leere Abfrage zeigt gespeicherte Nachrichtenköpfe.',
    'اختر الحسابات وابدأ البحث. تعرض العبارة الفارغة رؤوس الرسائل المحفوظة.',
  );
  String get mailCachedSearchNoAccounts => _text(
    'No saved accounts are available in this scope.',
    'In diesem Bereich sind keine gespeicherten Konten verfügbar.',
    'لا توجد حسابات محفوظة في هذا النطاق.',
  );
  String get mailCachedSearchInvalid => _text(
    'Check the search fields, dates, quotes and Boolean operators. Open search help for examples and limits.',
    'Prüfen Sie Suchfelder, Datumsangaben, Anführungszeichen und logische Operatoren. Die Suchhilfe enthält Beispiele und Grenzen.',
    'تحقق من حقول البحث والتواريخ والاقتباسات والعوامل المنطقية. تتضمن مساعدة البحث أمثلة وحدودًا.',
  );
  String get mailCachedSearchFailed => _text(
    'Saved mail could not be read. Start a new search to try again.',
    'Gespeicherte E-Mails konnten nicht gelesen werden. Starten Sie die Suche erneut.',
    'تعذرت قراءة البريد المحفوظ. ابدأ بحثًا جديدًا للمحاولة مجددًا.',
  );
  String get mailCachedSearchAccountsFailed => _text(
    'Saved accounts could not be read. Close and reopen search to try again.',
    'Gespeicherte Konten konnten nicht gelesen werden. Schließen und öffnen Sie die Suche erneut.',
    'تعذرت قراءة الحسابات المحفوظة. أغلق البحث وافتحه للمحاولة مجددًا.',
  );
  String get mailCachedSearchCloseFailed => _text(
    'Local storage could not be closed. Try Close again before opening another mailbox.',
    'Der lokale Speicher konnte nicht geschlossen werden. Versuchen Sie erneut „Schließen“, bevor Sie ein anderes Postfach öffnen.',
    'تعذر إغلاق التخزين المحلي. حاول الإغلاق مجددًا قبل فتح صندوق بريد آخر.',
  );
  String get mailCachedSearchExpired => _text(
    'The account context changed. Close and reopen saved mail search.',
    'Der Kontokontext hat sich geändert. Schließen und öffnen Sie die Suche erneut.',
    'تغير سياق الحساب. أغلق البحث في البريد المحفوظ وافتحه مجددًا.',
  );
  String get mailCachedSearchEmptyMore => _text(
    'No matches in the saved headers checked so far. Search more to continue.',
    'Bisher keine Treffer in den geprüften gespeicherten Nachrichtenköpfen. Setzen Sie die Suche fort.',
    'لا توجد نتائج في الرؤوس المحفوظة التي فُحصت حتى الآن. تابع البحث للمزيد.',
  );
  String get mailCachedSearchEmpty => _text(
    'No matches in the accounts that could be checked. Review coverage below.',
    'Keine Treffer in den Konten, die geprüft werden konnten. Beachten Sie den Suchumfang unten.',
    'لا توجد نتائج في الحسابات التي أمكن فحصها. راجع نطاق البحث أدناه.',
  );
  String get mailCachedSearchLimit => _text(
    'Showing 1,000 matches. The selected scope has not been fully checked; refine your query to continue.',
    '1.000 Treffer angezeigt. Der gewählte Bereich wurde noch nicht vollständig geprüft; grenzen Sie die Suche ein.',
    'تُعرض 1000 نتيجة. لم يُفحص النطاق المحدد بالكامل؛ حدّد عبارة البحث بدقة أكبر للمتابعة.',
  );
  String get mailCachedSearchCoverage =>
      _text('Search coverage', 'Suchumfang', 'نطاق البحث');
  String get mailCachedSearchAccountFailed => _text(
    'This account could not be checked completely.',
    'Dieses Konto konnte nicht vollständig geprüft werden.',
    'تعذر فحص هذا الحساب بالكامل.',
  );
  String get mailCachedSearchLocalFinished => _text(
    'Saved headers checked. Mail not saved on this device may be missing.',
    'Gespeicherte Nachrichtenköpfe geprüft. Nicht auf diesem Gerät gespeicherte E-Mails können fehlen.',
    'فُحصت الرؤوس المحفوظة. قد لا يظهر البريد غير المحفوظ على هذا الجهاز.',
  );
  String get mailCachedSearchPartialFolders => _text(
    'Some saved folders had more mail available when last updated.',
    'Einige gespeicherte Ordner enthielten beim letzten Aktualisieren weitere E-Mails.',
    'كانت بعض المجلدات المحفوظة تحتوي على بريد إضافي عند آخر تحديث.',
  );
  String get mailCachedSearchUnknownCoverage => _text(
    'Folder update checkpoints are unavailable; server coverage is unknown.',
    'Aktualisierungsstände der Ordner fehlen; der Serverumfang ist unbekannt.',
    'لا تتوفر نقاط تحديث المجلدات؛ نطاق البريد على الخادم غير معروف.',
  );
  String get mailCachedSearchSavedBody => _text(
    'Message saved offline',
    'Nachricht offline gespeichert',
    'الرسالة محفوظة دون اتصال',
  );
  String get mailCachedSearchHeaderOnly =>
      _text('Header only', 'Nur Nachrichtenkopf', 'رأس الرسالة فقط');
  String get mailCachedSearchMissingBody => _text(
    'This message body is not saved on this device. Connect to the account to download it.',
    'Der Nachrichtentext ist nicht auf diesem Gerät gespeichert. Verbinden Sie das Konto, um ihn herunterzuladen.',
    'نص هذه الرسالة غير محفوظ على هذا الجهاز. اتصل بالحساب لتنزيله.',
  );
  String get mailCachedSearchBack => _text(
    'Back to search results',
    'Zurück zu den Suchergebnissen',
    'العودة إلى نتائج البحث',
  );
  String get mailCachedSearchLoading => _text(
    'Reading saved mail…',
    'Gespeicherte E-Mails werden gelesen…',
    'جارٍ قراءة البريد المحفوظ…',
  );
  String mailCachedSearchMatches(int count) => _text(
    'Matches shown: $count',
    'Angezeigte Treffer: $count',
    'النتائج المعروضة: $count',
  );
  String mailCachedSearchProgress(int checked, int total) => _text(
    'Saved headers checked: $checked / $total',
    'Geprüfte gespeicherte Nachrichtenköpfe: $checked / $total',
    'الرؤوس المحفوظة التي فُحصت: $checked / $total',
  );
  String mailCachedSearchFolders(int browsed, int synced) => _text(
    'Browsed folders: $browsed · Synchronized folders: $synced',
    'Besuchte Ordner: $browsed · Synchronisierte Ordner: $synced',
    'المجلدات المتصفحة: $browsed · المجلدات المتزامنة: $synced',
  );
  String mailCachedSearchSavedBetween(String oldest, String newest) => _text(
    'Folder observations saved between $oldest and $newest.',
    'Ordnerstände zwischen $oldest und $newest gespeichert.',
    'حُفظت حالات المجلدات بين $oldest و$newest.',
  );
  String mailCachedSearchOtherFolders(int count) => _text(
    'Other folders: $count',
    'Weitere Ordner: $count',
    'مجلدات أخرى: $count',
  );
}
