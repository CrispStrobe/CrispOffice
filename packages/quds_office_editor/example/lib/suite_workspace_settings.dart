part of 'suite_workspace.dart';

/// Persistence state of the workspace's settings (see [StudioSettingsStore]).
final class _StudioSettingsBinding {
  _StudioSettingsBinding(this.store);
  final StudioSettingsStore store;

  /// False until the stored settings were applied: nothing is saved before,
  /// so defaults never overwrite a stored document.
  bool restored = false;
  StudioSettings? saved;
  int wordsRevision = -1;
  Map<String, List<String>> words = const <String, List<String>>{};
}

/// Restores the Studio settings at startup and saves them whenever the
/// workspace rebuilds with a changed value. Only preferences are stored —
/// UI language, theme, units, view and PDF viewer options, proofing options
/// and the personal dictionary — never credentials or document content.
extension _StudioSettingsPersistence on _SuiteWorkspaceState {
  Map<String, List<String>> _personalWords() {
    final vocabulary = _word.proofing.vocabulary;
    final binding = _settings;
    if (binding.wordsRevision != vocabulary.revision) {
      binding.wordsRevision = vocabulary.revision;
      final words = vocabulary.toJson()['words'];
      binding.words = <String, List<String>>{
        if (words is Map<String, Object?>)
          for (final entry in words.entries)
            if (entry.value is List && (entry.value! as List).isNotEmpty)
              entry.key: (entry.value! as List).cast<String>(),
      };
    }
    return binding.words;
  }

  StudioSettings _currentSettings() {
    final base = _settings.saved ?? StudioSettings.defaults();
    return base.copyWith(<String, Object?>{
      StudioSettingKeys.language: _language.name,
      StudioSettingKeys.look: _look.name,
      StudioSettingKeys.lengthUnit: _lengthUnit.name,
      StudioSettingKeys.wordRulers: _wordRulers,
      StudioSettingKeys.sheetGridlines: _sheetGridlines,
      StudioSettingKeys.sheetHeaders: _sheetHeaders,
      StudioSettingKeys.slideHandles: _slideHandles,
      StudioSettingKeys.showNotes: _showNotes,
      StudioSettingKeys.showComments: _showComments,
      StudioSettingKeys.showOutline: _showOutline,
      StudioSettingKeys.showAnimationPane: _showAnimPane,
      StudioSettingKeys.showSheetNavigation: _showSheetNav,
      StudioSettingKeys.showPasteOptions: _showPasteOptions,
      StudioSettingKeys.pdfNightMode: _pdfNightMode,
      StudioSettingKeys.pdfSwipeHorizontal: _pdfSwipeHorizontal,
      StudioSettingKeys.pdfPageSnap: _pdfPageSnap,
      StudioSettingKeys.pdfPageFling: _pdfPageFling,
      StudioSettingKeys.pdfEnableSwipe: _pdfEnableSwipe,
      StudioSettingKeys.pdfShowScroll: _pdfShowScroll,
      StudioSettingKeys.pdfPreventLinks: _pdfPreventLinks,
      StudioSettingKeys.pdfFitPolicy: _pdfFitPolicy.name,
      StudioSettingKeys.checkAsYouType: _word.proofing.enabled,
      StudioSettingKeys.detectLanguage:
          _word.proofing.automaticLanguageDetection,
      StudioSettingKeys.arabicContext:
          studioArabicMorphHost.grammarReading ==
          ArabicGrammarReading.contextual,
      StudioSettingKeys.personalWords: _personalWords(),
    });
  }

  /// Loads the stored settings and applies them. Never throws: anything
  /// unusable leaves the defaults in place.
  Future<void> _restoreSettings() async {
    final binding = _settings;
    final StudioSettings stored;
    try {
      stored = await binding.store.load();
    } on Object {
      binding.restored = true;
      return;
    }
    if (!mounted) return;
    final previousLanguage = _language;
    _language = stored.choiceOf(
      StudioSettingKeys.language,
      StudioLanguage.values,
      _language,
    );
    _look = stored.choiceOf(StudioSettingKeys.look, SuiteLook.values, _look);
    _lengthUnit = stored.choiceOf(
      StudioSettingKeys.lengthUnit,
      OfficeLengthUnit.values,
      _lengthUnit,
    );
    _wordRulers = stored.flag(StudioSettingKeys.wordRulers);
    _sheetGridlines = stored.flag(StudioSettingKeys.sheetGridlines);
    _sheetHeaders = stored.flag(StudioSettingKeys.sheetHeaders);
    _slideHandles = stored.flag(StudioSettingKeys.slideHandles);
    _showNotes = stored.flag(StudioSettingKeys.showNotes);
    _showComments = stored.flag(StudioSettingKeys.showComments);
    _showOutline = stored.flag(StudioSettingKeys.showOutline);
    _showAnimPane = stored.flag(StudioSettingKeys.showAnimationPane);
    _showSheetNav = stored.flag(StudioSettingKeys.showSheetNavigation);
    _showPasteOptions = stored.flag(StudioSettingKeys.showPasteOptions);
    _pdfNightMode = stored.flag(StudioSettingKeys.pdfNightMode);
    _pdfSwipeHorizontal = stored.flag(StudioSettingKeys.pdfSwipeHorizontal);
    _pdfPageSnap = stored.flag(StudioSettingKeys.pdfPageSnap);
    _pdfPageFling = stored.flag(StudioSettingKeys.pdfPageFling);
    _pdfEnableSwipe = stored.flag(StudioSettingKeys.pdfEnableSwipe);
    _pdfShowScroll = stored.flag(StudioSettingKeys.pdfShowScroll);
    _pdfPreventLinks = stored.flag(StudioSettingKeys.pdfPreventLinks);
    _pdfFitPolicy = stored.choiceOf(
      StudioSettingKeys.pdfFitPolicy,
      PdfFitPolicy.values,
      _pdfFitPolicy,
    );
    final proofing = _word.proofing;
    proofing.enabled = stored.flag(StudioSettingKeys.checkAsYouType);
    proofing.automaticLanguageDetection = stored.flag(
      StudioSettingKeys.detectLanguage,
    );
    studioArabicMorphHost.grammarReading =
        stored.flag(StudioSettingKeys.arabicContext)
        ? ArabicGrammarReading.contextual
        : ArabicGrammarReading.allAnalyses;
    for (final entry in stored.personalWords.entries) {
      for (final word in entry.value) {
        try {
          proofing.vocabulary.addWord(word, language: entry.key);
        } on ArgumentError {
          // A word or language the engine does not accept is skipped.
        }
      }
    }
    binding.saved = stored;
    binding.saved = _currentSettings();
    binding.restored = true;
    if (_language != previousLanguage) unawaited(_syncSpacyGrammar());
    _rebuild();
  }

  /// Saves the settings when they changed since the last save. Called on
  /// every workspace build; cheap when nothing changed.
  void _persistSettingsIfChanged() {
    final binding = _settings;
    if (!binding.restored || binding.store.readOnly) return;
    final current = _currentSettings();
    if (current == binding.saved) return;
    binding.saved = current;
    unawaited(binding.store.save(current));
  }
}
