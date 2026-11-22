import 'studio_strings.dart';

extension StudioMailSavedSearchStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailSavedSearches =>
      _text('Saved searches', 'Gespeicherte Suchen', 'عمليات البحث المحفوظة');
  String get mailSavedSearchChoose => _text(
    'Choose a saved search',
    'Gespeicherte Suche wählen',
    'اختر بحثًا محفوظًا',
  );
  String get mailSavedSearchReload => _text(
    'Reload saved searches',
    'Gespeicherte Suchen neu laden',
    'إعادة تحميل عمليات البحث المحفوظة',
  );
  String get mailSavedSearchAbout => _text(
    'Opening a saved search checks current saved headers in its original accounts. Use Search to refresh results.',
    'Beim Öffnen werden die aktuell gespeicherten Nachrichtenköpfe der ursprünglich gewählten Konten geprüft. Mit „Suchen“ aktualisieren Sie die Ergebnisse.',
    'يفحص فتح البحث المحفوظ رؤوس الرسائل المحفوظة حاليًا في حساباته الأصلية. استخدم «بحث» لتحديث النتائج.',
  );
  String get mailSavedSearchSaveAs =>
      _text('Save search as…', 'Suche speichern unter…', 'حفظ البحث باسم…');
  String get mailSavedSearchSave => _text('Save', 'Speichern', 'حفظ');
  String get mailSavedSearchName =>
      _text('Search name', 'Name der Suche', 'اسم البحث');
  String get mailSavedSearchUpdate => _text(
    'Update saved search…',
    'Gespeicherte Suche ändern…',
    'تحديث البحث المحفوظ…',
  );
  String get mailSavedSearchDelete => _text(
    'Delete saved search',
    'Gespeicherte Suche löschen',
    'حذف البحث المحفوظ',
  );
  String get mailSavedSearchSaved =>
      _text('Search saved.', 'Suche gespeichert.', 'حُفظ البحث.');
  String get mailSavedSearchDeleted => _text(
    'Saved search deleted. Messages are unchanged.',
    'Gespeicherte Suche gelöscht. Nachrichten bleiben unverändert.',
    'حُذف البحث المحفوظ. لم تتغير الرسائل.',
  );
  String mailSavedSearchDeleteAbout(String name) => _text(
    'Delete “$name”? This removes only the saved search. Your messages remain available.',
    '„$name“ löschen? Dadurch wird nur die gespeicherte Suche entfernt. Ihre Nachrichten bleiben verfügbar.',
    'هل تريد حذف «$name»؟ سيُحذف البحث المحفوظ فقط. ستظل رسائلك متاحة.',
  );
  String mailSavedSearchAccountCount(int count) => _text(
    'Saved account scope ($count)',
    'Gespeicherter Kontenbereich ($count)',
    'نطاق الحسابات المحفوظ ($count)',
  );
  String get mailSavedSearchMissingAccounts => _text(
    'Some accounts in this search are unavailable here. The search has not run. Choose an available account scope to update it.',
    'Einige Konten dieser Suche sind hier nicht verfügbar. Die Suche wurde nicht ausgeführt. Wählen Sie einen verfügbaren Kontenbereich, um sie zu ändern.',
    'بعض حسابات هذا البحث غير متاحة هنا. لم يُنفّذ البحث. اختر نطاق حسابات متاحًا لتحديثه.',
  );
  String get mailSavedSearchChooseFolders =>
      _text('Choose folders…', 'Ordner auswählen…', 'اختيار المجلدات…');
  String get mailSavedSearchAllFolders => _text(
    'All retained folders',
    'Alle gespeicherten Ordner',
    'جميع المجلدات المحفوظة',
  );
  String mailSavedSearchSelectedFolders(int count) => _text(
    '$count selected folders',
    '$count ausgewählte Ordner',
    '$count مجلدات محددة',
  );
  String get mailSavedSearchFolderScopeHelp => _text(
    'Select at least one retained folder per account. Only checked folders will be searched. Missing folders must be removed explicitly.',
    'Wählen Sie mindestens einen gespeicherten Ordner pro Konto. Nur markierte Ordner werden durchsucht. Fehlende Ordner müssen ausdrücklich entfernt werden.',
    'اختر مجلدًا محفوظًا واحدًا على الأقل لكل حساب. سيُبحث فقط في المجلدات المحددة. يجب إزالة المجلدات المفقودة صراحةً.',
  );
  String get mailSavedSearchApplyFolders => _text(
    'Use selected folders',
    'Ausgewählte Ordner verwenden',
    'استخدام المجلدات المحددة',
  );
  String get mailSavedSearchFolderMissing => _text(
    'A selected folder is no longer available in retained mail. The search was not expanded. Choose folders again to recover.',
    'Ein ausgewählter Ordner ist nicht mehr im gespeicherten Bestand verfügbar. Die Suche wurde nicht erweitert. Wählen Sie die Ordner erneut.',
    'لم يعد أحد المجلدات المحددة متاحًا في البريد المحفوظ. لم يتم توسيع البحث. اختر المجلدات مجددًا للاستعادة.',
  );
  String get mailSavedSearchFolderReadFailed => _text(
    'Retained folder inventory could not be verified. The previous selection is unchanged; retry Choose folders.',
    'Die gespeicherten Ordner konnten nicht überprüft werden. Die bisherige Auswahl bleibt erhalten; versuchen Sie „Ordner auswählen“ erneut.',
    'تعذر التحقق من قائمة المجلدات المحفوظة. لم يتغير التحديد السابق؛ أعد محاولة اختيار المجلدات.',
  );

  String get mailSavedSearchLoadFailed => _text(
    'Saved searches could not be loaded. Reload to try again.',
    'Gespeicherte Suchen konnten nicht geladen werden. Versuchen Sie es mit „Neu laden“ erneut.',
    'تعذر تحميل عمليات البحث المحفوظة. أعد التحميل للمحاولة مجددًا.',
  );
  String get mailSavedSearchWriteFailed => _text(
    'The change could not be confirmed. Reload saved searches to check their current state before trying again.',
    'Die Änderung konnte nicht bestätigt werden. Laden Sie die gespeicherten Suchen neu, um vor einem erneuten Versuch den aktuellen Stand zu prüfen.',
    'تعذر تأكيد التغيير. أعد تحميل عمليات البحث المحفوظة للتحقق من حالتها الحالية قبل المحاولة مجددًا.',
  );
  String get mailSavedSearchConflict => _text(
    'The name already exists, the search changed, or an account is no longer available. Reload saved searches and select the current definition before retrying.',
    'Der Name ist bereits vorhanden, die Suche wurde geändert oder ein Konto ist nicht mehr verfügbar. Laden Sie die Suchen neu und wählen Sie vor dem nächsten Versuch die aktuelle Definition.',
    'الاسم موجود بالفعل، أو تغير البحث، أو لم يعد أحد الحسابات متاحًا. أعد تحميل عمليات البحث واختر التعريف الحالي قبل المحاولة مجددًا.',
  );
  String get mailSavedSearchLimit => _text(
    'The saved-search limit was reached. Remove an unused saved search before adding another.',
    'Die Höchstzahl gespeicherter Suchen ist erreicht. Entfernen Sie eine nicht mehr benötigte Suche, bevor Sie eine weitere hinzufügen.',
    'وصلت إلى الحد الأقصى لعمليات البحث المحفوظة. احذف بحثًا لم تعد تحتاجه قبل إضافة بحث آخر.',
  );
}
