import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_proofing_aot/quds_proofing_aot.dart';

/// Explicit Studio settings. Opening analysis is always available and lazy;
/// document-wide checks are enabled only by an application setting.
final class StudioAotConfiguration {
  StudioAotConfiguration._({
    required this.executable,
    required this.rmlDirectory,
    required this.endpoint,
    required this.useGet,
    required this.manualEnabled,
  });

  factory StudioAotConfiguration.fromEnvironment() =>
      StudioAotConfiguration.fromSettings(
        executable: const String.fromEnvironment('QUDS_AOT_EXECUTABLE'),
        rmlDirectory: const String.fromEnvironment('QUDS_AOT_RML'),
        endpoint: const String.fromEnvironment('QUDS_AOT_ENDPOINT'),
        useGet: const bool.fromEnvironment('QUDS_AOT_USE_GET'),
        enableManual: const bool.fromEnvironment('QUDS_AOT_ENABLE'),
      );

  factory StudioAotConfiguration.fromSettings({
    String executable = '',
    String rmlDirectory = '',
    String endpoint = '',
    bool useGet = false,
    bool enableManual = false,
  }) {
    final localExecutable = executable.trim();
    final localResources = rmlDirectory.trim();
    final service = endpoint.trim();
    if (service.isNotEmpty &&
        (localExecutable.isNotEmpty || localResources.isNotEmpty)) {
      throw StateError(
        'Choose either local AOT settings (QUDS_AOT_EXECUTABLE / QUDS_AOT_RML) '
        'or QUDS_AOT_ENDPOINT, then restart Studio.',
      );
    }
    if (localExecutable.contains('\u0000') ||
        localResources.contains('\u0000')) {
      throw StateError('The local AOT executable or resource path is invalid.');
    }
    Uri? uri;
    if (service.isNotEmpty) {
      uri = Uri.tryParse(service);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw StateError(
          'QUDS_AOT_ENDPOINT must be an HTTP(S) address without credentials, '
          'a query or a fragment.',
        );
      }
      final host = uri.host.toLowerCase();
      final parts = host.split('.');
      final loopback =
          host == 'localhost' ||
          host == '::1' ||
          host == '[::1]' ||
          (parts.length == 4 &&
              parts.first == '127' &&
              parts.every((part) {
                final value = int.tryParse(part);
                return value != null &&
                    value >= 0 &&
                    value <= 255 &&
                    '$value' == part;
              }));
      if (!loopback) {
        throw StateError(
          'Studio accepts a local loopback AOT service address. '
          'Use the local worker to keep analysis on this device.',
        );
      }
    }
    return StudioAotConfiguration._(
      executable: localExecutable.isEmpty ? 'quds_aot_worker' : localExecutable,
      rmlDirectory: localResources.isEmpty ? null : localResources,
      endpoint: uri,
      useGet: useGet,
      manualEnabled:
          enableManual ||
          service.isNotEmpty ||
          localExecutable.isNotEmpty ||
          localResources.isNotEmpty,
    );
  }

  final String executable;
  final String? rmlDirectory;
  final Uri? endpoint;
  final bool useGet;
  final bool manualEnabled;

  bool get isLocal => endpoint == null;

  AotAnalyzer createAnalyzer() {
    if (endpoint case final Uri service) {
      return AotClient(
        transport: AotHttpTransport(
          endpoint: service,
          requestMethod: useGet ? AotRequestMethod.get : AotRequestMethod.post,
          timeout: const Duration(seconds: 60),
        ),
      );
    }
    return AotClient.local(
      executable: executable,
      rmlDirectory: rmlDirectory,
      timeout: const Duration(seconds: 60),
    );
  }
}

/// Exact text selected for a read-only analysis. It never uses the clipboard or
/// rewrites the document, and rejects oversized input instead of truncating it.
final class StudioAotTextSnapshot {
  StudioAotTextSnapshot._({
    required this.text,
    required this.scope,
    required this.document,
    required this.revision,
  });

  static const int maximumCodeUnits = 32768;

  factory StudioAotTextSnapshot.capture(WordEditorController controller) {
    final document = controller.document;
    final caret = controller.caret;
    final selection = !caret.isCollapsed;
    final Iterable<WmlParagraph> paragraphs;
    final String scope;
    if (selection && controller.isEditingComment) {
      paragraphs = controller.selectedComment!.paragraphs;
      scope = 'Selected comment text';
    } else if (selection && controller.isEditingHeaderFooter) {
      final section = document.sections[controller.editingSectionIndex];
      paragraphs = controller.isEditingFooter ? section.footer : section.header;
      scope = controller.isEditingFooter
          ? 'Selected footer text'
          : 'Selected header text';
    } else {
      paragraphs = document.paragraphs;
      scope = selection ? 'Selected body text' : 'Document body text';
    }
    final range = caret.normalizedRange;
    final buffer = StringBuffer();
    var count = 0;
    var index = 0;
    for (final paragraph in paragraphs) {
      final at = index++;
      if (selection && at < range.startPara) continue;
      if (selection && at > range.endPara) break;
      final text = paragraph.text;
      final start = selection && at == range.startPara ? range.startIdx : 0;
      final end = selection && at == range.endPara ? range.endIdx : text.length;
      if (start < 0 || end < start || end > text.length) {
        throw StateError('The selection changed. Select the text again.');
      }
      if (_splitsSurrogate(text, start) || _splitsSurrogate(text, end)) {
        throw StateError('Select complete Unicode characters for analysis.');
      }
      final length = end - start + (count == 0 ? 0 : 1);
      if (buffer.length + length > maximumCodeUnits) {
        throw StateError(
          'This text exceeds the analysis limit of $maximumCodeUnits '
          'UTF-16 characters. Select a shorter passage in the document.',
        );
      }
      if (count++ > 0) buffer.write('\n');
      buffer.write(text.substring(start, end));
    }
    if (selection && (range.startPara < 0 || range.endPara >= index)) {
      throw StateError('The selection changed. Select the text again.');
    }
    return StudioAotTextSnapshot._(
      text: buffer.toString(),
      scope: scope,
      document: document,
      revision: controller.contentRevision,
    );
  }

  final String text;
  final String scope;
  final WmlDocument document;
  final int revision;

  static bool _splitsSurrogate(String text, int offset) =>
      offset > 0 &&
      offset < text.length &&
      text.codeUnitAt(offset - 1) >= 0xd800 &&
      text.codeUnitAt(offset - 1) <= 0xdbff &&
      text.codeUnitAt(offset) >= 0xdc00 &&
      text.codeUnitAt(offset) <= 0xdfff;

  bool isCurrent(WordEditorController controller) =>
      identical(document, controller.document) &&
      revision == controller.contentRevision;
}

enum _StudioAotMode { syntax, morphology }

/// One private analyzer is reused for this dialog's explicit requests. Cancel,
/// stale text, a language change, failure and Close reset its local resources
/// without interrupting the separately owned manual checker.
class StudioAotAnalysisDialog extends StatefulWidget {
  const StudioAotAnalysisDialog({
    required this.controller,
    required this.createAnalyzer,
    this.initialLanguage = AotLanguage.german,
    this.isLocal = true,
    super.key,
  });

  final WordEditorController controller;
  final AotAnalyzer Function() createAnalyzer;
  final AotLanguage initialLanguage;
  final bool isLocal;

  @override
  State<StudioAotAnalysisDialog> createState() =>
      _StudioAotAnalysisDialogState();
}

class _StudioAotAnalysisDialogState extends State<StudioAotAnalysisDialog> {
  StudioAotTextSnapshot? _source;
  String? _sourceError;
  String? _error;
  AotAnalysis? _analysis;
  AotMorphology? _morphology;
  AotAnalyzer? _analyzer;
  late AotLanguage _language;
  late _StudioAotMode _mode;
  final Map<int, int> _variantIndexes = {};
  int? _selectedClause;
  int? _selectedWord;
  var _generation = 0;
  var _busy = false;
  var _stale = false;

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage;
    _mode = _language.supportsSyntax
        ? _StudioAotMode.syntax
        : _StudioAotMode.morphology;
    _capture();
    widget.controller.addListener(_documentChanged);
  }

  void _capture() {
    _sourceError = null;
    _source = null;
    try {
      _source = StudioAotTextSnapshot.capture(widget.controller);
    } on Object catch (error) {
      _sourceError = _message(error);
    }
    _stale = false;
    _analysis = null;
    _morphology = null;
    _selectedClause = null;
    _selectedWord = null;
    _variantIndexes.clear();
    _error = null;
  }

  void _documentChanged() {
    if (!mounted || _stale || (_source?.isCurrent(widget.controller) ?? true)) {
      return;
    }
    _stop();
    setState(() => _stale = true);
  }

  void _stop() {
    _generation++;
    final analyzer = _analyzer;
    _analyzer = null;
    _busy = false;
    if (analyzer != null) unawaited(_disposeAnalyzer(analyzer));
  }

  static Future<void> _disposeAnalyzer(AotAnalyzer analyzer) async {
    try {
      await analyzer.dispose();
    } on Object {
      // The canceled operation cannot publish, even if a custom host transport
      // fails while closing. The production transport has a bounded deadline.
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_documentChanged);
    _stop();
    super.dispose();
  }

  static String _message(Object error) => error is StateError
      ? error.message.toString()
      : 'This selection could not be captured. Select the text again.';

  String _operationMessage(Object error) {
    if (error is AotException) {
      return switch (error.code) {
        AotErrorCode.unavailable =>
          widget.isLocal
              ? 'Local AOT is not ready. Install the AOT worker and language '
                    'dictionaries, then try again. Setup: '
                    'packages/quds_proofing_aot/README.md.'
              : 'The configured AOT service is unavailable. Check its address '
                    'and connection, then try again.',
        AotErrorCode.timeout =>
          'AOT took too long to respond. Try a shorter '
              'passage or check the installation, then analyze again.',
        AotErrorCode.unsupportedLanguage =>
          'Syntax analysis supports German '
              'and Russian. Use Word forms for English morphology.',
        AotErrorCode.limit =>
          'The analysis exceeds a processing limit. '
              'Select a shorter passage or a single word and try again.',
        AotErrorCode.disposed =>
          'The analysis session was closed. '
              'Choose Analyze to start a new session.',
        AotErrorCode.http =>
          'The configured AOT service could not complete '
              'the request. Check the service and try again.',
        AotErrorCode.malformedResponse =>
          'AOT returned an unreadable result. '
              'Check that the installed AOT worker or service is compatible.',
      };
    }
    return 'AOT could not complete this analysis. Check the installation '
        'and try again.';
  }

  String? get _morphologyWord {
    final word = _source?.text.trim();
    if (word == null ||
        word.length > 256 ||
        !RegExp(
          r"^\p{L}[\p{L}\p{M}]*(?:[-’'][\p{L}\p{M}]+)*$",
          unicode: true,
        ).hasMatch(word)) {
      return null;
    }
    return word;
  }

  bool _current(int generation) =>
      mounted &&
      generation == _generation &&
      (_source?.isCurrent(widget.controller) ?? false);

  Future<void> _run(
    Future<void> Function(AotAnalyzer analyzer, int generation) operation,
  ) async {
    if (_busy || _stale || _source == null) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _morphology = null;
    });
    try {
      final analyzer = _analyzer ??= widget.createAnalyzer();
      await operation(analyzer, generation);
    } on Object catch (error) {
      if (_current(generation)) {
        setState(() {
          _stop();
          _error = _operationMessage(error);
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        final stale = !(_source?.isCurrent(widget.controller) ?? false);
        if (stale) _stop();
        setState(() {
          _busy = false;
          _stale = stale;
        });
      }
    }
  }

  Future<void> _analyze() async {
    final source = _source;
    if (_busy || _stale || source == null || source.text.trim().isEmpty) return;
    if (_mode == _StudioAotMode.morphology) {
      final word = _morphologyWord;
      if (word != null) await _lookupWordMorphology(word);
      return;
    }
    setState(() {
      _analysis = null;
      _selectedClause = null;
      _selectedWord = null;
      _variantIndexes.clear();
    });
    await _run((analyzer, generation) async {
      final result = await analyzer.analyze(source.text, language: _language);
      if (_current(generation)) setState(() => _analysis = result);
    });
  }

  List<({int sentence, int clauseIndex, AotClause clause})> get _clauses => [
    if (_analysis case final AotAnalysis analysis)
      for (var sentence = 0; sentence < analysis.sentences.length; sentence++)
        for (
          var clause = 0;
          clause < analysis.sentences[sentence].clauses.length;
          clause++
        )
          (
            sentence: sentence,
            clauseIndex: clause,
            clause: analysis.sentences[sentence].clauses[clause],
          ),
  ];

  AotToken? get _selectedToken {
    final clauses = _clauses;
    final clause = _selectedClause;
    final word = _selectedWord;
    if (clause == null || word == null || clause >= clauses.length) return null;
    final words = clauses[clause].clause.words;
    return word < words.length ? words[word] : null;
  }

  Future<void> _lookupMorphology() async {
    final token = _selectedToken;
    if (token != null && !RegExp(r'\s').hasMatch(token.text)) {
      await _lookupWordMorphology(token.text);
    }
  }

  Future<void> _lookupWordMorphology(String word) =>
      _run((analyzer, generation) async {
        final result = await analyzer.morphology(
          word,
          language: _language,
          withParadigms: true,
        );
        if (_current(generation)) setState(() => _morphology = result);
      });

  void _changeLanguage(AotLanguage language) {
    if (_language == language) return;
    setState(() {
      _stop();
      _language = language;
      if (!language.supportsSyntax) _mode = _StudioAotMode.morphology;
      _analysis = null;
      _morphology = null;
      _error = null;
      _selectedClause = null;
      _selectedWord = null;
      _variantIndexes.clear();
    });
  }

  void _changeMode(_StudioAotMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _analysis = null;
      _morphology = null;
      _error = null;
      _selectedClause = null;
      _selectedWord = null;
      _variantIndexes.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final clauses = _clauses;
    return AlertDialog(
      title: const Text('AOT linguistic analysis'),
      content: SizedBox(
        width: 920,
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isLocal
                  ? 'Local AOT · stays on this device'
                  : 'Configured AOT service',
              key: const ValueKey('aot-backend'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<AotLanguage>(
                  key: const ValueKey('aot-language'),
                  value: _language,
                  items: const [
                    DropdownMenuItem(
                      value: AotLanguage.german,
                      child: Text('German'),
                    ),
                    DropdownMenuItem(
                      value: AotLanguage.russian,
                      child: Text('Russian'),
                    ),
                    DropdownMenuItem(
                      value: AotLanguage.english,
                      child: Text('English'),
                    ),
                  ],
                  onChanged: (language) {
                    if (language != null) _changeLanguage(language);
                  },
                ),
                DropdownButton<_StudioAotMode>(
                  key: const ValueKey('aot-mode'),
                  value: _mode,
                  items: [
                    if (_language.supportsSyntax)
                      const DropdownMenuItem(
                        value: _StudioAotMode.syntax,
                        child: Text('Syntax'),
                      ),
                    const DropdownMenuItem(
                      value: _StudioAotMode.morphology,
                      child: Text('Word forms'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (mode) {
                          if (mode != null) _changeMode(mode);
                        },
                ),
                if (source != null)
                  Text(
                    '${source.scope} · ${source.text.runes.length} characters',
                  ),
              ],
            ),
            Text(
              _mode == _StudioAotMode.syntax
                  ? 'Inspect tokens, alternative readings and syntactic '
                        'relations. Analysis does not change the document.'
                  : 'Inspect the selected word’s dictionary readings and '
                        'inflected forms. Analysis does not change the document.',
            ),
            Text(
              'Document proofing language: ${widget.controller.proofing.language}. '
              'AOT grammar checking supports de-DE; de-AT and de-CH are '
              'currently unsupported. The language above controls analysis only.',
            ),
            const SizedBox(height: 8),
            if (_mode == _StudioAotMode.morphology && _morphologyWord == null)
              const Text(
                'Select one complete word in the document, then reload the text.',
                key: ValueKey('aot-word-selection'),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_stale)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'The document changed. Reload the text before analyzing again.',
                  key: ValueKey('aot-stale'),
                ),
              ),
            if (_sourceError ?? _error case final String error)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SelectableText(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: ListView(
                key: const ValueKey('aot-content'),
                children: [
                  if (source != null)
                    ExpansionTile(
                      title: const Text('Source text'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(source.text),
                          ),
                        ),
                      ],
                    ),
                  if (_analysis case final AotAnalysis analysis) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '${analysis.sentences.length} sentences · '
                        '${analysis.tokens.length} tokens. '
                        '${analysis.fullyAligned ? 'All token positions match the source.' : 'Some token positions could not be aligned to the source.'}',
                      ),
                    ),
                    if (clauses.isEmpty)
                      const Text(
                        'AOT returned no syntactic analysis. This does not '
                        'establish whether the text is grammatically correct.',
                      ),
                    for (var index = 0; index < clauses.length; index++)
                      _clauseCard(clauses[index], index),
                  ],
                  if (_morphology case final AotMorphology morphology
                      when _mode == _StudioAotMode.morphology) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('Word forms: ${morphology.word}'),
                    ),
                    if (morphology.readings.isEmpty)
                      const Text('No morphological readings were returned.'),
                    for (final reading in morphology.readings)
                      _readingDetails(reading),
                  ],
                  if (_analysis == null &&
                      _morphology == null &&
                      !_busy &&
                      _error == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Choose Analyze to inspect this text.'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  widget.controller.commitPendingEdits();
                  setState(_capture);
                },
          child: const Text('Reload text'),
        ),
        if (_busy)
          TextButton(
            onPressed: () => setState(_stop),
            child: const Text('Cancel analysis'),
          )
        else
          FilledButton(
            onPressed:
                _stale ||
                    source == null ||
                    source.text.trim().isEmpty ||
                    (_mode == _StudioAotMode.morphology &&
                        _morphologyWord == null)
                ? null
                : _analyze,
            child: const Text('Analyze'),
          ),
        TextButton(
          onPressed: () {
            _stop();
            Navigator.of(context).pop();
          },
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _clauseCard(
    ({int sentence, int clauseIndex, AotClause clause}) entry,
    int index,
  ) {
    final clause = entry.clause;
    final variantIndex = _variantIndexes[index] ?? 0;
    final variant = clause.variants.isEmpty
        ? null
        : clause.variants[variantIndex];
    return ExpansionTile(
      initiallyExpanded: index == 0,
      title: Text(
        'Sentence ${entry.sentence + 1} · clause ${entry.clauseIndex + 1}',
      ),
      subtitle: Text(
        clause.words.map((word) => word.text).join(' '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (var word = 0; word < clause.words.length; word++)
                ChoiceChip(
                  label: Text(clause.words[word].text),
                  selected: _selectedClause == index && _selectedWord == word,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() {
                          _selectedClause = index;
                          _selectedWord = word;
                          _morphology = null;
                          _error = null;
                        }),
                ),
            ],
          ),
        ),
        if (_selectedClause == index && _selectedToken != null) _tokenDetails(),
        if (variant == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No syntactic variant was returned for this clause.'),
          )
        else ...[
          DropdownButton<int>(
            value: variantIndex,
            isExpanded: true,
            items: [
              for (var n = 0; n < clause.variants.length; n++)
                DropdownMenuItem(
                  value: n,
                  child: Text('Variant ${n + 1} of ${clause.variants.length}'),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _variantIndexes[index] = value);
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Token')),
                  DataColumn(label: Text('Lemma')),
                  DataColumn(label: Text('Grammatical alternatives')),
                ],
                rows: [
                  for (var word = 0; word < clause.words.length; word++)
                    DataRow(
                      cells: [
                        DataCell(Text(clause.words[word].text)),
                        DataCell(
                          Text(
                            clause.words[word].homonyms[variant
                                .units[word]
                                .homonymIndex],
                          ),
                        ),
                        DataCell(
                          SelectableText(variant.units[word].grammar.raw),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          for (final group in variant.groups)
            ListTile(
              dense: true,
              title: Text(
                '${group.isSubject
                    ? 'Subject → predicate'
                    : group.isGroup
                    ? 'Group'
                    : 'Clause'}: '
                '${group.description}',
              ),
              subtitle: SelectableText(
                group.isSubject
                    ? '${clause.words[group.start].text} → '
                          '${clause.words[group.last].text}'
                    : clause.words
                          .sublist(group.start, group.last + 1)
                          .map((word) => word.text)
                          .join(' '),
              ),
            ),
          if (variant.groups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'No groups or relations were returned in this variant.',
              ),
            ),
        ],
      ],
    );
  }

  Widget _tokenDetails() {
    final token = _selectedToken!;
    final clause = _clauses[_selectedClause!].clause;
    final grammars = {
      for (final variant in clause.variants)
        variant.units[_selectedWord!].grammar.raw,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Token: ${token.text}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (token.isNormalized)
              SelectableText('Analyzed form: ${token.analysisText}'),
            SelectableText('Lemma alternatives: ${token.homonyms.join(' · ')}'),
            Text(
              token.isAligned
                  ? 'Source range: ${token.start}–${token.end} (UTF-16, end exclusive)'
                  : 'Source range: unavailable',
            ),
            const SizedBox(height: 8),
            for (final grammar in grammars) SelectableText(grammar),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed:
                  _busy ||
                      _stale ||
                      RegExp(r'\s').hasMatch(token.text) ||
                      !RegExp(r'\p{L}', unicode: true).hasMatch(token.text)
                  ? null
                  : _lookupMorphology,
              child: const Text('Look up morphology and forms'),
            ),
            if (RegExp(r'\s').hasMatch(token.text))
              const Text(
                'This analyzed token spans more than one source word. '
                'Select a single word in the document and use Word forms.',
              ),
            if (_morphology case final AotMorphology morphology) ...[
              if (morphology.readings.isEmpty)
                const Text('No morphological readings were returned.'),
              for (final reading in morphology.readings)
                _readingDetails(reading),
            ],
          ],
        ),
      ),
    );
  }

  Widget _readingDetails(AotMorphReading reading) {
    final forms = reading.forms.toList(growable: false);
    return ExpansionTile(
      title: Text(reading.lemma),
      subtitle: Text(
        '${reading.found ? 'Dictionary reading' : 'Predicted reading'} · '
        '${reading.grammar.raw}',
      ),
      children: [
        if (forms.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No inflected forms were returned.'),
          )
        else
          SizedBox(
            height: 220,
            child: ListView.builder(
              itemCount: forms.length,
              itemBuilder: (context, index) => ListTile(
                dense: true,
                title: SelectableText(forms[index].text),
                subtitle: SelectableText(forms[index].grammar.raw),
              ),
            ),
          ),
      ],
    );
  }
}
