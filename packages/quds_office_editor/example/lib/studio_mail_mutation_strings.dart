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
    'This receipt records the original action. Cached folders retain their last '
        'saved observation until refreshed or synchronized. Move and delete '
        'status checks are not available yet; an uncertain action stays saved '
        'and is never repeated automatically.',
    'Dieser Beleg hält die ursprüngliche Aktion fest. Gespeicherte Ordner '
        'behalten ihren letzten Stand bis zur Aktualisierung oder '
        'Synchronisierung. Statusprüfungen für Verschieben und Löschen sind '
        'noch nicht verfügbar; eine ungewisse Aktion bleibt gespeichert und '
        'wird nie automatisch wiederholt.',
    'يسجل هذا السجل الإجراء الأصلي. تحتفظ المجلدات المحفوظة بآخر حالة حتى '
        'تحديثها أو مزامنتها. لا تتوفر فحوص حالة النقل والحذف بعد؛ يبقى '
        'الإجراء غير المؤكد محفوظًا ولا يُكرر تلقائيًا.',
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
