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
      ...StudioSettings.proofingScheduleJson(_word.proofing.schedule),
      StudioSettingKeys.detectLanguage:
          _word.proofing.automaticLanguageDetection,
      StudioSettingKeys.arabicContext:
          studioArabicMorphHost.grammarReading ==
          ArabicGrammarReading.contextual,
      StudioSettingKeys.personalWords: _personalWords(),
      StudioSettingKeys.shortcuts: _shortcutOverrides,
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
    _shortcutOverrides = stored.shortcuts;
    _pdfFitPolicy = stored.choiceOf(
      StudioSettingKeys.pdfFitPolicy,
      PdfFitPolicy.values,
      _pdfFitPolicy,
    );
    final proofing = _word.proofing;
    proofing.schedule = stored.proofingSchedule;
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

/// The as-you-type proofing schedule in the Settings dialog. Every change is
/// applied to the session at once and persisted by the next workspace build.
extension _ProofingScheduleSettings on _SuiteWorkspaceState {
  /// The ribbon's Check as you type switch. Turning it on from "Only when I
  /// click Check document" chooses the recommended mode.
  void _toggleCheckAsYouType() {
    final proofing = _word.proofing;
    if (proofing.enabled && proofing.schedule.mode != WordProofingMode.manual) {
      proofing.enabled = false;
      return;
    }
    if (proofing.schedule.mode == WordProofingMode.manual) {
      proofing.schedule = proofing.schedule.copyWith(
        mode: WordProofingMode.whileTyping,
      );
    }
    proofing.enabled = true;
  }

  String _pauseLabel(Duration pause) {
    final seconds = pause.inMilliseconds / 1000;
    final text = seconds.toStringAsFixed(1);
    return _t('$text s', '${text.replaceAll('.', ',')} s', '$text ث');
  }

  List<Widget> _proofingScheduleSettings(void Function(VoidCallback) changed) {
    final proofing = _word.proofing;
    final schedule = proofing.schedule;
    final mode = proofing.enabled ? schedule.mode : WordProofingMode.manual;
    final automatic = mode != WordProofingMode.manual;
    void update(WordProofingSchedule next) =>
        changed(() => proofing.schedule = next);
    return <Widget>[
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          _t('Proofing', StudioStrings.de('Proofing'), 'التدقيق'),
          style: Theme.of(_themedContext).textTheme.titleSmall,
        ),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<WordProofingMode>(
        key: const ValueKey<String>('studio-setting-proofing-mode'),
        isExpanded: true,
        initialValue: mode,
        decoration: InputDecoration(
          labelText: _t('Checking mode', 'Prüfmodus', 'وضع التدقيق'),
        ),
        items: <DropdownMenuItem<WordProofingMode>>[
          DropdownMenuItem(
            value: WordProofingMode.whileTyping,
            child: Text(
              _t(
                'While typing (recommended)',
                'Während der Eingabe (empfohlen)',
                'أثناء الكتابة (مستحسن)',
              ),
            ),
          ),
          DropdownMenuItem(
            value: WordProofingMode.onPause,
            child: Text(
              _t(
                'When I pause',
                'Wenn ich eine Pause mache',
                'عندما أتوقف عن الكتابة',
              ),
            ),
          ),
          DropdownMenuItem(
            value: WordProofingMode.manual,
            child: Text(
              _t(
                'Only when I click Check document',
                'Nur wenn ich auf „Dokument prüfen“ klicke',
                'فقط عند النقر على «تدقيق المستند»',
              ),
            ),
          ),
        ],
        onChanged: (value) {
          if (value == null) return;
          changed(() {
            proofing.schedule = proofing.schedule.copyWith(mode: value);
            if (value != WordProofingMode.manual) proofing.enabled = true;
          });
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(switch (mode) {
          WordProofingMode.whileTyping => _t(
            'Spelling is checked when you finish a word, grammar when you '
                'finish a sentence or pause.',
            'Die Rechtschreibung wird nach jedem fertigen Wort geprüft, die '
                'Grammatik nach jedem fertigen Satz oder in einer Pause.',
            'يُدقَّق الإملاء عند إكمال الكلمة، والقواعد عند إكمال الجملة أو '
                'التوقف عن الكتابة.',
          ),
          WordProofingMode.onPause => _t(
            'Spelling and grammar are checked when you stop typing.',
            'Rechtschreibung und Grammatik werden geprüft, sobald Sie aufhören '
                'zu tippen.',
            'يُدقَّق الإملاء والقواعد عندما تتوقف عن الكتابة.',
          ),
          WordProofingMode.manual => _t(
            'Nothing is checked automatically.',
            'Es wird nichts automatisch geprüft.',
            'لا يُدقَّق شيء تلقائياً.',
          ),
        }, style: Theme.of(_themedContext).textTheme.bodySmall),
      ),
      SwitchListTile(
        key: const ValueKey<String>('studio-setting-check-spelling'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          _t(
            'Check spelling while typing',
            'Rechtschreibung während der Eingabe prüfen',
            'تدقيق الإملاء أثناء الكتابة',
          ),
        ),
        value: schedule.checkSpelling,
        onChanged: automatic
            ? (value) => update(schedule.copyWith(checkSpelling: value))
            : null,
      ),
      SwitchListTile(
        key: const ValueKey<String>('studio-setting-check-grammar'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          _t(
            'Check grammar while typing',
            'Grammatik während der Eingabe prüfen',
            'تدقيق القواعد أثناء الكتابة',
          ),
        ),
        value: schedule.checkGrammar,
        onChanged: automatic
            ? (value) => update(schedule.copyWith(checkGrammar: value))
            : null,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          _t(
            'Pause before checking',
            'Pause vor dem Prüfen',
            'مهلة قبل التدقيق',
          ),
        ),
        trailing: Text(_pauseLabel(schedule.pause)),
      ),
      Slider(
        key: const ValueKey<String>('studio-setting-proofing-pause'),
        min: WordProofingSchedule.minPause.inMilliseconds.toDouble(),
        max: WordProofingSchedule.maxPause.inMilliseconds.toDouble(),
        divisions:
            (WordProofingSchedule.maxPause - WordProofingSchedule.minPause)
                .inMilliseconds ~/
            100,
        value: schedule.pause.inMilliseconds
            .clamp(
              WordProofingSchedule.minPause.inMilliseconds,
              WordProofingSchedule.maxPause.inMilliseconds,
            )
            .toDouble(),
        label: _pauseLabel(schedule.pause),
        onChanged: automatic
            ? (value) => update(
                schedule.copyWith(
                  pause: Duration(milliseconds: (value / 100).round() * 100),
                ),
              )
            : null,
      ),
      SwitchListTile(
        key: const ValueKey<String>('studio-setting-background-check'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          _t(
            'Check the whole document in the background',
            'Das ganze Dokument im Hintergrund prüfen',
            'تدقيق المستند كاملاً في الخلفية',
          ),
        ),
        subtitle: Text(
          _t(
            'Only while you are not typing, visible pages first.',
            'Nur während Sie nicht tippen, sichtbare Seiten zuerst.',
            'فقط عندما لا تكتب، والصفحات الظاهرة أولاً.',
          ),
        ),
        value: schedule.backgroundCheck,
        onChanged: automatic
            ? (value) => update(schedule.copyWith(backgroundCheck: value))
            : null,
      ),
      SwitchListTile(
        key: const ValueKey<String>('studio-setting-hide-typing-errors'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          _t(
            "Hide errors in the word I'm typing",
            'Fehler im Wort, das ich gerade tippe, ausblenden',
            'إخفاء الأخطاء في الكلمة التي أكتبها',
          ),
        ),
        value: schedule.hideTypingErrors,
        onChanged: (value) =>
            update(schedule.copyWith(hideTypingErrors: value)),
      ),
    ];
  }
}
