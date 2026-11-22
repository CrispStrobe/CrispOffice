import 'studio_mail_archive_destination.dart';
import 'studio_strings.dart';

extension StudioMailArchiveSettingsStrings on StudioStrings {
  String _archiveText(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailArchiveSettingsTitle =>
      _archiveText('Archive destination', 'Archivzielordner', 'مجلد الأرشيف');

  String get mailArchiveSettingsHelp => _archiveText(
    'Choose the folder used by Archive for this account. Saving this choice does not move messages. You will still review each Archive action.',
    'Wählen Sie den Ordner, den Archivieren für dieses Konto verwendet. Das Speichern dieser Auswahl verschiebt keine Nachrichten. Jede Archivierung wird weiterhin bestätigt.',
    'اختر المجلد المستخدم للأرشفة في هذا الحساب. لا يؤدي حفظ الاختيار إلى نقل الرسائل. ستظل تراجع كل إجراء أرشفة.',
  );

  String get mailArchiveSettingsDefault => _archiveText(
    'No custom destination. Archive uses the server default when available, otherwise you choose a folder for each action.',
    'Kein eigener Zielordner. Archivieren verwendet den Serverstandard, sofern verfügbar. Andernfalls wählen Sie für jede Aktion einen Ordner.',
    'لا يوجد مجلد مخصص. تستخدم الأرشفة مجلد الخادم الافتراضي إن توفر، وإلا تختار مجلدًا لكل إجراء.',
  );

  String get mailArchiveSettingsSavedDestination => _archiveText(
    'Saved Archive destination',
    'Gespeicherter Archivzielordner',
    'مجلد الأرشيف المحفوظ',
  );

  String get mailArchiveSettingsMissing => _archiveText(
    'The saved folder is unavailable. Choose another folder or clear the saved destination. No other folder will be used automatically.',
    'Der gespeicherte Ordner ist nicht verfügbar. Wählen Sie einen anderen Ordner oder löschen Sie die gespeicherte Auswahl. Es wird nicht automatisch ein anderer Ordner verwendet.',
    'المجلد المحفوظ غير متاح. اختر مجلدًا آخر أو امسح الوجهة المحفوظة. لن يُستخدم مجلد آخر تلقائيًا.',
  );

  String get mailArchiveSettingsSave =>
      _archiveText('Save destination', 'Zielordner speichern', 'حفظ المجلد');

  String get mailArchiveSettingsClear => _archiveText(
    'Clear saved destination',
    'Gespeicherten Zielordner löschen',
    'مسح المجلد المحفوظ',
  );

  String get mailArchiveSettingsReload => _archiveText(
    'Reload settings and folders',
    'Einstellungen und Ordner neu laden',
    'إعادة تحميل الإعدادات والمجلدات',
  );

  String get mailArchiveSettingsLoadFailed => _archiveText(
    'The saved destination or folder list could not be read. Reload and try again.',
    'Der gespeicherte Zielordner oder die Ordnerliste konnte nicht gelesen werden. Laden Sie sie erneut und versuchen Sie es noch einmal.',
    'تعذر قراءة المجلد المحفوظ أو قائمة المجلدات. أعد التحميل وحاول مجددًا.',
  );

  String get mailArchiveSettingsSaveFailed => _archiveText(
    'The destination could not be saved, or it changed in another window. Reload before trying again.',
    'Der Zielordner konnte nicht gespeichert werden oder wurde in einem anderen Fenster geändert. Laden Sie die Einstellungen vor einem erneuten Versuch neu.',
    'تعذر حفظ المجلد أو تغير في نافذة أخرى. أعد التحميل قبل المحاولة مجددًا.',
  );

  String get mailArchiveSettingsUpdated => _archiveText(
    'Archive destination saved. No messages were moved.',
    'Archivzielordner gespeichert. Es wurden keine Nachrichten verschoben.',
    'حُفظ مجلد الأرشيف. لم تُنقل أي رسائل.',
  );

  String mailArchiveDestinationFailure(
    StudioMailArchiveDestinationFailure failure,
  ) => switch (failure) {
    StudioMailArchiveDestinationFailure.missing => _archiveText(
      'The saved Archive folder is unavailable. Open Archive destination to change or clear it. No messages were moved.',
      'Der gespeicherte Archivordner ist nicht verfügbar. Öffnen Sie Archivzielordner, um ihn zu ändern oder zu löschen. Es wurden keine Nachrichten verschoben.',
      'مجلد الأرشيف المحفوظ غير متاح. افتح مجلد الأرشيف لتغييره أو مسحه. لم تُنقل أي رسائل.',
    ),
    StudioMailArchiveDestinationFailure.changed => _archiveText(
      'The Archive destination changed while you were reviewing it. Review the action again. No messages were moved.',
      'Der Archivzielordner wurde während der Bestätigung geändert. Prüfen Sie die Aktion erneut. Es wurden keine Nachrichten verschoben.',
      'تغير مجلد الأرشيف أثناء المراجعة. راجع الإجراء مجددًا. لم تُنقل أي رسائل.',
    ),
    StudioMailArchiveDestinationFailure.stale => _archiveText(
      'The mail account changed. Open Archive destination again.',
      'Das Mail-Konto wurde geändert. Öffnen Sie Archivzielordner erneut.',
      'تغير حساب البريد. افتح مجلد الأرشيف مجددًا.',
    ),
    StudioMailArchiveDestinationFailure.unavailable =>
      mailArchiveSettingsLoadFailed,
  };
}
