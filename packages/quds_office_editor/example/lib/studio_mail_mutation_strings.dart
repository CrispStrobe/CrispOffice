import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_strings.dart';

extension StudioMailMutationStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailMoveMessage =>
      _text('Move message', 'Nachricht verschieben', 'نقل الرسالة');

  String get mailMoveSelection => _text(
    'Move selected messages',
    'Ausgewählte Nachrichten verschieben',
    'نقل الرسائل المحددة',
  );

  String mailOrganizationCount(int count) => _text(
    'Selected messages: $count',
    'Ausgewählte Nachrichten: $count',
    'الرسائل المحددة: $count',
  );

  String get mailOrganizationSource =>
      _text('Source folder', 'Quellordner', 'المجلد المصدر');

  String get mailOrganizationDestination => _text(
    'Choose destination',
    'Zielordner auswählen',
    'اختيار المجلد الهدف',
  );

  String get mailOrganizationNoDestination => _text(
    'No other folder is available for this account.',
    'Für dieses Konto ist kein anderer Ordner verfügbar.',
    'لا يتوفر مجلد آخر لهذا الحساب.',
  );

  String get mailOrganizationMoveExplanation => _text(
    'Move these selected messages from the source folder to the chosen destination.',
    'Diese ausgewählten Nachrichten aus dem Quellordner in den gewählten Zielordner verschieben.',
    'نقل هذه الرسائل المحددة من المجلد المصدر إلى المجلد الهدف المختار.',
  );

  String get mailOrganizationApplyMove => _text('Move', 'Verschieben', 'نقل');

  String mailOrganizationDeleteExplanation(MailProviderKind provider) =>
      provider == MailProviderKind.imap
      ? _text(
          'Mark the selected messages deleted on the IMAP server. This action '
              'does not purge them; another mail client or the server may later '
              'permanently remove messages marked deleted.',
          'Die ausgewählten Nachrichten auf dem IMAP-Server als gelöscht '
              'markieren. Diese Aktion entfernt sie nicht endgültig; ein '
              'anderer Mail-Client oder der Server kann sie später endgültig '
              'entfernen.',
          'تحديد الرسائل المختارة كمحذوفة على خادم IMAP. لا يزيلها هذا '
              'الإجراء نهائيًا؛ قد يزيل عميل بريد آخر أو الخادم الرسائل '
              'المحددة كمحذوفة لاحقًا.',
        )
      : _text(
          'Move the selected messages to this account’s deleted items or trash.',
          'Die ausgewählten Nachrichten in Gelöschte Elemente oder den '
              'Papierkorb dieses Kontos verschieben.',
          'نقل الرسائل المحددة إلى العناصر المحذوفة أو المهملات في هذا الحساب.',
        );

  String get mailMarkDeleted =>
      _text('Mark deleted', 'Als gelöscht markieren', 'تحديد كمحذوفة');

  String get mailMarkDeletedExplanation => _text(
    'Mark this message deleted on the IMAP server? It will not be permanently '
        'removed by this action. Another mail client or the server may later '
        'purge messages marked deleted.',
    'Diese Nachricht auf dem IMAP-Server als gelöscht markieren? Diese Aktion '
        'entfernt sie nicht endgültig. Ein anderer Mail-Client oder der Server '
        'kann als gelöscht markierte Nachrichten später endgültig entfernen.',
    'هل تريد تحديد هذه الرسالة كمحذوفة على خادم IMAP؟ لن يزيلها هذا الإجراء '
        'نهائيًا. قد يزيل عميل بريد آخر أو الخادم الرسائل المحددة كمحذوفة لاحقًا.',
  );

  String get mailMutationUnavailable => _text(
    'This action is unavailable for the connected account. No message was changed.',
    'Diese Aktion ist für das verbundene Konto nicht verfügbar. Keine Nachricht wurde geändert.',
    'هذا الإجراء غير متاح للحساب المتصل. لم تُغيّر أي رسالة.',
  );

  String get mailMutationCheckFailed => _text(
    'The available mail actions could not be checked. No change was sent. Refresh and try again.',
    'Die verfügbaren Mail-Aktionen konnten nicht geprüft werden. Es wurde keine Änderung gesendet. Aktualisieren Sie die Ansicht und versuchen Sie es erneut.',
    'تعذر فحص إجراءات البريد المتاحة. لم يُرسل أي تغيير. حدّث القائمة وحاول مجددًا.',
  );

  String get mailMutationHistoryScope => _text(
    'This receipt records the original action. A saved move acknowledgement may '
        'update exact folder entries; folder coverage keeps its original date '
        'until refreshed or synchronized. Later location checks '
        'do not prove whether the original action worked. Uncertain actions stay '
        'saved and are never repeated automatically.',
    'Dieser Beleg hält die ursprüngliche Aktion fest. Eine gespeicherte '
        'Verschiebebestätigung kann einzelne Ordnereinträge aktualisieren; '
        'der erfasste Ordnerumfang behält sein ursprüngliches Datum bis zur '
        'Aktualisierung oder Synchronisierung. Spätere Standortprüfungen beweisen nicht, ob die '
        'ursprüngliche Aktion erfolgreich war. Ungewisse Aktionen bleiben '
        'gespeichert und werden nie automatisch wiederholt.',
    'يسجل هذا السجل الإجراء الأصلي. قد يحدّث تأكيد النقل المحفوظ إدخالات '
        'محددة في المجلدات؛ ويحتفظ نطاق المحتوى المحفوظ بتاريخه الأصلي حتى '
        'التحديث أو المزامنة. لا تثبت فحوص الموقع اللاحقة نجاح الإجراء الأصلي. '
        'تبقى الإجراءات غير المؤكدة محفوظة ولا تُكرر تلقائيًا.',
  );

  String mailMutationDestination(String destination) => _text(
    'Destination folder: $destination',
    'Zielordner: $destination',
    'المجلد الهدف: $destination',
  );

  String mailDeleteAction(MailProviderKind provider) =>
      provider == MailProviderKind.imap
      ? mailMarkDeleted
      : _text(
          'Move to deleted items / trash',
          'In Gelöschte Elemente / Papierkorb verschieben',
          'نقل إلى العناصر المحذوفة / المهملات',
        );
}
