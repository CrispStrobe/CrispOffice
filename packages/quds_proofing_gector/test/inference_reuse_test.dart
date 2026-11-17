import 'dart:async';
import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import 'support.dart';

String _inputKey(GectorPreparedInput input) => jsonEncode(<Object>[
  input.inputIds,
  input.attentionMask,
  input.firstSubwordIndices,
]);

/// Successful predictions are input-driven, unlike ScriptedBackend's sequence.
final class _InputBackend implements GectorDeterministicBackend {
  _InputBackend(
    this.fixtures,
    Map<String, List<String>> proposals, {
    this.artifactSha256 = 'test',
  }) : proposals = <String, List<String>>{
         for (final entry in proposals.entries)
           _keyFor(fixtures, entry.key): entry.value,
       };

  final TestBundle fixtures;
  final String artifactSha256;
  final Map<String, List<String>> proposals;
  final List<String> forwarded = <String>[];
  String? failOnInput;
  void Function()? onForward;
  int get calls => forwarded.length;

  static String _keyFor(TestBundle fixtures, String text) {
    final source = GectorSourceText(text, fixtures.bundle.configuration);
    return _inputKey(
      fixtures.bundle.tokenizer.encode(source.words(source.plain)),
    );
  }

  @override
  GectorBackendIdentity get identity => GectorBackendIdentity(
    artifactSha256: artifactSha256,
    sourceModelSha256: gectorSourceModelSha256,
  );

  @override
  Future<GectorLogits> forward(GectorPreparedInput input) {
    final key = _inputKey(input);
    forwarded.add(key);
    onForward?.call();
    if (key == failOnInput) {
      throw StateError('Injected deterministic-input failure');
    }
    return ScriptedBackend(fixtures.bundle.configuration, <List<String>>[
      proposals[key] ??
          List<String>.filled(input.firstSubwordIndices.length, r'$KEEP'),
    ]).forward(input);
  }

  @override
  Future<void> dispose() async {}
}

final class _InputBackendFactory implements GectorBackendFactory {
  const _InputBackendFactory(this.fixtures);
  final TestBundle fixtures;
  @override
  Future<GectorBackend> open(GectorModelArtifact artifact) async =>
      _InputBackend(fixtures, const {}, artifactSha256: artifact.sha256);
}

final class _DecoderTransport implements GectorTransport {
  _DecoderTransport(this.decoder);
  final GectorDecoder decoder;
  GectorDecodedText? lastResult;
  @override
  Future<GectorDecodedText> check(GectorCheckRequest request) async =>
      lastResult = await decoder.correct(
        request.text,
        personalWords: request.personalWords,
      );
  @override
  Future<void> dispose() async {}
}

void main() {
  late TestBundle fixtures;
  setUpAll(() async {
    fixtures = await TestBundle.load();
  });

  GectorDecoder decoder(
    GectorBackend backend, {
    int target = 3,
    int maximumPasses = 5,
    int maximumSegments = 32,
    int maximumTotalTokens = 4096,
    GectorInferenceReuseOptions? reuse,
    bool enabled = true,
  }) => GectorDecoder.guarded(
    configuration: fixtures.bundle.configuration,
    tokenizer: fixtures.bundle.tokenizer,
    backend: backend,
    guards: GectorGermanGuards.fromJson(
      fixtures.bundle.guardsJson,
      configuration: fixtures.bundle.configuration,
      lexicon: GectorWordSetLexicon(const <String>[
        'Buch',
        'Haus',
        'haus',
        'sind',
        'zufrieden',
      ]),
    ),
    options: GectorDecodeOptions(
      maximumPasses: maximumPasses,
      segmentation: GectorSegmentationOptions(
        targetTokens: target,
        maximumSegments: maximumSegments,
        maximumTotalTokens: maximumTotalTokens,
        inferenceReuse: enabled ? reuse ?? GectorInferenceReuseOptions() : null,
      ),
    ),
  );

  test(
    'reuse is explicit, bounded and requires a deterministic capability',
    () {
      expect(GectorSegmentationOptions().inferenceReuse, isNull);
      for (final value in <int>[0, 129]) {
        expect(
          () => GectorInferenceReuseOptions(maximumCachedInputs: value),
          throwsArgumentError,
        );
      }
      for (final value in <int>[1, 4097]) {
        expect(
          () => GectorInferenceReuseOptions(maximumCachedTokens: value),
          throwsArgumentError,
        );
      }
      expect(
        () => decoder(ScriptedBackend(fixtures.bundle.configuration, const [])),
        throwsArgumentError,
      );
      expect(
        () => GectorDecoder.reference(
          configuration: fixtures.bundle.configuration,
          tokenizer: fixtures.bundle.tokenizer,
          backend: _InputBackend(fixtures, const {}),
          options: GectorDecodeOptions(
            segmentation: GectorSegmentationOptions(
              inferenceReuse: GectorInferenceReuseOptions(),
            ),
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'identical clean inputs reuse raw tags and record actual forwards',
    () async {
      final backend = _InputBackend(fixtures, const {});
      final result = await decoder(backend).correct('Buch. Buch! Buch?');
      expect(result.corrected, 'Buch. Buch! Buch?');
      expect(result.complete, isTrue);
      expect(result.edits, isEmpty);
      expect(result.segmentCount, 3);
      expect(result.passes, hasLength(3));
      expect(backend.calls, 1);
      expect(result.forwardCount, 1);
      expect(result.reusedPassCount, 2);
      expect(result.forwardTokens, 3);
      expect(result.decodedTokens, 9);
      expect(result.passes.map((p) => p.sourceStart), <int>[0, 6, 12]);
      expect(
        result.passes
            .skip(1)
            .every((p) => p.reusedInference && p.inferenceMicroseconds == 0),
        isTrue,
      );
      expect(() => result.passes.last.tags.clear(), throwsUnsupportedError);
    },
  );

  test(
    'deterministic capability alone leaves default forwards unchanged',
    () async {
      final backend = _InputBackend(fixtures, const {});
      final result = await decoder(
        backend,
        enabled: false,
      ).correct('Buch. Buch. Buch.');
      expect(backend.calls, 3);
      expect(result.forwardCount, 3);
      expect(result.reusedPassCount, 0);
      expect(result.forwardTokens, result.decodedTokens);
    },
  );

  test(
    'cached corrections retain every occurrence and its UTF-16 source',
    () async {
      const prefix = '  😊 Gut.\r\n';
      const text = '${prefix}Wir ist zufrieden.\r\nWir ist zufrieden!  ';
      final backend = _InputBackend(fixtures, const {
        'Wir ist zufrieden.': <String>[
          r'$KEEP',
          r'$KEEP',
          r'$TRANSFORM_VERB_P3S_P3P',
          r'$KEEP',
        ],
      });
      final result = await decoder(backend, target: 5).correct(text);
      expect(
        result.corrected,
        '${prefix}Wir sind zufrieden.\r\nWir sind zufrieden!  ',
      );
      expect(
        result.edits.map((e) => (e.start, e.end, e.original, e.replacement)),
        <(int, int, String, String)>[
          (prefix.length + 4, prefix.length + 7, 'ist', 'sind'),
          (
            text.lastIndexOf('Wir') + 4,
            text.lastIndexOf('Wir') + 7,
            'ist',
            'sind',
          ),
        ],
      );
      expect(result.reusedPassCount, 2);
      expect(backend.calls, 3);
      expect(
        GectorSourceText(
          text,
          fixtures.bundle.configuration,
        ).apply(result.edits),
        result.corrected,
      );
    },
  );

  test(
    'cached START proposals are guarded again at later source positions',
    () async {
      final backend = _InputBackend(fixtures, const {
        'Buch.': <String>[r'$APPEND_sind', r'$KEEP'],
      });
      final result = await decoder(backend).correct('Buch. Buch.');
      expect(result.corrected, 'sind Buch. Buch.');
      expect(result.edits, hasLength(1));
      expect(result.edits.single.start, 0);
      expect(result.reusedPassCount, 1);
      expect(backend.calls, 2);
    },
  );

  test(
    'cached duplicate proposals retain the later case-differing pair',
    () async {
      final backend = _InputBackend(fixtures, const {
        'Haus haus.': <String>[r'$KEEP', r'$DELETE', r'$KEEP'],
      });
      final result = await decoder(
        backend,
        target: 4,
      ).correct('Haus haus. Haus haus.');
      expect(result.corrected, 'haus. Haus haus.');
      expect(result.edits, hasLength(1));
      expect(result.reusedPassCount, 1);
      expect(backend.calls, 2);
    },
  );

  test(
    'request-local cache never retains previous personal-word decisions',
    () async {
      final backend = _InputBackend(fixtures, const {
        'Wir ist zufrieden.': <String>[
          r'$KEEP',
          r'$KEEP',
          r'$TRANSFORM_VERB_P3S_P3P',
          r'$KEEP',
        ],
      });
      final checker = decoder(backend, target: 5);
      const text = 'Wir ist zufrieden. Wir ist zufrieden.';
      final first = await checker.correct(text);
      expect(first.corrected, 'Wir sind zufrieden. Wir sind zufrieden.');
      expect(backend.calls, 2);
      final second = await checker.correct(
        text,
        personalWords: const <String>{'ist'},
      );
      expect(second.corrected, text);
      expect(second.edits, isEmpty);
      expect(second.forwardCount, 1);
      expect(second.reusedPassCount, 1);
      expect(backend.calls, 3);
    },
  );

  test(
    'entry and token cache limits fall back to ordinary inference',
    () async {
      for (final reuse in <GectorInferenceReuseOptions>[
        GectorInferenceReuseOptions(maximumCachedInputs: 1),
        GectorInferenceReuseOptions(maximumCachedTokens: 3),
      ]) {
        final backend = _InputBackend(fixtures, const {});
        const text = 'Buch. Haus. Haus. Buch.';
        final result = await decoder(backend, reuse: reuse).correct(text);
        expect(result.corrected, text);
        expect(result.complete, isTrue);
        expect(backend.calls, 3);
        expect(result.reusedPassCount, 1);
      }
      final backend = _InputBackend(fixtures, const {});
      final result = await decoder(
        backend,
        reuse: GectorInferenceReuseOptions(maximumCachedTokens: 2),
      ).correct('Buch. Buch.');
      expect(result.complete, isTrue);
      expect(backend.calls, 2);
      expect(result.reusedPassCount, 0);
    },
  );

  test(
    'different source words sharing an UNK ID do not share cached tags',
    () async {
      final first = List<String>.filled(101, 'A').join();
      final second = List<String>.filled(101, 'B').join();
      expect(
        _InputBackend._keyFor(fixtures, first),
        _InputBackend._keyFor(fixtures, second),
      );
      final backend = _InputBackend(fixtures, const {});
      final text = '$first. $second.';
      final result = await decoder(backend).correct(text);
      expect(result.corrected, text);
      expect(result.segmentCount, 2);
      expect(result.reusedPassCount, 0);
      expect(backend.calls, 2);
    },
  );

  test(
    'duplicate input still consumes complete original admission budgets',
    () async {
      for (final limits in <(int, int)>[(1, 4096), (32, 5)]) {
        final backend = _InputBackend(fixtures, const {});
        await expectLater(
          decoder(
            backend,
            maximumSegments: limits.$1,
            maximumTotalTokens: limits.$2,
          ).correct('Buch. Buch.'),
          throwsA(isA<GectorCapacityException>()),
        );
        expect(backend.calls, 0);
      }
    },
  );

  test(
    'late invalid source still fails preflight before any forward',
    () async {
      for (final text in <String>[
        'Buch. Buch. \ud800',
        'Buch. Buch. ${List<String>.filled(520, 'Haus').join(' ')}.',
      ]) {
        final backend = _InputBackend(fixtures, const {});
        await expectLater(
          decoder(backend).correct(text),
          throwsA(isA<Exception>()),
        );
        expect(backend.calls, 0);
      }
    },
  );

  test('cache hits yield so later cancellation remains observable', () async {
    final backend = _InputBackend(fixtures, const {});
    var phase = 0;
    var checksDuringHit = 0;
    backend.onForward = () {
      Timer.run(() {
        phase = 1;
        Timer.run(() => phase = 2);
      });
    };
    await expectLater(
      decoder(backend).correct(
        'Buch. Buch. Buch. Buch.',
        isCancelled: () {
          if (phase == 1) checksDuringHit++;
          return phase == 2;
        },
      ),
      throwsA(isA<GectorCancelledException>()),
    );
    expect(checksDuringHit, greaterThan(0));
    expect(backend.calls, 1);
  });

  test(
    'a late native failure after hits exposes no partial provider edits',
    () async {
      final backend = _InputBackend(fixtures, const {
        'Wir ist zufrieden.': <String>[
          r'$KEEP',
          r'$KEEP',
          r'$TRANSFORM_VERB_P3S_P3P',
          r'$KEEP',
        ],
      })..failOnInput = _InputBackend._keyFor(fixtures, 'Haus.');
      final provider = GectorProofingProvider.withTransport(
        transport: _DecoderTransport(decoder(backend, target: 5)),
        configuration: fixtures.bundle.configuration,
      );
      final result = await provider.check(
        OfficeProofingRequest(
          documentId: 'reuse-test',
          blockId: 'failure',
          revision: 1,
          text: 'Wir ist zufrieden. Wir ist zufrieden. Haus.',
          language: 'de-DE',
        ),
      );
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.findings, isEmpty);
      expect(backend.calls, 3);
      await provider.dispose();
    },
  );

  test('a late cycle after reused corrections discards every edit', () async {
    final backend = _InputBackend(fixtures, const {
      'Wir ist zufrieden.': <String>[
        r'$KEEP',
        r'$KEEP',
        r'$TRANSFORM_VERB_P3S_P3P',
        r'$KEEP',
      ],
      'Buch.': <String>[r'$KEEP', r'$REPLACE_Haus'],
      'Haus.': <String>[r'$KEEP', r'$REPLACE_Buch'],
    });
    const text = 'Wir ist zufrieden. Wir ist zufrieden. Buch.';
    final result = await decoder(backend, target: 5).correct(text);
    expect(result.stopReason, GectorStopReason.cycle);
    expect(result.corrected, text);
    expect(result.edits, isEmpty);
    expect(result.reusedPassCount, 2);
  });

  test('a late pass limit after a cache hit remains incomplete', () async {
    final backend = _InputBackend(fixtures, const {
      'Buch.': <String>[r'$KEEP', r'$REPLACE_Haus'],
    });
    const text = 'Gut. Gut. Buch.';
    final result = await decoder(backend, maximumPasses: 1).correct(text);
    expect(result.stopReason, GectorStopReason.passLimit);
    expect(result.corrected, text);
    expect(result.edits, isEmpty);
    expect(result.reusedPassCount, 1);
    expect(backend.calls, 2);
  });

  test(
    'actual forward budget excludes reuse while logical work is retained',
    () async {
      final backend = _InputBackend(fixtures, const {
        'Buch.': <String>[r'$KEEP', r'$APPEND_sind'],
      });
      final result = await decoder(
        backend,
        maximumPasses: 2,
        maximumTotalTokens: 6,
      ).correct('Buch. Buch.');
      expect(result.complete, isTrue);
      expect(result.corrected, 'Buch sind. Buch sind.');
      expect(result.forwardTokens, 7);
      expect(result.decodedTokens, 14);
      expect(result.reusedPassCount, 2);
      expect(backend.calls, 2);
    },
  );

  test(
    'unique expansion still cannot escape the actual forward budget',
    () async {
      final backend = _InputBackend(fixtures, const {
        'Buch.': <String>[r'$KEEP', r'$APPEND_sind'],
        'Haus.': <String>[r'$KEEP', r'$APPEND_sind'],
      });
      await expectLater(
        decoder(
          backend,
          maximumPasses: 2,
          maximumTotalTokens: 6,
        ).correct('Buch. Haus.'),
        throwsA(isA<GectorCapacityException>()),
      );
      expect(backend.calls, 3);
    },
  );

  test(
    'real worker transports reuse policy and per-source diagnostics',
    () async {
      final worker = await startGectorWorker(
        bundle: fixtures.bundle,
        backendFactory: _InputBackendFactory(fixtures),
        lexiconFactory: GectorWordSetLexiconFactory(const <String>[]),
        options: GectorDecodeOptions(
          segmentation: GectorSegmentationOptions(
            targetTokens: 3,
            inferenceReuse: GectorInferenceReuseOptions(),
          ),
        ),
      );
      addTearDown(worker.dispose);
      for (var request = 0; request < 2; request++) {
        final result = await worker.check(
          GectorCheckRequest(text: 'Buch. Buch.', key: 'reuse-worker-$request'),
        );
        expect(result.corrected, 'Buch. Buch.');
        expect(result.forwardCount, 1);
        expect(result.reusedPassCount, 1);
        expect(result.passes.map((pass) => pass.sourceStart), <int>[0, 6]);
      }
    },
  );

  test(
    'provider rechecks protected text and adds document offsets after reuse',
    () async {
      final backend = _InputBackend(fixtures, const {
        'Wir ist zufrieden.': <String>[
          r'$KEEP',
          r'$KEEP',
          r'$TRANSFORM_VERB_P3S_P3P',
          r'$KEEP',
        ],
        'Code `Wir ist zufrieden.` hier.': <String>[
          r'$KEEP',
          r'$KEEP',
          r'$KEEP',
          r'$KEEP',
          r'$TRANSFORM_VERB_P3S_P3P',
          r'$KEEP',
          r'$KEEP',
          r'$KEEP',
          r'$KEEP',
        ],
      });
      final transport = _DecoderTransport(decoder(backend, target: 5));
      final provider = GectorProofingProvider.withTransport(
        transport: transport,
        configuration: fixtures.bundle.configuration,
      );
      addTearDown(provider.dispose);
      const text =
          '😊 Gut.\r\nWir ist zufrieden. Wir ist zufrieden. Code `Wir ist zufrieden.` hier.';
      final result = await provider.check(
        OfficeProofingRequest(
          documentId: 'reuse-test',
          blockId: 'protected',
          revision: 1,
          text: text,
          language: 'de-DE',
          startOffset: 120,
        ),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(transport.lastResult!.reusedPassCount, 2);
      expect(transport.lastResult!.edits, hasLength(3));
      expect(result.findings, hasLength(2));
      expect(
        result.findings.map(
          (f) => (f.start, f.end, f.originalText, f.replacements.single),
        ),
        <(int, int, String, String)>[
          (120 + text.indexOf('ist'), 123 + text.indexOf('ist'), 'ist', 'sind'),
          (
            120 + text.indexOf('ist', text.indexOf('ist') + 1),
            123 + text.indexOf('ist', text.indexOf('ist') + 1),
            'ist',
            'sind',
          ),
        ],
      );
    },
  );
}
