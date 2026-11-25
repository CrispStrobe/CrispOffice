import 'studio_strings.dart';

extension StudioMailRichStrings on StudioStrings {
  String _richText(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailRichBody => _richText('Message', 'Nachricht', 'الرسالة');
  String get mailRichHelp => _richText(
    'Format text and paragraphs, or add a link. A plain-text version is included when sending.',
    'Formatieren Sie Text und Absätze oder fügen Sie einen Link ein. Beim Senden ist eine Klartextfassung enthalten.',
    'نسّق النص والفقرات أو أضف رابطًا. تُرفق نسخة نصية عادية عند الإرسال.',
  );
  String get mailRichBold => _richText('Bold', 'Fett', 'غامق');
  String get mailRichItalic => _richText('Italic', 'Kursiv', 'مائل');
  String get mailRichUnderline =>
      _richText('Underline', 'Unterstreichen', 'تسطير');
  String get mailRichStrike =>
      _richText('Strikethrough', 'Durchstreichen', 'يتوسطه خط');
  String get mailRichAlignment =>
      _richText('Paragraph alignment', 'Absatzausrichtung', 'محاذاة الفقرة');
  String get mailRichLeft =>
      _richText('Align left', 'Linksbündig', 'محاذاة لليسار');
  String get mailRichCenter => _richText('Center', 'Zentriert', 'توسيط');
  String get mailRichRight =>
      _richText('Align right', 'Rechtsbündig', 'محاذاة لليمين');
  String get mailRichJustify => _richText('Justify', 'Blocksatz', 'ضبط');
  String get mailRichRtl => _richText(
    'Right-to-left paragraph',
    'Absatz von rechts nach links',
    'فقرة من اليمين إلى اليسار',
  );
  String get mailRichLtr => _richText(
    'Left-to-right paragraph',
    'Absatz von links nach rechts',
    'فقرة من اليسار إلى اليمين',
  );
  String get mailRichUndo => _richText('Undo', 'Rückgängig', 'تراجع');
  String get mailRichRedo => _richText('Redo', 'Wiederholen', 'إعادة');
  String get mailRichLink =>
      _richText('Add link', 'Link einfügen', 'إضافة رابط');
  String get mailRichLinkAddress =>
      _richText('Link address', 'Linkadresse', 'عنوان الرابط');
  String get mailRichLinkLabel =>
      _richText('Link text', 'Linktext', 'نص الرابط');
  String get mailRichLinkHelp => _richText(
    'Use an http or https address, or mailto followed by one email address. Links are not opened while composing.',
    'Verwenden Sie eine http- oder https-Adresse oder mailto gefolgt von einer E-Mail-Adresse. Links werden beim Verfassen nicht geöffnet.',
    'استخدم عنوان http أو https، أو mailto متبوعًا بعنوان بريد إلكتروني واحد. لا تُفتح الروابط أثناء الكتابة.',
  );
  String get mailRichLinkInvalid => _richText(
    'Enter a supported link and nonempty link text.',
    'Geben Sie einen unterstützten Link und einen nicht leeren Linktext ein.',
    'أدخل رابطًا مدعومًا ونصًا غير فارغ للرابط.',
  );
  String get mailRichChanged => _richText(
    'The message or selection changed. Select the text again before adding a link.',
    'Die Nachricht oder Auswahl hat sich geändert. Wählen Sie den Text erneut aus, bevor Sie einen Link einfügen.',
    'تغيّرت الرسالة أو التحديد. حدد النص مجددًا قبل إضافة الرابط.',
  );
  String get mailRichUnsupported => _richText(
    'This message cannot be saved with its current formatting or size. Undo the last change or paste as plain text. Mail supports bold, italic, underline, strikethrough, links, alignment and paragraph direction; lists, tables and inline objects are not supported yet.',
    'Diese Nachricht kann mit ihrer aktuellen Formatierung oder Größe nicht gespeichert werden. Machen Sie die letzte Änderung rückgängig oder fügen Sie Klartext ein. Mail unterstützt Fett, Kursiv, Unterstreichen, Durchstreichen, Links, Ausrichtung und Absatzrichtung; Listen, Tabellen und eingebettete Objekte werden noch nicht unterstützt.',
    'لا يمكن حفظ الرسالة بتنسيقها أو حجمها الحالي. تراجع عن آخر تغيير أو الصق كنص عادي. يدعم البريد الغامق والمائل والتسطير ويتوسطه خط والروابط والمحاذاة واتجاه الفقرة؛ القوائم والجداول والعناصر المضمنة غير مدعومة بعد.',
  );
  String get mailRichConflict => _richText(
    'The saved text and formatting disagree. The saved plain text is shown. Close without saving to retain the original draft for recovery.',
    'Der gespeicherte Text und die Formatierung stimmen nicht überein. Der gespeicherte Klartext wird angezeigt. Schließen Sie ohne Speichern, um den ursprünglichen Entwurf für die Wiederherstellung zu behalten.',
    'لا يتطابق النص المحفوظ مع التنسيق. يظهر النص العادي المحفوظ. أغلق دون حفظ للاحتفاظ بالمسودة الأصلية واستعادتها لاحقًا.',
  );
  String get mailRichTemplateTitle => _richText(
    'Save a plain-text template?',
    'Klartextvorlage speichern?',
    'حفظ قالب نصي عادي؟',
  );
  String get mailRichTemplateHelp => _richText(
    'Message templates currently keep plain text. This template will include the text without formatting. The draft keeps its formatting.',
    'Nachrichtenvorlagen speichern derzeit Klartext. Diese Vorlage enthält den Text ohne Formatierung. Der Entwurf behält seine Formatierung.',
    'تحتفظ قوالب الرسائل حاليًا بالنص العادي. سيتضمن هذا القالب النص دون تنسيق. تحتفظ المسودة بتنسيقها.',
  );
  String get mailRichTemplateConfirm =>
      _richText('Use plain text', 'Klartext verwenden', 'استخدام النص العادي');
}
