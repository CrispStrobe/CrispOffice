import 'studio_strings.dart';

extension StudioMailCachedStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailCachedMail =>
      _text('Cached mail', 'Gespeicherte E-Mails', 'البريد المحفوظ');

  String get mailCacheClear =>
      _text('Clear cached mail', 'Mail-Cache leeren', 'مسح البريد المحفوظ');

  String get mailCacheClearHelp => _text(
    'Remove saved folder views and unprotected downloaded mail from this device? Drafts, Outbox, server mail, saved credentials, pending operations and content pinned by open editors are kept. You can download mail again after reconnecting.',
    'Gespeicherte Ordneransichten und ungeschützte heruntergeladene E-Mails von diesem Gerät entfernen? Entwürfe, Postausgang, Servernachrichten, Zugangsdaten, ausstehende Vorgänge und von offenen Editoren geschützte Inhalte bleiben erhalten. Nach dem Verbinden können Sie E-Mails erneut herunterladen.',
    'هل تريد إزالة عروض المجلدات المحفوظة والبريد المحمّل غير المحمي من هذا الجهاز؟ تبقى المسودات والصادر وبريد الخادم وبيانات الاعتماد والعمليات المعلّقة والمحتوى الذي تحميه المحررات المفتوحة. يمكنك تنزيل البريد مجددًا بعد إعادة الاتصال.',
  );

  String mailCacheCleared(int views, int bodies, int headers) => _text(
    'Removed $views saved folder views, $bodies downloaded messages and $headers cached headers.',
    '$views gespeicherte Ordneransichten, $bodies heruntergeladene Nachrichten und $headers gespeicherte Kopfzeilen entfernt.',
    'أُزيل $views من عروض المجلدات المحفوظة و$bodies من الرسائل المحمّلة و$headers من عناوين الرسائل المحفوظة.',
  );

  String get mailCacheClearMore => _text(
    'More cached mail remains. Choose Clear cached mail again to remove the next batch.',
    'Weitere gespeicherte E-Mails verbleiben. Wählen Sie erneut „Mail-Cache leeren“, um die nächste Gruppe zu entfernen.',
    'يبقى بريد محفوظ آخر. اختر مسح البريد المحفوظ مجددًا لإزالة المجموعة التالية.',
  );

  String mailCacheProtected(int count) => _text(
    '$count downloaded messages are protected by open editors. Close those editors before trying again.',
    '$count heruntergeladene Nachrichten werden von offenen Editoren geschützt. Schließen Sie diese Editoren, bevor Sie es erneut versuchen.',
    'تحمي المحررات المفتوحة $count من الرسائل المحمّلة. أغلق تلك المحررات قبل المحاولة مجددًا.',
  );

  String get mailCacheClearFailed => _text(
    'Could not clear cached mail. The previous saved view is retained. Try again or close this workspace.',
    'Der Mail-Cache konnte nicht geleert werden. Die zuvor gespeicherte Ansicht bleibt erhalten. Versuchen Sie es erneut oder schließen Sie diese Ansicht.',
    'تعذر مسح البريد المحفوظ. يبقى العرض المحفوظ السابق محفوظًا. حاول مجددًا أو أغلق مساحة العمل هذه.',
  );

  String get mailCacheClearing => _text(
    'Clearing cached mail…',
    'Mail-Cache wird geleert…',
    'جارٍ مسح البريد المحفوظ…',
  );

  String get mailCacheDraftClearHelp => _text(
    'Your current draft stays open. After clearing cached mail, saving this draft is retried.',
    'Ihr aktueller Entwurf bleibt geöffnet. Nach dem Leeren des Mail-Caches wird das Speichern dieses Entwurfs erneut versucht.',
    'تبقى مسودتك الحالية مفتوحة. بعد مسح البريد المحفوظ، تُعاد محاولة حفظ هذه المسودة.',
  );

  String get mailCacheDraftClearFailed => _text(
    'Could not clear cached mail. Your draft is still open. Try again or retry saving.',
    'Der Mail-Cache konnte nicht geleert werden. Ihr Entwurf bleibt geöffnet. Versuchen Sie es erneut oder speichern Sie erneut.',
    'تعذر مسح البريد المحفوظ. تبقى مسودتك مفتوحة. حاول مجددًا أو أعد محاولة الحفظ.',
  );

  String get mailCacheDraftClearMore => _text(
    'More cached mail remains. If saving still fails, you can clear another batch.',
    'Weitere gespeicherte E-Mails verbleiben. Falls das Speichern weiterhin fehlschlägt, können Sie eine weitere Gruppe entfernen.',
    'يبقى بريد محفوظ آخر. إذا استمر تعذر الحفظ، يمكنك مسح مجموعة أخرى.',
  );

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

  String get mailCacheRetainedScope => _text(
    'Browse saved folder views and synchronized headers together. Search and unread counts cover the displayed view or page. Reading and refreshing here use only this device; later server changes may not be saved yet.',
    'Gespeicherte Ordneransichten und synchronisierte Kopfzeilen gemeinsam durchsuchen. Suche und Ungelesen-Zähler beziehen sich auf die angezeigte Ansicht oder Seite. Lesen und Aktualisieren greifen nur auf dieses Gerät zu; spätere Serveränderungen sind möglicherweise noch nicht gespeichert.',
    'تصفّح عروض المجلدات المحفوظة والعناوين المتزامنة معًا. يشمل البحث وعدد غير المقروء العرض أو الصفحة الظاهرة. تستخدم القراءة والتحديث هنا هذا الجهاز فقط؛ قد لا تكون تغييرات الخادم اللاحقة محفوظة بعد.',
  );

  String get mailCacheRetainedEmpty => _text(
    'No saved folders yet. Connect and browse or synchronize a folder to retain its headers.',
    'Noch keine gespeicherten Ordner. Verbinden Sie sich und öffnen oder synchronisieren Sie einen Ordner, um dessen Kopfzeilen zu speichern.',
    'لا توجد مجلدات محفوظة بعد. اتصل وافتح مجلدًا أو زامنه للاحتفاظ بعناوينه.',
  );

  String get mailCacheBrowseSource => _text(
    'Saved browsing view',
    'Gespeicherte Ordneransicht',
    'عرض التصفّح المحفوظ',
  );

  String get mailCacheSyncSource => _text(
    'Synchronized headers',
    'Synchronisierte Kopfzeilen',
    'العناوين المتزامنة',
  );

  String get mailCacheRefresh => _text(
    'Refresh local mail',
    'Lokale E-Mails aktualisieren',
    'تحديث البريد المحلي',
  );

  String get mailCacheSourceMissing => _text(
    'This saved source is no longer available. Choose another source or refresh local mail.',
    'Diese gespeicherte Quelle ist nicht mehr verfügbar. Wählen Sie eine andere Quelle oder aktualisieren Sie die lokalen E-Mails.',
    'لم يعد هذا المصدر المحفوظ متاحًا. اختر مصدرًا آخر أو حدّث البريد المحلي.',
  );

  String get mailCacheChooseMessage => _text(
    'Choose a saved message to read it offline.',
    'Wählen Sie eine gespeicherte Nachricht zum Offline-Lesen.',
    'اختر رسالة محفوظة لقراءتها دون اتصال.',
  );

  String get mailCachePartial => _text(
    'This is a partial folder view. More messages may be available on the server. Reconnect to continue loading.',
    'Dies ist eine unvollständige Ordneransicht. Weitere Nachrichten können auf dem Server verfügbar sein. Verbinden Sie sich erneut, um weiterzuladen.',
    'هذا عرض جزئي للمجلد. قد تتوفر رسائل أخرى على الخادم. أعد الاتصال لمتابعة التحميل.',
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

  String mailCacheUnread(int unread, int unknown) => _text(
    '$unread unread in this saved view${unknown == 0 ? '' : ' · $unknown with unknown read status'}',
    '$unread ungelesen in dieser gespeicherten Ansicht${unknown == 0 ? '' : ' · $unknown mit unbekanntem Lesestatus'}',
    '$unread غير مقروءة في هذا العرض المحفوظ${unknown == 0 ? '' : ' · $unknown بحالة قراءة غير معروفة'}',
  );

  String get mailCacheMissingBody => _text(
    'This message was not saved for offline reading. Reconnect and open it to save a local copy.',
    'Diese Nachricht wurde nicht zum Offline-Lesen gespeichert. Verbinden Sie sich erneut und öffnen Sie sie, um eine lokale Kopie zu speichern.',
    'لم تُحفظ هذه الرسالة للقراءة دون اتصال. أعد الاتصال وافتحها لحفظ نسخة محلية.',
  );

  String get mailCacheReadFailed => _text(
    'Could not read this saved mailbox view or message. Refresh local mail to try again. Your saved mail is retained.',
    'Die gespeicherte Ordneransicht oder Nachricht konnte nicht gelesen werden. Aktualisieren Sie die lokalen E-Mails, um es erneut zu versuchen. Ihre gespeicherten E-Mails bleiben erhalten.',
    'تعذرت قراءة عرض صندوق البريد أو الرسالة المحفوظة. حدّث البريد المحلي للمحاولة مجددًا. يبقى بريدك المحفوظ محفوظًا.',
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
