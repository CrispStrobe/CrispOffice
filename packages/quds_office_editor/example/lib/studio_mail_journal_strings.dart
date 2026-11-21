import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_strings.dart';

extension StudioMailJournalStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailActivity =>
      _text('Mail activity', 'Mail-Aktivitäten', 'نشاط البريد');
  String get mailActivityScope => _text(
    'Read and flag changes saved on this device. Interrupted changes are never sent again automatically.',
    'Auf diesem Gerät gespeicherte Lese- und Kennzeichnungsänderungen. Unterbrochene Änderungen werden nie automatisch erneut gesendet.',
    'تغييرات القراءة والعلامات المحفوظة على هذا الجهاز. لا تُرسل التغييرات المتوقفة مرة أخرى تلقائيًا.',
  );
  String get mailActivityEmpty => _text(
    'No saved mail activity yet.',
    'Noch keine gespeicherten Mail-Aktivitäten.',
    'لا يوجد نشاط بريد محفوظ بعد.',
  );
  String get mailActivityFailed => _text(
    'Mail activity could not be read. Close this view and try again.',
    'Mail-Aktivitäten konnten nicht gelesen werden. Schließen Sie diese Ansicht und versuchen Sie es erneut.',
    'تعذرت قراءة نشاط البريد. أغلق هذا العرض وحاول مرة أخرى.',
  );
  String get mailActivityInterrupted => _text(
    'Interrupted. The original outcomes are retained below. Remaining changes were not replayed.',
    'Unterbrochen. Die ursprünglichen Ergebnisse bleiben unten erhalten. Ausstehende Änderungen wurden nicht erneut ausgeführt.',
    'توقف الإجراء. تُحفظ النتائج الأصلية أدناه. لم تُنفذ التغييرات المتبقية مرة أخرى.',
  );
  String get mailActivityRunning => _text(
    'Still in progress. A pending server reply is not a confirmed change.',
    'Noch in Bearbeitung. Eine ausstehende Serverantwort ist keine bestätigte Änderung.',
    'ما زال الإجراء قيد التنفيذ. انتظار رد الخادم لا يعني تأكيد التغيير.',
  );
  String get mailActivityMore =>
      _text('Older activity', 'Ältere Aktivitäten', 'نشاط أقدم');
  String get mailActivityBack =>
      _text('All activity', 'Alle Aktivitäten', 'كل النشاط');
  String get mailActivityClear => _text(
    'Clear completed receipts',
    'Abgeschlossene Belege löschen',
    'مسح سجلات الإجراءات المكتملة',
  );
  String get mailActivityClearQuestion => _text(
    'Clear completed receipts, including uncertain actions whose current status was checked? Running actions and unchecked uncertainty are kept. Mail on the server is unchanged.',
    'Abgeschlossene Belege einschließlich ungewisser Aktionen mit geprüftem aktuellem Status löschen? Laufende Aktionen und ungeprüfte ungewisse Ergebnisse bleiben erhalten. Servernachrichten bleiben unverändert.',
    'هل تريد مسح السجلات المكتملة، بما فيها الإجراءات غير المؤكدة التي فُحصت حالتها الحالية؟ تُحفظ الإجراءات الجارية والنتائج غير المؤكدة التي لم تُفحص. لا يتغير البريد على الخادم.',
  );
  String get mailActivityCheck => _text(
    'Check current status',
    'Aktuellen Status prüfen',
    'فحص الحالة الحالية',
  );
  String get mailActivityStopCheck =>
      _text('Stop checking', 'Prüfung anhalten', 'إيقاف الفحص');
  String get mailActivityReconnect => _text(
    'Connect this account and open Mail activity to check unresolved actions. Cached activity can be read without connecting.',
    'Verbinden Sie dieses Konto und öffnen Sie die Mail-Aktivitäten, um ungeklärte Aktionen zu prüfen. Gespeicherte Aktivitäten sind auch ohne Verbindung lesbar.',
    'اتصل بهذا الحساب وافتح نشاط البريد لفحص الإجراءات غير المحسومة. يمكن قراءة النشاط المحفوظ دون اتصال.',
  );
  String get mailActivityObservationScope => _text(
    'A status check reads the server without repeating the action. It records the state at the time of the check; the original action remains uncertain. Checked receipts can be cleared from history.',
    'Eine Statusprüfung liest den Server, ohne die Aktion zu wiederholen. Sie speichert den Status zum Prüfzeitpunkt; das ursprüngliche Ergebnis bleibt ungewiss. Geprüfte Belege können aus dem Verlauf gelöscht werden.',
    'يقرأ فحص الحالة الخادم دون تكرار الإجراء. ويسجل الحالة وقت الفحص؛ تظل نتيجة الإجراء الأصلي غير مؤكدة. يمكن مسح السجلات المفحوصة من المحفوظات.',
  );
  String get mailActivityNoSubject =>
      _text('(No subject)', '(Kein Betreff)', '(بلا موضوع)');
  String mailActivityCheckedCounts(MailStoredFlagBatchSummary batch) => _text(
    '${batch.reconciledCount} checked · ${batch.unresolvedCount} still to check',
    '${batch.reconciledCount} geprüft · ${batch.unresolvedCount} noch zu prüfen',
    '${batch.reconciledCount} فُحصت · ${batch.unresolvedCount} لم تُفحص بعد',
  );
  String mailActivityCheckedAt(String date) =>
      _text('Checked $date', 'Geprüft am $date', 'فُحصت في $date');

  String mailActivityObserved(
    MailFlagResolutionKind kind,
    MailBulkFlagAction action,
  ) {
    if (kind == MailFlagResolutionKind.missing) {
      return _text(
        'The original message is no longer available at this server address.',
        'Die ursprüngliche Nachricht ist unter dieser Serveradresse nicht mehr verfügbar.',
        'لم تعد الرسالة الأصلية متاحة في عنوان الخادم هذا.',
      );
    }
    if (kind == MailFlagResolutionKind.identityChanged) {
      return _text(
        'The folder was reset or replaced. The original message can no longer be checked.',
        'Der Ordner wurde zurückgesetzt oder ersetzt. Die ursprüngliche Nachricht kann nicht mehr geprüft werden.',
        'أُعيد تعيين المجلد أو استُبدل. لم يعد بالإمكان فحص الرسالة الأصلية.',
      );
    }
    final desired =
        action == MailBulkFlagAction.markRead ||
        action == MailBulkFlagAction.flag;
    final observed = kind == MailFlagResolutionKind.matches
        ? desired
        : !desired;
    final state = switch (action) {
      MailBulkFlagAction.markRead || MailBulkFlagAction.markUnread =>
        observed
            ? _text('Read', 'Gelesen', 'مقروءة')
            : _text('Unread', 'Ungelesen', 'غير مقروءة'),
      MailBulkFlagAction.flag || MailBulkFlagAction.unflag =>
        observed
            ? _text('Flagged', 'Gekennzeichnet', 'معلّمة')
            : _text('Not flagged', 'Nicht gekennzeichnet', 'غير معلّمة'),
    };
    return kind == MailFlagResolutionKind.matches
        ? _text(
            '$state at the time of the check · matches the requested state',
            '$state zum Prüfzeitpunkt · entspricht dem gewünschten Status',
            '$state وقت الفحص · تطابق الحالة المطلوبة',
          )
        : _text(
            '$state at the time of the check · differs from the requested state',
            '$state zum Prüfzeitpunkt · weicht vom gewünschten Status ab',
            '$state وقت الفحص · تختلف عن الحالة المطلوبة',
          );
  }

  String mailActivityCheckFailed(MailProblemCode code) => switch (code) {
    MailProblemCode.cancelled => _text(
      'Checking stopped. Any completed checks remain saved.',
      'Prüfung angehalten. Abgeschlossene Prüfungen bleiben gespeichert.',
      'توقف الفحص. تبقى نتائج الفحوص المكتملة محفوظة.',
    ),
    MailProblemCode.authenticationRequired => _text(
      'Connect the account again before checking. Unchecked actions remain unresolved.',
      'Verbinden Sie das Konto vor der Prüfung erneut. Ungeprüfte Aktionen bleiben ungeklärt.',
      'أعد الاتصال بالحساب قبل الفحص. تظل الإجراءات التي لم تُفحص غير محسومة.',
    ),
    MailProblemCode.conflict || MailProblemCode.staleOperation => _text(
      'The account or saved mail changed during the check. Reopen this activity and check again.',
      'Das Konto oder gespeicherte Nachrichten haben sich während der Prüfung geändert. Öffnen Sie diese Aktivität erneut und prüfen Sie noch einmal.',
      'تغير الحساب أو البريد المحفوظ أثناء الفحص. أعد فتح هذا النشاط وافحصه مرة أخرى.',
    ),
    MailProblemCode.storageFailure || MailProblemCode.quotaExceeded => _text(
      'The check could not be saved reliably. Unchecked actions remain unresolved. Free device storage if needed, then try again.',
      'Die Prüfung konnte nicht zuverlässig gespeichert werden. Ungeprüfte Aktionen bleiben ungeklärt. Geben Sie bei Bedarf Gerätespeicher frei und versuchen Sie es erneut.',
      'تعذر حفظ الفحص بشكل موثوق. تظل الإجراءات التي لم تُفحص غير محسومة. حرر مساحة على الجهاز عند الحاجة، ثم حاول مجددًا.',
    ),
    _ => _text(
      'The server status could not be verified. Any completed checks remain saved; unchecked actions remain unresolved.',
      'Der Serverstatus konnte nicht geprüft werden. Abgeschlossene Prüfungen bleiben gespeichert; ungeprüfte Aktionen bleiben ungeklärt.',
      'تعذر التحقق من حالة الخادم. تبقى نتائج الفحوص المكتملة محفوظة؛ وتظل الإجراءات التي لم تُفحص غير محسومة.',
    ),
  };
  String get mailActivityPersistenceFailed => _text(
    'The local receipt could not be saved reliably. Further changes stopped. Refresh the folder and check Mail activity before another change.',
    'Der lokale Beleg konnte nicht zuverlässig gespeichert werden. Weitere Änderungen wurden gestoppt. Aktualisieren Sie den Ordner und prüfen Sie die Mail-Aktivitäten vor einer weiteren Änderung.',
    'تعذر حفظ السجل المحلي بشكل موثوق. توقفت التغييرات التالية. حدّث المجلد وتحقق من نشاط البريد قبل إجراء تغيير آخر.',
  );
  String mailActivityAction(MailBulkFlagAction action) => switch (action) {
    MailBulkFlagAction.markRead => _text(
      'Mark read',
      'Als gelesen markieren',
      'تحديد كمقروءة',
    ),
    MailBulkFlagAction.markUnread => _text(
      'Mark unread',
      'Als ungelesen markieren',
      'تحديد كغير مقروءة',
    ),
    MailBulkFlagAction.flag => _text(
      'Flag messages',
      'Kennzeichnen',
      'تعليم الرسائل',
    ),
    MailBulkFlagAction.unflag => _text(
      'Unflag messages',
      'Kennzeichnung entfernen',
      'إزالة تعليم الرسائل',
    ),
  };
  String mailActivityCounts(MailStoredFlagBatchSummary batch) {
    final original = _text(
      '${batch.confirmedCount} confirmed · ${batch.failedCount} failed · ${batch.uncertainCount} uncertain · ${batch.unattemptedCount} not attempted',
      '${batch.confirmedCount} bestätigt · ${batch.failedCount} fehlgeschlagen · ${batch.uncertainCount} ungewiss · ${batch.unattemptedCount} nicht versucht',
      '${batch.confirmedCount} مؤكدة · ${batch.failedCount} فشلت · ${batch.uncertainCount} غير مؤكدة · ${batch.unattemptedCount} لم تُحاول',
    );
    return batch.reconciledCount == 0
        ? original
        : '$original\n${mailActivityCheckedCounts(batch)}';
  }
}
