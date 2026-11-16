import 'dart:async';
import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_harper/quds_proofing_harper.dart';
import 'package:test/test.dart';

final class _ReplyTransport implements HarperTransport {
  _ReplyTransport(this.reply);

  final Future<String> Function(String request) reply;
  int calls = 0;

  @override
  Future<String> check(String request) {
    calls++;
    return reply(request);
  }

  @override
  Future<void> dispose() async {}
}

OfficeProofingRequest _request(
  String text, {
  String language = 'en-US',
  int startOffset = 0,
  Set<String> ignoredRuleIds = const <String>{},
}) => OfficeProofingRequest(
  documentId: 'document',
  blockId: 'paragraph',
  revision: 9,
  text: text,
  language: language,
  startOffset: startOffset,
  ignoredRuleIds: ignoredRuleIds,
);

Map<String, Object?> _finding(
  int start,
  int end, {
  String category = 'spelling',
  String rule = 'harper.TestSpelling',
  List<String> replacements = const <String>['replacement'],
}) => <String, Object?>{
  'start': start,
  'end': end,
  'rule': rule,
  'category': category,
  'message': 'Review this text.',
  'replacements': replacements,
};

String _response(List<Map<String, Object?>> findings) =>
    jsonEncode(<String, Object?>{
      'status': 'success',
      'offsets': 'unicode-scalar',
      'findings': findings,
    });

void main() {
  test(
    'English code findings do not hide ordinary prose corrections',
    () async {
      final provider = HarperProofingProvider(
        transport: _ReplyTransport(
          (_) async => _response([
            _finding(3, 5, category: 'grammar', rule: 'harper.AnA'),
            _finding(7, 9, category: 'grammar', rule: 'harper.AnA'),
          ]),
        ),
      );
      addTearDown(provider.dispose);
      final report = await OfficeProofingService(
        providers: [provider],
      ).check(_request('😀 `an` an test.', startOffset: 3));
      expect(report.complete, isTrue);
      expect(report.findings.single.originalText, 'an');
      expect(report.findings.single.start, 11);
      expect(report.findings.single.end, 13);
    },
  );

  test(
    'protected English spans use original source after soft hyphens',
    () async {
      for (final text in [
        '`sp\u00adeling`',
        '``sp\u00adeling `nested` words``',
        '```sp\u00adeling\nwords```',
        'HTTPS://example.invalid/sp\u00adeling',
        'müller+speling@büro.example',
      ]) {
        final provider = HarperProofingProvider(
          transport: _ReplyTransport(
            (_) async => _response([
              _finding(0, text.replaceAll('\u00ad', '').runes.length),
            ]),
          ),
        );
        addTearDown(provider.dispose);
        final result = await provider.check(_request(text));
        expect(
          result.status,
          OfficeProofingStatus.success,
          reason: result.message,
        );
        expect(result.findings, isEmpty, reason: text);
      }
    },
  );

  test(
    'unmatched backticks and punctuation following links remain checkable',
    () async {
      for (final text in ['`an', '``an`']) {
        final start = text.indexOf('an');
        final provider = HarperProofingProvider(
          transport: _ReplyTransport(
            (_) async =>
                _response([_finding(start, start + 2, category: 'grammar')]),
          ),
        );
        addTearDown(provider.dispose);
        expect(
          (await provider.check(_request(text))).findings.single.originalText,
          'an',
        );
      }
      const url = 'https://example.invalid';
      final provider = HarperProofingProvider(
        transport: _ReplyTransport(
          (_) async =>
              _response([_finding(url.length, url.length, category: 'style')]),
        ),
      );
      addTearDown(provider.dispose);
      final result = await provider.check(_request(url));
      expect(result.findings.single.start, url.length);
      expect(result.findings.single.originalText, isEmpty);
    },
  );

  test('code protection never conceals malformed backend ranges', () async {
    final provider = HarperProofingProvider(
      transport: _ReplyTransport((_) async => _response([_finding(1, 100)])),
    );
    addTearDown(provider.dispose);
    final result = await provider.check(_request('`code`'));
    expect(result.status, OfficeProofingStatus.failed);
    expect(result.findings, isEmpty);
  });

  test(
    'backend sees complete English words and findings retain Word offsets',
    () async {
      const source = '😀 hy\u00adphen an test.';
      final transport = _ReplyTransport((raw) async {
        final decoded = jsonDecode(raw) as Map<String, Object?>;
        expect(decoded['text'], '😀 hyphen an test.');
        expect(decoded['language'], 'en-US');
        return _response(<Map<String, Object?>>[
          _finding(2, 8),
          _finding(9, 11, category: 'grammar', rule: 'harper.AnA'),
        ]);
      });
      final provider = HarperProofingProvider(transport: transport);
      final service = OfficeProofingService(
        providers: <OfficeProofingProvider>[provider],
      );
      addTearDown(service.dispose);
      final request = _request(source, startOffset: 7);
      final report = await service.check(request);
      expect(report.complete, isTrue);
      expect(report.findings, hasLength(2));
      expect(report.findings.first.start, 10);
      expect(report.findings.first.end, 17);
      expect(report.findings.first.originalText, 'hy\u00adphen');
      expect(report.findings.last.start, 18);
      expect(report.findings.last.end, 20);
      expect(report.findings.last.originalText, 'an');
      expect(report.findings.last.revision, 9);
      expect(request.text, source);
    },
  );

  test(
    'zero-length corrections beside controls keep source insertion points',
    () async {
      final provider = HarperProofingProvider(
        transport: _ReplyTransport(
          (_) async => _response(<Map<String, Object?>>[
            _finding(1, 1, category: 'style', replacements: <String>[' ']),
            _finding(2, 2, category: 'style', replacements: <String>['.']),
          ]),
        ),
      );
      addTearDown(provider.dispose);
      final report = await OfficeProofingService(
        providers: <OfficeProofingProvider>[provider],
      ).check(_request('a\u00adb', startOffset: 10));
      expect(report.complete, isTrue);
      expect(report.findings.map((finding) => finding.start), <int>[12, 13]);
      expect(report.findings.map((finding) => finding.end), <int>[12, 13]);
      expect(
        report.findings.every((finding) => finding.originalText.isEmpty),
        isTrue,
      );
    },
  );

  test(
    'partial accent findings cannot discard unrelated grammar findings',
    () async {
      final provider = HarperProofingProvider(
        transport: _ReplyTransport(
          (_) async => _response(<Map<String, Object?>>[
            _finding(0, 1),
            _finding(3, 5, category: 'grammar', rule: 'harper.AnA'),
          ]),
        ),
      );
      addTearDown(provider.dispose);
      final report = await OfficeProofingService(
        providers: <OfficeProofingProvider>[provider],
      ).check(_request('e\u0301 an test.'));
      expect(report.complete, isTrue);
      expect(report.findings.single.ruleId, 'harper.AnA');
      expect(report.findings.single.originalText, 'an');
    },
  );

  test(
    'source projection does not turn malformed backend ranges into success',
    () async {
      for (final range in <(int, int)>[(-1, 1), (2, 1), (0, 5), (5, 5)]) {
        final provider = HarperProofingProvider(
          transport: _ReplyTransport(
            (_) async =>
                _response(<Map<String, Object?>>[_finding(range.$1, range.$2)]),
          ),
        );
        addTearDown(provider.dispose);
        final result = await provider.check(_request('ab\u00adcd'));
        expect(result.status, OfficeProofingStatus.failed);
        expect(result.findings, isEmpty);
      }
    },
  );

  test(
    'shared vocabulary suppresses only spelling in its own dialect',
    () async {
      final vocabulary = OfficeProofingVocabulary(ownerId: 'account-1');
      vocabulary.addWord('Quds', language: 'en-US');
      final provider = HarperProofingProvider(
        vocabulary: vocabulary,
        transport: _ReplyTransport(
          (_) async => _response(<Map<String, Object?>>[
            _finding(0, 4),
            _finding(0, 4, category: 'grammar', rule: 'harper.TestGrammar'),
          ]),
        ),
      );
      addTearDown(provider.dispose);
      expect(provider.configurationRevision, vocabulary.revision);
      final american = await provider.check(_request('Qu\u00adds'));
      expect(american.findings.single.category, OfficeProofingCategory.grammar);
      final british = await provider.check(_request('Quds', language: 'en-GB'));
      expect(british.findings, hasLength(2));
      final revision = provider.configurationRevision;
      vocabulary.ignoreWord('Quds', language: 'en-GB');
      expect(provider.configurationRevision, greaterThan(revision));
      final ignored = await provider.check(_request('Quds', language: 'en-GB'));
      expect(ignored.findings.single.category, OfficeProofingCategory.grammar);
      vocabulary.unignoreWord('Quds', language: 'en-GB');
      expect(
        (await provider.check(_request('Quds', language: 'en-GB'))).findings,
        hasLength(2),
      );
    },
  );

  test(
    'an in-flight vocabulary change requires a fresh English check',
    () async {
      final vocabulary = OfficeProofingVocabulary();
      final gate = Completer<String>();
      final provider = HarperProofingProvider(
        vocabulary: vocabulary,
        transport: _ReplyTransport((_) => gate.future),
      );
      addTearDown(provider.dispose);
      final pending = provider.check(_request('Quds'));
      vocabulary.addWord('Quds', language: 'en-US');
      gate.complete(_response(<Map<String, Object?>>[_finding(0, 4)]));
      final stale = await pending;
      expect(stale.status, OfficeProofingStatus.failed);
      expect(stale.findings, isEmpty);
      expect(stale.message, contains('vocabulary changed'));
    },
  );

  test(
    'all supported English dialects and ignored rules survive projection',
    () async {
      for (final language in <String>[
        'en',
        'en_US',
        'en-GB',
        'en-CA',
        'en-AU',
        'en-IN',
      ]) {
        final provider = HarperProofingProvider(
          transport: _ReplyTransport((raw) async {
            final decoded = jsonDecode(raw) as Map<String, Object?>;
            expect(decoded['language'], normalizeProofingLanguage(language));
            expect(decoded['text'], 'Quds');
            expect(decoded['ignored_rules'], <String>['harper.TestSpelling']);
            return _response(<Map<String, Object?>>[_finding(0, 4)]);
          }),
        );
        addTearDown(provider.dispose);
        final result = await provider.check(
          _request(
            'Qu\u00adds',
            language: language,
            ignoredRuleIds: <String>{'harper.TestSpelling'},
          ),
        );
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, isEmpty);
      }
    },
  );

  test(
    'original source size remains bounded before projecting controls',
    () async {
      final transport = _ReplyTransport(
        (_) async => _response(<Map<String, Object?>>[]),
      );
      final provider = HarperProofingProvider(transport: transport);
      addTearDown(provider.dispose);
      final result = await provider.check(
        _request(List<String>.filled(32769, '\u00ad').join()),
      );
      expect(result.status, OfficeProofingStatus.failed);
      expect(transport.calls, 0);
    },
  );
}
