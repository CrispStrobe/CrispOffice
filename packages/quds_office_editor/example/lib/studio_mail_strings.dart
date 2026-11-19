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
  String get mailMarkReadFailed => _mailText(
    'The read status could not be confirmed. Refresh the mailbox before trying again.',
    'Der Lesestatus konnte nicht bestätigt werden. Vor einem erneuten Versuch das Postfach aktualisieren.',
    'تعذر تأكيد حالة القراءة. حدّث صندوق البريد قبل المحاولة مجددًا.',
  );
  String get mailRetainedDraft => _mailText(
    'Open Compose to review the retained draft, or discard it before starting a reply or forward.',
    'Zum Prüfen des gespeicherten Entwurfs „Verfassen“ öffnen oder den Entwurf vor dem Antworten oder Weiterleiten verwerfen.',
    'افتح إنشاء رسالة لمراجعة المسودة المحفوظة، أو احذفها قبل بدء الرد أو إعادة التوجيه.',
  );
  String get mailDiscardDraft => _mailText(
    'Discard retained draft',
    'Gespeicherten Entwurf verwerfen',
    'حذف المسودة المحفوظة',
  );
  String get mailDiscardDraftExplanation => _mailText(
    'This removes only the draft kept in this session. It does not cancel a message already submitted. Check delivery before sending another copy.',
    'Dies entfernt nur den in dieser Sitzung gespeicherten Entwurf. Eine bereits übermittelte Nachricht wird dadurch nicht zurückgerufen. Vor dem Senden einer weiteren Kopie die Zustellung prüfen.',
    'يؤدي هذا إلى حذف المسودة المحفوظة في هذه الجلسة فقط. ولا يلغي رسالة أُرسلت بالفعل. تحقق من التسليم قبل إرسال نسخة أخرى.',
  );
  String get mailPlainTextUnavailable => _mailText(
    'This message has no plain-text body to quote. Use Compose to write a new message.',
    'Diese Nachricht enthält keinen Klartext zum Zitieren. Mit „Verfassen“ eine neue Nachricht schreiben.',
    'لا تحتوي هذه الرسالة على نص عادي للاقتباس. استخدم إنشاء رسالة لكتابة رسالة جديدة.',
  );
  String get mailQuotedTextTruncated => _mailText(
    '[Quoted text truncated.]',
    '[Zitierter Text gekürzt.]',
    '[تم اقتطاع النص المقتبس.]',
  );
  String get mailTextOnlyForward => _mailText(
    '[Text-only forward; attachments are not included.]',
    '[Weiterleitung nur als Text; Anlagen sind nicht enthalten.]',
    '[إعادة توجيه النص فقط؛ المرفقات غير مضمنة.]',
  );
  String get reply => _mailText('Reply', 'Antworten', 'رد');
  String get forward => _mailText('Forward', 'Weiterleiten', 'إعادة توجيه');
  String get markRead =>
      _mailText('Mark as read', 'Als gelesen markieren', 'وضع علامة كمقروء');

  String get ewsTitle => _mailText(
    'Exchange Server (EWS)',
    'Exchange Server (EWS)',
    'خادم Exchange ‏(EWS)',
  );
  String get ewsSetupHelp => _mailText(
    'Connect directly to your organization’s Exchange Server using its EWS address.',
    'Direkt über die EWS-Adresse mit dem Exchange-Server Ihrer Organisation verbinden.',
    'اتصل مباشرة بخادم Exchange لمؤسستك باستخدام عنوان EWS.',
  );
  String get ewsEndpoint => _mailText(
    'EWS address (HTTPS)',
    'EWS-Adresse (HTTPS)',
    'عنوان EWS ‏(HTTPS)',
  );
  String get ewsLogin => _mailText(
    'Login (leave blank to use email)',
    'Anmeldename (leer: E-Mail-Adresse)',
    'اسم الدخول (اتركه فارغًا لاستخدام البريد)',
  );
  String get ewsDomain => _mailText(
    'Windows domain (optional)',
    'Windows-Domäne (optional)',
    'نطاق Windows (اختياري)',
  );
  String get ewsAuthentication =>
      _mailText('Authentication', 'Authentifizierung', 'المصادقة');
  String get ewsNtlm =>
      _mailText('Windows (NTLMv2)', 'Windows (NTLMv2)', 'Windows ‏(NTLMv2)');
  String get ewsBasic =>
      _mailText('Basic over HTTPS', 'Basic über HTTPS', 'Basic عبر HTTPS');
  String get ewsSessionNotice => _mailText(
    'Session only: credentials, downloaded messages and unsent drafts are kept in memory and cleared when you disconnect or close this window.',
    'Nur für diese Sitzung: Zugangsdaten, geladene Nachrichten und ungesendete Entwürfe bleiben im Arbeitsspeicher und werden beim Trennen oder Schließen gelöscht.',
    'للجلسة فقط: تُحفظ بيانات الدخول والرسائل المحمّلة والمسودات غير المرسلة في الذاكرة وتُمسح عند قطع الاتصال أو إغلاق النافذة.',
  );
  String get ewsInvalidSettings => _mailText(
    'Enter a valid email address, password and explicit HTTPS EWS address.',
    'Eine gültige E-Mail-Adresse, ein Passwort und eine vollständige HTTPS-EWS-Adresse eingeben.',
    'أدخل عنوان بريد صالحًا وكلمة مرور وعنوان EWS كاملًا باستخدام HTTPS.',
  );
  String get ewsAuthenticationFailed => _mailText(
    'Exchange could not authenticate this account. Check the login, domain, password and enabled authentication method.',
    'Exchange konnte dieses Konto nicht authentifizieren. Anmeldename, Domäne, Passwort und aktivierte Anmeldemethode prüfen.',
    'تعذرت مصادقة هذا الحساب لدى Exchange. تحقق من اسم الدخول والنطاق وكلمة المرور وطريقة المصادقة المفعّلة.',
  );
  String get ewsAccessFailed => _mailText(
    'Exchange access was refused. Check mailbox permissions and the server’s trusted HTTPS certificate.',
    'Der Exchange-Zugriff wurde abgelehnt. Postfachberechtigungen und das vertrauenswürdige HTTPS-Zertifikat des Servers prüfen.',
    'رُفض الوصول إلى Exchange. تحقق من أذونات صندوق البريد وشهادة HTTPS الموثوقة للخادم.',
  );
  String get ewsUnsupported => _mailText(
    'This Exchange server does not support the requested operation or authentication method.',
    'Dieser Exchange-Server unterstützt den Vorgang oder die Anmeldemethode nicht.',
    'لا يدعم خادم Exchange هذا العملية المطلوبة أو طريقة المصادقة.',
  );
  String get ewsBudgetExceeded => _mailText(
    'The request exceeded a message or server limit. Try a smaller folder or message.',
    'Die Anfrage überschritt eine Nachrichten- oder Servergrenze. Einen kleineren Ordner oder eine kleinere Nachricht versuchen.',
    'تجاوز الطلب حدًا للرسالة أو الخادم. جرّب مجلدًا أو رسالة أصغر.',
  );
  String get ewsSearchLoaded => _mailText(
    'Search loaded messages',
    'Geladene Nachrichten durchsuchen',
    'بحث في الرسائل المحمّلة',
  );
  String get ewsLoadMore => _mailText(
    'Load more messages',
    'Weitere Nachrichten laden',
    'تحميل المزيد من الرسائل',
  );
  String get ewsHeaderLimit => _mailText(
    'Showing up to 1,000 messages in this folder. Refresh or choose another folder to continue.',
    'Bis zu 1.000 Nachrichten in diesem Ordner werden angezeigt. Aktualisieren oder einen anderen Ordner wählen.',
    'تُعرض حتى 1000 رسالة في هذا المجلد. حدّث القائمة أو اختر مجلدًا آخر للمتابعة.',
  );
  String get ewsSubmissionAccepted => _mailText(
    'Exchange accepted the message and saved a copy in Sent Items.',
    'Exchange hat die Nachricht angenommen und eine Kopie unter „Gesendete Elemente“ gespeichert.',
    'قبل Exchange الرسالة وحفظ نسخة في العناصر المرسلة.',
  );
  String get ewsSubmissionRejected => _mailText(
    'The message was not submitted. Your draft is retained for this session.',
    'Die Nachricht wurde nicht übermittelt. Der Entwurf bleibt in dieser Sitzung erhalten.',
    'لم تُرسل الرسالة. تبقى المسودة محفوظة لهذه الجلسة.',
  );
  String get ewsActionConfirmed => _mailText(
    'Exchange confirmed the change.',
    'Exchange hat die Änderung bestätigt.',
    'أكد Exchange التغيير.',
  );
  String get ewsFolderChanged => _mailText(
    'Exchange confirmed the move. Refresh this folder before loading more messages.',
    'Exchange hat das Verschieben bestätigt. Den Ordner vor dem Laden weiterer Nachrichten aktualisieren.',
    'أكد Exchange النقل. حدّث هذا المجلد قبل تحميل المزيد من الرسائل.',
  );
  String get ewsMutationFailed => _mailText(
    'The change could not be confirmed. Refresh this folder before trying again.',
    'Die Änderung konnte nicht bestätigt werden. Den Ordner vor einem erneuten Versuch aktualisieren.',
    'تعذر تأكيد التغيير. حدّث هذا المجلد قبل المحاولة مجددًا.',
  );
  String get ewsMarkUnread => _mailText(
    'Mark as unread',
    'Als ungelesen markieren',
    'وضع علامة كغير مقروء',
  );
  String get ewsFlag => _mailText('Flag', 'Kennzeichnen', 'وضع علامة');
  String get ewsUnflag =>
      _mailText('Remove flag', 'Kennzeichnung entfernen', 'إزالة العلامة');
  String get ewsMove =>
      _mailText('Move to folder', 'In Ordner verschieben', 'نقل إلى مجلد');
  String get ewsDelete => _mailText(
    'Move to Deleted Items',
    'In „Gelöschte Elemente“ verschieben',
    'نقل إلى العناصر المحذوفة',
  );
  String get ewsDeleteExplanation => _mailText(
    'Move this message to the Exchange Deleted Items folder?',
    'Diese Nachricht in den Exchange-Ordner „Gelöschte Elemente“ verschieben?',
    'هل تريد نقل هذه الرسالة إلى مجلد العناصر المحذوفة في Exchange؟',
  );
  String get useStartTls => _mailText(
    'Use STARTTLS (ports 143/587)',
    'STARTTLS verwenden (Ports 143/587)',
    'استخدام STARTTLS (المنفذان 143/587)',
  );
  String get rememberAccount => _mailText(
    'Remember this account in the system keychain',
    'Dieses Konto im Systemschlüsselbund speichern',
    'حفظ هذا الحساب في سلسلة مفاتيح النظام',
  );
  String get forgetAccount => _mailText(
    'Forget saved account',
    'Gespeichertes Konto entfernen',
    'نسيان الحساب المحفوظ',
  );
}
