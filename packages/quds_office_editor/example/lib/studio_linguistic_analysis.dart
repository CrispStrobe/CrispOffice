import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

import 'studio_spacy_config.dart';
import 'studio_spacy_setup.dart';

/// One body paragraph, including a paragraph inside a body table. Other stories
/// and multi-paragraph selections are not silently remapped or concatenated.
final class StudioAnalysisSnapshot {
  StudioAnalysisSnapshot._({
    required this.request,
    required this.document,
    required this.paragraph,
    required this.paragraphIndex,
    required this.paragraphText,
    required this.languageSignature,
    required this.selectedText,
  });

  static final _documentIds = Expando<String>('analysis document');
  static final _paragraphIds = Expando<String>('analysis body paragraph');
  static var _nextId = 0;

  final LinguisticAnalysisRequest request;
  final WmlDocument document;
  final WmlParagraph paragraph;
  final int paragraphIndex;
  final String paragraphText;
  final String languageSignature;
  final bool selectedText;

  /// The analysis language of [request] (German de-DE, English or French).
  SpacyLanguage get language => SpacyLanguage.forLocale(request.locale)!;

  /// Captures the current body paragraph or selection. The language comes
  /// from the text's proofing language unless [analyzeAs] explicitly names
  /// one; an explicit choice keeps a marked regional variant of the same
  /// language (for example en-GB) and otherwise uses its default locale.
  static StudioAnalysisSnapshot capture(
    WordEditorController controller, {
    required int generation,
    required String configurationId,
    SpacyLanguage? analyzeAs,
  }) {
    if (controller.isDisposed || !_bodyTextActive(controller)) {
      throw const FormatException(
        'Choose text in the document body or a body table. Headers, footers, '
        'comments and selected objects are outside this analysis view.',
      );
    }
    controller.commitPendingEdits();
    final document = controller.document;
    final paragraphs = document.paragraphs.toList();
    final caret = controller.documentCaret;
    if (paragraphs.isEmpty ||
        caret.paragraphIndex < 0 ||
        caret.paragraphIndex >= paragraphs.length) {
      throw const FormatException('Place the cursor in a body paragraph.');
    }
    final paragraph = paragraphs[caret.paragraphIndex];
    if (!_ownsAnalysisParagraph(document, paragraph)) {
      throw const FormatException(
        'Choose a body or table paragraph. Text boxes and generated contents are outside this analysis view.',
      );
    }
    final text = paragraph.text;
    final range = caret.normalizedRange;
    final selected = !caret.isCollapsed;
    if (selected && range.startPara != range.endPara) {
      throw const FormatException(
        'Select text within one paragraph at a time.',
      );
    }
    final start = selected ? range.startIdx : 0;
    final end = selected ? range.endIdx : text.length;
    if (!_wellFormedUtf16(text) ||
        start < 0 ||
        end < start ||
        end > text.length ||
        !_graphemeBoundary(text, start) ||
        !_graphemeBoundary(text, end)) {
      throw const FormatException(
        'The selection does not have complete text boundaries. Select the text again.',
      );
    }
    final marked = _selectedLocale(document, paragraph, start, end);
    final locale =
        analyzeAs == null || SpacyLanguage.forLocale(marked) == analyzeAs
        ? marked
        : analyzeAs.defaultLocale;
    if (SpacyLanguage.forLocale(locale) == null) {
      throw const FormatException(
        'This analysis supports German (Germany), English and French. Choose '
        'text marked de-DE, en or fr, or pick a language under “Analyze as”.',
      );
    }
    return StudioAnalysisSnapshot._(
      request: LinguisticAnalysisRequest(
        text: text.substring(start, end),
        documentId: _documentIds[document] ??= 'analysis-document-${++_nextId}',
        blockId: _paragraphIds[paragraph] ??= 'analysis-body-${++_nextId}',
        revision: controller.contentRevision,
        locale: locale,
        startOffset: start,
        generation: generation,
        configurationId: configurationId,
      ),
      document: document,
      paragraph: paragraph,
      paragraphIndex: caret.paragraphIndex,
      paragraphText: text,
      languageSignature: _languageSignature(document, paragraph),
      selectedText: selected,
    );
  }

  bool isCurrent(WordEditorController controller, String configurationId) {
    if (controller.isDisposed ||
        !_bodyTextActive(controller) ||
        !identical(controller.document, document) ||
        controller.contentRevision != request.revision ||
        configurationId != request.configurationId ||
        paragraph.text != paragraphText ||
        !_ownsAnalysisParagraph(document, paragraph) ||
        _languageSignature(document, paragraph) != languageSignature) {
      return false;
    }
    final paragraphs = controller.document.paragraphs.toList();
    return paragraphIndex < paragraphs.length &&
        identical(paragraphs[paragraphIndex], paragraph);
  }

  /// Selects an exact current source range through the existing navigation API.
  /// Native offsets are relative to the selected input; the origin is added once.
  bool revealToken(
    WordEditorController controller,
    String configurationId,
    LinguisticToken token,
  ) {
    if (!controller.config.allowsSelection ||
        !isCurrent(controller, configurationId)) {
      return false;
    }
    controller.commitPendingEdits();
    if (!isCurrent(controller, configurationId)) return false;
    final start = request.startOffset + token.start;
    final end = request.startOffset + token.end;
    if (token.start < 0 ||
        token.end < token.start ||
        token.end > request.text.length ||
        end > paragraphText.length ||
        paragraphText.substring(start, end) != token.text ||
        !_graphemeBoundary(paragraphText, start) ||
        !_graphemeBoundary(paragraphText, end)) {
      return false;
    }
    controller.revealFindHit(
      OfficeFindHit(
        kind: OpcPackageKindHint.word,
        paragraphIndex: paragraphIndex,
        start: start,
        end: end,
        preview: token.text,
      ),
    );
    return true;
  }
}

bool _ownsAnalysisParagraph(WmlDocument document, WmlParagraph paragraph) =>
    document.sections.any(
      (section) => _bodyTableParagraphs(
        section.blocks,
      ).any((candidate) => identical(candidate, paragraph)),
    );

Iterable<WmlParagraph> _bodyTableParagraphs(Iterable<WmlBlock> blocks) sync* {
  for (final block in blocks) {
    if (block is WmlParagraph) {
      yield block;
    } else if (block is WmlContentControlBlock) {
      yield* _bodyTableParagraphs(block.blocks);
    } else if (block is WmlTable) {
      for (final row in block.rows) {
        for (final cell in row.cells) {
          yield* _bodyTableParagraphs(cell.blocks);
        }
      }
    }
  }
}

bool _bodyTextActive(WordEditorController controller) =>
    !controller.isEditingComment &&
    !controller.isEditingHeaderFooter &&
    controller.selectedFrame == null &&
    controller.selectedVisual == null &&
    controller.selectedEquation == null &&
    controller.selectedTable == null &&
    controller.selectedTableBand == null;

String _languageSignature(WmlDocument document, WmlParagraph paragraph) =>
    jsonEncode([
      document.proofingLanguage,
      paragraph.properties.proofingLanguage,
      for (final inline in paragraph.inlines)
        if (inline is WmlRun)
          [
            inline.text.length,
            inline.properties.proofingLanguage,
            inline.properties.noProof,
          ],
    ]);

String _selectedLocale(
  WmlDocument document,
  WmlParagraph paragraph,
  int start,
  int end,
) {
  final fallback = normalizeProofingLanguage(
    paragraph.properties.proofingLanguage ??
        document.proofingLanguage ??
        'de-DE',
  );
  final languages = <String>{};
  var offset = 0;
  for (final inline in paragraph.inlines) {
    if (inline is! WmlRun) continue;
    final next = offset + inline.text.length;
    if (offset < end && next > start) {
      languages.add(
        normalizeProofingLanguage(
          inline.properties.proofingLanguage ?? fallback,
        ),
      );
    }
    offset = next;
  }
  if (languages.length > 1) {
    throw const FormatException(
      'The selection contains several languages. Select a passage in one language.',
    );
  }
  return languages.isEmpty ? fallback : languages.single;
}

bool _graphemeBoundary(String text, int offset) =>
    offset == 0 ||
    offset == text.length ||
    GraphemeClusters.segment(text).any((cluster) => cluster.end == offset);

bool _wellFormedUtf16(String text) {
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if (code >= 0xd800 && code <= 0xdbff) {
      if (++i >= text.length) return false;
      final low = text.codeUnitAt(i);
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      return false;
    }
  }
  return true;
}

/// An explicit manual analysis view. It owns its worker and never registers a
/// grammar provider or changes document text. A factory can be injected by hosts
/// and tests; results must still match the complete captured request identity.
class StudioLinguisticAnalysisDialog extends StatefulWidget {
  const StudioLinguisticAnalysisDialog({
    super.key,
    required this.controller,
    this.transportFactory,
    this.configurationId,
  });

  final WordEditorController controller;

  /// Injected worker factory (hosts and tests); used for every language.
  final Future<SpacyTransport> Function()? transportFactory;
  final String? configurationId;

  @override
  State<StudioLinguisticAnalysisDialog> createState() =>
      _StudioLinguisticAnalysisDialogState();
}

class _StudioLinguisticAnalysisDialogState
    extends State<StudioLinguisticAnalysisDialog> {
  StudioAnalysisSnapshot? _snapshot;
  LinguisticAnalysisResult? _result;
  String? _message;
  bool _busy = false;
  int _generation = 0;
  int _transportEpoch = 0;
  SpacyTransport? _transport;
  Future<SpacyTransport>? _opening;
  SpacyLanguage? _transportLanguage;

  /// Explicit language choice; null follows the text's proofing language.
  SpacyLanguage? _analyzeAs;
  final Set<SpacyTransport> _disposedTransports = Set.identity();
  final ScrollController _tokenScroll = ScrollController();

  String get _configurationId =>
      widget.configurationId ?? studioSpacyConfigurationId();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onDocumentChanged);
  }

  @override
  void didUpdateWidget(StudioLinguisticAnalysisDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onDocumentChanged);
      widget.controller.addListener(_onDocumentChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.configurationId != widget.configurationId ||
        oldWidget.transportFactory != widget.transportFactory) {
      _cancel('The document or analysis configuration changed. Analyze again.');
      _releaseTransport();
    }
  }

  void _onDocumentChanged() {
    final snapshot = _snapshot;
    if (snapshot != null &&
        !snapshot.isCurrent(widget.controller, _configurationId)) {
      _cancel(
        'The text or language changed. Analyze again to see current results.',
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _disposeTransport(SpacyTransport transport) async {
    if (!_disposedTransports.add(transport)) return;
    try {
      // The transport acknowledges its in-flight slot before native teardown.
      await transport.dispose();
    } on Object {
      // A closed dialog cannot publish an error; the worker owns cleanup.
    }
  }

  void _releaseTransport() {
    _transportEpoch++;
    final transport = _transport;
    final opening = _opening;
    _transport = null;
    _opening = null;
    if (transport != null) unawaited(_disposeTransport(transport));
    if (opening != null) {
      unawaited(
        opening.then(_disposeTransport, onError: (Object _, StackTrace _) {}),
      );
    }
  }

  Future<SpacyTransport> _getTransport(SpacyLanguage language) async {
    // One owned worker per dialog; switching language replaces it.
    if (_transportLanguage != language) {
      _releaseTransport();
      _transportLanguage = language;
    }
    final current = _transport;
    if (current != null) return current;
    final epoch = _transportEpoch;
    final factory = widget.transportFactory;
    final future = _opening ??= Future.sync(
      factory ?? () => openStudioSpacyTransport(language: language),
    );
    final SpacyTransport transport;
    try {
      transport = await future;
    } on Object {
      // A cancelled caller may observe this failure too. Clear only this owned
      // startup attempt so a later explicit retry can create a fresh worker.
      if (epoch == _transportEpoch && identical(_opening, future)) {
        _opening = null;
      }
      rethrow;
    }
    if (!mounted || epoch != _transportEpoch) {
      await _disposeTransport(transport);
      throw const SpacyUnavailableException(
        'The analysis view was closed or replaced.',
      );
    }
    _transport = transport;
    return transport;
  }

  void _cancel(String message) {
    _generation++;
    final request = _snapshot?.request;
    if (request != null) _transport?.cancel(request.key);
    _snapshot = null;
    _result = null;
    _busy = false;
    _message = message;
  }

  Future<void> _analyze() async {
    _cancel('Preparing local analysis…');
    final generation = _generation;
    StudioAnalysisSnapshot snapshot;
    try {
      snapshot = StudioAnalysisSnapshot.capture(
        widget.controller,
        generation: generation,
        configurationId: _configurationId,
        analyzeAs: _analyzeAs,
      );
    } on FormatException catch (error) {
      setState(() => _message = error.message);
      return;
    } on Object {
      setState(
        () => _message =
            'The current text could not be captured. Select it again.',
      );
      return;
    }
    setState(() {
      _snapshot = snapshot;
      _busy = true;
      _message = 'Analyzing locally…';
    });
    try {
      final transport = await _getTransport(snapshot.language);
      if (!mounted || generation != _generation) return;
      if (!snapshot.isCurrent(widget.controller, _configurationId)) {
        _onDocumentChanged();
        return;
      }
      final result = await transport.analyze(snapshot.request);
      if (!mounted || generation != _generation) return;
      if (!snapshot.isCurrent(widget.controller, _configurationId)) {
        _onDocumentChanged();
        return;
      }
      if (!result.request.sameSnapshot(snapshot.request) ||
          (result.isSuccess && result.identity != transport.identity)) {
        throw const FormatException('Result identity mismatch.');
      }
      setState(() {
        _busy = false;
        _result = result;
        _message = result.isSuccess ? null : _statusMessage(result.status);
      });
      if (result.status == LinguisticAnalysisStatus.unavailable) {
        _releaseTransport();
      }
    } on SpacyUnavailableException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _message = error.message;
      });
      _releaseTransport();
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _message =
            'Analysis could not finish. Check the local installation and try again.';
      });
      _releaseTransport();
    }
  }

  String _statusMessage(LinguisticAnalysisStatus status) => switch (status) {
    LinguisticAnalysisStatus.cancelled => 'Analysis cancelled.',
    LinguisticAnalysisStatus.stale =>
      'The analysis is out of date. Analyze again.',
    LinguisticAnalysisStatus.capacity =>
      'Local analysis is busy. Try again shortly.',
    LinguisticAnalysisStatus.timeout =>
      'Analysis took too long. Try a shorter passage.',
    LinguisticAnalysisStatus.unsupported =>
      'This text or platform is unsupported by local analysis.',
    LinguisticAnalysisStatus.unavailable =>
      'Local analysis is unavailable. Check the host installation.',
    LinguisticAnalysisStatus.failed =>
      'Analysis could not finish. Please try again.',
    LinguisticAnalysisStatus.success => '',
  };

  /// Explicit acquisition/opt-in flow. Any configuration change releases the
  /// current worker so the next analysis opens the newly verified setup.
  Future<void> _openSetup() async {
    final before = _configurationId;
    await showStudioSpacySetup(context);
    if (!mounted || before == _configurationId) return;
    setState(() => _cancel('The analysis setup changed. Analyze again.'));
    _releaseTransport();
  }

  void _reveal(LinguisticToken token) {
    final snapshot = _snapshot;
    if (snapshot == null ||
        !snapshot.revealToken(widget.controller, _configurationId, token)) {
      _onDocumentChanged();
      setState(
        () => _message ??=
            'This token cannot be selected at a complete text boundary.',
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onDocumentChanged);
    _cancel('Analysis closed.');
    _releaseTransport();
    _tokenScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final snapshot = _snapshot;
    return AlertDialog(
      title: const Text('Text analysis'),
      content: SizedBox(
        width: 760,
        height: math.max(
          180,
          math.min(600, MediaQuery.sizeOf(context).height - 230),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selection within one paragraph, or the current paragraph. '
              'Body and table text · German (Germany), English or French.',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Analyze as: '),
                DropdownButton<SpacyLanguage?>(
                  key: const Key('analysis-language'),
                  value: _analyzeAs,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _analyzeAs = value;
                          _cancel(
                            'The analysis language changed. Analyze again.',
                          );
                        }),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Marked text language'),
                    ),
                    for (final language in SpacyLanguage.values)
                      DropdownMenuItem(
                        value: language,
                        child: Text(
                          language == SpacyLanguage.german
                              ? 'German (Germany)'
                              : language.displayName,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (snapshot != null)
              Text(
                snapshot.selectedText ? 'Selected text' : 'Current paragraph',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, key: const Key('analysis-status')),
            ],
            if (result != null && result.isSuccess) ...[
              const SizedBox(height: 8),
              Text(
                '${result.tokens.length} ${result.tokens.length == 1 ? 'token' : 'tokens'} · '
                '${result.sentences.length} ${result.sentences.length == 1 ? 'sentence' : 'sentences'} '
                '· ${result.identity?.bundle?.modelName ?? 'spaCy'} 3.8.0',
              ),
              if (result.entitiesAvailable) ...[
                const SizedBox(height: 4),
                Text(
                  result.entities.isEmpty
                      ? 'Named entities: none found'
                      : 'Named entities: ${result.entities.map((entity) => '${entity.text} (${entity.label})').join(' · ')}',
                  key: const Key('analysis-entities'),
                ),
              ],
              const SizedBox(height: 8),
              if (result.tokens.isEmpty) const Text('The input is empty.'),
              Expanded(
                child: Scrollbar(
                  controller: _tokenScroll,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _tokenScroll,
                    itemCount: result.tokens.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final token = result.tokens[index];
                      final head = result.tokens[token.head];
                      return ListTile(
                        key: ValueKey('analysis-token-$index'),
                        contentPadding: EdgeInsets.zero,
                        title: Text('${index + 1}. ${jsonEncode(token.text)}'),
                        subtitle: Text(
                          'Lemma: ${token.lemma} · ${token.pos} (${token.tag})\n'
                          '${token.morphology.isEmpty ? 'No morphological features' : token.morphology.replaceAll('|', ' · ')}\n'
                          'Dependency: ${token.dependency} · Head: ${token.head == token.index ? 'root' : '${head.index + 1}. ${head.text}'}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Select token in document',
                          onPressed: () => _reveal(token),
                          icon: const Icon(Icons.my_location),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
      actions: [
        if (widget.transportFactory == null)
          TextButton(
            key: const Key('analysis-setup'),
            onPressed: _busy ? null : _openSetup,
            child: const Text('Setup…'),
          ),
        if (_busy)
          TextButton(
            onPressed: () => setState(() => _cancel('Analysis cancelled.')),
            child: const Text('Cancel analysis'),
          ),
        FilledButton(
          onPressed: _busy ? null : _analyze,
          child: const Text('Analyze text'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
