import 'dart:async';
import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_harper/quds_proofing_harper.dart';
import 'package:test/test.dart';

final class _Transport implements HarperTransport {
  _Transport(this.answer, {this.onDispose});
  final Future<String> Function(String) answer;
  final Future<void> Function()? onDispose;
  bool disposed = false;
  int calls = 0;
  @override
  Future<String> check(String request) {
    calls++;
    return answer(request);
  }

  @override
  Future<void> dispose() {
    disposed = true;
    return onDispose?.call() ?? Future<void>.value();
  }
}

OfficeProofingRequest request({String language = 'en-US'}) =>
    OfficeProofingRequest(
      documentId: 'document',
      blockId: 'paragraph',
      revision: 7,
      text: '😀 This is an test.',
      language: language,
      startOffset: 5,
    );

String response({int start = 10, int end = 12}) => jsonEncode({
  'status': 'success',
  'offsets': 'unicode-scalar',
  'findings': [
    {
      'start': start,
      'end': end,
      'rule': 'harper.AnA',
      'category': 'grammar',
      'message': 'Use a before a consonant.',
      'replacements': ['a'],
    },
  ],
});

void main() {
  test('rejects zero and negative timeouts before using a transport', () {
    final transport = _Transport((_) async => response());
    for (final timeout in [Duration.zero, const Duration(microseconds: -1)]) {
      expect(
        () => HarperProofingProvider(transport: transport, timeout: timeout),
        throwsArgumentError,
      );
    }
    expect(transport.calls, 0);
    expect(transport.disposed, isFalse);
  });

  test(
    'converts scalar offsets after emoji and preserves segment identity',
    () async {
      final provider = HarperProofingProvider(
        transport: _Transport((_) async => response()),
      );
      final result = await provider.check(request());
      expect(result.status, OfficeProofingStatus.success);
      final finding = result.findings.single;
      expect(finding.start, 16);
      expect(finding.end, 18);
      expect(finding.originalText, 'an');
      expect(finding.replacements, ['a']);
      expect(finding.revision, 7);
      expect(finding.documentId, 'document');
    },
  );

  test('unsupported language never invokes English backend', () async {
    final transport = _Transport((_) async => response());
    final result = await HarperProofingProvider(
      transport: transport,
    ).check(request(language: 'de-DE'));
    expect(result.status, OfficeProofingStatus.unsupported);
    expect(transport.calls, 0);
  });

  test(
    'Latin and Unicode locale aliases dispatch the correct English dialect',
    () async {
      final List<String> languages = <String>[];
      final _Transport transport = _Transport((String payload) async {
        final Map<String, Object?> decoded =
            jsonDecode(payload) as Map<String, Object?>;
        languages.add(decoded['language']! as String);
        return response();
      });
      final HarperProofingProvider provider = HarperProofingProvider(
        transport: transport,
      );
      addTearDown(provider.dispose);
      const Map<String, String> aliases = <String, String>{
        'en-Latn': 'en-US',
        'en-Latn-GB-u-nu-latn': 'en-GB',
        'EN_latn_CA': 'en-CA',
        'en-AU-u-ca-gregory': 'en-AU',
        'en-Latn-IN': 'en-IN',
      };
      for (final MapEntry<String, String> alias in aliases.entries) {
        expect(provider.supportsLanguage(alias.key), isTrue);
        final OfficeProofingResult result = await provider.check(
          request(language: alias.key),
        );
        expect(result.status, OfficeProofingStatus.success, reason: alias.key);
        expect(languages.last, alias.value);
        expect(result.findings.single.originalText, 'an');
        expect(result.findings.single.start, 16);
      }
      expect(transport.calls, aliases.length);
    },
  );

  test(
    'unknown dialects, variants and scripts never become American English',
    () async {
      final _Transport transport = _Transport((_) async => response());
      final HarperProofingProvider provider = HarperProofingProvider(
        transport: transport,
      );
      addTearDown(provider.dispose);
      for (final String tag in <String>[
        'en-NZ',
        'en-ZZ',
        'en-Cyrl-US',
        'en-US-1901',
        'en-GB-oxendict',
        'en-US-x-private',
        'en-US-u',
        'en-US-u-12',
        'en--US',
        'de-1901',
        'de-Latn-DE-1996',
      ]) {
        expect(provider.supportsLanguage(tag), isFalse, reason: tag);
        expect(
          (await provider.check(request(language: tag))).status,
          OfficeProofingStatus.unsupported,
          reason: tag,
        );
      }
      expect(transport.calls, 0);
    },
  );

  test('unavailable backend differs from a successful clean result', () async {
    final absent = HarperProofingProvider(
      transport: _Transport(
        (_) async => throw const HarperUnavailableException('missing'),
      ),
    );
    expect(
      (await absent.check(request())).status,
      OfficeProofingStatus.unavailable,
    );
    final clean = HarperProofingProvider(
      transport: _Transport(
        (_) async =>
            '{"status":"success","offsets":"unicode-scalar","findings":[]}',
      ),
    );
    final result = await clean.check(request());
    expect(result.status, OfficeProofingStatus.success);
    expect(result.findings, isEmpty);
  });

  test(
    'rejects invalid offset, format and category instead of clean success',
    () async {
      for (final raw in [
        response(end: 9999),
        'not json',
        response().replaceFirst('grammar', 'unrecognized'),
      ]) {
        final provider = HarperProofingProvider(
          transport: _Transport((_) async => raw),
        );
        final result = await provider.check(request());
        expect(result.status, OfficeProofingStatus.failed);
        expect(result.findings, isEmpty);
      }
    },
  );

  test('timeout disposes worker and future checks are unavailable', () async {
    final transport = _Transport((_) => Completer<String>().future);
    final provider = HarperProofingProvider(
      transport: transport,
      timeout: const Duration(milliseconds: 10),
    );
    expect(
      (await provider.check(request())).status,
      OfficeProofingStatus.failed,
    );
    expect(transport.disposed, isTrue);
    expect(
      (await provider.check(request())).status,
      OfficeProofingStatus.unavailable,
    );
  });

  test('disposal rejects an already in-flight result', () async {
    final gate = Completer<String>();
    final provider = HarperProofingProvider(
      transport: _Transport((_) => gate.future),
    );
    final pending = provider.check(request());
    await provider.dispose();
    gate.complete(response());
    expect((await pending).status, OfficeProofingStatus.unavailable);
  });

  test('timeout result survives throwing and stuck disposal', () async {
    for (final onDispose in <Future<void> Function()>[
      () => throw StateError('broken shutdown'),
      () async => throw StateError('broken async shutdown'),
      () => Completer<void>().future,
    ]) {
      final transport = _Transport(
        (_) => Completer<String>().future,
        onDispose: onDispose,
      );
      final provider = HarperProofingProvider(
        transport: transport,
        timeout: const Duration(milliseconds: 10),
      );
      final result = await provider
          .check(request())
          .timeout(const Duration(seconds: 1));
      expect(result.status, OfficeProofingStatus.failed);
      expect(transport.disposed, isTrue);
      expect(
        (await provider.check(request())).status,
        OfficeProofingStatus.unavailable,
      );
    }
  });
}
