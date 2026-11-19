import 'studio_strings.dart';

/// Shared Mail feedback contains no server response or credential fragments.
extension StudioMailFeedback on StudioStrings {
  String _mailText(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailInvalidRecipient => _mailText(
    'Enter one email address, such as person@example.com.',
    'Eine E-Mail-Adresse eingeben, zum Beispiel person@example.com.',
    'أدخل عنوان بريد واحدًا، مثل person@example.com.',
  );
  String get mailInvalidSubject => _mailText(
    'Use a subject of at most 512 characters, without line breaks.',
    'Der Betreff darf höchstens 512 Zeichen und keine Zeilenumbrüche enthalten.',
    'يجب ألا يتجاوز الموضوع 512 حرفًا وألا يحتوي على فواصل أسطر.',
  );
  String get mailInvalidBody => _mailText(
    'The message body must be at most 1 MiB and contain no null characters.',
    'Der Nachrichtentext darf höchstens 1 MiB groß sein und keine Nullzeichen enthalten.',
    'يجب ألا يتجاوز نص الرسالة 1 ميبيبايت وألا يحتوي على محارف فارغة.',
  );
  String get mailPlainTextBody => _mailText(
    'Message body · plain text',
    'Nachrichtentext · unformatiert',
    'نص الرسالة · نص عادي',
  );
  String get mailSubmissionAccepted => _mailText(
    'The sending server accepted the message. This session does not save a Sent copy.',
    'Der Versandserver hat die Nachricht angenommen. Diese Sitzung speichert keine Kopie unter „Gesendet“.',
    'قبل خادم الإرسال الرسالة. لا تحفظ هذه الجلسة نسخة في البريد المرسل.',
  );
  String get mailSubmissionFollowUpFailed => _mailText(
    'The sending server accepted the message, but follow-up cleanup failed. Do not resend this message. This session does not save a Sent copy.',
    'Der Versandserver hat die Nachricht angenommen, aber die anschließende Bereinigung ist fehlgeschlagen. Diese Nachricht nicht erneut senden. Diese Sitzung speichert keine Kopie unter „Gesendet“.',
    'قبل خادم الإرسال الرسالة، لكن التنظيف اللاحق فشل. لا ترسل هذه الرسالة مجددًا. لا تحفظ هذه الجلسة نسخة في البريد المرسل.',
  );
  String get mailSubmissionUncertain => _mailText(
    'Submission could not be confirmed. Your draft is retained for this session. Check delivery before sending it again.',
    'Der Versand konnte nicht bestätigt werden. Der Entwurf bleibt in dieser Sitzung erhalten. Vor einem erneuten Versand die Zustellung prüfen.',
    'تعذر تأكيد الإرسال. حُفظت المسودة لهذه الجلسة. تحقق من التسليم قبل إرسالها مجددًا.',
  );
  String get mailRetryAcknowledgement => _mailText(
    'I checked delivery and want to send this draft again.',
    'Ich habe die Zustellung geprüft und möchte diesen Entwurf erneut senden.',
    'تحققت من التسليم وأريد إرسال هذه المسودة مجددًا.',
  );
  String get mailInvalidSender => _mailText(
    'The account needs a valid email address before it can send.',
    'Das Konto benötigt zum Senden eine gültige E-Mail-Adresse.',
    'يحتاج الحساب إلى عنوان بريد صالح قبل الإرسال.',
  );
  String get mailConnectionFailed => _mailText(
    'Could not connect to this account. Check the server settings and credentials.',
    'Die Verbindung zum Konto ist fehlgeschlagen. Servereinstellungen und Zugangsdaten prüfen.',
    'تعذر الاتصال بهذا الحساب. تحقق من إعدادات الخادم وبيانات الدخول.',
  );
  String get mailMailboxFailed => _mailText(
    'Could not load this mailbox. Refresh to try again.',
    'Das Postfach konnte nicht geladen werden. Zum erneuten Versuch aktualisieren.',
    'تعذر تحميل صندوق البريد. حدّث الصفحة للمحاولة مجددًا.',
  );
  String get mailMessageFailed => _mailText(
    'Could not open the complete message safely. Refresh the mailbox and try again.',
    'Die vollständige Nachricht konnte nicht sicher geöffnet werden. Das Postfach aktualisieren und erneut versuchen.',
    'تعذر فتح الرسالة كاملة بأمان. حدّث صندوق البريد وحاول مجددًا.',
  );
}
