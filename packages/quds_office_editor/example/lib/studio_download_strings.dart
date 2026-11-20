import 'studio_download_catalog.dart';
import 'studio_strings.dart';

/// English, German and Arabic text for the Downloads overview,
/// following the [StudioStrings] pattern.
final class StudioDownloadStrings {
  const StudioDownloadStrings(this.language);

  final StudioLanguage language;

  String _t(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get title => _t('Downloads', 'Downloads', 'التنزيلات');
  String get intro => _t(
    'Review language and font support, size, source and licence before installing. Downloads start only when you choose Install in the package review. Removing downloaded data leaves your documents unchanged.',
    'Sprach- und Schriftunterstützung, Größe, Quelle und Lizenz vor der Installation prüfen. Downloads beginnen erst, wenn Sie in der Paketprüfung „Installieren“ wählen. Das Entfernen heruntergeladener Daten lässt Ihre Dokumente unverändert.',
    'راجع دعم اللغات والخطوط والحجم والمصدر والترخيص قبل التثبيت. لا يبدأ التنزيل إلا عند اختيار «تثبيت» في مراجعة الحزمة. إزالة البيانات المنزّلة لا تغيّر مستنداتك.',
  );
  String summary(int installed, int total, String size) => _t(
    '$installed of $total packages installed · $size on this device',
    '$installed von $total Paketen installiert · $size auf diesem Gerät',
    'تم تثبيت $installed من $total حزم · $size على هذا الجهاز',
  );
  String get forThisDocument =>
      _t('For this document', 'Für dieses Dokument', 'لهذا المستند');
  String get included =>
      _t('Included with the app', 'In der App enthalten', 'مضمّن في التطبيق');
  String get includedNote => _t(
    'Bundled data is part of the application and needs no download.',
    'Mitgelieferte Daten gehören zur App und brauchen keinen Download.',
    'البيانات المضمّنة جزء من التطبيق ولا تحتاج إلى تنزيل.',
  );
  List<String> get includedItems => <String>[
    _t(
      'German spelling and writing rules',
      'Deutsche Rechtschreibung und Schreibregeln',
      'تدقيق الإملاء وقواعد الكتابة الألمانية',
    ),
    _t(
      'English spelling and grammar (Harper)',
      'Englische Rechtschreibung und Grammatik (Harper)',
      'الإملاء والنحو الإنجليزي (Harper)',
    ),
    _t(
      'Arabic writing rules',
      'Arabische Schreibregeln',
      'قواعد الكتابة العربية',
    ),
    _t(
      'Language detection (CLD3)',
      'Spracherkennung (CLD3)',
      'التعرّف على اللغة (CLD3)',
    ),
    _t('Thesaurus data', 'Thesaurus-Daten', 'بيانات المرادفات'),
  ];
  String get available =>
      _t('Available downloads', 'Verfügbare Downloads', 'التنزيلات المتاحة');
  String get licences => _t('Licences', 'Lizenzen', 'التراخيص');
  String get close => _t('Close', 'Schließen', 'إغلاق');
  String get notNow => _t('Not now', 'Nicht jetzt', 'ليس الآن');
  String get install => _t('Install…', 'Installieren…', 'تثبيت…');
  String get repair => _t('Repair…', 'Reparieren…', 'إصلاح…');
  String get details => _t('Details…', 'Details…', 'التفاصيل…');
  String get remove => _t('Remove', 'Entfernen', 'إزالة');
  String get cancel => _t('Cancel', 'Abbrechen', 'إلغاء');
  String get fontsUnavailable => _t(
    'Font pack status is not available on this platform.',
    'Der Status der Schriftpakete ist auf dieser Plattform nicht verfügbar.',
    'حالة حزم الخطوط غير متاحة على هذه المنصة.',
  );
  String get empty => _t(
    'No downloadable packages are offered on this device.',
    'Auf diesem Gerät werden keine Pakete zum Download angeboten.',
    'لا تتوفر حزم للتنزيل على هذا الجهاز.',
  );
  String installLabel(String title) =>
      _t('Install $title', '$title installieren', 'تثبيت $title');
  String removeLabel(String title) =>
      _t('Remove $title', '$title entfernen', 'إزالة $title');
  String cancelLabel(String title) => _t(
    'Cancel download of $title',
    'Download von $title abbrechen',
    'إلغاء تنزيل $title',
  );
  String licenceLabel(String licence) => _t(
    'Licence $licence (opens in browser)',
    'Lizenz $licence (öffnet im Browser)',
    'الترخيص $licence (يفتح في المتصفح)',
  );

  String languageName(String code) => switch (code) {
    'ar' => _t('Arabic', 'Arabisch', 'العربية'),
    'de' => _t('German', 'Deutsch', 'الألمانية'),
    'en' => _t('English', 'Englisch', 'الإنجليزية'),
    'fr' => _t('French', 'Französisch', 'الفرنسية'),
    studioFontGroup => _t('Fonts', 'Schriften', 'الخطوط'),
    _ => code,
  };

  String kind(StudioDownloadKind kind) => switch (kind) {
    StudioDownloadKind.spelling => _t(
      'Spelling dictionary',
      'Rechtschreibwörterbuch',
      'قاموس إملائي',
    ),
    StudioDownloadKind.morphology => _t(
      'Morphology data',
      'Morphologiedaten',
      'بيانات صرفية',
    ),
    StudioDownloadKind.contextModel => _t(
      'Context model',
      'Kontextmodell',
      'نموذج السياق',
    ),
    StudioDownloadKind.analysis => _t(
      'Analysis model',
      'Analysemodell',
      'نموذج تحليل',
    ),
    StudioDownloadKind.entities => _t(
      'Named-entity model',
      'Modell für Eigennamen',
      'نموذج أسماء الأعلام',
    ),
    StudioDownloadKind.fonts => _t('Font pack', 'Schriftpaket', 'حزمة خطوط'),
  };

  String note(StudioDownloadNote note) => switch (note) {
    StudioDownloadNote.modelFilesOnly => _t(
      'Model files only (library built into the app)',
      'Nur Modelldateien (Bibliothek in der App enthalten)',
      'ملفات النموذج فقط (المكتبة مضمّنة في التطبيق)',
    ),
    StudioDownloadNote.includesNativePackage => _t(
      'Native package for this platform; analysis, manual grammar only for a qualified build',
      'Natives Paket für diese Plattform; Analyse, manuelle Grammatik nur für einen qualifizierten Build',
      'حزمة أصلية لهذه المنصة؛ تحليل، والتدقيق النحوي اليدوي فقط لإصدار مؤهَّل',
    ),
    StudioDownloadNote.includesSharedRuntime => _t(
      'Analysis only; includes the shared runtime',
      'Nur Analyse; enthält die gemeinsame Laufzeit',
      'تحليل فقط؛ يشمل بيئة التشغيل المشتركة',
    ),
    StudioDownloadNote.developerConfiguration => _t(
      'Developer configuration',
      'Entwicklerkonfiguration',
      'إعداد المطوّر',
    ),
    StudioDownloadNote.analysisOnly => _t(
      'Analysis only; not a spelling or grammar checker',
      'Nur Analyse; keine Rechtschreib- oder Grammatikprüfung',
      'تحليل فقط؛ ليس مدققًا إملائيًا أو نحويًا',
    ),
  };

  String state(StudioDownloadItem item, String size) => switch (item.state) {
    StudioDownloadState.notInstalled => _t(
      'Not installed',
      'Nicht installiert',
      'غير مثبّت',
    ),
    StudioDownloadState.installed =>
      item.exactSizeOnDisk
          ? _t('Installed · $size', 'Installiert · $size', 'مثبّت · $size')
          : _t('Installed', 'Installiert', 'مثبّت'),
    StudioDownloadState.downloading => () {
      final percent = item.progress == null
          ? ''
          : ' ${(item.progress! * 100).round()}%';
      return _t(
        'Downloading$percent',
        'Wird geladen$percent',
        'جارٍ التنزيل$percent',
      );
    }(),
    StudioDownloadState.needsRepair => _t(
      'Needs repair',
      'Reparatur nötig',
      'يحتاج إلى إصلاح',
    ),
    StudioDownloadState.needsPrerequisite => _t(
      'Needs base package',
      'Basispaket fehlt',
      'يحتاج الحزمة الأساسية',
    ),
    StudioDownloadState.unavailable => _t(
      'Not available here',
      'Hier nicht verfügbar',
      'غير متاح هنا',
    ),
  };

  /// Precedes the required package's (Latin) title.
  String get requires => _t('Requires', 'Benötigt', 'يتطلب');

  /// What is already covered for a document language and what is optional.
  String coverage(String language) {
    final primary = language
        .replaceAll('_', '-')
        .split('-')
        .first
        .toLowerCase();
    return switch (primary) {
      'en' => _t(
        '$language: English spelling and grammar use the bundled Harper checker. No dictionary download is required. The optional English spaCy model provides analysis, not grammar checking.',
        '$language: Englische Rechtschreibung und Grammatik nutzen den mitgelieferten Harper-Prüfer. Kein Wörterbuch-Download nötig. Das optionale englische spaCy-Modell liefert Analyse, keine Grammatikprüfung.',
        '$language: يستخدم التدقيق الإملائي والنحوي الإنجليزي مدقق Harper المضمّن. لا حاجة إلى تنزيل قاموس. نموذج spaCy الإنجليزي الاختياري للتحليل فقط وليس للتدقيق النحوي.',
      ),
      'de' => _t(
        '$language: German spelling and deterministic writing rules are included. German spaCy analysis and qualified manual grammar are optional downloads.',
        '$language: Deutsche Rechtschreibung und deterministische Schreibregeln sind enthalten. Deutsche spaCy-Analyse und qualifizierte manuelle Grammatik sind optionale Downloads.',
        '$language: التدقيق الإملائي الألماني وقواعد الكتابة الحتمية مضمّنة. تحليل spaCy الألماني والتدقيق النحوي اليدوي المؤهَّل تنزيلات اختيارية.',
      ),
      'ar' => _t(
        '$language: Arabic writing rules are included. Download the Arabic dictionary for spelling and the optional morphology database and context model for additional rules.',
        '$language: Arabische Schreibregeln sind enthalten. Laden Sie das arabische Wörterbuch für die Rechtschreibung und optional die Morphologiedatenbank und das Kontextmodell für weitere Regeln herunter.',
        '$language: قواعد الكتابة العربية مضمّنة. نزّل القاموس العربي للتدقيق الإملائي، وقاعدة البيانات الصرفية ونموذج السياق الاختياريين لمزيد من القواعد.',
      ),
      'fr' => _t(
        '$language: Optional French analysis is available. Analysis does not provide a French spelling or grammar checker.',
        '$language: Optionale französische Analyse ist verfügbar. Die Analyse ist keine französische Rechtschreib- oder Grammatikprüfung.',
        '$language: يتوفر تحليل فرنسي اختياري. التحليل لا يوفّر مدققًا إملائيًا أو نحويًا فرنسيًا.',
      ),
      _ => _t(
        '$language: No spelling/grammar download is currently offered in the verified catalogue. Changing the document language does not install another language’s checker.',
        '$language: Im geprüften Katalog wird derzeit kein Rechtschreib-/Grammatik-Download angeboten. Ein Wechsel der Dokumentsprache installiert keinen Prüfer einer anderen Sprache.',
        '$language: لا يتوفر حاليًا تنزيل للتدقيق الإملائي أو النحوي في الفهرس المعتمد. تغيير لغة المستند لا يثبّت مدقق لغة أخرى.',
      ),
    };
  }
}
