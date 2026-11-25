import 'studio_strings.dart';

extension StudioMailIdentityStrings on StudioStrings {
  String _identityText(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailSenderIdentities =>
      _identityText('Sender identities', 'Absenderidentitäten', 'هويات المرسل');
  String get mailSenderIdentityAdd => _identityText(
    'Add sender identity',
    'Absenderidentität hinzufügen',
    'إضافة هوية مرسل',
  );
  String get mailSenderAddress =>
      _identityText('From address', 'Absenderadresse', 'عنوان المرسل');
  String get mailSenderDisplayName =>
      _identityText('Display name', 'Anzeigename', 'اسم العرض');
  String get mailSenderReplyTo => _identityText(
    'Reply-To address (optional)',
    'Antwortadresse (optional)',
    'عنوان الرد (اختياري)',
  );
  String get mailSenderPrimary =>
      _identityText('Account address', 'Kontoadresse', 'عنوان الحساب');
  String get mailSenderDefault => _identityText(
    'Default for new messages',
    'Standard für neue Nachrichten',
    'الافتراضي للرسائل الجديدة',
  );
  String get mailSenderSaved => _identityText(
    'Saved draft sender',
    'Gespeicherter Entwurfsabsender',
    'مرسل المسودة المحفوظ',
  );
  String get mailSenderHelp => _identityText(
    'Identities use this account’s existing connection. Your provider must permit each From address. They do not create another account or grant sending permission.',
    'Identitäten verwenden die bestehende Verbindung dieses Kontos. Ihr Anbieter muss jede Absenderadresse erlauben. Sie erstellen kein weiteres Konto und erteilen keine Sendeberechtigung.',
    'تستخدم الهويات اتصال هذا الحساب الحالي. يجب أن يسمح مزودك بكل عنوان مرسل. لا تنشئ الهويات حسابًا آخر ولا تمنح صلاحية الإرسال.',
  );
  String get mailSenderRestricted => _identityText(
    'This connection currently supports the account’s From address only. Choose the account address to send; the saved sender has not been changed.',
    'Diese Verbindung unterstützt derzeit nur die Absenderadresse des Kontos. Wählen Sie zum Senden die Kontoadresse; der gespeicherte Absender wurde nicht geändert.',
    'يدعم هذا الاتصال حاليًا عنوان مرسل الحساب فقط. اختر عنوان الحساب للإرسال؛ لم يتغير المرسل المحفوظ.',
  );
  String get mailSenderInvalid => _identityText(
    'Enter a unique name and a valid email address. Check the optional Reply-To address and remove unsupported characters.',
    'Geben Sie einen eindeutigen Namen und eine gültige E-Mail-Adresse ein. Prüfen Sie die optionale Antwortadresse und entfernen Sie unzulässige Zeichen.',
    'أدخل اسمًا فريدًا وعنوان بريد صالحًا. تحقق من عنوان الرد الاختياري وأزل المحارف غير المدعومة.',
  );
  String get mailSenderInUse => _identityText(
    'A template uses this identity. Choose another sender in that template before removing it.',
    'Eine Vorlage verwendet diese Identität. Wählen Sie dort vor dem Entfernen einen anderen Absender.',
    'يستخدم قالب هذه الهوية. اختر مرسلًا آخر في القالب قبل إزالتها.',
  );
  String get mailMessageTemplates => _identityText(
    'Message templates',
    'Nachrichtenvorlagen',
    'قوالب الرسائل',
  );
  String get mailMessageTemplateAdd => _identityText(
    'Add message template',
    'Nachrichtenvorlage hinzufügen',
    'إضافة قالب رسالة',
  );
  String get mailMessageTemplateUse =>
      _identityText('Use template', 'Vorlage verwenden', 'استخدام قالب');
  String get mailMessageTemplateSave =>
      _identityText('Save as template', 'Als Vorlage speichern', 'حفظ كقالب');
  String get mailMessageTemplateHelp => _identityText(
    'Save recipients, subject, supported text formatting and an optional sender. Templates contain no attachments and never send a message automatically.',
    'Speichern Sie Empfänger, Betreff, unterstützte Textformatierungen und optional einen Absender. Vorlagen enthalten keine Anhänge und senden niemals automatisch eine Nachricht.',
    'احفظ المستلمين والموضوع وتنسيقات النص المدعومة ومرسلًا اختياريًا. لا تحتوي القوالب على مرفقات ولا ترسل رسالة تلقائيًا.',
  );
  String get mailMessageTemplateReplace => _identityText(
    'Replace this draft?',
    'Diesen Entwurf ersetzen?',
    'استبدال هذه المسودة؟',
  );
  String get mailMessageTemplateReplaceHelp => _identityText(
    'The template replaces recipients, subject, body and sender. Existing attachments and reply threading are removed. This creates an independent message and does not send it.',
    'Die Vorlage ersetzt Empfänger, Betreff, Text und Absender. Vorhandene Anhänge und Antwortbezüge werden entfernt. Es entsteht eine eigenständige Nachricht, die nicht gesendet wird.',
    'يستبدل القالب المستلمين والموضوع والنص والمرسل. تُزال المرفقات الحالية وروابط الرد. ينشئ ذلك رسالة مستقلة ولا يرسلها.',
  );
  String get mailMessageTemplateInvalid => _identityText(
    'Use a unique name, a subject of at most 512 characters and a body of at most 16,384 characters. Simplify formatting or remove unused writing tools if storage is full. Recipient fields are checked again before sending.',
    'Verwenden Sie einen eindeutigen Namen, höchstens 512 Zeichen im Betreff und 16.384 Zeichen im Text. Vereinfachen Sie bei vollem Speicher die Formatierung oder entfernen Sie ungenutzte Schreibhilfen. Empfänger werden vor dem Senden erneut geprüft.',
    'استخدم اسمًا فريدًا وموضوعًا لا يتجاوز 512 حرفًا ونصًا لا يتجاوز 16,384 حرفًا. بسّط التنسيق أو احذف أدوات الكتابة غير المستخدمة إذا امتلأت مساحة التخزين. تُفحص حقول المستلمين مجددًا قبل الإرسال.',
  );
  String get mailMessageTemplateChanged => _identityText(
    'The draft or account changed while the template was open. Review the current draft and try again.',
    'Entwurf oder Konto haben sich geändert, während die Vorlage geöffnet war. Prüfen Sie den aktuellen Entwurf und versuchen Sie es erneut.',
    'تغيرت المسودة أو الحساب أثناء فتح القالب. راجع المسودة الحالية وحاول مجددًا.',
  );
}
