import 'dart:async';

import 'package:characters/characters.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'client.dart';
import 'german_rules.dart';
import 'models.dart';
import 'transport.dart';

/// Optional, explicit German grammar checking through an AOT analyzer.
///
/// Configure on the editor's manual service so document text is sent only when
/// the user asks to check it. This adapter never edits a document. It reports
/// source-bound suggestions and keeps transport/coverage failures visible.
final class AotProofingProvider extends OfficeProofingProvider {
  AotProofingProvider({
    required this.analyzer,
    OfficeProofingVocabulary? vocabulary,
    this.ownsAnalyzer = true,
    this.timeout = const Duration(seconds: 15),
    this.maximumMorphologyLookups = 24,
    this.maximumFindings = 100,
    this.maximumTextCodeUnits = 32768,
  }) : vocabulary = vocabulary ?? OfficeProofingVocabulary() {
    if (timeout <= Duration.zero ||
        maximumMorphologyLookups < 1 ||
        maximumMorphologyLookups > 256 ||
        maximumFindings < 1 ||
        maximumFindings > 2000 ||
        maximumTextCodeUnits < 1) {
      throw ArgumentError('Invalid AOT grammar limits.');
    }
  }

  final AotAnalyzer analyzer;
  final OfficeProofingVocabulary vocabulary;
  final bool ownsAnalyzer;
  final Duration timeout;
  final int maximumMorphologyLookups;
  final int maximumFindings;
  final int maximumTextCodeUnits;
  bool _disposed = false;
  bool _timedOut = false;

  @override
  String get id => 'aot-de';

  @override
  int get configurationRevision => vocabulary.revision;

  @override
  bool supportsLanguage(String language) =>
      normalizeProofingLanguage(language) == 'de-DE';

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    if (_disposed || _timedOut) {
      return _result(
        request,
        OfficeProofingStatus.unavailable,
        'AOT grammar provider is no longer available.',
      );
    }
    if (!supportsLanguage(request.language)) {
      return _result(
        request,
        OfficeProofingStatus.unsupported,
        'AOT grammar rules are qualified for de-DE only.',
      );
    }
    if (request.text.length > maximumTextCodeUnits) {
      return _result(
        request,
        OfficeProofingStatus.failed,
        'Text exceeds the AOT grammar request limit.',
      );
    }
    if (request.text.trim().isEmpty) {
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
      );
    }
    final revision = vocabulary.revision;
    final personal = <String>{
      ...vocabulary.wordsFor(request.language),
      ...vocabulary.ignoredWordsFor(request.language),
    };
    var active = true;
    bool current() =>
        active && !_disposed && !_timedOut && vocabulary.revision == revision;
    try {
      final result = await _check(request, personal, current).timeout(timeout);
      if (_disposed) {
        return _result(
          request,
          OfficeProofingStatus.unavailable,
          'AOT grammar provider was disposed during the check.',
        );
      }
      if (!current()) {
        return _result(
          request,
          OfficeProofingStatus.failed,
          'AOT proofing configuration changed; check the current text again.',
        );
      }
      return result;
    } on AotException catch (error) {
      final status = switch (error.code) {
        AotErrorCode.unavailable ||
        AotErrorCode.disposed => OfficeProofingStatus.unavailable,
        AotErrorCode.unsupportedLanguage => OfficeProofingStatus.unsupported,
        _ => OfficeProofingStatus.failed,
      };
      return _result(request, status, error.message);
    } on TimeoutException {
      active = false;
      _timedOut = true;
      if (ownsAnalyzer) {
        unawaited(
          Future<void>.sync(analyzer.dispose).catchError((Object _) {}),
        );
      }
      return _result(
        request,
        OfficeProofingStatus.failed,
        'AOT grammar check exceeded its deadline.',
      );
    } on Object {
      return _result(
        request,
        _disposed
            ? OfficeProofingStatus.unavailable
            : OfficeProofingStatus.failed,
        'AOT grammar check could not validate the current analysis.',
      );
    } finally {
      active = false;
    }
  }

  Future<OfficeProofingResult> _check(
    OfficeProofingRequest request,
    Set<String> personal,
    bool Function() current,
  ) async {
    final analysis = await analyzer.analyze(request.text);
    if (!current()) throw StateError('AOT check is no longer current.');
    if (analysis.text != request.text ||
        analysis.language != AotLanguage.german ||
        !analysis.fullyAligned ||
        analysis.tokens.isEmpty) {
      throw const FormatException('AOT analysis is incomplete or mismatched.');
    }
    final boundaries = <int>{0};
    var end = 0;
    for (final cluster in request.text.characters) {
      end += cluster.length;
      boundaries.add(end);
    }
    var previousEnd = 0;
    for (final word in analysis.tokens) {
      final start = word.start;
      final end = word.end;
      if (start == null ||
          end == null ||
          start < previousEnd ||
          end <= start ||
          end > request.text.length ||
          !boundaries.contains(start) ||
          !boundaries.contains(end) ||
          request.text.substring(start, end) != word.text) {
        throw const FormatException('AOT source coordinates are invalid.');
      }
      previousEnd = end;
    }
    if (analysis.sentences.any(
      (sentence) => sentence.clauses.any(
        (clause) =>
            clause.variants.isEmpty &&
            clause.words.any((word) => _letters.hasMatch(word.text)),
      ),
    )) {
      throw const FormatException('AOT did not analyze a lexical clause.');
    }
    final protected = OfficeProofingTextRanges(request.text);
    final personalRanges = <({int start, int end})>[
      for (final match in _words.allMatches(request.text))
        if (personal.contains(normalizeGermanWord(match.group(0)!)))
          (start: match.start, end: match.end),
    ];
    bool protectedRange(int start, int end) =>
        !boundaries.contains(start) ||
        !boundaries.contains(end) ||
        protected.overlaps(start, end) ||
        personalRanges.any((span) => span.start < end && start < span.end);

    final cache = <String, Future<AotMorphology>>{};
    Future<AotMorphology> morphology(String word) {
      if (!current()) throw StateError('AOT check is no longer current.');
      final existing = cache[word];
      if (existing != null) return existing;
      if (cache.length >= maximumMorphologyLookups) {
        throw const AotException(
          AotErrorCode.limit,
          'AOT morphology request budget was exceeded; check a shorter passage.',
        );
      }
      final pending = analyzer.morphology(word, withParadigms: true);
      cache[word] = pending;
      return pending;
    }

    final diagnostics = await const AotGermanGrammar().check(
      analysis,
      morphology: morphology,
      protected: protectedRange,
      ignoredRuleIds: request.ignoredRuleIds,
      isCurrent: current,
    );
    if (diagnostics.length > maximumFindings) {
      throw const AotException(
        AotErrorCode.limit,
        'AOT grammar finding limit was exceeded; check a shorter passage.',
      );
    }
    final findings = <OfficeProofingFinding>[
      for (final diagnostic in diagnostics)
        OfficeProofingFinding.forRequest(
          request,
          providerId: id,
          start: diagnostic.start,
          end: diagnostic.end,
          ruleId: diagnostic.ruleId,
          message: diagnostic.message,
          category: OfficeProofingCategory.grammar,
          replacements: diagnostic.replacements,
        ),
    ];
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: findings,
    );
  }

  OfficeProofingResult _result(
    OfficeProofingRequest request,
    OfficeProofingStatus status,
    String message,
  ) => OfficeProofingResult(
    request: request,
    providerId: id,
    status: status,
    message: message,
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (ownsAnalyzer) await analyzer.dispose();
  }
}

final _letters = RegExp(r'\p{L}', unicode: true);
final _words = RegExp(r'[\p{L}\p{M}]+', unicode: true);
