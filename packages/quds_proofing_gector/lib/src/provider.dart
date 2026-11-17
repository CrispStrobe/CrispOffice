import 'dart:async';
import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';

import 'backend.dart';
import 'bundle.dart';
import 'decoder.dart';
import 'guards.dart';
import 'source_text.dart';
import 'transport.dart';

/// Optional manual German proofing. Preload with [load], then configure this
/// provider on the editor's manual proofing service. No model is auto-downloaded.
final class GectorProofingProvider extends OfficeProofingProvider {
  GectorProofingProvider.withTransport({
    required this._transport,
    required this.configuration,
    OfficeProofingVocabulary? vocabulary,
    this.timeout = const Duration(seconds: 15),
  }) : vocabulary = vocabulary ?? OfficeProofingVocabulary() {
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
  }

  static Future<GectorProofingProvider> load({
    required GectorVerifiedBundle bundle,
    required GectorBackendFactory backendFactory,
    required GectorLexiconFactory lexiconFactory,
    OfficeProofingVocabulary? vocabulary,
    GectorDecodeOptions? options,
    int maximumPendingRequests = 3,
    Duration startupTimeout = const Duration(seconds: 60),
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
    final transport = await startGectorWorker(
      bundle: bundle,
      backendFactory: backendFactory,
      lexiconFactory: lexiconFactory,
      options: options,
      maximumPendingRequests: maximumPendingRequests,
      startupTimeout: startupTimeout,
    );
    return GectorProofingProvider.withTransport(
      transport: transport,
      configuration: bundle.configuration,
      vocabulary: vocabulary,
      timeout: timeout,
    );
  }

  final GectorConfiguration configuration;
  final OfficeProofingVocabulary vocabulary;
  final Duration timeout;
  final GectorTransport _transport;
  bool _disposed = false;

  @override
  String get id => 'gector-de';
  @override
  int get configurationRevision => vocabulary.revision;
  @override
  bool supportsLanguage(String language) =>
      normalizeProofingLanguage(language) == 'de-DE';

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    if (_disposed) {
      return _result(
        request,
        OfficeProofingStatus.unavailable,
        'GECToR was disposed.',
      );
    }
    if (!supportsLanguage(request.language)) {
      return _result(
        request,
        OfficeProofingStatus.unsupported,
        'This German model policy supports de-DE only; de-AT and de-CH are not qualified.',
      );
    }
    final revision = vocabulary.revision;
    final personal = <String>{
      ...vocabulary.wordsFor(request.language),
      ...vocabulary.ignoredWordsFor(request.language),
    };
    try {
      final result = await _transport
          .check(
            GectorCheckRequest(
              text: request.text,
              key: jsonEncode(<Object>[
                request.documentId,
                request.blockId,
                request.startOffset,
              ]),
              personalWords: personal,
            ),
          )
          .timeout(timeout);
      if (_disposed) {
        return _result(
          request,
          OfficeProofingStatus.unavailable,
          'GECToR was disposed.',
        );
      }
      if (revision != vocabulary.revision) {
        return _result(
          request,
          OfficeProofingStatus.failed,
          'Personal vocabulary changed during this check; check again.',
        );
      }
      if (result.original != request.text || !result.guarded) {
        throw const FormatException(
          'Worker returned a different source or unguarded result.',
        );
      }
      if (!result.complete) {
        return _result(
          request,
          OfficeProofingStatus.failed,
          'GECToR did not converge within its bounded passes (${result.stopReason.name}).',
        );
      }
      final source = GectorSourceText(request.text, configuration);
      if (source.apply(result.edits) != result.corrected) {
        throw const FormatException(
          'Worker edits disagree with corrected text.',
        );
      }
      final boundaries = source.graphemeBoundaries;
      final protected = OfficeProofingTextRanges(request.text);
      final literals = GermanLiteralTextRanges(request.text);
      final findings = <OfficeProofingFinding>[];
      final seen = <(int, int, String)>{};
      var previousEnd = -1;
      for (final edit in result.edits) {
        if (edit.start < 0 ||
            edit.end < edit.start ||
            edit.end > request.text.length ||
            edit.start < previousEnd ||
            request.text.substring(edit.start, edit.end) != edit.original ||
            !GectorSourceText.isWellFormedUtf16(edit.replacement)) {
          throw const FormatException(
            'Worker returned an invalid source edit.',
          );
        }
        previousEnd = edit.end;
        if (edit.original == edit.replacement ||
            !boundaries.contains(edit.start) ||
            !boundaries.contains(edit.end) ||
            protected.overlaps(edit.start, edit.end) ||
            literals.overlaps(edit.start, edit.end) ||
            _personalOverlap(source, personal, edit) ||
            !seen.add((edit.start, edit.end, edit.replacement)) ||
            request.ignoredRuleIds.contains('gector.de.grammar')) {
          continue;
        }
        findings.add(
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            start: edit.start,
            end: edit.end,
            ruleId: 'gector.de.grammar',
            message: 'Mögliche Grammatik- oder Wortformkorrektur.',
            category: OfficeProofingCategory.grammar,
            replacements: <String>[edit.replacement],
          ),
        );
      }
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: findings,
      );
    } on GectorUnavailableException catch (error) {
      return _result(request, OfficeProofingStatus.unavailable, error.message);
    } on TimeoutException {
      unawaited(Future<void>.sync(dispose).catchError((Object _) {}));
      return _result(
        request,
        OfficeProofingStatus.failed,
        'The local GECToR worker timed out and was disposed.',
      );
    } on Object catch (error) {
      return _result(
        request,
        OfficeProofingStatus.failed,
        'Local GECToR check failed: $error',
      );
    }
  }

  static bool _personalOverlap(
    GectorSourceText source,
    Set<String> personal,
    GectorEdit edit,
  ) {
    for (final span in source.wordSpans(source.plain, surface: true)) {
      final overlaps = edit.start == edit.end
          ? span.start <= edit.start && edit.start < span.end
          : span.start < edit.end && edit.start < span.end;
      if (overlaps && personal.contains(normalizeGermanWord(span.word))) {
        return true;
      }
    }
    return false;
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
    await _transport.dispose();
  }
}
