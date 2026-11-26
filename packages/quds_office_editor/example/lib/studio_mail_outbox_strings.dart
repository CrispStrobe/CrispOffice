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
    'The Outbox operation could not be saved. Open or refresh Outbox to check its state before trying again.',
    'Der Vorgang konnte nicht gespeichert werden. Öffnen oder aktualisieren Sie den Postausgang und prüfen Sie den Status vor einem weiteren Versuch.',
    'تعذر حفظ إجراء صندوق الصادر. افتح صندوق الصادر أو حدّثه للتحقق من الحالة قبل المحاولة مجددًا.',
  );
  String get mailOutboxInspect => _outboxText(
    'Open Outbox to review the saved message.',
    'Öffnen Sie den Postausgang, um die gespeicherte Nachricht zu prüfen.',
    'افتح صندوق الصادر لمراجعة الرسالة المحفوظة.',
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
  String get mailOutboxPreview =>
      _outboxText('Review message', 'Nachricht prüfen', 'مراجعة الرسالة');
  String get mailOutboxPreviewExplanation => _outboxText(
    'This is the saved message. Text and supported formatting are shown with inactive links; attachments are listed without opening them.',
    'Dies ist die gespeicherte Nachricht. Text und unterstützte Formatierungen werden mit inaktiven Links angezeigt; Anhänge werden aufgelistet, ohne sie zu öffnen.',
    'هذه هي الرسالة المحفوظة. يُعرض النص والتنسيق المدعوم بروابط غير نشطة وتُدرج المرفقات دون فتحها.',
  );
  String get mailOutboxFormattedBody => _outboxText(
    'Formatted body',
    'Formatierter Nachrichtentext',
    'نص الرسالة المنسق',
  );
  String get mailOutboxPreviewUnavailable => _outboxText(
    'This saved message cannot be safely shown or edited. You can still export its original EML and recipient record.',
    'Diese gespeicherte Nachricht kann nicht sicher angezeigt oder bearbeitet werden. Die ursprüngliche EML und der Empfängerdatensatz lassen sich weiterhin exportieren.',
    'لا يمكن عرض هذه الرسالة المحفوظة أو تحريرها بأمان. لا يزال بإمكانك تصدير ملف EML الأصلي وسجل المستلمين.',
  );
  String get mailOutboxBodyTruncated => _outboxText(
    'This preview is shortened. Export and the editable draft retain the complete body.',
    'Diese Vorschau ist gekürzt. Export und bearbeitbarer Entwurf enthalten den vollständigen Inhalt.',
    'هذه المعاينة مختصرة. يحتفظ التصدير والمسودة القابلة للتحرير بالنص الكامل.',
  );
  String get mailOutboxSender => _outboxText('Sender', 'Absender', 'المرسل');
  String get mailOutboxMessageId =>
      _outboxText('Message ID', 'Nachrichten-ID', 'معرّف الرسالة');
  String get mailOutboxMessageDate => _outboxText(
    'Message date (UTC)',
    'Nachrichtendatum (UTC)',
    'تاريخ الرسالة (UTC)',
  );
  String get mailOutboxExport =>
      _outboxText('Export EML', 'EML exportieren', 'تصدير EML');
  String get mailOutboxExportEnvelope => _outboxText(
    'Export private recipient record',
    'Privaten Empfängerdatensatz exportieren',
    'تصدير سجل المستلمين الخاص',
  );
  String get mailOutboxExportExplanation => _outboxText(
    'EML preserves the original message bytes and attachments. The separate private recipient record preserves the complete transport recipient list, including Bcc.',
    'EML bewahrt die ursprünglichen Nachrichtendaten und Anhänge. Der separate private Empfängerdatensatz bewahrt die vollständige Versandempfängerliste einschließlich Bcc.',
    'يحفظ EML بيانات الرسالة الأصلية ومرفقاتها. يحفظ سجل المستلمين الخاص المنفصل قائمة مستلمي الإرسال الكاملة، بما في ذلك النسخة المخفية.',
  );
  String get mailOutboxExportPrivateExplanation => _outboxText(
    'Save the complete transport recipient list, including Bcc, to a separate JSON file? This private record can reveal hidden recipients to anyone you share it with.',
    'Die vollständige Versandempfängerliste einschließlich Bcc in einer separaten JSON-Datei speichern? Dieser private Datensatz legt verborgene Empfänger gegenüber Personen offen, mit denen Sie ihn teilen.',
    'حفظ قائمة مستلمي الإرسال الكاملة، بما في ذلك النسخة المخفية، في ملف JSON منفصل؟ قد يكشف هذا السجل الخاص المستلمين المخفيين لأي شخص تشاركه معه.',
  );
  String get mailOutboxExported =>
      _outboxText('File saved.', 'Datei gespeichert.', 'حُفظ الملف.');
  String get mailOutboxExportFailed => _outboxText(
    'The file could not be saved. Choose a new filename in a writable folder. The saved Outbox message is unchanged.',
    'Die Datei konnte nicht gespeichert werden. Wählen Sie einen neuen Dateinamen in einem beschreibbaren Ordner. Die Nachricht im Postausgang bleibt unverändert.',
    'تعذر حفظ الملف. اختر اسم ملف جديدًا في مجلد قابل للكتابة. لم تتغير الرسالة المحفوظة في صندوق الصادر.',
  );
  String get mailOutboxEdit => _outboxText(
    'Edit as new draft',
    'Als neuen Entwurf bearbeiten',
    'تحرير كمسودة جديدة',
  );
  String get mailOutboxEditExplanation => _outboxText(
    'Cancel this queued message and open a new saved draft with its recipients, text and attachments? The original frozen copy remains in Outbox. Your other drafts are kept. Sending the edited draft creates a new message.',
    'Diese wartende Nachricht abbrechen und einen neuen gespeicherten Entwurf mit Empfängern, Text und Anhängen öffnen? Die ursprüngliche Kopie bleibt im Postausgang. Andere Entwürfe bleiben erhalten. Das Senden des bearbeiteten Entwurfs erstellt eine neue Nachricht.',
    'إلغاء هذه الرسالة المنتظرة وفتح مسودة جديدة محفوظة بمستلميها ونصها ومرفقاتها؟ تبقى النسخة الأصلية في صندوق الصادر وتُحفظ مسوداتك الأخرى. إرسال المسودة المعدلة ينشئ رسالة جديدة.',
  );
  String get mailOutboxStopRetrying => _outboxText(
    'Stop retrying',
    'Weitere Versuche beenden',
    'إيقاف إعادة المحاولة',
  );
  String get mailOutboxStopRetryingExplanation => _outboxText(
    'Close this local entry without sending again? Delivery remains unknown. This does not recall mail, mark it delivered or prove it failed. The original message and attempt information remain available until you separately remove the local record.',
    'Diesen lokalen Eintrag ohne erneutes Senden abschließen? Die Zustellung bleibt unbekannt. Dies ruft keine Nachricht zurück und bestätigt weder Zustellung noch Fehlschlag. Die ursprüngliche Nachricht und die Versuchsinformationen bleiben bis zum separaten Entfernen des lokalen Eintrags verfügbar.',
    'إغلاق هذا الإدخال المحلي دون الإرسال مجددًا؟ تبقى حالة التسليم مجهولة. لا يستدعي هذا البريد ولا يؤكد تسليمه أو فشله. تبقى الرسالة الأصلية ومعلومات المحاولة متاحين حتى تزيل السجل المحلي بشكل منفصل.',
  );
  String get mailOutboxClosedExplanation => _outboxText(
    'Further sending is disabled for this entry. Delivery of an earlier attempt is still unknown.',
    'Weiteres Senden ist für diesen Eintrag deaktiviert. Die Zustellung eines früheren Versuchs bleibt unbekannt.',
    'عُطّل الإرسال مجددًا لهذا الإدخال. لا تزال حالة تسليم محاولة سابقة مجهولة.',
  );
  String get mailOutboxRemoveUnknownExplanation => _outboxText(
    'Remove this local record and its message bytes? Delivery remains unknown, and this removes your local copy of the attempt information. This does not recall mail or remove a server copy.',
    'Diesen lokalen Eintrag und seine Nachrichtendaten entfernen? Die Zustellung bleibt unbekannt; die lokale Kopie der Versuchsinformationen wird entfernt. Dies ruft keine Nachricht zurück und entfernt keine Serverkopie.',
    'إزالة هذا السجل المحلي وبيانات الرسالة؟ تبقى حالة التسليم مجهولة وستُحذف نسختك المحلية من معلومات المحاولة. لا يستدعي هذا البريد ولا يحذف نسخة الخادم.',
  );
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
    MailOutboxState.closedUncertain => _outboxText(
      'Closed locally — delivery unknown',
      'Lokal abgeschlossen — Zustellung unbekannt',
      'أُغلق محليًا — التسليم مجهول',
    ),
  };
}
