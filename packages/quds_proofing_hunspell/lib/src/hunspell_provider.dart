import 'dart:async';
import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';

import 'hunspell_catalog.dart';
import 'hunspell_transport.dart';
import 'hunspell_transport_stub.dart'
    if (dart.library.io) 'hunspell_transport_native.dart'
    if (dart.library.js_interop) 'hunspell_transport_web.dart'
    as platform;
import 'hunspell_words.dart';

/// Rule id of every finding; listing it in a request's ignored rules turns
/// this provider's findings off for that request.
const hunspellSpellingRule = 'hunspell.spelling';

/// Spelling for the languages of one user-downloaded Hunspell dictionary.
///
/// Hosts construct it only after the user has installed and verified the
/// dictionary ([HunspellDictionaryFiles] natively, [HunspellDictionaryBytes]
/// on the web); nothing is enabled or downloaded by default. Native checks
/// run in a persistent isolate, web checks in a Web Worker with the bundled
/// WebAssembly engine.
final class HunspellProofingProvider extends OfficeProofingProvider {
  HunspellProofingProvider({
    required this.bundle,
    required this.dictionary,
    String? nativeLibraryPath,
    Uri? workerUrl,
    HunspellTransport? transport,
    OfficeProofingVocabulary? vocabulary,
    this.timeout = const Duration(seconds: 20),
    this.maxSuggestedWords = 24,
    this.maxReplacements = 5,
  }) : vocabulary = vocabulary ?? OfficeProofingVocabulary(),
       _transport =
           transport ??
           platform.createHunspellTransport(
             nativeLibraryPath: nativeLibraryPath,
             workerUrl: workerUrl,
           ) {
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
  }

  final HunspellBundleDownload bundle;

  /// The verified, user-downloaded dictionary this provider opens on first use.
  final HunspellDictionary dictionary;

  /// Host-owned, language-scoped personal and ignored words (shared with the
  /// Word session when supplied).
  final OfficeProofingVocabulary vocabulary;
  final Duration timeout;

  /// Distinct misspelled words per request that receive suggestions; further
  /// ones are still reported, without replacements, to bound the work.
  final int maxSuggestedWords;
  final int maxReplacements;
  final HunspellTransport _transport;
  Future<void>? _opened;
  bool _disposed = false;

  @override
  String get id => 'hunspell-${bundle.id}';

  @override
  int get configurationRevision => vocabulary.revision;

  @override
  bool supportsLanguage(String language) => bundle.languages.contains(
    normalizeProofingLanguage(language).split('-').first,
  );

  RegExp? get _script =>
      bundle.languages.contains('ar') ? arabicScriptLetter : null;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    if (_disposed) {
      return _result(
        request,
        OfficeProofingStatus.unavailable,
        'Hunspell has been disposed.',
      );
    }
    if (!supportsLanguage(request.language)) {
      return _result(
        request,
        OfficeProofingStatus.unsupported,
        '${bundle.displayName} does not cover ${request.language}.',
      );
    }
    if (request.text.runes.length > 32768) {
      return _result(
        request,
        OfficeProofingStatus.failed,
        'Hunspell segment exceeds the 32768-character limit.',
      );
    }
    if (request.ignoredRuleIds.contains(hunspellSpellingRule)) {
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
      );
    }
    final vocabularyRevision = vocabulary.revision;
    try {
      final protected = OfficeProofingTextRanges(request.text);
      final words = <HunspellWord>[
        for (final word in hunspellWords(request.text, script: _script))
          if (!protected.overlaps(word.start, word.end) &&
              utf8.encode(word.text).length <= 400 &&
              !vocabulary.contains(word.text, language: request.language))
            word,
      ];
      final unique = <String>{for (final word in words) word.text}.toList();
      if (unique.isEmpty) {
        return OfficeProofingResult(
          request: request,
          providerId: id,
          status: OfficeProofingStatus.success,
        );
      }
      await (_opened ??= _transport.open(dictionary)).timeout(timeout);
      // First pass: spelling only. Second pass: suggestions for the first
      // misspelled distinct words in document order.
      final spelled = _decode(
        await _transport
            .check(unique, List<bool>.filled(unique.length, false))
            .timeout(timeout),
        unique.length,
      );
      final wrong = [
        for (var i = 0; i < unique.length; i++)
          if (!spelled[i].ok) unique[i],
      ];
      final suggestions = <String, List<String>>{};
      final suggested = wrong.take(maxSuggestedWords).toList();
      if (suggested.isNotEmpty) {
        final results = _decode(
          await _transport
              .check(suggested, List<bool>.filled(suggested.length, true))
              .timeout(timeout),
          suggested.length,
        );
        for (var i = 0; i < suggested.length; i++) {
          suggestions[suggested[i]] = results[i].suggestions
              .take(maxReplacements)
              .toList();
        }
      }
      if (_disposed) {
        return _result(
          request,
          OfficeProofingStatus.unavailable,
          'Hunspell has been disposed.',
        );
      }
      if (vocabulary.revision != vocabularyRevision) {
        return _result(
          request,
          OfficeProofingStatus.failed,
          'Personal vocabulary changed during this check; check again.',
        );
      }
      final misspelled = wrong.toSet();
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: [
          for (final word in words)
            if (misspelled.contains(word.text))
              OfficeProofingFinding.forRequest(
                request,
                providerId: id,
                start: word.start,
                end: word.end,
                ruleId: hunspellSpellingRule,
                message:
                    'This word is not in the installed ${bundle.displayName} dictionary.',
                category: OfficeProofingCategory.spelling,
                replacements: suggestions[word.text] ?? const <String>[],
              ),
        ],
      );
    } on HunspellUnavailableException catch (error) {
      _opened = null;
      return _result(request, OfficeProofingStatus.unavailable, error.message);
    } on TimeoutException {
      unawaited(Future<void>.sync(dispose).catchError((Object _) {}));
      return _result(
        request,
        OfficeProofingStatus.failed,
        'The local Hunspell worker timed out and was disposed.',
      );
    } on Object catch (error) {
      return _result(
        request,
        OfficeProofingStatus.failed,
        'Local Hunspell check failed: $error',
      );
    }
  }

  List<({bool ok, List<String> suggestions})> _decode(String raw, int count) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid Hunspell response.');
    }
    final status = decoded['status'];
    if (status == 'unavailable') {
      throw HunspellUnavailableException(
        decoded['message'] is String
            ? decoded['message']! as String
            : 'Hunspell is unavailable.',
      );
    }
    if (status != 'success') {
      throw FormatException(
        decoded['message'] is String
            ? decoded['message']! as String
            : 'Hunspell check failed.',
      );
    }
    final results = decoded['results'];
    if (results is! List<Object?> || results.length != count) {
      throw const FormatException('Invalid Hunspell result list.');
    }
    return [
      for (final item in results)
        if (item case {'ok': final bool ok})
          (
            ok: ok,
            suggestions: switch (item['suggestions']) {
              final List<Object?> list when list.every((s) => s is String) =>
                list.cast<String>(),
              null => const <String>[],
              _ => throw const FormatException('Invalid Hunspell suggestions.'),
            },
          )
        else
          throw const FormatException('Invalid Hunspell result.'),
    ];
  }

  OfficeProofingResult _result(
    OfficeProofingRequest request,
    OfficeProofingStatus status,
    String? message,
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
