import 'studio_strings.dart';

extension StudioMailServerSearchStrings on StudioStrings {
  String _t(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailServerSearch =>
      _t('Search on server', 'Auf dem Server suchen', 'البحث على الخادم');
  String get mailServerSearchHelp => _t(
    'Searches the entire selected folder on the mail server. Only the first 50 results are shown, attachment text is not searched, and provider indexing determines what body text can be found.',
    'Durchsucht den gesamten ausgewählten Ordner auf dem Mailserver. Es werden nur die ersten 50 Treffer angezeigt, Anhangstexte werden nicht durchsucht, und die Indizierung des Anbieters bestimmt, welcher Nachrichtentext gefunden wird.',
    'يبحث في المجلد المحدد بالكامل على خادم البريد. تُعرض أول 50 نتيجة فقط، ولا يُبحث في نص المرفقات، وتحدد فهرسة المزود النص الذي يمكن العثور عليه.',
  );
  String get mailServerSearchField => _t('Search in', 'Suchen in', 'البحث في');
  String get mailServerSearchBody =>
      _t('Message body', 'Nachrichtentext', 'نص الرسالة');
  String get mailServerSearchSubject => _t('Subject', 'Betreff', 'الموضوع');
  String get mailServerSearchFrom => _t('From', 'Von', 'من');
  String get mailServerSearchTo => _t('To', 'An', 'إلى');
  String get mailServerSearchQuery => _t('Search text', 'Suchtext', 'نص البحث');
  String get mailServerSearchRun => _t('Search', 'Suchen', 'بحث');
  String get mailServerSearchStop => _t('Stop', 'Stoppen', 'إيقاف');
  String get mailServerSearchStopping => _t(
    'Stopping after the current server command. No new results will be adopted.',
    'Wird nach dem aktuellen Serverbefehl beendet. Es werden keine neuen Ergebnisse übernommen.',
    'يتوقف بعد أمر الخادم الحالي. لن تُعتمد نتائج جديدة.',
  );
  String get mailServerSearchRunning => _t(
    'Searching the selected folder on the server…',
    'Der ausgewählte Ordner wird auf dem Server durchsucht…',
    'جارٍ البحث في المجلد المحدد على الخادم…',
  );
  String get mailServerSearchFailed => _t(
    'The server search failed. The folder and its messages were not changed.',
    'Die Serversuche ist fehlgeschlagen. Der Ordner und seine Nachrichten wurden nicht geändert.',
    'فشل البحث على الخادم. لم يتغير المجلد أو رسائله.',
  );
  String get mailServerSearchEmpty => _t(
    'No messages matched in this folder.',
    'Keine Nachrichten in diesem Ordner gefunden.',
    'لا توجد رسائل مطابقة في هذا المجلد.',
  );
  String get mailServerSearchInvalid => _t(
    'Enter 1–512 characters without control characters.',
    'Geben Sie 1–512 Zeichen ohne Steuerzeichen ein.',
    'أدخل من 1 إلى 512 حرفًا دون أحرف تحكم.',
  );
  String get mailServerSearchOpen =>
      _t('Open result', 'Treffer öffnen', 'فتح النتيجة');
  String mailServerSearchCount(int total, int shown) => _t(
    '$total matches · showing $shown',
    '$total Treffer · $shown angezeigt',
    '$total نتيجة · يتم عرض $shown',
  );
  String get mailServerSearchTruncated => _t(
    'More matches exist. Refine the search to narrow the result.',
    'Es gibt weitere Treffer. Verfeinern Sie die Suche, um das Ergebnis einzugrenzen.',
    'توجد نتائج إضافية. حسّن البحث لتضييق النتيجة.',
  );
}
