import 'studio_strings.dart';

extension StudioMailCachedStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailCachedMail =>
      _text('Cached mail', 'Gespeicherte E-Mails', 'البريد المحفوظ');

  String get mailCachedAccountsHelp => _text(
    'Tap an account to edit drafts, or choose Cached mail to read its saved folder views offline.',
    'Tippen Sie zum Bearbeiten von Entwürfen auf ein Konto. Unter „Gespeicherte E-Mails“ lesen Sie dessen gespeicherte Ordneransichten offline.',
    'اضغط على حساب لتحرير المسودات، أو اختر البريد المحفوظ لقراءة عروض مجلداته المحفوظة دون اتصال.',
  );

  String get mailCacheScope => _text(
    'Only visited, saved folder views are listed. Search covers their saved headers. These dated copies may differ from your server mailbox.',
    'Nur besuchte, gespeicherte Ordneransichten werden angezeigt. Die Suche umfasst deren gespeicherte Kopfzeilen. Diese älteren Kopien können vom Serverpostfach abweichen.',
    'تظهر فقط عروض المجلدات التي زرتها وحفظتها. يشمل البحث عناوينها المحفوظة. قد تختلف هذه النسخ المؤرخة عن صندوق البريد على الخادم.',
  );

  String get mailCacheEmpty => _text(
    'No saved folder views yet. Connect and open a folder to save its loaded headers.',
    'Noch keine gespeicherten Ordneransichten. Verbinden Sie sich und öffnen Sie einen Ordner, um dessen geladene Kopfzeilen zu speichern.',
    'لا توجد عروض مجلدات محفوظة بعد. اتصل وافتح مجلدًا لحفظ عناوين رسائله المحمّلة.',
  );

  String get mailCacheChooseMessage => _text(
    'Choose a saved message to read it offline.',
    'Wählen Sie eine gespeicherte Nachricht zum Offline-Lesen.',
    'اختر رسالة محفوظة لقراءتها دون اتصال.',
  );

  String get mailCachePartial => _text(
    'More messages were available on the server when this view was saved. Reconnect to load them.',
    'Beim Speichern dieser Ansicht waren weitere Nachrichten auf dem Server verfügbar. Verbinden Sie sich erneut, um sie zu laden.',
    'كانت هناك رسائل أخرى على الخادم عند حفظ هذا العرض. أعد الاتصال لتحميلها.',
  );

  String mailCacheSnapshot(DateTime capturedAt, int count) {
    final stamp = capturedAt.toUtc().toIso8601String().substring(0, 19);
    final display = '${stamp.replaceFirst('T', ' ')} UTC';
    return _text(
      '$count saved headers · Saved $display',
      '$count gespeicherte Kopfzeilen · Gespeichert $display',
      '$count من عناوين الرسائل المحفوظة · حُفظت $display',
    );
  }

  String get mailCacheMissingBody => _text(
    'This message was not saved for offline reading. Reconnect and open it to save a local copy.',
    'Diese Nachricht wurde nicht zum Offline-Lesen gespeichert. Verbinden Sie sich erneut und öffnen Sie sie, um eine lokale Kopie zu speichern.',
    'لم تُحفظ هذه الرسالة للقراءة دون اتصال. أعد الاتصال وافتحها لحفظ نسخة محلية.',
  );

  String get mailCacheReadFailed => _text(
    'Could not read this saved mailbox view or message. Reopen the account to try again. Your saved mail is retained.',
    'Die gespeicherte Ordneransicht oder Nachricht konnte nicht gelesen werden. Öffnen Sie das Konto erneut. Ihre gespeicherten E-Mails bleiben erhalten.',
    'تعذرت قراءة عرض صندوق البريد أو الرسالة المحفوظة. افتح الحساب مجددًا للمحاولة. يبقى بريدك المحفوظ محفوظًا.',
  );

  String get mailCacheCloseFailed => _text(
    'The local mailbox could not be closed. Try Close again before opening this account elsewhere.',
    'Das lokale Postfach konnte nicht geschlossen werden. Versuchen Sie erneut zu schließen, bevor Sie dieses Konto an anderer Stelle öffnen.',
    'تعذر إغلاق صندوق البريد المحلي. حاول الإغلاق مجددًا قبل فتح هذا الحساب في مكان آخر.',
  );

  String get mailCacheSaveFailed => _text(
    'Mail is available online, but this view or message could not be saved for offline reading. Previously saved mail is retained.',
    'Die E-Mails sind online verfügbar, aber diese Ansicht oder Nachricht konnte nicht zum Offline-Lesen gespeichert werden. Zuvor gespeicherte E-Mails bleiben erhalten.',
    'البريد متاح عبر الاتصال، لكن تعذر حفظ هذا العرض أو الرسالة للقراءة دون اتصال. يبقى البريد المحفوظ سابقًا محفوظًا.',
  );
}
