import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_strings.dart';

extension StudioMailOutboxStrings on StudioStrings {
  String _outboxText(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailOutbox => _outboxText('Outbox', 'Postausgang', 'صندوق الصادر');
  String get mailQueue => _outboxText(
    'Queue in Outbox',
    'In Postausgang legen',
    'إضافة إلى صندوق الصادر',
  );
  String get mailQueued => _outboxText(
    'Saved in Outbox. Open Outbox to send it when ready.',
    'Im Postausgang gespeichert. Öffnen Sie den Postausgang, um die Nachricht zu senden.',
    'حُفظت في صندوق الصادر. افتح صندوق الصادر لإرسالها عندما تكون جاهزًا.',
  );
  String get mailOutboxExplanation => _outboxText(
    'Messages are saved locally for this account. Sending is explicit; reopening Mail does not send queued messages. Acceptance by a server does not confirm delivery.',
    'Nachrichten werden lokal für dieses Konto gespeichert. Senden erfolgt ausdrücklich; beim erneuten Öffnen werden keine Nachrichten versendet. Die Serverannahme bestätigt keine Zustellung.',
    'تُحفظ الرسائل محليًا لهذا الحساب. الإرسال يتطلب إجراءً صريحًا؛ إعادة فتح البريد لا ترسل الرسائل المنتظرة. قبول الخادم لا يؤكد التسليم.',
  );
  String get mailOutboxEmpty => _outboxText(
    'Outbox is empty.',
    'Der Postausgang ist leer.',
    'صندوق الصادر فارغ.',
  );
  String get mailOutboxFailed => _outboxText(
    'The Outbox operation could not be saved. Refresh to check its state before trying again.',
    'Der Vorgang konnte nicht gespeichert werden. Aktualisieren Sie den Postausgang und prüfen Sie den Status vor einem weiteren Versuch.',
    'تعذر حفظ إجراء صندوق الصادر. حدّث العرض للتحقق من الحالة قبل المحاولة مجددًا.',
  );
  String get mailQueueFailed => _outboxText(
    'Could not queue the message. Your saved draft is retained. The local Outbox holds up to 100 entries within the account storage limit.',
    'Die Nachricht konnte nicht eingereiht werden. Ihr gespeicherter Entwurf bleibt erhalten. Der lokale Postausgang fasst bis zu 100 Einträge innerhalb des Kontospeicherlimits.',
    'تعذرت إضافة الرسالة. احتُفظ بالمسودة المحفوظة. يتسع صندوق الصادر المحلي لما يصل إلى 100 إدخال ضمن حد تخزين الحساب.',
  );
  String get mailOutboxSend =>
      _outboxText('Send now', 'Jetzt senden', 'إرسال الآن');
  String get mailOutboxRetry =>
      _outboxText('Retry', 'Erneut versuchen', 'إعادة المحاولة');
  String get mailOutboxCheckRetry => _outboxText(
    'Check delivery and retry',
    'Zustellung prüfen und erneut versuchen',
    'التحقق من التسليم وإعادة المحاولة',
  );
  String get mailOutboxCancel => _outboxText(
    'Cancel queued message',
    'Wartende Nachricht abbrechen',
    'إلغاء الرسالة المنتظرة',
  );
  String get mailOutboxRemove => _outboxText(
    'Remove local record',
    'Lokalen Eintrag entfernen',
    'إزالة السجل المحلي',
  );
  String get mailOutboxRemoveExplanation => _outboxText(
    'Remove this local Outbox record and its saved message bytes? This does not recall mail or delete a server copy.',
    'Diesen lokalen Postausgangseintrag und seine Nachrichtendaten entfernen? Dies ruft keine Nachricht zurück und löscht keine Serverkopie.',
    'إزالة سجل صندوق الصادر المحلي وبيانات الرسالة المحفوظة؟ لا يؤدي ذلك إلى استدعاء البريد أو حذف نسخة الخادم.',
  );
  String get mailOutboxCancelExplanation => _outboxText(
    'Stop this queued message from being sent? Its frozen copy remains in Outbox until you remove the local record.',
    'Das Senden dieser wartenden Nachricht abbrechen? Ihre gespeicherte Kopie bleibt im Postausgang, bis Sie den lokalen Eintrag entfernen.',
    'إيقاف إرسال هذه الرسالة المنتظرة؟ تبقى نسختها المحفوظة في صندوق الصادر حتى تزيل السجل المحلي.',
  );
  String get mailOutboxUncertainExplanation => _outboxText(
    'An earlier attempt may already have been accepted. Check Sent and delivery with the recipient before retrying. Retrying sends the same message and can create a duplicate. A later failed attempt does not resolve earlier uncertainty.',
    'Ein früherer Versuch wurde möglicherweise bereits angenommen. Prüfen Sie Gesendet und die Zustellung beim Empfänger. Ein erneuter Versuch sendet dieselbe Nachricht und kann ein Duplikat erzeugen. Ein späterer Fehler klärt die frühere Ungewissheit nicht.',
    'قد تكون محاولة سابقة قد قُبلت بالفعل. تحقق من البريد المرسل ومن التسليم مع المستلم قبل إعادة المحاولة. تُرسل الرسالة نفسها وقد تنتج نسخة مكررة. فشل محاولة لاحقة لا يحسم حالة المحاولة السابقة.',
  );
  String get mailOutboxAcknowledgement => _outboxText(
    'I checked delivery and accept the risk of sending a duplicate.',
    'Ich habe die Zustellung geprüft und akzeptiere das Risiko einer doppelten Sendung.',
    'تحققت من التسليم وأقبل خطر إرسال نسخة مكررة.',
  );
  String get mailOutboxRecipients => _outboxText(
    'Envelope recipients (includes Bcc)',
    'Versandempfänger (einschließlich Bcc)',
    'مستلمو الإرسال (بما فيهم النسخة المخفية)',
  );
  String get mailOutboxNoSubject =>
      _outboxText('(No subject)', '(Kein Betreff)', '(بلا موضوع)');
  String mailOutboxAttempt(int count) =>
      _outboxText('Attempts: $count', 'Versuche: $count', 'المحاولات: $count');
  String mailOutboxState(MailOutboxState state) => switch (state) {
    MailOutboxState.queued => _outboxText(
      'Queued — awaiting explicit send',
      'Wartend — ausdrückliches Senden erforderlich',
      'في الانتظار — بانتظار إجراء إرسال صريح',
    ),
    MailOutboxState.submitting => _outboxText(
      'Sending — outcome pending',
      'Wird gesendet — Ergebnis ausstehend',
      'جارٍ الإرسال — النتيجة قيد الانتظار',
    ),
    MailOutboxState.submitted => _outboxText(
      'Accepted by sending server',
      'Vom Versandserver angenommen',
      'قبلها خادم الإرسال',
    ),
    MailOutboxState.retryableFailure => _outboxText(
      'Latest attempt not accepted — retry available',
      'Letzter Versuch nicht angenommen — erneuter Versuch möglich',
      'لم تُقبل المحاولة الأخيرة — يمكن إعادة المحاولة',
    ),
    MailOutboxState.permanentFailure => _outboxText(
      'Latest attempt rejected — review before composing again',
      'Letzter Versuch abgelehnt — vor erneutem Verfassen prüfen',
      'رُفضت المحاولة الأخيرة — راجعها قبل إنشاء رسالة أخرى',
    ),
    MailOutboxState.uncertain => _outboxText(
      'Uncertain — check delivery',
      'Ungewiss — Zustellung prüfen',
      'غير مؤكدة — تحقق من التسليم',
    ),
    MailOutboxState.cancelled => _outboxText(
      'Cancelled locally',
      'Lokal abgebrochen',
      'أُلغيت محليًا',
    ),
  };
}
