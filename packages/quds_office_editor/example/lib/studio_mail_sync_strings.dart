import 'studio_strings.dart';

extension StudioMailSyncStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailSync =>
      _text('Synchronized mail', 'Synchronisierte E-Mails', 'البريد المتزامن');
  String get mailSyncStart =>
      _text('Start sync', 'Synchronisierung starten', 'بدء المزامنة');
  String get mailSyncContinue =>
      _text('Continue sync', 'Synchronisierung fortsetzen', 'متابعة المزامنة');
  String get mailSyncCheckChanges =>
      _text('Check for changes', 'Änderungen abrufen', 'التحقق من التغييرات');
  String get mailSyncStop => _text('Stop', 'Anhalten', 'إيقاف');
  String get mailSyncStopping =>
      _text('Stopping…', 'Wird angehalten…', 'جارٍ الإيقاف…');
  String get mailSyncClosing =>
      _text('Closing…', 'Wird geschlossen…', 'جارٍ الإغلاق…');
  String get mailSyncPrevious =>
      _text('Previous page', 'Vorherige Seite', 'الصفحة السابقة');
  String get mailSyncNext =>
      _text('Next page', 'Nächste Seite', 'الصفحة التالية');

  String get mailSyncScope => _text(
    'Sync saves message headers for offline browsing. Message bodies are available here only if previously opened and saved. Saved counts describe this device and may differ from the server.',
    'Die Synchronisierung speichert Nachrichtenkopfzeilen zum Offline-Lesen. Nachrichteninhalte sind hier nur verfügbar, wenn sie zuvor geöffnet und gespeichert wurden. Die Anzahl bezieht sich auf dieses Gerät und kann vom Server abweichen.',
    'تحفظ المزامنة عناوين الرسائل لتصفحها دون اتصال. لا تتوفر محتويات الرسائل هنا إلا إذا فُتحت وحُفظت سابقًا. تخص الأعداد المحفوظة هذا الجهاز وقد تختلف عن الخادم.',
  );

  String get mailSyncForeground => _text(
    'Sync runs only when you start it. Keep this window open while it runs. You can stop and continue from the last saved step.',
    'Die Synchronisierung läuft nur, wenn Sie sie starten. Lassen Sie dieses Fenster währenddessen geöffnet. Sie können anhalten und beim zuletzt gespeicherten Schritt fortfahren.',
    'تعمل المزامنة فقط عند بدء تشغيلها. أبقِ هذه النافذة مفتوحة أثناء عملها. يمكنك الإيقاف والمتابعة من آخر خطوة محفوظة.',
  );

  String get mailSyncOffline => _text(
    'Offline view. Reconnect to an account and open a folder to check for changes.',
    'Offline-Ansicht. Verbinden Sie sich erneut mit einem Konto und öffnen Sie einen Ordner, um Änderungen abzurufen.',
    'عرض دون اتصال. أعد الاتصال بحساب وافتح مجلدًا للتحقق من التغييرات.',
  );

  String get mailSyncEmpty => _text(
    'No synchronized folders yet.',
    'Noch keine synchronisierten Ordner.',
    'لا توجد مجلدات متزامنة بعد.',
  );
  String get mailSyncNotStarted => _text(
    'This folder has no saved sync yet.',
    'Für diesen Ordner ist noch keine Synchronisierung gespeichert.',
    'لا توجد مزامنة محفوظة لهذا المجلد بعد.',
  );
  String get mailSyncPartial => _text(
    'Partial scan saved · Continue sync to scan more headers.',
    'Teilweise Erfassung gespeichert · Setzen Sie die Synchronisierung für weitere Kopfzeilen fort.',
    'حُفظ فحص جزئي · تابع المزامنة لفحص المزيد من العناوين.',
  );
  String get mailSyncComplete => _text(
    'Latest scan finished · Later server changes may not be saved yet.',
    'Letzte Erfassung abgeschlossen · Spätere Serveränderungen sind möglicherweise noch nicht gespeichert.',
    'اكتمل آخر فحص · قد لا تكون تغييرات الخادم اللاحقة محفوظة بعد.',
  );
  String get mailSyncPaused => _text(
    'Sync paused after this step. Choose Continue sync to resume.',
    'Synchronisierung nach diesem Schritt pausiert. Wählen Sie „Synchronisierung fortsetzen“.',
    'توقفت المزامنة مؤقتًا بعد هذه الخطوة. اختر متابعة المزامنة للاستئناف.',
  );
  String get mailSyncCancelled => _text(
    'Sync stopped. Completed steps remain saved.',
    'Synchronisierung angehalten. Abgeschlossene Schritte bleiben gespeichert.',
    'أُوقفت المزامنة. تبقى الخطوات المكتملة محفوظة.',
  );
  String get mailSyncFinished => _text(
    'Sync finished. The saved view is ready.',
    'Synchronisierung abgeschlossen. Die gespeicherte Ansicht ist bereit.',
    'اكتملت المزامنة. العرض المحفوظ جاهز.',
  );
  String get mailSyncFailed => _text(
    'Sync could not finish. Completed steps remain saved. Try again after checking the connection.',
    'Die Synchronisierung konnte nicht abgeschlossen werden. Abgeschlossene Schritte bleiben gespeichert. Prüfen Sie die Verbindung und versuchen Sie es erneut.',
    'تعذر إكمال المزامنة. تبقى الخطوات المكتملة محفوظة. تحقق من الاتصال وحاول مجددًا.',
  );
  String get mailSyncAuthentication => _text(
    'Reconnect to this account before continuing sync. Completed steps remain saved.',
    'Verbinden Sie sich erneut mit diesem Konto, bevor Sie fortfahren. Abgeschlossene Schritte bleiben gespeichert.',
    'أعد الاتصال بهذا الحساب قبل متابعة المزامنة. تبقى الخطوات المكتملة محفوظة.',
  );
  String get mailSyncConflict => _text(
    'This account or saved folder changed. Reopen the folder before continuing sync.',
    'Dieses Konto oder der gespeicherte Ordner wurde geändert. Öffnen Sie den Ordner erneut, bevor Sie fortfahren.',
    'تغيّر هذا الحساب أو المجلد المحفوظ. أعد فتح المجلد قبل متابعة المزامنة.',
  );
  String get mailSyncQuota => _text(
    'Sync reached a storage or provider limit. Completed steps remain saved.',
    'Die Synchronisierung hat ein Speicher- oder Anbieterlimit erreicht. Abgeschlossene Schritte bleiben gespeichert.',
    'وصلت المزامنة إلى حد التخزين أو المزوّد. تبقى الخطوات المكتملة محفوظة.',
  );
  String get mailSyncUnsupported => _text(
    'This account does not support folder synchronization.',
    'Dieses Konto unterstützt keine Ordnersynchronisierung.',
    'لا يدعم هذا الحساب مزامنة المجلدات.',
  );
  String get mailSyncReadFailed => _text(
    'Could not read the saved sync. Reopen this window to try again. Your saved mail is retained.',
    'Die gespeicherte Synchronisierung konnte nicht gelesen werden. Öffnen Sie dieses Fenster erneut. Ihre gespeicherten E-Mails bleiben erhalten.',
    'تعذرت قراءة المزامنة المحفوظة. أعد فتح هذه النافذة للمحاولة. يبقى بريدك المحفوظ محفوظًا.',
  );
  String get mailSyncCloseFailed => _text(
    'Could not finish closing this view. Try Close again before leaving this account.',
    'Diese Ansicht konnte nicht vollständig geschlossen werden. Versuchen Sie erneut zu schließen, bevor Sie dieses Konto verlassen.',
    'تعذر إكمال إغلاق هذا العرض. حاول الإغلاق مجددًا قبل مغادرة هذا الحساب.',
  );
  String get mailSyncChooseMessage => _text(
    'Choose a saved message to read it offline.',
    'Wählen Sie eine gespeicherte Nachricht zum Offline-Lesen.',
    'اختر رسالة محفوظة لقراءتها دون اتصال.',
  );
  String get mailSyncMissingBody => _text(
    'Only this message’s header is saved. Reconnect and open the message in its mailbox to save its body for offline reading.',
    'Nur die Kopfzeile dieser Nachricht ist gespeichert. Verbinden Sie sich erneut und öffnen Sie die Nachricht im Postfach, um ihren Inhalt zum Offline-Lesen zu speichern.',
    'حُفظ عنوان هذه الرسالة فقط. أعد الاتصال وافتح الرسالة في صندوق بريدها لحفظ محتواها للقراءة دون اتصال.',
  );

  String mailSyncSaved(DateTime updatedAt, int count) {
    final stamp = updatedAt.toUtc().toIso8601String().substring(0, 19);
    final display = '${stamp.replaceFirst('T', ' ')} UTC';
    return _text(
      '$count saved headers · Last saved $display',
      '$count gespeicherte Kopfzeilen · Zuletzt gespeichert $display',
      '$count من العناوين المحفوظة · آخر حفظ $display',
    );
  }

  String mailSyncProgress(int pages, int processed) => _text(
    '$pages steps saved · $processed headers processed',
    '$pages Schritte gespeichert · $processed Kopfzeilen verarbeitet',
    'حُفظت $pages خطوة · عُولج $processed عنوانًا',
  );

  String mailSyncPage(int first, int last, int count) => _text(
    '$first–$last of $count saved headers',
    '$first–$last von $count gespeicherten Kopfzeilen',
    '$first–$last من $count عنوانًا محفوظًا',
  );
}
