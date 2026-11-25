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
    'Searches the entire selected folder on the mail server, optionally limited by received date. Only the first 50 results are shown, attachment text is not searched, and provider indexing determines what body text can be found.',
    'Durchsucht den gesamten ausgewählten Ordner auf dem Mailserver, optional begrenzt nach Empfangsdatum. Es werden nur die ersten 50 Treffer angezeigt, Anhangstexte werden nicht durchsucht, und die Indizierung des Anbieters bestimmt, welcher Nachrichtentext gefunden wird.',
    'يبحث في المجلد المحدد بالكامل على خادم البريد. تُعرض أول 50 نتيجة فقط، ولا يُبحث في نص المرفقات، وتحدد فهرسة المزود النص الذي يمكن العثور عليه.',
  );
  String get mailServerSearchField => _t('Search in', 'Suchen in', 'البحث في');
  String get mailProviderSearchHelp => _t(
    'Searches this folder on the provider, with at most 50 results. Only supported fields are offered. Provider indexing and phrase matching determine coverage; totals may be estimated or unavailable. Quotes, backslashes and wildcards may be unsupported by the provider.',
    'Durchsucht diesen Ordner beim Anbieter mit höchstens 50 Treffern. Es werden nur unterstützte Felder angeboten. Indexierung und Phrasensuche des Anbieters bestimmen die Abdeckung; Gesamtzahlen können geschätzt oder unbekannt sein. Anführungszeichen, umgekehrte Schrägstriche und Platzhalter werden möglicherweise nicht unterstützt.',
    'يبحث في هذا المجلد لدى المزود ويعرض 50 نتيجة كحد أقصى. تتوفر الحقول المدعومة فقط. تعتمد التغطية على فهرسة المزود ومطابقة العبارات؛ وقد يكون العدد تقديريًا أو غير متاح. قد لا يدعم المزود علامات الاقتباس والشرطات المائلة العكسية وأحرف البدل.',
  );
  String mailServerSearchFolder(String folder) =>
      _t('Folder: $folder', 'Ordner: $folder', 'المجلد: $folder');
  String get mailServerSearchNoSubject =>
      _t('(no subject)', '(kein Betreff)', '(بلا موضوع)');
  String get mailServerSearchBody =>
      _t('Message body', 'Nachrichtentext', 'نص الرسالة');
  String get mailServerSearchSubject => _t('Subject', 'Betreff', 'الموضوع');
  String get mailServerSearchFrom => _t('From', 'Von', 'من');
  String get mailServerSearchTo => _t('To', 'An', 'إلى');
  String get mailServerSearchRange =>
      _t('Received', 'Empfangen', 'تاريخ الاستلام');
  String get mailServerSearchAnyTime => _t('Any time', 'Beliebig', 'أي وقت');
  String get mailServerSearchLast7 =>
      _t('Last 7 days', 'Letzte 7 Tage', 'آخر 7 أيام');
  String get mailServerSearchLast30 =>
      _t('Last 30 days', 'Letzte 30 Tage', 'آخر 30 يومًا');
  String get mailServerSearchLast90 =>
      _t('Last 90 days', 'Letzte 90 Tage', 'آخر 90 يومًا');
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
  String get mailServerSearchUnsupported => _t(
    'This provider cannot search that field or literal text. Try a supported field or text without quotes, backslashes or wildcards.',
    'Dieser Anbieter kann dieses Feld oder diesen Suchtext nicht durchsuchen. Versuchen Sie ein unterstütztes Feld oder Text ohne Anführungszeichen, umgekehrte Schrägstriche und Platzhalter.',
    'لا يمكن لهذا المزود البحث في هذا الحقل أو النص. جرّب حقلًا مدعومًا أو نصًا دون علامات اقتباس أو شرطات مائلة عكسية أو أحرف بدل.',
  );
  String get mailServerSearchAuthorization => _t(
    'Search needs a valid sign-in and permission to read this folder. Reconnect the account and try again.',
    'Die Suche erfordert eine gültige Anmeldung und Leseberechtigung für diesen Ordner. Verbinden Sie das Konto erneut und versuchen Sie es noch einmal.',
    'يتطلب البحث تسجيل دخول صالحًا وإذنًا لقراءة هذا المجلد. أعد ربط الحساب وحاول مجددًا.',
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
  String mailServerSearchEstimate(int total, int shown) => _t(
    'About $total matches · showing $shown',
    'Etwa $total Treffer · $shown angezeigt',
    'نحو $total نتيجة · يتم عرض $shown',
  );
  String mailServerSearchUnknown(int shown) => _t(
    'Showing $shown · total unavailable',
    '$shown angezeigt · Gesamtzahl unbekannt',
    'يتم عرض $shown · العدد الإجمالي غير متاح',
  );
  String get mailServerSearchMorePossible => _t(
    'More matches may be available beyond this result limit. Refine the search.',
    'Außerhalb dieser Ergebnisgrenze können weitere Treffer vorhanden sein. Verfeinern Sie die Suche.',
    'قد تتوفر نتائج إضافية تتجاوز هذا الحد. حسّن البحث.',
  );
  String get mailServerSearchTruncated => _t(
    'More matches exist. Refine the search to narrow the result.',
    'Es gibt weitere Treffer. Verfeinern Sie die Suche, um das Ergebnis einzugrenzen.',
    'توجد نتائج إضافية. حسّن البحث لتضييق النتيجة.',
  );
}
