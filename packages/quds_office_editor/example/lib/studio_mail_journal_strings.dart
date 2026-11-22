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
    'Read, flag, move and delete actions saved on this device. Interrupted changes are never sent again automatically.',
    'Auf diesem Gerät gespeicherte Aktionen zum Lesen, Kennzeichnen, Verschieben und Löschen. Unterbrochene Änderungen werden nie automatisch erneut gesendet.',
    'إجراءات القراءة والعلامات والنقل والحذف المحفوظة على هذا الجهاز. لا تُرسل التغييرات المتوقفة مرة أخرى تلقائيًا.',
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
    'Clear completed receipts, including uncertain read/flag actions with a saved status check? Running actions, unchecked uncertainty and uncertain move/delete actions are kept. Mail on the server is unchanged.',
    'Abgeschlossene Belege einschließlich ungewisser Lese- und Markierungsaktionen mit gespeicherter Statusprüfung löschen? Laufende Aktionen, ungeprüfte ungewisse Ergebnisse und ungewisse Verschiebe- oder Löschaktionen bleiben erhalten. Servernachrichten bleiben unverändert.',
    'هل تريد مسح السجلات المكتملة، بما فيها إجراءات القراءة والعلامات غير المؤكدة ذات فحص حالة محفوظ؟ تُحفظ الإجراءات الجارية والنتائج غير المفحوصة وإجراءات النقل والحذف غير المؤكدة. لا يتغير البريد على الخادم.',
  );
  String get mailActivityCheck => _text(
    'Check current status',
    'Aktuellen Status prüfen',
    'فحص الحالة الحالية',
  );
  String get mailActivityStopCheck =>
      _text('Stop checking', 'Prüfung anhalten', 'إيقاف الفحص');
  String get mailActivityLocationCheck => _text(
    'Check current location',
    'Aktuellen Standort prüfen',
    'فحص الموقع الحالي',
  );
  String get mailActivityLocationScope => _text(
    'A location check only reads the server. It saves the latest observation, '
        'without repeating the action or changing cached folders. The original '
        'result stays uncertain, and this receipt remains protected from cleanup.',
    'Eine Standortprüfung liest nur den Server. Sie speichert die neueste '
        'Beobachtung, ohne die Aktion zu wiederholen oder gespeicherte Ordner zu '
        'ändern. Das ursprüngliche Ergebnis bleibt ungewiss; dieser Beleg wird '
        'bei der Verlaufsbereinigung nicht gelöscht.',
    'يقرأ فحص الموقع الخادم فقط. ويحفظ أحدث ملاحظة دون تكرار الإجراء أو تغيير '
        'المجلدات المحفوظة. تظل النتيجة الأصلية غير مؤكدة، ولا يُحذف هذا السجل '
        'عند تنظيف المحفوظات.',
  );
  String get mailActivityLocationReconnect => _text(
    'Connect this account with a provider that supports location checks to '
        'observe the current state. Saved observations remain readable offline.',
    'Verbinden Sie dieses Konto mit einem Anbieter, der Standortprüfungen '
        'unterstützt, um den aktuellen Stand zu prüfen. Gespeicherte '
        'Beobachtungen bleiben offline lesbar.',
    'اتصل بهذا الحساب باستخدام موفر يدعم فحص الموقع لملاحظة الحالة الحالية. '
        'تبقى الملاحظات المحفوظة قابلة للقراءة دون اتصال.',
  );
  String mailActivitySource(String folder) => _text(
    'Original folder: $folder',
    'Ursprünglicher Ordner: $folder',
    'المجلد الأصلي: $folder',
  );
  String get mailActivityMoveEvidence => _text(
    'Saved move acknowledgement',
    'Gespeicherte Verschiebebestätigung',
    'تأكيد النقل المحفوظ',
  );
  String mailActivityMoveRecordedAt(String date) => _text(
    'Acknowledgement saved: $date',
    'Bestätigung gespeichert: $date',
    'حُفظ التأكيد: $date',
  );
  String mailActivityMoveCacheStatus(bool projected) => projected
      ? _text(
          'Saved folder entries were updated from the server acknowledgement. '
              'Refresh or synchronize to check the current folder contents.',
          'Gespeicherte Ordnereinträge wurden anhand der Serverbestätigung '
              'aktualisiert. Aktualisieren oder synchronisieren Sie, um den '
              'aktuellen Ordnerinhalt zu prüfen.',
          'حُدثت إدخالات المجلدات المحفوظة بناءً على تأكيد الخادم. '
              'حدّث أو زامن للتحقق من محتويات المجلد الحالية.',
        )
      : _text(
          'The move acknowledgement is saved. Saved folder entries could not '
              'be updated from it; refresh or synchronize the folders.',
          'Die Verschiebebestätigung ist gespeichert. Gespeicherte '
              'Ordnereinträge konnten daraus nicht aktualisiert werden; '
              'aktualisieren oder synchronisieren Sie die Ordner.',
          'حُفظ تأكيد النقل. تعذر تحديث إدخالات المجلدات المحفوظة بناءً عليه؛ '
              'حدّث المجلدات أو زامنها.',
        );
  String mailActivityLocationCount(int observed, int uncertain) => _text(
    '$observed of $uncertain uncertain actions have a saved location check',
    'Für $observed von $uncertain ungewissen Aktionen ist eine Standortprüfung gespeichert',
    'حُفظ فحص الموقع لـ $observed من أصل $uncertain إجراء غير مؤكد',
  );

  List<String> mailActivityLocationDetails(
    MailMembershipObservation observation,
    MailStoredFlagBatchSummary batch,
  ) {
    if (observation.kind == MailMembershipObservationKind.missing) {
      return [
        _text(
          'The original message identity is unavailable. Its destination and '
              'the result of the earlier action are not verified.',
          'Die ursprüngliche Nachrichtenkennung ist nicht verfügbar. Ihr Ziel '
              'und das Ergebnis der früheren Aktion sind nicht bestätigt.',
          'هوية الرسالة الأصلية غير متاحة. لم يُتحقق من وجهتها أو نتيجة الإجراء السابق.',
        ),
      ];
    }
    if (observation.kind == MailMembershipObservationKind.identityChanged) {
      return [
        _text(
          'The original folder was reset or replaced. The old message identity '
              'cannot be checked in the replacement folder.',
          'Der ursprüngliche Ordner wurde zurückgesetzt oder ersetzt. Die alte '
              'Nachrichtenkennung kann im neuen Ordner nicht geprüft werden.',
          'أُعيد تعيين المجلد الأصلي أو استُبدل. لا يمكن فحص هوية الرسالة القديمة '
              'في المجلد البديل.',
        ),
      ];
    }
    final folders = observation.mailboxes.map((box) => box.value).join(', ');
    final labels = observation.identity.provider == MailProviderKind.gmail;
    return [
      if (labels)
        folders.isEmpty
            ? _text(
                'Current labels: none',
                'Aktuelle Labels: keine',
                'التصنيفات الحالية: لا توجد',
              )
            : _text(
                'Current labels: $folders',
                'Aktuelle Labels: $folders',
                'التصنيفات الحالية: $folders',
              )
      else
        _text(
          'Current folder: $folders',
          'Aktueller Ordner: $folders',
          'المجلد الحالي: $folders',
        ),
      if (observation.mailboxes.contains(batch.mailbox))
        _text(
          'The message was present in the original folder at the time of this check.',
          'Die Nachricht befand sich zum Prüfzeitpunkt im ursprünglichen Ordner.',
          'كانت الرسالة موجودة في المجلد الأصلي وقت هذا الفحص.',
        )
      else
        _text(
          'The message was outside the original folder at the time of this check.',
          'Die Nachricht befand sich zum Prüfzeitpunkt außerhalb des ursprünglichen Ordners.',
          'كانت الرسالة خارج المجلد الأصلي وقت هذا الفحص.',
        ),
      if (batch.destination != null)
        if (observation.identity is MailImapIdentity)
          _text(
            'This check does not verify whether the message is in the destination folder.',
            'Diese Prüfung bestätigt nicht, ob sich die Nachricht im Zielordner befindet.',
            'لا يتحقق هذا الفحص مما إذا كانت الرسالة موجودة في المجلد الهدف.',
          )
        else if (observation.mailboxes.contains(batch.destination))
          _text(
            'The requested destination was among the observed locations. This does not prove the earlier move succeeded.',
            'Das gewünschte Ziel gehörte zu den beobachteten Standorten. Dies beweist nicht, dass das frühere Verschieben erfolgreich war.',
            'كانت الوجهة المطلوبة ضمن المواقع الملاحظة. لا يثبت ذلك نجاح النقل السابق.',
          )
        else
          _text(
            'The requested destination was not among the observed locations.',
            'Das gewünschte Ziel gehörte nicht zu den beobachteten Standorten.',
            'لم تكن الوجهة المطلوبة ضمن المواقع الملاحظة.',
          ),
      if (observation.identity is MailImapIdentity)
        observation.isDeleted == true
            ? _text(
                'Marked deleted; not evidence of permanent removal.',
                'Als gelöscht markiert; kein Nachweis einer endgültigen Entfernung.',
                'محددة كمحذوفة؛ هذا ليس دليلًا على الإزالة النهائية.',
              )
            : _text(
                'Not marked deleted at the time of the check.',
                'Zum Prüfzeitpunkt nicht als gelöscht markiert.',
                'لم تكن محددة كمحذوفة وقت الفحص.',
              )
      else if (observation.isDeleted == null)
        _text(
          'Deleted Items / Trash membership was not verified.',
          'Die Zugehörigkeit zu Gelöschte Elemente / Papierkorb wurde nicht bestätigt.',
          'لم يُتحقق من وجودها في العناصر المحذوفة / المهملات.',
        )
      else if (observation.isDeleted!)
        _text(
          'Present in Deleted Items / Trash at the time of the check.',
          'Zum Prüfzeitpunkt in Gelöschte Elemente / Papierkorb vorhanden.',
          'موجودة في العناصر المحذوفة / المهملات وقت الفحص.',
        )
      else
        _text(
          'Outside Deleted Items / Trash at the time of the check.',
          'Zum Prüfzeitpunkt außerhalb von Gelöschte Elemente / Papierkorb.',
          'خارج العناصر المحذوفة / المهملات وقت الفحص.',
        ),
    ];
  }

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
      MailBulkFlagAction.move || MailBulkFlagAction.delete => throw StateError(
        'A flag observation cannot resolve membership changes.',
      ),
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
    MailBulkFlagAction.move => _text(
      'Move message',
      'Nachricht verschieben',
      'نقل الرسالة',
    ),
    MailBulkFlagAction.delete => _text(
      'Delete action',
      'Löschaktion',
      'إجراء الحذف',
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
