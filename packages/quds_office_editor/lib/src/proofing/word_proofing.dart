import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// A finding together with its exact paragraph, story and input snapshot.
final class WordProofingIssue {
  WordProofingIssue._(this.finding, this._snapshot, this.language);

  final OfficeProofingFinding finding;
  final _ParagraphSnapshot _snapshot;
  final String language;
  WmlParagraph get paragraph => _snapshot.paragraph;
  String get story => _snapshot.story;
}

/// Coverage and operational outcomes of one document-wide proofing pass.
final class WordProofingSummary {
  WordProofingSummary({
    this.paragraphCount = 0,
    this.checkedParagraphCount = 0,
    this.skippedContentCount = 0,
    this.hasResults = false,
    List<WordProofingIssue> issues = const [],
    List<OfficeProofingReport> reports = const [],
    this.checking = false,
  }) : issues = List.unmodifiable(issues),
       reports = List.unmodifiable(reports);

  final int paragraphCount;
  final int checkedParagraphCount;
  final int skippedContentCount;
  final bool hasResults;
  final bool checking;
  final List<WordProofingIssue> issues;
  final List<OfficeProofingReport> reports;

  bool get complete =>
      hasResults && !checking && skippedContentCount == 0 &&
      reports.isNotEmpty && reports.every((report) => report.complete);

  String get statusMessage {
    if (checking) return 'Checking document…';
    if (!hasResults) return 'Document has not been checked.';
    final problems = <String>{};
    for (final report in reports) {
      if (!report.complete) {
        for (final result in report.results) {
          if (result.status != OfficeProofingStatus.success) {
            problems.add(result.message ??
                '${result.providerId}: ${result.status.name}');
          }
        }
      }
    }
    final coverage = '$checkedParagraphCount of $paragraphCount paragraphs checked';
    final excluded = skippedContentCount == 0 ? '' :
        '; $skippedContentCount excluded or unsupported content ranges';
    if (problems.isNotEmpty) return '$coverage$excluded. ${problems.join(' ')}';
    if (reports.isEmpty) return '$coverage$excluded. No checkable text.';
    if (!complete) return '$coverage$excluded. ${issues.length} findings; coverage is incomplete.';
    return issues.isEmpty
        ? '$coverage. No issues found by the configured providers.'
        : '$coverage. ${issues.length} findings to review.';
  }
}

/// Ephemeral document proofing. The host owns vocabulary persistence; the
/// session owns and disposes its service. Unchanged paragraphs reuse checked
/// results while every published finding is rebound to the current revision.
final class WordProofingSession extends ChangeNotifier {
  WordProofingSession({
    required WmlDocument Function() document,
    required int Function() revision,
    OfficeProofingService? service,
    OfficeProofingVocabulary? vocabulary,
    this.debounce = const Duration(milliseconds: 400),
  }) : _document = document,
       _revision = revision,
       vocabulary = vocabulary ?? OfficeProofingVocabulary() {
    _service = service ?? OfficeProofingService(providers: [
      GermanSpellingProvider(vocabulary: this.vocabulary),
      GermanWritingRulesProvider(),
    ]);
  }

  final WmlDocument Function() _document;
  final int Function() _revision;
  final OfficeProofingVocabulary vocabulary;
  final Duration debounce;
  late OfficeProofingService _service;
  final Set<String> _ignoredRules = {};
  final Expando<String> _ids = Expando<String>('proofing paragraph id');
  final Expando<String> _documentIds = Expando<String>('proofing document id');
  final Map<WmlParagraph, _CachedParagraph> _cache = HashMap.identity();
  Map<WmlParagraph, List<OfficeProofingFinding>> _findings = HashMap.identity();
  int _nextId = 0;
  int _generation = 0;
  int _configuration = 0;
  bool _disposed = false;
  bool _enabled = false;
  Timer? _timer;
  WmlDocument? _observedDocument;
  int? _observedRevision;
  String? _observedConfiguration;
  WordProofingSummary _summary = WordProofingSummary();

  WordProofingSummary get summary => _summary;
  bool get checking => _summary.checking;
  bool get enabled => _enabled;
  String get language => normalizeProofingLanguage(_document().proofingLanguage ?? 'de-DE');
  Set<String> get ignoredRuleIds => Set.unmodifiable(_ignoredRules);
  Map<WmlParagraph, List<OfficeProofingFinding>> get findingsByParagraph =>
      UnmodifiableMapView(_findings);

  set enabled(bool value) {
    if (_enabled == value || _disposed) return;
    _enabled = value;
    refresh();
  }

  String get _configurationKey =>
      '$_configuration|${_service.configurationKey}|${vocabulary.revision}|'
      '$language|${_ignoredRules.join(',')}';

  /// Replacing a provider configuration invalidates pending checks immediately.
  void configure(OfficeProofingService service) {
    if (identical(_service, service)) return;
    final previous = _service;
    _service = service;
    _configuration++;
    _cache.clear();
    unawaited(previous.dispose());
    refresh();
  }

  /// Called for controller-observed content changes. Selection and scroll
  /// notifications do not repeatedly cancel work or schedule new checks.
  void observeDocument() {
    if (_disposed) return;
    final document = _document();
    final revision = _revision();
    final configuration = _configurationKey;
    if (identical(document, _observedDocument) &&
        revision == _observedRevision && configuration == _observedConfiguration) return;
    _observedDocument = document;
    _observedRevision = revision;
    _observedConfiguration = configuration;
    _invalidate();
  }

  /// Hosts call this after direct model edits or changes to host-owned words.
  void refresh() {
    if (_disposed) return;
    _observedDocument = _document();
    _observedRevision = _revision();
    _observedConfiguration = _configurationKey;
    _invalidate();
    notifyListeners();
  }

  void _invalidate() {
    _generation++;
    _timer?.cancel();
    _summary = WordProofingSummary();
    _findings = HashMap.identity();
    if (_enabled) _timer = Timer(debounce, () => unawaited(checkNow()));
  }

  void ignoreWord(WordProofingIssue issue) {
    if (!isCurrent(issue)) return;
    vocabulary.ignoreWord(issue.finding.originalText, language: issue.language);
    refresh();
  }

  void addWord(WordProofingIssue issue) {
    if (!isCurrent(issue)) return;
    vocabulary.addWord(issue.finding.originalText, language: issue.language);
    refresh();
  }

  void ignoreRule(String ruleId) {
    if (_ignoredRules.add(ruleId)) refresh();
  }

  void restoreRule(String ruleId) {
    if (_ignoredRules.remove(ruleId)) refresh();
  }

  /// Results are accepted only for the current document, revision, language,
  /// provider configuration, story membership and complete paragraph snapshot.
  bool isCurrent(WordProofingIssue issue) {
    if (_disposed || !_summary.issues.contains(issue) ||
        issue.finding.revision != _revision() ||
        issue.finding.documentId != _documentIds[_document()] ||
        issue._snapshot.configuration != _configurationKey) return false;
    final current = _capture(_document()).paragraphs
        .where((snapshot) => identical(snapshot.paragraph, issue.paragraph))
        .firstOrNull;
    return current != null && current.key == issue._snapshot.key &&
        issue.finding.end <= current.text.length &&
        current.text.substring(issue.finding.start, issue.finding.end) ==
            issue.finding.originalText;
  }

  bool canCorrect(WordProofingIssue issue) {
    if (!isCurrent(issue)) return false;
    final snapshot = issue._snapshot;
    final finding = issue.finding;
    if (snapshot.locked || snapshot.guards.any((range) =>
        _touches(finding.start, finding.end, range.start, range.end))) return false;
    try {
      WordContentControls.assertCanEdit(issue.paragraph, finding.start, finding.end);
      final normalized = WmlRunEdit.normalizeRange(issue.paragraph, finding.start, finding.end);
      return normalized.start == finding.start && normalized.end == finding.end;
    } on Object {
      return false;
    }
  }

  Future<WordProofingSummary> checkNow() async {
    if (_disposed) return _summary;
    _timer?.cancel();
    final generation = ++_generation;
    final document = _document();
    final revision = _revision();
    final configuration = _configurationKey;
    _observedDocument = document;
    _observedRevision = revision;
    _observedConfiguration = configuration;
    final documentId = _documentIds[document] ??= 'document-${++_nextId}';
    final captured = _capture(document);
    _summary = WordProofingSummary(paragraphCount: captured.paragraphs.length, checking: true);
    _findings = HashMap.identity();
    notifyListeners();
    final reports = <OfficeProofingReport>[];
    final issues = <WordProofingIssue>[];
    var checked = 0;
    bool current() => !_disposed && generation == _generation &&
        identical(document, _document()) && revision == _revision() &&
        configuration == _configurationKey;
    for (final snapshot in captured.paragraphs) {
      // Yield between paragraphs even when a cached/provider Future completes
      // synchronously. Web typing and painting get an event-loop turn.
      await Future<void>.delayed(Duration.zero);
      if (!current()) return _summary;
      final cached = _cache[snapshot.paragraph];
      final paragraphReports = <OfficeProofingReport>[];
      for (var index = 0; index < snapshot.segments.length; index++) {
        final segment = snapshot.segments[index];
        final request = OfficeProofingRequest(
          documentId: documentId,
          blockId: _ids[snapshot.paragraph] ??= 'paragraph-${++_nextId}',
          revision: revision,
          text: segment.text,
          startOffset: segment.start,
          language: segment.language,
          ignoredRuleIds: _ignoredRules,
        );
        final report = cached?.key == snapshot.key &&
                cached!.reports.length == snapshot.segments.length &&
                cached.reports.every((report) => report.complete)
            ? _retarget(cached.reports[index], request)
            : await _service.check(request);
        if (!current()) return _summary;
        paragraphReports.add(report);
        for (final finding in report.findings) {
          if (finding.category == OfficeProofingCategory.spelling &&
              vocabulary.contains(finding.originalText, language: segment.language)) continue;
          issues.add(WordProofingIssue._(finding, snapshot, segment.language));
        }
      }
      if (paragraphReports.isNotEmpty && paragraphReports.every((report) => report.complete)) checked++;
      reports.addAll(paragraphReports);
      _cache[snapshot.paragraph] = _CachedParagraph(snapshot.key, paragraphReports);
    }
    if (!current()) return _summary;
    final after = _capture(document);
    if (captured.key != after.key) {
      refresh();
      return _summary;
    }
    final attached = captured.paragraphs.map((snapshot) => snapshot.paragraph).toSet();
    _cache.removeWhere((paragraph, _) => !attached.contains(paragraph));
    final findings = HashMap<WmlParagraph, List<OfficeProofingFinding>>.identity();
    for (final issue in issues) {
      findings.putIfAbsent(issue.paragraph, () => []).add(issue.finding);
    }
    _findings = {for (final entry in findings.entries) entry.key: List.unmodifiable(entry.value)};
    _summary = WordProofingSummary(
      paragraphCount: captured.paragraphs.length,
      checkedParagraphCount: checked,
      skippedContentCount: captured.skipped,
      hasResults: true,
      reports: reports,
      issues: issues,
    );
    notifyListeners();
    return _summary;
  }

  _DocumentSnapshot _capture(WmlDocument document) {
    final snapshots = <_ParagraphSnapshot>[];
    final seen = HashSet<WmlParagraph>.identity();
    var skipped = 0;
    final configuration = _configurationKey;
    final deletions = HashMap<WmlParagraph, List<({int start, int end})>>.identity();
    for (final revision in document.revisions) {
      if (revision.kind != WmlRevisionKind.delete) continue;
      final paragraph = WordRevisions.resolveParagraph(document, revision);
      if (paragraph != null && revision.start >= 0 && revision.end <= paragraph.text.length) {
        deletions.putIfAbsent(paragraph, () => []).add((start: revision.start, end: revision.end));
      }
    }
    void story(Iterable<({WmlParagraph paragraph, bool locked, bool generated})> entries, String name) {
      var fieldDepth = 0;
      for (final entry in entries) {
        final paragraph = entry.paragraph;
        if (!seen.add(paragraph)) continue;
        final text = paragraph.text;
        final exclusions = <({int start, int end})>[...?deletions[paragraph]];
        final guards = <({int start, int end})>[];
        final languageRuns = <({int start, int end, String language})>[];
        var offset = 0;
        var locked = entry.locked || paragraph.contentControlWrappers.any(_lockedControl);
        var generated = entry.generated || paragraph.properties.fieldInstruction != null;
        if (generated && text.isNotEmpty) exclusions.add((start: 0, end: text.length));
        try {
          for (final span in WordContentControls.spans(paragraph)) {
            if (_lockedControl(span.control)) guards.add((start: span.start, end: span.end));
          }
        } on Object {
          locked = true;
        }
        for (final inline in paragraph.inlines) {
          if (inline is WmlFieldBoundary) {
            switch (inline.kind) {
              case WmlFieldBoundaryKind.begin: fieldDepth++;
              case WmlFieldBoundaryKind.end: if (fieldDepth > 0) fieldDepth--;
              case WmlFieldBoundaryKind.instruction:
              case WmlFieldBoundaryKind.separate: break;
            }
          } else if (inline is WmlRun) {
            final end = offset + inline.text.length;
            if (inline.isAtomic || inline.properties.noProof == true || fieldDepth > 0) {
              exclusions.add((start: offset, end: end));
            }
            languageRuns.add((start: offset, end: end, language: normalizeProofingLanguage(
                inline.properties.proofingLanguage ?? paragraph.properties.proofingLanguage ?? language)));
            offset = end;
          } else if (inline is WmlOpaqueInline || inline is WmlObject) {
            skipped++;
          }
        }
        guards.addAll(exclusions);
        // Existing insert revisions are not rewritten by a second command.
        for (final revision in document.revisions) {
          if (identical(revision.targetParagraph, paragraph)) {
            guards.add((start: revision.start, end: revision.end));
          }
        }
        final boundaries = <int>{0, text.length};
        for (final run in languageRuns) { boundaries.add(run.start); boundaries.add(run.end); }
        for (final range in exclusions) { boundaries.add(range.start); boundaries.add(range.end); }
        final sorted = boundaries.where((value) => value >= 0 && value <= text.length).toList()..sort();
        final segments = <_Segment>[];
        var paragraphSkipped = generated;
        for (var i = 0; i + 1 < sorted.length; i++) {
          final start = sorted[i];
          final end = sorted[i + 1];
          if (start == end) continue;
          if (exclusions.any((range) => start < range.end && end > range.start)) {
            paragraphSkipped = true;
            continue;
          }
          final tag = languageRuns.where((run) => start >= run.start && start < run.end).firstOrNull?.language ?? language;
          if (segments.isNotEmpty && segments.last.end == start && segments.last.language == tag) {
            final last = segments.removeLast();
            segments.add(_Segment(last.start, end, text.substring(last.start, end), tag));
          } else {
            segments.add(_Segment(start, end, text.substring(start, end), tag));
          }
        }
        if (paragraphSkipped) skipped++;
        if (text.isEmpty && !generated) segments.add(_Segment(0, 0, '', paragraph.properties.proofingLanguage ?? language));
        final key = jsonEncode([configuration, name, text, locked,
          for (final range in guards) [range.start, range.end],
          for (final segment in segments) [segment.start, segment.end, segment.language],
        ]);
        snapshots.add(_ParagraphSnapshot(paragraph, name, text, key, configuration, locked, guards, segments));
      }
    }
    Iterable<({WmlParagraph paragraph, bool locked, bool generated})> blocks(
        Iterable<WmlBlock> children, {bool locked = false}) sync* {
      for (final block in children) {
        if (block is WmlParagraph) {
          yield (paragraph: block, locked: locked, generated: false);
        } else if (block is WmlContentControlBlock) {
          yield* blocks(block.blocks, locked: locked || _lockedControl(block.control));
        } else if (block is WmlToc) {
          for (final paragraph in [block.titleParagraph, ...block.itemParagraphs]) {
            yield (paragraph: paragraph, locked: true, generated: true);
          }
        } else if (block is WmlOpaqueBlock || block is WmlVisual || block is WmlEquation) {
          skipped++;
        } else {
          for (final childList in WordTree.childLists(block)) {
            yield* blocks(childList, locked: locked);
          }
        }
      }
    }
    // A complex field can span sections in the main document story.
    story(blocks(document.sections.expand((section) => section.blocks)), 'Body');
    for (var i = 0; i < document.sections.length; i++) {
      final section = document.sections[i];
      final stories = {
        'Header': section.header, 'Footer': section.footer,
        'First-page header': section.firstHeader, 'First-page footer': section.firstFooter,
        'Even-page header': section.evenHeader, 'Even-page footer': section.evenFooter,
      };
      for (final entry in stories.entries) {
        story(entry.value.map((p) => (paragraph: p, locked: false, generated: false)), '${entry.key} · section ${i + 1}');
      }
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      story(blocks(note.blocks), '${note.endnote ? 'Endnote' : 'Footnote'} ${note.id}');
    }
    for (final comment in document.comments) {
      story(comment.paragraphs.map((p) => (paragraph: p, locked: false, generated: false)), 'Comment ${comment.id}');
    }
    return _DocumentSnapshot(snapshots, skipped);
  }

  static bool _lockedControl(WmlContentControlData control) {
    try {
      final properties = WordContentControls.template(control).firstChild('sdtPr');
      final lock = properties?.firstChild('lock');
      final value = lock?.getAttribute('val');
      return lock != null && value != 'unlocked' && value != 'sdtLocked';
    } on Object {
      return true;
    }
  }

  static bool _touches(int start, int end, int from, int to) =>
      start == end ? start >= from && start <= to : start < to && end > from;

  static OfficeProofingReport _retarget(OfficeProofingReport report, OfficeProofingRequest request) =>
      OfficeProofingReport(request: request, results: [
        for (final result in report.results) OfficeProofingResult(
          request: request, providerId: result.providerId, status: result.status, message: result.message,
          findings: [for (final finding in result.findings) OfficeProofingFinding(
            documentId: request.documentId, blockId: request.blockId, revision: request.revision,
            providerId: finding.providerId, start: finding.start, end: finding.end,
            originalText: finding.originalText, ruleId: finding.ruleId, message: finding.message,
            category: finding.category, replacements: finding.replacements,
          )],
        ),
      ]);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _cache.clear();
    _findings.clear();
    unawaited(_service.dispose());
    super.dispose();
  }
}

final class _Segment {
  const _Segment(this.start, this.end, this.text, this.language);
  final int start;
  final int end;
  final String text;
  final String language;
}

final class _ParagraphSnapshot {
  const _ParagraphSnapshot(this.paragraph, this.story, this.text, this.key,
      this.configuration, this.locked, this.guards, this.segments);
  final WmlParagraph paragraph;
  final String story;
  final String text;
  final String key;
  final String configuration;
  final bool locked;
  final List<({int start, int end})> guards;
  final List<_Segment> segments;
}

final class _DocumentSnapshot {
  const _DocumentSnapshot(this.paragraphs, this.skipped);
  final List<_ParagraphSnapshot> paragraphs;
  final int skipped;
  String get key => jsonEncode([skipped, for (final p in paragraphs) [identityHashCode(p.paragraph), p.key]]);
}

final class _CachedParagraph {
  const _CachedParagraph(this.key, this.reports);
  final String key;
  final List<OfficeProofingReport> reports;
}
