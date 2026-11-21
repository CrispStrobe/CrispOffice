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
    'Sync saves message headers. Offline reading needs a saved body and attachments. Opening a message here reads only this device. Saved counts may differ from the server.',
    'Die Synchronisierung speichert Nachrichtenkopfzeilen. Zum Offline-Lesen müssen Inhalt und Anhänge gespeichert sein. Das Öffnen einer Nachricht hier liest nur von diesem Gerät. Die Anzahl kann vom Server abweichen.',
    'تحفظ المزامنة عناوين الرسائل. تتطلب القراءة دون اتصال حفظ المحتوى والمرفقات. فتح رسالة هنا يقرأ من هذا الجهاز فقط. قد تختلف الأعداد المحفوظة عن الخادم.',
  );

  String get mailDownloadPage => _text(
    'Download this page',
    'Diese Seite herunterladen',
    'تنزيل هذه الصفحة',
  );
  String get mailDownloadMessage => _text(
    'Download for offline reading',
    'Zum Offline-Lesen herunterladen',
    'تنزيل للقراءة دون اتصال',
  );
  String get mailDownloadScope => _text(
    'Download this page saves bodies and attachments for up to 100 headers on this page, including rows hidden by filters. Each run saves up to 64 MiB of message content. Already saved messages are skipped. Downloads do not mark messages as read.',
    '„Diese Seite herunterladen“ speichert Inhalte und Anhänge für bis zu 100 Kopfzeilen dieser Seite, auch für ausgefilterte Zeilen. Pro Durchlauf werden bis zu 64 MiB Nachrichteninhalt gespeichert. Bereits gespeicherte Nachrichten werden übersprungen. Downloads markieren Nachrichten nicht als gelesen.',
    'يحفظ تنزيل هذه الصفحة المحتوى والمرفقات لما يصل إلى 100 عنوان في هذه الصفحة، بما في ذلك الصفوف المخفية بالفلاتر. يحفظ كل تشغيل ما يصل إلى 64 ميبيبايت من محتوى الرسائل. تُتخطى الرسائل المحفوظة مسبقًا. لا يغيّر التنزيل حالة الرسائل إلى مقروءة.',
  );
  String get mailDownloadFinished => _text(
    'This download request is complete. These messages are available offline.',
    'Dieser Downloadauftrag ist abgeschlossen. Diese Nachrichten sind offline verfügbar.',
    'اكتمل طلب التنزيل هذا. هذه الرسائل متاحة دون اتصال.',
  );
  String get mailDownloadPaused => _text(
    'The download reached its batch limit. Download this page again to continue; saved messages will be skipped.',
    'Das Downloadlimit dieses Durchlaufs wurde erreicht. Laden Sie diese Seite erneut herunter, um fortzufahren. Gespeicherte Nachrichten werden übersprungen.',
    'وصل التنزيل إلى حد هذا التشغيل. نزّل هذه الصفحة مجددًا للمتابعة؛ ستُتخطى الرسائل المحفوظة.',
  );
  String get mailDownloadCancelled => _text(
    'Download stopped. Completed downloads remain saved. Download again to continue.',
    'Download angehalten. Abgeschlossene Downloads bleiben gespeichert. Laden Sie erneut herunter, um fortzufahren.',
    'أُوقف التنزيل. تبقى التنزيلات المكتملة محفوظة. نزّل مجددًا للمتابعة.',
  );
  String get mailDownloadFailed => _text(
    'The download could not finish. Completed downloads remain saved. Check the connection and try again.',
    'Der Download konnte nicht abgeschlossen werden. Abgeschlossene Downloads bleiben gespeichert. Prüfen Sie die Verbindung und versuchen Sie es erneut.',
    'تعذر إكمال التنزيل. تبقى التنزيلات المكتملة محفوظة. تحقق من الاتصال وحاول مجددًا.',
  );
  String get mailDownloadAuthentication => _text(
    'Reconnect to this account before downloading again. Completed downloads remain saved.',
    'Verbinden Sie sich erneut mit diesem Konto, bevor Sie wieder herunterladen. Abgeschlossene Downloads bleiben gespeichert.',
    'أعد الاتصال بهذا الحساب قبل التنزيل مجددًا. تبقى التنزيلات المكتملة محفوظة.',
  );
  String get mailDownloadConflict => _text(
    'The account or message changed. Reopen the synchronized folder before downloading again.',
    'Das Konto oder die Nachricht wurde geändert. Öffnen Sie den synchronisierten Ordner erneut, bevor Sie wieder herunterladen.',
    'تغيّر الحساب أو الرسالة. أعد فتح المجلد المتزامن قبل التنزيل مجددًا.',
  );
  String get mailDownloadQuota => _text(
    'A message or local storage limit stopped this download. Completed downloads remain saved. Free local cache space or download another message.',
    'Ein Nachrichten- oder Speicherlimit hat den Download angehalten. Abgeschlossene Downloads bleiben gespeichert. Geben Sie lokalen Cache-Speicher frei oder laden Sie eine andere Nachricht herunter.',
    'أوقف حد الرسالة أو التخزين المحلي هذا التنزيل. تبقى التنزيلات المكتملة محفوظة. حرر مساحة في الذاكرة المحلية أو نزّل رسالة أخرى.',
  );
  String get mailDownloadUnsupported => _text(
    'This account cannot download the requested message. Completed downloads remain saved.',
    'Dieses Konto kann die angeforderte Nachricht nicht herunterladen. Abgeschlossene Downloads bleiben gespeichert.',
    'لا يستطيع هذا الحساب تنزيل الرسالة المطلوبة. تبقى التنزيلات المكتملة محفوظة.',
  );

  String mailDownloadProgress(
    int downloaded,
    int cached,
    int remaining,
  ) => _text(
    'This request: downloaded $downloaded · already saved $cached · remaining $remaining',
    'Dieser Auftrag: heruntergeladen $downloaded · bereits gespeichert $cached · verbleibend $remaining',
    'هذا الطلب: نُزّل $downloaded · محفوظ مسبقًا $cached · متبقٍ $remaining',
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
    'Only this message’s header is saved. Connect to this account and choose Download for offline reading in Synchronized mail to save its body and attachments.',
    'Nur die Kopfzeile dieser Nachricht ist gespeichert. Verbinden Sie sich mit diesem Konto und wählen Sie im synchronisierten Postfach „Zum Offline-Lesen herunterladen“, um Inhalt und Anhänge zu speichern.',
    'حُفظ عنوان هذه الرسالة فقط. اتصل بهذا الحساب واختر التنزيل للقراءة دون اتصال في البريد المتزامن لحفظ المحتوى والمرفقات.',
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
