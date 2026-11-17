import 'dart:async';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import 'support.dart';

final class _Transport implements GectorTransport {
  _Transport(this.handler);
  final Future<GectorDecodedText> Function(GectorCheckRequest) handler;
  bool disposed = false;
  int calls = 0;
  @override
  Future<GectorDecodedText> check(GectorCheckRequest request) {
    calls++;
    return handler(request);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  late GectorConfiguration config;
  setUpAll(() async {
    config = (await TestBundle.load()).bundle.configuration;
  });
  OfficeProofingRequest request(
    String text, {
    String language = 'de-DE',
    int offset = 0,
  }) => OfficeProofingRequest(
    documentId: 'doc',
    blockId: 'p',
    revision: 7,
    text: text,
    language: language,
    startOffset: offset,
  );
  GectorDecodedText result(
    String text,
    List<GectorEdit> edits, {
    bool guarded = true,
    GectorStopReason reason = GectorStopReason.stable,
  }) => GectorDecodedText(
    original: text,
    corrected: GectorSourceText(text, config).apply(edits),
    edits: edits,
    passes: const <GectorPass>[],
    stopReason: reason,
    guarded: guarded,
  );

  test(
    'result retains original request identity and adds UTF-16 base once',
    () async {
      const text = '😊 mude';
      final transport = _Transport(
        (r) async => result(r.text, const <GectorEdit>[
          GectorEdit(start: 3, end: 7, original: 'mude', replacement: 'müde'),
        ]),
      );
      final provider = GectorProofingProvider.withTransport(
        transport: transport,
        configuration: config,
      );
      final input = request(text, offset: 120);
      final report = await OfficeProofingService(
        providers: <OfficeProofingProvider>[provider],
      ).check(input);
      expect(report.complete, isTrue);
      expect(identical(report.results.single.request, input), isTrue);
      expect(report.findings.single.start, 123);
      expect(report.findings.single.end, 127);
      expect(report.findings.single.originalText, 'mude');
      expect(report.findings.single.replacements, <String>['müde']);
      await provider.dispose();
    },
  );

  test('de-AT and de-CH remain explicitly unsupported', () async {
    final transport = _Transport(
      (r) async => result(r.text, const <GectorEdit>[]),
    );
    final provider = GectorProofingProvider.withTransport(
      transport: transport,
      configuration: config,
    );
    expect(
      (await provider.check(request('Grüezi.', language: 'de-CH'))).status,
      OfficeProofingStatus.unsupported,
    );
    expect(
      (await provider.check(request('Servus.', language: 'de-AT'))).status,
      OfficeProofingStatus.unsupported,
    );
    expect(transport.calls, 0);
    expect(provider.supportsLanguage('de_DE'), isTrue);
    await provider.dispose();
  });

  test(
    'links, code, personal words and grapheme-interior edits are suppressed',
    () async {
      const text = 'https://mude.de `mude` Mude Mu\u0308de';
      final transport = _Transport(
        (r) async => result(r.text, const <GectorEdit>[
          GectorEdit(start: 8, end: 12, original: 'mude', replacement: 'müde'),
          GectorEdit(start: 17, end: 21, original: 'mude', replacement: 'müde'),
          GectorEdit(start: 23, end: 27, original: 'Mude', replacement: 'Müde'),
          GectorEdit(start: 28, end: 30, original: 'Mu', replacement: 'Mü'),
        ]),
      );
      final vocabulary = OfficeProofingVocabulary()..addWord('Mude');
      final provider = GectorProofingProvider.withTransport(
        transport: transport,
        configuration: config,
        vocabulary: vocabulary,
      );
      final checked = await provider.check(request(text));
      expect(checked.status, OfficeProofingStatus.success);
      expect(checked.findings, isEmpty);
      await provider.dispose();
    },
  );

  test('vocabulary changes during work invalidate the result', () async {
    final pending = Completer<GectorDecodedText>();
    final transport = _Transport((r) => pending.future);
    final vocabulary = OfficeProofingVocabulary();
    final provider = GectorProofingProvider.withTransport(
      transport: transport,
      configuration: config,
      vocabulary: vocabulary,
    );
    final checked = provider.check(request('mude'));
    vocabulary.addWord('mude');
    pending.complete(result('mude', const <GectorEdit>[]));
    expect((await checked).status, OfficeProofingStatus.failed);
    expect(provider.configurationRevision, vocabulary.revision);
    await provider.dispose();
  });

  test(
    'unguarded and incomplete outputs do not become successful empty reports',
    () async {
      for (final invalid in <GectorDecodedText>[
        result('mude', const <GectorEdit>[], guarded: false),
        result(
          'mude',
          const <GectorEdit>[],
          reason: GectorStopReason.passLimit,
        ),
        result('mude', const <GectorEdit>[], reason: GectorStopReason.cycle),
      ]) {
        final provider = GectorProofingProvider.withTransport(
          transport: _Transport((r) async => invalid),
          configuration: config,
        );
        final checked = await provider.check(request('mude'));
        expect(checked.status, OfficeProofingStatus.failed);
        expect(checked.findings, isEmpty);
        await provider.dispose();
      }
    },
  );

  test('deadline failure disposes worker and prevents later checks', () async {
    final transport = _Transport((r) => Completer<GectorDecodedText>().future);
    final provider = GectorProofingProvider.withTransport(
      transport: transport,
      configuration: config,
      timeout: const Duration(milliseconds: 10),
    );
    expect(
      (await provider.check(request('mude'))).status,
      OfficeProofingStatus.failed,
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.disposed, isTrue);
    expect(
      (await provider.check(request('mude'))).status,
      OfficeProofingStatus.unavailable,
    );
  });

  test(
    'transport edits must reproduce its corrected text before filtering',
    () async {
      final malformed = GectorDecodedText(
        original: 'Du ist hier.',
        corrected: 'Du bist hier.',
        edits: const <GectorEdit>[],
        passes: const <GectorPass>[],
        stopReason: GectorStopReason.stable,
        guarded: true,
      );
      final provider = GectorProofingProvider.withTransport(
        transport: _Transport((r) async => malformed),
        configuration: config,
      );
      expect(
        (await provider.check(request('Du ist hier.'))).status,
        OfficeProofingStatus.failed,
      );
      await provider.dispose();
    },
  );
}
