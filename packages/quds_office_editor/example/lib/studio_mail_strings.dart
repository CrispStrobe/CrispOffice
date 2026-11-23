import 'studio_strings.dart';

/// Shared Mail feedback contains no server response or credential fragments.
extension StudioMailFeedback on StudioStrings {
  String _mailText(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailDismissNotice =>
      _mailText('Dismiss notice', 'Hinweis ausblenden', 'إخفاء الإشعار');

  String get mailSavedAccounts => _mailText(
    'Saved IMAP accounts',
    'Gespeicherte IMAP-Konten',
    'حسابات IMAP المحفوظة',
  );
  String get mailChooseAccount =>
      _mailText('Choose an account', 'Konto auswählen', 'اختر حسابًا');
  String get mailNewAccount =>
      _mailText('New account', 'Neues Konto', 'حساب جديد');
  String get mailSwitchAccount =>
      _mailText('Switch account', 'Konto wechseln', 'تبديل الحساب');
  String mailAccountSender(String sender) =>
      _mailText('Sender: $sender', 'Absender: $sender', 'المرسل: $sender');
  String mailAccountLogin(String login) =>
      _mailText('Login: $login', 'Anmeldename: $login', 'اسم الدخول: $login');
  String mailAccountImapLogin(String login) => _mailText(
    'IMAP login: $login',
    'IMAP-Anmeldename: $login',
    'اسم دخول IMAP: $login',
  );
  String mailAccountSmtpLogin(String login) => _mailText(
    'SMTP login: $login',
    'SMTP-Anmeldename: $login',
    'اسم دخول SMTP: $login',
  );
  String get mailSavedAccountsHelp => _mailText(
    'Choose a saved IMAP account, then Connect. New account keeps your other saved accounts. Forget removes only the selected sign-in; local drafts and saved messages stay on this device.',
    'Ein gespeichertes IMAP-Konto auswählen und dann verbinden. „Neues Konto“ behält die anderen gespeicherten Konten. „Konto vergessen“ entfernt nur die ausgewählten Zugangsdaten; lokale Entwürfe und gespeicherte Nachrichten bleiben auf diesem Gerät.',
    'اختر حساب IMAP محفوظًا ثم اتصل. يحتفظ الحساب الجديد بالحسابات المحفوظة الأخرى. يزيل نسيان الحساب بيانات الدخول المحددة فقط؛ وتبقى المسودات المحلية والرسائل المحفوظة على هذا الجهاز.',
  );
  String get mailAccountsLoadFailed => _mailText(
    'Saved accounts could not be opened. You can enter account settings manually; existing saved accounts have not been replaced.',
    'Gespeicherte Konten konnten nicht geöffnet werden. Kontoeinstellungen können manuell eingegeben werden; vorhandene gespeicherte Konten wurden nicht ersetzt.',
    'تعذر فتح الحسابات المحفوظة. يمكنك إدخال إعدادات الحساب يدويًا؛ لم تُستبدل الحسابات المحفوظة الحالية.',
  );
  String get mailAccountSelectFailed => _mailText(
    'Could not select this saved account. Your current settings are unchanged. Try again.',
    'Das gespeicherte Konto konnte nicht ausgewählt werden. Die aktuellen Einstellungen bleiben erhalten. Erneut versuchen.',
    'تعذر اختيار هذا الحساب المحفوظ. لم تتغير إعداداتك الحالية. حاول مجددًا.',
  );
  String get mailAccountLimitReached => _mailText(
    'This device already remembers 20 IMAP accounts. The current connection is available for this session. Forget an account before saving another.',
    'Auf diesem Gerät sind bereits 20 IMAP-Konten gespeichert. Die aktuelle Verbindung ist für diese Sitzung verfügbar. Vor dem Speichern eines weiteren Kontos eines der Konten vergessen.',
    'يحفظ هذا الجهاز بالفعل 20 حساب IMAP. الاتصال الحالي متاح لهذه الجلسة. انسَ أحد الحسابات قبل حفظ حساب آخر.',
  );

  String get mailDraftSaving => _mailText(
    'Saving draft…',
    'Entwurf wird gespeichert…',
    'جارٍ حفظ المسودة…',
  );
  String get mailDraftSaved => _mailText(
    'Draft saved on this device.',
    'Entwurf auf diesem Gerät gespeichert.',
    'حُفظت المسودة على هذا الجهاز.',
  );
  String get mailDraftAutosave => _mailText(
    'Draft changes are saved on this device.',
    'Entwurfsänderungen werden auf diesem Gerät gespeichert.',
    'تُحفظ تعديلات المسودة على هذا الجهاز.',
  );
  String get mailDraftCloseUnsaved => _mailText(
    'Close without saving',
    'Ohne Speichern schließen',
    'إغلاق دون حفظ',
  );
  String get mailDraftCloseUnsavedExplanation => _mailText(
    'The latest changes have not been saved and may be lost when you leave Mail. Previously saved draft content stays on this device. Close anyway?',
    'Die letzten Änderungen wurden nicht gespeichert und können beim Verlassen von Mail verloren gehen. Zuvor gespeicherte Entwurfsinhalte bleiben auf diesem Gerät. Trotzdem schließen?',
    'لم تُحفظ آخر التعديلات وقد تفقدها عند مغادرة البريد. تبقى محتويات المسودة المحفوظة سابقًا على هذا الجهاز. هل تريد الإغلاق؟',
  );
  String get mailDraftSaveFailed => _mailText(
    'Could not save the draft. Keep this window open and try again.',
    'Der Entwurf konnte nicht gespeichert werden. Dieses Fenster offen lassen und erneut versuchen.',
    'تعذر حفظ المسودة. أبقِ هذه النافذة مفتوحة وحاول مجددًا.',
  );
  String get mailDraftRetrySave =>
      _mailText('Retry saving', 'Erneut speichern', 'إعادة محاولة الحفظ');
  String get mailDraftSaveClose =>
      _mailText('Save and close', 'Speichern und schließen', 'حفظ وإغلاق');
  String get mailDraftRestored => _mailText(
    'A draft was restored from this device. Open Compose to continue.',
    'Ein Entwurf wurde von diesem Gerät wiederhergestellt. Mit „Verfassen“ fortfahren.',
    'استُعيدت مسودة من هذا الجهاز. افتح إنشاء رسالة للمتابعة.',
  );
  String get mailDraftStorageFailed => _mailText(
    'Local drafts are unavailable. Open Compose to retry. No message was sent.',
    'Lokale Entwürfe sind nicht verfügbar. Mit „Verfassen“ erneut versuchen. Es wurde keine Nachricht gesendet.',
    'المسودات المحلية غير متاحة. افتح إنشاء رسالة للمحاولة مجددًا. لم تُرسل أي رسالة.',
  );
  String get mailDraftAcceptedCleanupFailed => _mailText(
    'The server accepted this message, but the local draft could not be cleared. Do not resend it. A recovered copy will require a delivery check.',
    'Der Server hat diese Nachricht angenommen, aber der lokale Entwurf konnte nicht entfernt werden. Nicht erneut senden. Eine wiederhergestellte Kopie erfordert eine Zustellungsprüfung.',
    'قبل الخادم هذه الرسالة، لكن تعذر حذف المسودة المحلية. لا تُعد إرسالها. ستتطلب النسخة المستعادة التحقق من التسليم.',
  );

  String get mailInvalidRecipient => _mailText(
    'Enter 1–100 email addresses without display names, separated by commas or semicolons.',
    '1–100 E-Mail-Adressen ohne Anzeigenamen eingeben, durch Kommas oder Semikolons getrennt.',
    'أدخل من 1 إلى 100 عنوان بريد دون أسماء عرض، وافصل بينها بفواصل أو فواصل منقوطة.',
  );
  String get mailRecipientListHint => _mailText(
    'Separate email addresses with commas or semicolons.',
    'E-Mail-Adressen durch Kommas oder Semikolons trennen.',
    'افصل عناوين البريد بفواصل أو فواصل منقوطة.',
  );
  String get mailCopyRecipients =>
      _mailText('Cc / Bcc', 'Cc / Bcc', 'نسخة / نسخة مخفية');
  String get mailCc => _mailText('Cc', 'Cc', 'نسخة');
  String get mailBcc => _mailText('Bcc', 'Bcc', 'نسخة مخفية');
  String get mailReplyRecipientsUnavailable => _mailText(
    'The message has unsupported or too many reply recipients. Use Compose to choose recipients explicitly.',
    'Die Nachricht enthält nicht unterstützte oder zu viele Antwortadressen. Mit „Verfassen“ die Empfänger ausdrücklich auswählen.',
    'تحتوي الرسالة على عناوين رد غير مدعومة أو كثيرة جدًا. استخدم إنشاء رسالة لاختيار المستلمين صراحةً.',
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
  String get mailAddAttachments =>
      _mailText('Attach files', 'Dateien anhängen', 'إرفاق ملفات');
  String get mailReadingAttachments => _mailText(
    'Reading attachments…',
    'Anhänge werden gelesen…',
    'جارٍ قراءة المرفقات…',
  );
  String mailAttachmentSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
  }

  String mailAttachmentSummary(int count, int bytes) => _mailText(
    '$count / 10 attachments · ${mailAttachmentSize(bytes)} / 10 MiB total',
    '$count / 10 Anhänge · ${mailAttachmentSize(bytes)} / 10 MiB insgesamt',
    '$count / 10 مرفقات · ${mailAttachmentSize(bytes)} / 10 MiB إجمالًا',
  );
  String mailRemoveAttachment(String name) =>
      _mailText('Remove $name', '$name entfernen', 'إزالة $name');
  String get mailAttachmentFailed => _mailText(
    'No files were added. Choose up to 10 files totaling at most 10 MiB, with ordinary file names. Check that each file is available and try again.',
    'Es wurden keine Dateien hinzugefügt. Bis zu 10 Dateien mit insgesamt höchstens 10 MiB und gewöhnlichen Dateinamen auswählen. Prüfen, ob jede Datei verfügbar ist, und erneut versuchen.',
    'لم تُضف أي ملفات. اختر حتى 10 ملفات بأسماء عادية وبحجم إجمالي لا يتجاوز 10 ميبيبايت. تحقق من توفر كل ملف وحاول مجددًا.',
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
    'Submission could not be confirmed. Your draft is retained. Check delivery before sending it again.',
    'Der Versand konnte nicht bestätigt werden. Der Entwurf bleibt erhalten. Vor einem erneuten Versand die Zustellung prüfen.',
    'تعذر تأكيد الإرسال. حُفظت المسودة. تحقق من التسليم قبل إرسالها مجددًا.',
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
    'This removes the local draft and its saved attachments. It does not cancel a message already submitted. Check delivery before sending another copy.',
    'Dies entfernt den lokalen Entwurf und seine gespeicherten Anhänge. Eine bereits übermittelte Nachricht wird dadurch nicht zurückgerufen. Vor dem Senden einer weiteren Kopie die Zustellung prüfen.',
    'يؤدي هذا إلى حذف المسودة المحلية ومرفقاتها المحفوظة. ولا يلغي رسالة أُرسلت بالفعل. تحقق من التسليم قبل إرسال نسخة أخرى.',
  );
  String get mailPlainTextUnavailable => _mailText(
    'This message has no safely quotable body. Use Compose to write a new message.',
    'Der Nachrichtentext kann nicht sicher zitiert werden. Mit „Verfassen“ eine neue Nachricht schreiben.',
    'لا يوجد نص يمكن اقتباسه بأمان في هذه الرسالة. استخدم إنشاء رسالة لكتابة رسالة جديدة.',
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
  String get mailForwardWithAttachments => _mailText(
    'Forward with attachments',
    'Mit Anhängen weiterleiten',
    'إعادة التوجيه مع المرفقات',
  );
  String get mailAttachedForwardNotice => _mailText(
    '[Forwarded as text with original attachments. Inline images are attached as files.]',
    '[Als Text mit den ursprünglichen Anhängen weitergeleitet. Eingebettete Bilder sind als Dateien angehängt.]',
    '[أُعيد التوجيه كنص مع المرفقات الأصلية. تُرفق الصور المضمنة كملفات.]',
  );
  String get mailForwardAttachmentsUnavailable => _mailText(
    'Attachments could not be forwarded as a complete set. Use Forward text only or add files manually (up to 10 files / 10 MiB).',
    'Die Anhänge können nicht vollständig weitergeleitet werden. Nur Text weiterleiten oder Dateien manuell hinzufügen (bis zu 10 Dateien / 10 MiB).',
    'تعذر إعادة توجيه جميع المرفقات معًا. أعد توجيه النص فقط أو أضف الملفات يدويًا (حتى 10 ملفات / 10 ميبيبايت).',
  );
  String get reply => _mailText('Reply', 'Antworten', 'رد');
  String get replyAll =>
      _mailText('Reply all', 'Allen antworten', 'رد على الجميع');
  String get forward => _mailText(
    'Forward text only',
    'Nur Text weiterleiten',
    'إعادة توجيه النص فقط',
  );
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

  String get mailCloudSetupHelp => _mailText(
    'Sign in securely in your browser. Enter the email address of the mailbox you will authorize.',
    'Sicher im Browser anmelden. Die E-Mail-Adresse des freizugebenden Postfachs eingeben.',
    'سجّل الدخول بأمان في المتصفح. أدخل عنوان صندوق البريد الذي ستسمح بالوصول إليه.',
  );
  String get mailCloudClientId => _mailText(
    'Application client ID',
    'Client-ID der Anwendung',
    'معرّف عميل التطبيق',
  );
  String get mailCloudClientSecret => _mailText(
    'Google Desktop client secret (if issued)',
    'Google-Desktop-Client-Secret (falls ausgestellt)',
    'سر عميل Google لسطح المكتب (إن وُجد)',
  );
  String get mailCloudTenant => _mailText(
    'Microsoft tenant (common, organizations, consumers, or tenant ID)',
    'Microsoft-Mandant (common, organizations, consumers oder Mandanten-ID)',
    'مستأجر Microsoft ‏(common أو organizations أو consumers أو معرّف المستأجر)',
  );
  String get mailCloudGoogleRegistration => _mailText(
    'Use a Google Desktop app registration with Gmail API enabled. Your administrator may need to approve access. Never enter your Google account password here.',
    'Eine Google-Desktop-App-Registrierung mit aktivierter Gmail API verwenden. Möglicherweise muss die Administration den Zugriff erlauben. Hier niemals das Google-Kontopasswort eingeben.',
    'استخدم تسجيل تطبيق سطح مكتب من Google مع تفعيل Gmail API. قد يحتاج الوصول إلى موافقة المسؤول. لا تدخل كلمة مرور حساب Google هنا.',
  );
  String get mailCloudMicrosoftRegistration => _mailText(
    'Use a Microsoft public desktop app registration with a loopback redirect and delegated Mail.ReadWrite, Mail.Send and User.Read permissions. Your administrator may need to approve access.',
    'Eine öffentliche Microsoft-Desktop-App mit Loopback-Umleitung und delegierten Berechtigungen Mail.ReadWrite, Mail.Send und User.Read verwenden. Möglicherweise muss die Administration den Zugriff erlauben.',
    'استخدم تسجيل تطبيق Microsoft عام لسطح المكتب مع إعادة توجيه محلية وأذونات مفوّضة Mail.ReadWrite وMail.Send وUser.Read. قد يلزم الحصول على موافقة المسؤول.',
  );
  String get mailCloudDiagnostics => _mailText(
    'Verbose diagnostic logs',
    'Ausführliche Diagnoseprotokolle',
    'سجلات تشخيص مفصّلة',
  );
  String get mailCloudDiagnosticsHelp => _mailText(
    'Write operation, timing, status and size information to the application log. Addresses, message content and authorization values are excluded.',
    'Vorgänge, Laufzeiten, Status und Größen im Anwendungsprotokoll erfassen. Adressen, Nachrichteninhalte und Anmeldedaten sind ausgeschlossen.',
    'سجّل العمليات والأوقات والحالات والأحجام في سجل التطبيق. تُستبعد العناوين ومحتويات الرسائل وقيم المصادقة.',
  );
  String get mailCloudBrowserPending => _mailText(
    'Complete sign-in in your browser. You can cancel here at any time.',
    'Die Anmeldung im Browser abschließen. Hier kann jederzeit abgebrochen werden.',
    'أكمل تسجيل الدخول في المتصفح. يمكنك الإلغاء هنا في أي وقت.',
  );
  String get mailCloudSignIn => _mailText(
    'Sign in with browser',
    'Im Browser anmelden',
    'تسجيل الدخول بالمتصفح',
  );
  String get mailCloudInvalidSettings => _mailText(
    'Enter a valid mailbox address, application client ID and tenant settings.',
    'Eine gültige Postfachadresse, Client-ID und Mandanteneinstellungen eingeben.',
    'أدخل عنوان صندوق بريد صالحًا ومعرّف عميل التطبيق وإعدادات المستأجر.',
  );
  String get mailCloudSignInFailed => _mailText(
    'Sign-in did not complete. Check the app registration and browser, then try again.',
    'Die Anmeldung wurde nicht abgeschlossen. App-Registrierung und Browser prüfen und erneut versuchen.',
    'لم يكتمل تسجيل الدخول. تحقق من تسجيل التطبيق والمتصفح، ثم حاول مجددًا.',
  );
  String get mailCloudAuthenticationFailed => _mailText(
    'The account needs authorization. Sign in again with the same mailbox address.',
    'Das Konto benötigt eine Freigabe. Mit derselben Postfachadresse erneut anmelden.',
    'يحتاج الحساب إلى تفويض. سجّل الدخول مجددًا بعنوان صندوق البريد نفسه.',
  );
  String get mailCloudAccessFailed => _mailText(
    'Mailbox access was refused. Check that you selected the same account and granted the requested mail permissions.',
    'Der Postfachzugriff wurde abgelehnt. Dasselbe Konto auswählen und die angeforderten Mail-Berechtigungen freigeben.',
    'رُفض الوصول إلى صندوق البريد. تحقق من اختيار الحساب نفسه ومنح أذونات البريد المطلوبة.',
  );
  String get mailCloudUnsupported => _mailText(
    'This account or platform does not support the requested mail operation.',
    'Dieses Konto oder diese Plattform unterstützt den angeforderten Mail-Vorgang nicht.',
    'لا يدعم هذا الحساب أو هذه المنصة عملية البريد المطلوبة.',
  );
  String mailCloudRetryAfter(int seconds) => _mailText(
    'The mail service asked you to wait $seconds seconds before trying again. This action will not retry automatically.',
    'Der Mail-Dienst bittet darum, vor dem nächsten Versuch $seconds Sekunden zu warten. Der Vorgang wird nicht automatisch wiederholt.',
    'طلبت خدمة البريد الانتظار $seconds ثانية قبل المحاولة مجددًا. لن تُعاد هذه العملية تلقائيًا.',
  );
  String get mailCloudSubmissionAccepted => _mailText(
    'The mail service accepted the message for sending. Check Sent for the saved copy; acceptance does not confirm delivery.',
    'Der Mail-Dienst hat die Nachricht zum Senden angenommen. Die Kopie unter „Gesendet“ prüfen; die Annahme bestätigt keine Zustellung.',
    'قبلت خدمة البريد الرسالة للإرسال. تحقق من النسخة في البريد المرسل؛ القبول لا يؤكد التسليم.',
  );
  String get mailCloudActionConfirmed => _mailText(
    'The mail service confirmed the change.',
    'Der Mail-Dienst hat die Änderung bestätigt.',
    'أكدت خدمة البريد التغيير.',
  );
  String get mailCloudFolderChanged => _mailText(
    'The mail service confirmed the move. Refresh this folder before loading more messages.',
    'Der Mail-Dienst hat das Verschieben bestätigt. Den Ordner vor dem Laden weiterer Nachrichten aktualisieren.',
    'أكدت خدمة البريد النقل. حدّث هذا المجلد قبل تحميل المزيد من الرسائل.',
  );
  String get mailCloudDelete => _mailText(
    'Move to Trash / Deleted Items',
    'In Papierkorb / Gelöschte Elemente verschieben',
    'نقل إلى المهملات / العناصر المحذوفة',
  );
  String get mailCloudDeleteExplanation => _mailText(
    'Move this message to the account’s trash folder?',
    'Diese Nachricht in den Papierkorb des Kontos verschieben?',
    'هل تريد نقل هذه الرسالة إلى مجلد المهملات في الحساب؟',
  );
  String get mailProvider =>
      _mailText('Mail provider', 'Mail-Anbieter', 'مزوّد البريد');
  String get mailOtherProvider => _mailText(
    'Other IMAP / SMTP account',
    'Anderes IMAP-/SMTP-Konto',
    'حساب IMAP / SMTP آخر',
  );
  String get mailAppPassword =>
      _mailText('App password', 'App-Passwort', 'كلمة مرور التطبيق');
  String get mailPrimaryLogin => _mailText(
    'Primary account email (if different)',
    'Primäre Konto-E-Mail-Adresse (falls abweichend)',
    'البريد الأساسي للحساب (إن كان مختلفًا)',
  );
  String get mailIcloudFullLogin => _mailText(
    'Use the full email address for iCloud incoming login if the short name fails',
    'Bei fehlgeschlagenem Kurznamen die vollständige E-Mail-Adresse für die iCloud-Eingangsanmeldung verwenden',
    'استخدم عنوان البريد الكامل لتسجيل الدخول إلى بريد iCloud الوارد إذا لم يعمل الاسم المختصر',
  );
  String get mailPresetPasswordHelp => _mailText(
    'Create an app password in your provider’s account settings. Fastmail requires a plan with IMAP/SMTP access. For aliases or custom domains, enter the primary account email below.',
    'In den Kontoeinstellungen des Anbieters ein App-Passwort erstellen. Fastmail benötigt einen Tarif mit IMAP-/SMTP-Zugriff. Für Aliase oder eigene Domains unten die primäre Konto-E-Mail-Adresse eingeben.',
    'أنشئ كلمة مرور للتطبيق في إعدادات حساب المزوّد. يتطلب Fastmail خطة تدعم IMAP/SMTP. للأسماء المستعارة أو النطاقات الخاصة، أدخل البريد الأساسي للحساب أدناه.',
  );
  String get useStartTls => _mailText(
    'Use STARTTLS (ports 143/587)',
    'STARTTLS verwenden (Ports 143/587)',
    'استخدام STARTTLS (المنفذان 143/587)',
  );
  String get rememberAccount => _mailText(
    'Remember this account in the selected credential store',
    'Dieses Konto im gewählten Zugangsdaten-Speicher speichern',
    'حفظ هذا الحساب في مخزن بيانات الاعتماد المحدد',
  );
  String get forgetAccount => _mailText(
    'Forget saved account',
    'Gespeichertes Konto entfernen',
    'نسيان الحساب المحفوظ',
  );
  // Keep the recovery branch's feedback names compatible with the more
  // detailed provider-aware strings used by the current account dialog.
  String get mailAccountStorageNotice => mailSessionNotice;
  String get mailAccountSaveFailed => mailKeychainSaveFailed;
  String get mailAccountForgetFailed => mailKeychainClearFailed;

  String get mailKeychainSaveFailed => _mailText(
    'Connected, but the account could not be saved in the selected credential store. This session remains available.',
    'Verbunden, aber das Konto konnte nicht im gewählten Zugangsdaten-Speicher gespeichert werden. Diese Sitzung bleibt verfügbar.',
    'تم الاتصال، لكن تعذر حفظ الحساب في مخزن بيانات الاعتماد المحدد. تبقى هذه الجلسة متاحة.',
  );
  String get mailKeychainClearFailed => _mailText(
    'The saved account could not be removed from the selected credential store. Try Forget saved account again.',
    'Das gespeicherte Konto konnte nicht aus dem gewählten Zugangsdaten-Speicher entfernt werden. „Gespeichertes Konto entfernen“ erneut versuchen.',
    'تعذر إزالة الحساب المحفوظ من مخزن بيانات الاعتماد المحدد. حاول نسيان الحساب المحفوظ مجددًا.',
  );
}
