import 'dart:async';
import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';

import 'harper_transport.dart';
import 'harper_transport_stub.dart'
    if (dart.library.io) 'harper_transport_native.dart'
    if (dart.library.js_interop) 'harper_transport_web.dart'
    as platform;

/// English spelling, grammar and style via an explicitly installed local backend.
/// Native checks run in a persistent isolate; web checks run in a Web Worker.
final class HarperProofingProvider extends OfficeProofingProvider {
  HarperProofingProvider({
    String? nativeLibraryPath,
    Uri? workerUrl,
    HarperTransport? transport,
    this.timeout = const Duration(seconds: 15),
  }) : _transport =
           transport ??
           platform.createHarperTransport(
             nativeLibraryPath: nativeLibraryPath,
             workerUrl: workerUrl,
           );

  final HarperTransport _transport;
  final Duration timeout;
  bool _disposed = false;

  @override
  String get id => 'harper';

  @override
  bool supportsLanguage(String language) => const {
    'en',
    'en-US',
    'en-GB',
    'en-CA',
    'en-AU',
    'en-IN',
  }.contains(normalizeProofingLanguage(language));

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    if (_disposed) {
      return _result(
        request,
        OfficeProofingStatus.unavailable,
        'Harper has been disposed.',
      );
    }
    if (!supportsLanguage(request.language)) {
      return _result(
        request,
        OfficeProofingStatus.unsupported,
        'Harper supports English only.',
      );
    }
    if (request.text.runes.length > 32768) {
      return _result(
        request,
        OfficeProofingStatus.failed,
        'Harper segment exceeds the 32768-character limit.',
      );
    }
    try {
      final raw = await _transport
          .check(
            jsonEncode({
              'text': request.text,
              'language': normalizeProofingLanguage(request.language),
              'ignored_rules': request.ignoredRuleIds.toList(),
            }),
          )
          .timeout(timeout);
      if (_disposed) {
        return _result(
          request,
          OfficeProofingStatus.unavailable,
          'Harper has been disposed.',
        );
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?> ||
          decoded['offsets'] != 'unicode-scalar') {
        throw const FormatException(
          'Invalid Harper response or offset convention.',
        );
      }
      final status = switch (decoded['status']) {
        'success' => OfficeProofingStatus.success,
        'unsupported' => OfficeProofingStatus.unsupported,
        'unavailable' => OfficeProofingStatus.unavailable,
        'failed' => OfficeProofingStatus.failed,
        _ => throw const FormatException('Unknown Harper status.'),
      };
      final message = decoded['message'];
      if (message != null && message is! String) {
        throw const FormatException('Invalid Harper message.');
      }
      if (status != OfficeProofingStatus.success) {
        return _result(request, status, message as String?);
      }
      final rawFindings = decoded['findings'];
      if (rawFindings is! List<Object?> || rawFindings.length > 2000) {
        throw const FormatException('Invalid Harper finding list.');
      }
      final findings = <OfficeProofingFinding>[];
      for (final rawFinding in rawFindings) {
        if (rawFinding is! Map<String, Object?>) {
          throw const FormatException('Invalid Harper finding.');
        }
        final start = rawFinding['start'];
        final end = rawFinding['end'];
        final rule = rawFinding['rule'];
        final explanation = rawFinding['message'];
        final replacements = rawFinding['replacements'];
        if (start is! int ||
            end is! int ||
            start < 0 ||
            end < start ||
            rule is! String ||
            rule.isEmpty ||
            explanation is! String ||
            replacements is! List<Object?> ||
            replacements.any((r) => r is! String)) {
          throw const FormatException('Invalid Harper finding fields.');
        }
        if (request.ignoredRuleIds.contains(rule)) continue;
        final category = switch (rawFinding['category']) {
          'spelling' => OfficeProofingCategory.spelling,
          'grammar' => OfficeProofingCategory.grammar,
          'style' => OfficeProofingCategory.style,
          _ => throw const FormatException('Unknown Harper category.'),
        };
        findings.add(
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            start: scalarOffsetToUtf16(request.text, start),
            end: scalarOffsetToUtf16(request.text, end),
            ruleId: rule,
            message: explanation,
            category: category,
            replacements: replacements.cast<String>(),
          ),
        );
      }
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: status,
        findings: findings,
      );
    } on HarperUnavailableException catch (error) {
      return _result(request, OfficeProofingStatus.unavailable, error.message);
    } on TimeoutException {
      // A broken transport must not extend the deadline while shutting down.
      // dispose marks this provider unavailable before awaiting the transport.
      unawaited(Future<void>.sync(dispose).catchError((Object _) {}));
      return _result(
        request,
        OfficeProofingStatus.failed,
        'The local Harper worker timed out and was disposed.',
      );
    } on Object catch (error) {
      return _result(
        request,
        OfficeProofingStatus.failed,
        'Local Harper check failed: $error',
      );
    }
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
