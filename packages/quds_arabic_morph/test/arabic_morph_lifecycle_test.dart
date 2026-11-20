import 'dart:async';

import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _database = MorphDatabaseFiles(
  camelMorphMsaProofingBin,
  manifestPath: 'controlled-database',
);
const _model = MorphDatabaseFiles(
  camelMorphMsaDisambig,
  manifestPath: 'controlled-model',
);

final class _ControlledTransport implements ArabicMorphTransport {
  Completer<void>? databaseGate;
  Completer<void>? modelGate;
  Completer<void>? unloadGate;
  Completer<void>? readingsGate;
  final databaseStarted = Completer<void>();
  final modelStarted = Completer<void>();
  final unloadStarted = Completer<void>();
  final readingsStarted = Completer<void>();
  final events = <String>[];
  int databaseOpens = 0;
  int modelOpens = 0;
  int readingCalls = 0;
  bool failModel = false;
  bool failUnload = false;
  bool disposed = false;

  @override
  Future<Map<String, Object?>> open(MorphDatabase database) async {
    databaseOpens++;
    events.add('database');
    if (!databaseStarted.isCompleted) databaseStarted.complete();
    await databaseGate?.future;
    return {'variant': 'controlled'};
  }

  @override
  Future<Map<String, Object?>> openDisambiguator(MorphDatabase model) async {
    modelOpens++;
    events.add('model-$modelOpens');
    if (!modelStarted.isCompleted) modelStarted.complete();
    await modelGate?.future;
    if (failModel) throw StateError('controlled model failure');
    return {'generation': modelOpens};
  }

  @override
  Future<void> unloadDisambiguator() async {
    events.add('unload-start');
    if (!unloadStarted.isCompleted) unloadStarted.complete();
    await unloadGate?.future;
    if (failUnload) {
      throw const ArabicMorphUnavailableException('worker stopped');
    }
    events.add('unload-end');
  }

  @override
  Future<List<List<ArabicAnalysis>?>> analyze(List<String> words) async => [
    for (final word in words)
      [
        {'lex': word, 'pos': 'noun'},
      ],
  ];

  @override
  Future<List<List<ArabicContextReading>>> disambiguate(
    List<List<String>> sentences,
  ) async {
    readingCalls++;
    final generation = modelOpens;
    if (!readingsStarted.isCompleted) readingsStarted.complete();
    await readingsGate?.future;
    return [
      for (final sentence in sentences)
        [
          for (final word in sentence)
            ArabicContextReading(
              [
                {'lex': '$word-$generation', 'pos': 'noun'},
              ],
              const [1.0],
              const [0],
            ),
        ],
    ];
  }

  @override
  Future<void> dispose() async => disposed = true;
}

CamelArabicMorphology _morphology(
  _ControlledTransport transport, {
  bool constructorModel = true,
}) => CamelArabicMorphology(
  database: _database,
  disambiguator: constructorModel ? _model : null,
  transport: transport,
);

void main() {
  for (final explicitFirst in [false, true]) {
    test(
      'constructor and explicit loads finish, explicit first=$explicitFirst',
      () async {
        final transport = _ControlledTransport()
          ..databaseGate = Completer<void>();
        final morphology = _morphology(transport);
        addTearDown(morphology.dispose);
        final first = explicitFirst
            ? morphology.loadDisambiguator(_model)
            : morphology.load();
        await transport.databaseStarted.future;
        final second = explicitFirst
            ? morphology.load()
            : morphology.loadDisambiguator(_model);
        transport.databaseGate!.complete();
        await Future.wait([first, second]).timeout(const Duration(seconds: 2));
        expect(morphology.isAvailable, isTrue);
        expect(morphology.canDisambiguate, isTrue);
        expect(transport.databaseOpens, 1);
        expect(transport.modelOpens, 1);
      },
    );
  }

  test(
    'unload preserves analysis and discards cached model readings',
    () async {
      final transport = _ControlledTransport();
      final morphology = _morphology(transport);
      addTearDown(morphology.dispose);
      final initial = await morphology.disambiguate([
        ['word'],
      ]);
      expect(initial.single.single.best.single['lex'], 'word-1');
      await morphology.unloadDisambiguator();
      expect(morphology.isAvailable, isTrue);
      expect(morphology.canDisambiguate, isFalse);
      expect(morphology.disambiguatorInfo, isNull);
      expect(morphology.disambiguatorFailure, isNull);
      expect(
        await morphology.disambiguate([
          ['word'],
        ]),
        isEmpty,
      );
      expect(
        (await morphology.analyzeWords(['new']))['new']!.single['lex'],
        'new',
      );
      await morphology.loadDisambiguator(_model);
      final reloaded = await morphology.disambiguate([
        ['word'],
      ]);
      expect(reloaded.single.single.best.single['lex'], 'word-2');
      expect(transport.databaseOpens, 1);
      expect(transport.readingCalls, 2);
      expect(transport.disposed, isFalse);
    },
  );

  test('unload cancels a constructor model waiting for its database', () async {
    final transport = _ControlledTransport()..databaseGate = Completer<void>();
    final morphology = _morphology(transport);
    addTearDown(morphology.dispose);
    final loading = morphology.load();
    await transport.databaseStarted.future;
    await morphology.unloadDisambiguator();
    transport.databaseGate!.complete();
    await loading;
    expect(morphology.isAvailable, isTrue);
    expect(morphology.canDisambiguate, isFalse);
    expect(transport.modelOpens, 0);
  });

  test('unload waits for model open and prevents late availability', () async {
    final transport = _ControlledTransport()..modelGate = Completer<void>();
    final morphology = _morphology(transport);
    addTearDown(morphology.dispose);
    final loading = morphology.load();
    await transport.modelStarted.future;
    final unloading = morphology.unloadDisambiguator();
    transport.modelGate!.complete();
    await Future.wait([loading, unloading]);
    expect(morphology.canDisambiguate, isFalse);
    expect(morphology.disambiguatorInfo, isNull);
    expect(transport.events, [
      'database',
      'model-1',
      'unload-start',
      'unload-end',
    ]);
  });

  test('a new model waits until an overlapping unload finishes', () async {
    final transport = _ControlledTransport()..unloadGate = Completer<void>();
    final morphology = _morphology(transport);
    addTearDown(morphology.dispose);
    await morphology.load();
    final unloading = morphology.unloadDisambiguator();
    await transport.unloadStarted.future;
    final loading = morphology.loadDisambiguator(_model);
    expect(transport.modelOpens, 1);
    transport.unloadGate!.complete();
    await Future.wait([unloading, loading]);
    expect(morphology.canDisambiguate, isTrue);
    expect(transport.events, [
      'database',
      'model-1',
      'unload-start',
      'unload-end',
      'model-2',
    ]);
  });

  test(
    'late readings from a removed model cannot fill the new cache',
    () async {
      final transport = _ControlledTransport()
        ..readingsGate = Completer<void>();
      final morphology = _morphology(transport);
      addTearDown(morphology.dispose);
      final old = morphology.disambiguate([
        ['word'],
      ]);
      await transport.readingsStarted.future;
      await morphology.unloadDisambiguator();
      await morphology.loadDisambiguator(_model);
      transport.readingsGate!.complete();
      expect(await old, isEmpty);
      final current = await morphology.disambiguate([
        ['word'],
      ]);
      expect(current.single.single.best.single['lex'], 'word-2');
      expect(transport.readingCalls, 2);
    },
  );

  test(
    'model failure can retry and unload failure reports unavailable',
    () async {
      final transport = _ControlledTransport()..failModel = true;
      final morphology = _morphology(transport);
      addTearDown(morphology.dispose);
      await morphology.load();
      expect(morphology.isAvailable, isTrue);
      expect(morphology.canDisambiguate, isFalse);
      transport.failModel = false;
      await morphology.loadDisambiguator(_model);
      expect(morphology.canDisambiguate, isTrue);
      expect(morphology.disambiguatorFailure, isNull);
      transport.failUnload = true;
      await morphology.unloadDisambiguator();
      expect(morphology.isAvailable, isFalse);
      expect(morphology.canDisambiguate, isFalse);
      expect(
        morphology.disambiguatorFailure,
        isA<ArabicMorphUnavailableException>(),
      );
    },
  );
}
