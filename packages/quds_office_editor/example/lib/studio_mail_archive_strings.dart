import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_strings.dart';

/// Archive feedback never includes platform exceptions, paths or credentials.
extension StudioMailArchiveStrings on StudioStrings {
  String _archiveText(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get archiveCurrentMessage =>
      _archiveText('Archive message', 'Nachricht archivieren', 'أرشفة الرسالة');
  String get archiveMessageStored => _archiveText(
    'Message archived locally.',
    'Nachricht lokal archiviert.',
    'أُرشفت الرسالة محليًا.',
  );
  String get archiveMessageDuplicate => _archiveText(
    'This original is already archived. Its source information is retained.',
    'Dieses Original ist bereits archiviert. Die Quellenangaben bleiben erhalten.',
    'هذه الرسالة الأصلية مؤرشفة بالفعل. حُفظت معلومات مصدرها.',
  );
  String get archiveMessageFailed => _archiveText(
    'The message could not be archived. The live mailbox is unchanged.',
    'Die Nachricht konnte nicht archiviert werden. Das Live-Postfach bleibt unverändert.',
    'تعذرت أرشفة الرسالة. لم يتغير صندوق البريد المباشر.',
  );
  String get archiveTitle =>
      _archiveText('Mail archive', 'Mail-Archiv', 'أرشيف البريد');
  String get archiveDesktopRequired => _archiveText(
    'The persistent mail archive requires the desktop app. Saved messages can still be opened here.',
    'Das dauerhafte Mail-Archiv benötigt die Desktop-App. Gespeicherte Nachrichten können hier weiterhin geöffnet werden.',
    'يتطلب أرشيف البريد الدائم تطبيق سطح المكتب. لا يزال بإمكانك فتح الرسائل المحفوظة هنا.',
  );
  String get archiveStorageNotice => _archiveText(
    'Original messages are saved locally and remain available after disconnecting mail accounts. Export important messages or back up the application data.',
    'Originalnachrichten werden lokal gespeichert und bleiben nach dem Trennen der E-Mail-Konten verfügbar. Wichtige Nachrichten exportieren oder die Anwendungsdaten sichern.',
    'تُحفظ الرسائل الأصلية محليًا وتبقى متاحة بعد فصل حسابات البريد. صدّر الرسائل المهمة أو انسخ بيانات التطبيق احتياطيًا.',
  );
  String get archiveSearch =>
      _archiveText('Search archive', 'Archiv durchsuchen', 'بحث في الأرشيف');
  String get archiveSearchHelp => _archiveText(
    'Use words, "exact phrases", a trailing prefix*, subject:, from:, to:, cc:, bcc:, bcontent:, acontent: or attachment:. Combine with AND, OR, NOT, parentheses or [alternatives]. Leading wildcards, ? and wildcards inside phrases are unsupported.',
    'Wörter, "genaue Wortgruppen", Präfix*, subject:, from:, to:, cc:, bcc:, bcontent:, acontent: oder attachment: verwenden. Mit AND, OR, NOT, Klammern oder [Alternativen] kombinieren. Führende Platzhalter, ? und Platzhalter in Wortgruppen werden nicht unterstützt.',
    'استخدم كلمات أو "عبارات مطابقة" أو بادئة* أو subject: أو from: أو to: أو cc: أو bcc: أو bcontent: أو acontent: أو attachment:. اجمعها باستخدام AND أو OR أو NOT أو الأقواس أو [البدائل]. لا تُدعم الرموز البديلة في البداية أو ? أو داخل العبارات.',
  );
  String get archiveFilters =>
      _archiveText('Search filters', 'Suchfilter', 'مرشّحات البحث');
  String get archiveSource => _archiveText('Source', 'Quelle', 'المصدر');
  String get archiveFolder => _archiveText('Folder', 'Ordner', 'المجلد');
  String get archiveSubfolders => _archiveText(
    'Include subfolders',
    'Unterordner einschließen',
    'تضمين المجلدات الفرعية',
  );
  String get archiveSentSince => _archiveText(
    'Sent from (UTC, YYYY-MM-DD)',
    'Gesendet ab (UTC, JJJJ-MM-TT)',
    'أُرسلت منذ (UTC، YYYY-MM-DD)',
  );
  String get archiveSentThrough => _archiveText(
    'Sent through (inclusive)',
    'Gesendet bis (einschließlich)',
    'أُرسلت حتى (شامل)',
  );
  String get archiveStoredSince => _archiveText(
    'Archived from (UTC, YYYY-MM-DD)',
    'Archiviert ab (UTC, JJJJ-MM-TT)',
    'أُرشفت منذ (UTC، YYYY-MM-DD)',
  );
  String get archiveStoredThrough => _archiveText(
    'Archived through (inclusive)',
    'Archiviert bis (einschließlich)',
    'أُرشفت حتى (شامل)',
  );
  String get archiveMinSize => _archiveText(
    'Minimum size (bytes)',
    'Mindestgröße (Bytes)',
    'الحجم الأدنى (بايت)',
  );
  String get archiveMaxSize => _archiveText(
    'Maximum size (bytes)',
    'Höchstgröße (Bytes)',
    'الحجم الأقصى (بايت)',
  );
  String get archiveAttachments =>
      _archiveText('Attachments', 'Anhänge', 'المرفقات');
  String get archiveAny => _archiveText('Any', 'Alle', 'الكل');
  String get archiveWithAttachments =>
      _archiveText('With attachments', 'Mit Anhängen', 'بمرفقات');
  String get archiveWithoutAttachments =>
      _archiveText('Without attachments', 'Ohne Anhänge', 'بلا مرفقات');
  String get archiveSort => _archiveText('Sort', 'Sortierung', 'الترتيب');
  String get archiveNewestStored =>
      _archiveText('Recently archived', 'Zuletzt archiviert', 'الأحدث أرشفة');
  String get archiveNewestSent =>
      _archiveText('Newest message', 'Neueste Nachricht', 'الرسالة الأحدث');
  String get archiveOldestSent =>
      _archiveText('Oldest message', 'Älteste Nachricht', 'الرسالة الأقدم');
  String get archiveClearFilters =>
      _archiveText('Clear filters', 'Filter zurücksetzen', 'مسح المرشّحات');
  String get archiveImport => _archiveText(
    'Import EML / MBOX',
    'EML / MBOX importieren',
    'استيراد EML / MBOX',
  );
  String get archiveMboxFormat =>
      _archiveText('MBOX format', 'MBOX-Format', 'تنسيق MBOX');
  String get archiveMboxHelp => _archiveText(
    'Choose the format used by the application that exported the MBOX file. It controls how quoted From lines are restored; EML files are unaffected.',
    'Das Format der Anwendung wählen, die die MBOX-Datei exportiert hat. Es bestimmt die Wiederherstellung maskierter From-Zeilen; EML-Dateien sind nicht betroffen.',
    'اختر التنسيق الذي استخدمه التطبيق لتصدير ملف MBOX. يحدد كيفية استعادة أسطر From المقتبسة؛ لا تتأثر ملفات EML.',
  );
  String get archiveLocalFiles =>
      _archiveText('Local files', 'Lokale Dateien', 'ملفات محلية');
  String get archiveImportHelp => _archiveText(
    'Choose a source name and original folder for this import. Source files are kept unchanged. Duplicate original messages are stored once.',
    'Quellennamen und ursprünglichen Ordner für diesen Import wählen. Quelldateien bleiben unverändert. Identische Originalnachrichten werden nur einmal gespeichert.',
    'اختر اسم المصدر والمجلد الأصلي لهذا الاستيراد. تبقى الملفات المصدر دون تغيير. تُحفظ الرسائل الأصلية المتطابقة مرة واحدة.',
  );
  String get archiveIndexAttachmentText => _archiveText(
    'Index supported attachment text',
    'Text unterstützter Anhänge indizieren',
    'فهرسة نص المرفقات المدعومة',
  );
  String get archiveAttachmentHelp => _archiveText(
    'Attachment names are searchable. Text extraction is bounded; unsupported or oversized attachment content is skipped.',
    'Anhangnamen sind durchsuchbar. Die Textextraktion ist begrenzt; nicht unterstützte oder zu große Anhanginhalte werden übersprungen.',
    'يمكن البحث في أسماء المرفقات. استخراج النص محدود؛ يُتجاوز محتوى المرفقات غير المدعوم أو الكبير جدًا.',
  );
  String get archiveChooseFiles =>
      _archiveText('Choose files', 'Dateien auswählen', 'اختيار ملفات');
  String get archiveCancel => _archiveText('Cancel', 'Abbrechen', 'إلغاء');
  String get archiveSaveSearch =>
      _archiveText('Save search', 'Suche speichern', 'حفظ البحث');
  String get archiveSavedSearches => _archiveText(
    'Saved searches',
    'Gespeicherte Suchen',
    'عمليات البحث المحفوظة',
  );
  String get archiveSearchName =>
      _archiveText('Search name', 'Name der Suche', 'اسم البحث');
  String get archiveDeleteSearch => _archiveText(
    'Delete saved search',
    'Gespeicherte Suche löschen',
    'حذف البحث المحفوظ',
  );
  String get archiveSearchSaved =>
      _archiveText('Search saved.', 'Suche gespeichert.', 'حُفظ البحث.');
  String get archiveSearchRemoved => _archiveText(
    'Saved search removed.',
    'Gespeicherte Suche entfernt.',
    'حُذف البحث المحفوظ.',
  );
  String get archiveExport => _archiveText(
    'Export original EML',
    'Original als EML exportieren',
    'تصدير EML الأصلي',
  );
  String get archiveExported => _archiveText(
    'Original message exported.',
    'Originalnachricht exportiert.',
    'صُدّرت الرسالة الأصلية.',
  );
  String get archiveVerify =>
      _archiveText('Check integrity', 'Integrität prüfen', 'فحص السلامة');
  String get archiveRebuild => _archiveText(
    'Rebuild search index',
    'Suchindex neu aufbauen',
    'إعادة بناء فهرس البحث',
  );
  String get archiveIndexingOptions => _archiveText(
    'Indexing options',
    'Indexierungsoptionen',
    'خيارات الفهرسة',
  );
  String get archiveRebuildHelp => _archiveText(
    'Used for new imports. Rebuild the index to apply this setting to existing messages; original bytes remain unchanged.',
    'Gilt für neue Importe. Den Index neu aufbauen, um diese Einstellung auf vorhandene Nachrichten anzuwenden; Originaldaten bleiben unverändert.',
    'يُستخدم للاستيراد الجديد. أعد بناء الفهرس لتطبيق الإعداد على الرسائل الحالية؛ تبقى البيانات الأصلية دون تغيير.',
  );
  String get archiveDiagnostics => _archiveText(
    'Verbose diagnostic logs',
    'Ausführliche Diagnoseprotokolle',
    'سجلات تشخيص مفصّلة',
  );
  String get archiveDiagnosticsHelp => _archiveText(
    'Logs contain operation IDs, status, timing and counts. Message content, addresses, paths and search text are excluded.',
    'Protokolliert werden Vorgangs-IDs, Status, Laufzeiten und Anzahlen. Nachrichteninhalt, Adressen, Pfade und Suchtext werden ausgeschlossen.',
    'تحتوي السجلات على معرّفات العمليات والحالة والأوقات والأعداد. تُستبعد محتويات الرسائل والعناوين والمسارات ونص البحث.',
  );
  String get archiveWorking =>
      _archiveText('Working…', 'Wird verarbeitet …', 'جارٍ المعالجة…');
  String get archiveNoResults => _archiveText(
    'No archived messages match this search.',
    'Keine archivierten Nachrichten entsprechen dieser Suche.',
    'لا توجد رسائل مؤرشفة تطابق هذا البحث.',
  );
  String get archivePrevious =>
      _archiveText('Previous page', 'Vorherige Seite', 'الصفحة السابقة');
  String get archiveNext =>
      _archiveText('Next page', 'Nächste Seite', 'الصفحة التالية');
  String get archiveBack => _archiveText(
    'Back to results',
    'Zurück zu Ergebnissen',
    'العودة إلى النتائج',
  );
  String get archiveRetry => _archiveText(
    'Retry opening archive',
    'Archiv erneut öffnen',
    'إعادة فتح الأرشيف',
  );
  String get archiveQueryInvalid => _archiveText(
    'Check the query syntax, valid calendar dates and size range. End dates include the whole UTC day.',
    'Suchsyntax, gültige Kalenderdaten und Größenbereich prüfen. Enddaten schließen den gesamten UTC-Tag ein.',
    'تحقق من صيغة البحث والتواريخ الصحيحة ونطاق الحجم. يشمل تاريخ النهاية اليوم بأكمله بتوقيت UTC.',
  );
  String get archiveNoSubject =>
      _archiveText('(No subject)', '(Kein Betreff)', '(بلا موضوع)');
  String get archiveLimitedIndex => _archiveText(
    'Some message or attachment text was not indexed. The original message is preserved.',
    'Ein Teil des Nachrichten- oder Anhangtexts wurde nicht indiziert. Die Originalnachricht bleibt erhalten.',
    'لم يُفهرس بعض نص الرسالة أو المرفقات. حُفظت الرسالة الأصلية.',
  );
  String archiveStats(int messages, int bytes, int indexed) => _archiveText(
    '$messages messages · $bytes bytes · $indexed indexed',
    '$messages Nachrichten · $bytes Bytes · $indexed indiziert',
    '$messages رسالة · $bytes بايت · $indexed مفهرسة',
  );
  String archivePage(int first, int last, int total) => _archiveText(
    '$first–$last of $total',
    '$first–$last von $total',
    '$first–$last من $total',
  );
  String archiveProgress(int processed) => _archiveText(
    '$processed processed',
    '$processed verarbeitet',
    'عُولج $processed',
  );
  String archiveImportSummary(
    int imported,
    int duplicates,
    int failed,
    int warnings,
    bool cancelled,
  ) => _archiveText(
    '$imported imported · $duplicates duplicates · $failed failed · $warnings with limited extraction${cancelled ? ' · cancelled' : ''}',
    '$imported importiert · $duplicates Duplikate · $failed fehlgeschlagen · $warnings mit begrenzter Extraktion${cancelled ? ' · abgebrochen' : ''}',
    '$imported مستوردة · $duplicates مكررة · $failed فاشلة · $warnings باستخراج محدود${cancelled ? ' · أُلغي' : ''}',
  );
  String archiveMaintenanceSummary(
    int processed,
    int issues,
    bool cancelled,
  ) => _archiveText(
    '$processed processed · $issues issues${cancelled ? ' · cancelled' : ''}',
    '$processed verarbeitet · $issues Probleme${cancelled ? ' · abgebrochen' : ''}',
    '$processed معالجة · $issues مشكلة${cancelled ? ' · أُلغي' : ''}',
  );
  String get archiveIntegrityIssues => _archiveText(
    'Integrity issues (up to 100)',
    'Integritätsprobleme (bis zu 100)',
    'مشكلات السلامة (حتى 100)',
  );
  String archiveIntegrityIssue(MailArchiveIntegrityCode code) => switch (code) {
    MailArchiveIntegrityCode.rawHashMismatch => _archiveText(
      'Original content changed',
      'Originalinhalt verändert',
      'تغيّر المحتوى الأصلي',
    ),
    MailArchiveIntegrityCode.metadataHashMismatch => _archiveText(
      'Stored metadata changed',
      'Gespeicherte Metadaten verändert',
      'تغيّرت البيانات الوصفية المحفوظة',
    ),
    MailArchiveIntegrityCode.missingIndex => _archiveText(
      'Search index missing',
      'Suchindex fehlt',
      'فهرس البحث مفقود',
    ),
    MailArchiveIntegrityCode.indexMismatch => _archiveText(
      'Search index needs repair',
      'Suchindex muss repariert werden',
      'يحتاج فهرس البحث إلى إصلاح',
    ),
    MailArchiveIntegrityCode.missingOrigin => _archiveText(
      'Source information missing',
      'Quellenangaben fehlen',
      'معلومات المصدر مفقودة',
    ),
    MailArchiveIntegrityCode.exceedsReadLimit => _archiveText(
      'Message exceeds read limit',
      'Nachricht überschreitet die Lesegrenze',
      'تتجاوز الرسالة حد القراءة',
    ),
  };
  String archiveProblem(MailProblemCode code) => switch (code) {
    MailProblemCode.invalidInput => archiveQueryInvalid,
    MailProblemCode.quotaExceeded => _archiveText(
      'A message, archive or disk limit was reached. Try smaller files or free disk space.',
      'Eine Nachrichten-, Archiv- oder Datenträgergrenze wurde erreicht. Kleinere Dateien verwenden oder Speicherplatz freigeben.',
      'بُلِغ حد الرسالة أو الأرشيف أو القرص. جرّب ملفات أصغر أو وفّر مساحة.',
    ),
    MailProblemCode.permissionDenied => _archiveText(
      'Access was denied. Check the selected file or application-data permissions.',
      'Zugriff verweigert. Berechtigungen der ausgewählten Datei oder Anwendungsdaten prüfen.',
      'رُفض الوصول. تحقق من أذونات الملف المحدد أو بيانات التطبيق.',
    ),
    MailProblemCode.conflict => _archiveText(
      'The archive is in use, or the export destination already exists. Close the other archive window or choose a new file name.',
      'Das Archiv wird verwendet oder das Exportziel existiert bereits. Das andere Archivfenster schließen oder einen neuen Dateinamen wählen.',
      'الأرشيف قيد الاستخدام أو وجهة التصدير موجودة بالفعل. أغلق نافذة الأرشيف الأخرى أو اختر اسم ملف جديدًا.',
    ),
    MailProblemCode.cancelled || MailProblemCode.staleOperation => _archiveText(
      'Operation cancelled. Completed archive writes are retained.',
      'Vorgang abgebrochen. Abgeschlossene Archivschreibvorgänge bleiben erhalten.',
      'أُلغيت العملية. تبقى عمليات الكتابة المكتملة في الأرشيف محفوظة.',
    ),
    MailProblemCode.unsupported => _archiveText(
      'This file or operation is not supported.',
      'Diese Datei oder dieser Vorgang wird nicht unterstützt.',
      'هذا الملف أو هذه العملية غير مدعومين.',
    ),
    _ => _archiveText(
      'The archive operation failed. Retry; diagnostic status codes can help investigate.',
      'Der Archivvorgang ist fehlgeschlagen. Erneut versuchen; Diagnose-Statuscodes können bei der Untersuchung helfen.',
      'فشلت عملية الأرشيف. حاول مجددًا؛ قد تساعد رموز حالة التشخيص في التحقيق.',
    ),
  };
}
