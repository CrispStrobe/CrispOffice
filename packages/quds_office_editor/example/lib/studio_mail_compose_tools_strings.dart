import 'studio_strings.dart';

extension StudioMailComposeToolsStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailComposeTools =>
      _text('Writing tools', 'Schreibhilfen', 'أدوات الكتابة');
  String get mailComposeToolsHelp => _text(
    'Save a plain-text signature and reusable text for this account on this device. Changes are saved together when you choose Save.',
    'Speichern Sie eine Klartextsignatur und wiederverwendbare Texte für dieses Konto auf diesem Gerät. Alle Änderungen werden gemeinsam mit „Speichern“ übernommen.',
    'احفظ توقيعًا نصيًا ونصوصًا قابلة لإعادة الاستخدام لهذا الحساب على هذا الجهاز. تُحفظ جميع التغييرات معًا عند اختيار حفظ.',
  );
  String get mailComposeSignature => _text('Signature', 'Signatur', 'التوقيع');
  String get mailComposeSignatureForNew => _text(
    'Add to new messages',
    'Bei neuen Nachrichten einfügen',
    'إضافة إلى الرسائل الجديدة',
  );
  String get mailComposeSignatureForReplies => _text(
    'Add to replies and forwards',
    'Bei Antworten und Weiterleitungen einfügen',
    'إضافة إلى الردود والرسائل المعاد توجيهها',
  );
  String get mailComposeQuickTexts =>
      _text('Quick Text', 'Schnelltexte', 'النصوص السريعة');
  String get mailComposeQuickTextsHelp => _text(
    'Keep up to 32 named snippets to insert while composing a message.',
    'Speichern Sie bis zu 32 benannte Textbausteine zum Einfügen beim Verfassen.',
    'احفظ حتى 32 نصًا مسمى لإدراجه أثناء كتابة الرسائل.',
  );
  String get mailComposeQuickTextsEmpty => _text(
    'No Quick Text saved yet.',
    'Noch keine Schnelltexte gespeichert.',
    'لم تُحفظ نصوص سريعة بعد.',
  );
  String get mailComposeQuickTextAdd =>
      _text('Add Quick Text', 'Schnelltext hinzufügen', 'إضافة نص سريع');
  String get mailComposeQuickTextEdit => _text('Edit', 'Bearbeiten', 'تحرير');
  String get mailComposeQuickTextDelete =>
      _text('Remove', 'Entfernen', 'إزالة');
  String get mailComposeQuickTextApply =>
      _text('Apply text', 'Text übernehmen', 'اعتماد النص');
  String get mailComposeQuickTextName => _text('Name', 'Name', 'الاسم');
  String get mailComposeQuickTextText =>
      _text('Text to insert', 'Einzufügender Text', 'النص المراد إدراجه');
  String get mailComposeQuickTextInvalid => _text(
    'Enter a name and text. The name can contain up to 80 characters and the text up to 16,384. Unsupported control characters are not allowed.',
    'Geben Sie einen Namen und Text ein. Der Name darf bis zu 80 Zeichen und der Text bis zu 16.384 Zeichen enthalten. Nicht unterstützte Steuerzeichen sind nicht zulässig.',
    'أدخل اسمًا ونصًا. يمكن أن يحتوي الاسم على 80 حرفًا والنص على 16,384 حرفًا كحد أقصى. لا يُسمح بمحارف التحكم غير المدعومة.',
  );
  String get mailComposeQuickTextDuplicate => _text(
    'A Quick Text entry already uses this name. Choose a different name.',
    'Ein Schnelltext verwendet diesen Namen bereits. Wählen Sie einen anderen Namen.',
    'يوجد نص سريع بهذا الاسم بالفعل. اختر اسمًا آخر.',
  );
  String get mailComposeToolsInvalid => _text(
    'These writing tools exceed the text limits or contain unsupported characters. Shorten the signature or Quick Text entries before saving.',
    'Diese Schreibhilfen überschreiten die Textgrenzen oder enthalten nicht unterstützte Zeichen. Kürzen Sie die Signatur oder Schnelltexte vor dem Speichern.',
    'تتجاوز أدوات الكتابة حدود النص أو تحتوي على محارف غير مدعومة. اختصر التوقيع أو النصوص السريعة قبل الحفظ.',
  );
  String get mailComposeToolsSaveUnconfirmed => _text(
    'The save could not be confirmed. Your edits are still shown. Close and reopen Writing tools to load the saved version before saving again.',
    'Das Speichern konnte nicht bestätigt werden. Ihre Änderungen werden weiterhin angezeigt. Schließen und öffnen Sie die Schreibhilfen erneut, um vor einem weiteren Speicherversuch den gespeicherten Stand zu laden.',
    'تعذر تأكيد الحفظ. ما زالت تعديلاتك ظاهرة. أغلق أدوات الكتابة وافتحها مجددًا لتحميل النسخة المحفوظة قبل إعادة الحفظ.',
  );
  String get mailComposeToolsStale => _text(
    'This account is no longer active. Close Writing tools and reopen it for the current account.',
    'Dieses Konto ist nicht mehr aktiv. Schließen Sie die Schreibhilfen und öffnen Sie sie für das aktuelle Konto erneut.',
    'لم يعد هذا الحساب نشطًا. أغلق أدوات الكتابة وافتحها مجددًا للحساب الحالي.',
  );
  String get mailComposeToolsSaving => _text(
    'Saving writing tools…',
    'Schreibhilfen werden gespeichert…',
    'جارٍ حفظ أدوات الكتابة…',
  );
  String get mailComposeInsertSignature =>
      _text('Insert signature', 'Signatur einfügen', 'إدراج التوقيع');
  String get mailComposeInsertQuickText =>
      _text('Insert Quick Text', 'Schnelltext einfügen', 'إدراج نص سريع');
  String get mailComposeToolsLoading => _text(
    'Loading writing tools…',
    'Schreibhilfen werden geladen…',
    'جارٍ تحميل أدوات الكتابة…',
  );
  String get mailComposeToolsLoadFailed => _text(
    'Could not load writing tools. Retry to load your saved signature and Quick Text.',
    'Schreibhilfen konnten nicht geladen werden. Versuchen Sie es erneut, um Ihre gespeicherte Signatur und Schnelltexte zu laden.',
    'تعذر تحميل أدوات الكتابة. أعد المحاولة لتحميل توقيعك ونصوصك السريعة المحفوظة.',
  );
  String get mailComposeToolsReload => _text(
    'Reload writing tools',
    'Schreibhilfen neu laden',
    'إعادة تحميل أدوات الكتابة',
  );
  String get mailComposeToolsSelectionFailed => _text(
    'Place the cursor in one paragraph, or select the whole message, before inserting writing tools.',
    'Setzen Sie den Cursor in einen Absatz oder wählen Sie die gesamte Nachricht aus, bevor Sie Schreibhilfen einfügen.',
    'ضع المؤشر في فقرة واحدة، أو حدد الرسالة بأكملها، قبل إدراج نصوص أدوات الكتابة.',
  );
  String get mailComposeToolsInsertionFailed => _text(
    'This text cannot be inserted because the message would exceed its size limit.',
    'Dieser Text kann nicht eingefügt werden, da die Nachricht dadurch ihre Größenbegrenzung überschreiten würde.',
    'لا يمكن إدراج هذا النص لأن الرسالة ستتجاوز حد الحجم.',
  );
  String get mailComposeSignatureAlreadyPresent => _text(
    'This signature is already in the message.',
    'Diese Signatur ist bereits in der Nachricht enthalten.',
    'هذا التوقيع موجود بالفعل في الرسالة.',
  );
  String get mailComposeToolsSaved => _text(
    'Writing tools saved. Changes apply to future messages; insert text explicitly in this draft.',
    'Schreibhilfen gespeichert. Änderungen gelten für künftige Nachrichten; fügen Sie den Text in diesem Entwurf bei Bedarf selbst ein.',
    'حُفظت أدوات الكتابة. تسري التغييرات على الرسائل القادمة؛ أدرج النص يدويًا في هذه المسودة.',
  );
}
