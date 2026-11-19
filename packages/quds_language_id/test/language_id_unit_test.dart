import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_language_id/quds_language_id.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

final class _FakeTransport implements LanguageIdTransport {
  _FakeTransport(this.answers);
  final Map<String, List<(String, double)>> answers;
  Uint8List? opened;
  final calls = <List<String>>[];
  bool failDetect = false;
  bool disposed = false;
  int opens = 0;
  int disposes = 0;
  Future<void>? waitOpen;
  Future<List<List<(String, double)>>> Function(List<String>, int)? respond;

  @override
  Future<void> open(Uint8List model) async {
    opens++;
    opened = model;
    await waitOpen;
  }

  @override
  Future<List<List<(String, double)>>> detect(List<String> texts, int k) async {
    calls.add(texts);
    if (failDetect) throw const LanguageIdUnavailableException('stopped');
    final callback = respond;
    if (callback != null) return callback(texts, k);
    return [for (final t in texts) answers[t] ?? const []];
  }

  @override
  Future<void> dispose() async {
    disposes++;
    disposed = true;
  }
}

Uint8List _model() => File('assets/cld3-f16.gguf').readAsBytesSync();

void main() {
  test('the bundled model is the pinned one', () {
    final model = _model();
    expect(model.length, Cld3Model.bytes);
    expect(Cld3Model.verify(model), isTrue);
    final tampered = Uint8List.fromList(model)..[1000] ^= 1;
    expect(Cld3Model.verify(tampered), isFalse);
  });

  test('CLD3 has 109 distinct labels and legacy codes map to BCP-47', () {
    expect(cld3Labels, hasLength(109));
    expect(cld3Labels.toSet(), hasLength(109));
    expect(cld3LabelToLanguage('iw'), 'he');
    expect(cld3LabelToLanguage('jw'), 'jv');
    expect(cld3LabelToLanguage('zh-Latn'), 'zh-Latn');
    expect(cld3LabelToLanguage('de'), 'de');
    final mapped = cld3Labels.map(cld3LabelToLanguage).toSet();
    expect(mapped, hasLength(109));
    expect(mapped, isNot(contains('iw')));
  });

  test('result lines parse into label/probability pairs', () {
    expect(parseLanguageIdLines('fr 0.999403\nda 0.000375\n'), [
      ('fr', 0.999403),
      ('da', 0.000375),
    ]);
    expect(parseLanguageIdLines(''), isEmpty);
  });

  test('identify maps labels, batches and keeps input order', () async {
    final transport = _FakeTransport({
      'שלום עולם': [('iw', 0.99), ('yi', 0.01)],
      'Bonjour le monde': [('fr', 0.999)],
    });
    final identifier = Cld3LanguageIdentifier(
      model: _model(),
      transport: transport,
      batchTexts: 1,
    );
    final result = await identifier.identify([
      'שלום עולם',
      '123',
      'Bonjour le monde',
    ]);
    expect(identifier.isAvailable, isTrue);
    expect(transport.opened, isNotNull);
    expect(transport.calls, [
      ['שלום עולם'],
      ['Bonjour le monde'],
    ]);
    expect(result[0], const [
      LanguageGuess('he', 0.99),
      LanguageGuess('yi', 0.01),
    ]);
    expect(result[1], isEmpty);
    expect(result[2].single.language, 'fr');
    await identifier.dispose();
    expect(transport.disposed, isTrue);
    expect(identifier.isAvailable, isFalse);
  });

  test('a tampered model is never opened', () async {
    final transport = _FakeTransport({});
    final identifier = Cld3LanguageIdentifier(
      model: Uint8List(10),
      transport: transport,
    );
    expect(await identifier.detect('Hallo Welt, wie geht es dir?'), isEmpty);
    expect(transport.opened, isNull);
    expect(identifier.isAvailable, isFalse);
    expect(identifier.failure, isA<LanguageIdUnavailableException>());
  });

  test('a stopped worker degrades to empty answers', () async {
    final transport = _FakeTransport({})..failDetect = true;
    final identifier = Cld3LanguageIdentifier(
      model: _model(),
      transport: transport,
    );
    expect(await identifier.detectBatch(['a b c', 'd e f']), [
      isEmpty,
      isEmpty,
    ]);
    expect(identifier.isAvailable, isFalse);
  });

  test('batch and candidate limits reject invalid arguments immediately', () {
    for (final batch in [0, -1]) {
      expect(
        () => Cld3LanguageIdentifier(model: Uint8List(0), batchTexts: batch),
        throwsRangeError,
      );
    }
    for (final topK in [0, -1, 17]) {
      expect(
        () => Cld3LanguageIdentifier(model: Uint8List(0), topK: topK),
        throwsRangeError,
      );
    }
  });

  test(
    'Unicode digits, marks, punctuation and emoji never reach the worker',
    () async {
      final transport = _FakeTransport({});
      final identifier = Cld3LanguageIdentifier(
        model: _model(),
        transport: transport,
      );
      final result = await identifier.identify([
        '',
        '١۲1。؟🙂\u064e\u05b0',
        '\u200d',
      ]);
      expect(result, [isEmpty, isEmpty, isEmpty]);
      expect(transport.opened, isNull);
      expect(transport.calls, isEmpty);
      await identifier.dispose();
    },
  );

  test(
    'malformed response counts degrade without throwing or accepting a prefix',
    () async {
      final transport = _FakeTransport({})
        ..respond = (_, _) async => const [
          [('en', 0.99)],
        ];
      final identifier = Cld3LanguageIdentifier(
        model: _model(),
        transport: transport,
      );
      expect(
        await identifier.identify(['First paragraph', 'Second paragraph']),
        [isEmpty, isEmpty],
      );
      expect(identifier.failure, isA<FormatException>());
      expect(identifier.isAvailable, isFalse);
      expect(await identifier.detect('Later paragraph'), isEmpty);
      expect(transport.calls, hasLength(1));
      await identifier.dispose();
    },
  );

  test(
    'invalid probabilities, labels, order and candidate counts fail closed',
    () async {
      for (final answer in <List<(String, double)>>[
        [('en', double.nan)],
        [('en', double.infinity)],
        [('en', -0.1)],
        [('en', 1.1)],
        [('unknown', 0.99)],
        [('en', 0.2), ('fr', 0.9)],
        [('en', 0.4), ('fr', 0.3), ('de', 0.2), ('es', 0.1)],
      ]) {
        final transport = _FakeTransport({'Paragraph text': answer});
        final identifier = Cld3LanguageIdentifier(
          model: _model(),
          transport: transport,
        );
        expect(await identifier.detect('Paragraph text'), isEmpty);
        expect(identifier.failure, isA<FormatException>());
        expect(identifier.isAvailable, isFalse);
        await identifier.dispose();
      }
    },
  );

  test(
    'a failed later batch retains only already completed valid results',
    () async {
      var calls = 0;
      final transport = _FakeTransport({})
        ..respond = (_, _) async {
          if (++calls == 2) throw StateError('stopped');
          return const [
            [('fr', 0.99)],
          ];
        };
      final identifier = Cld3LanguageIdentifier(
        model: _model(),
        transport: transport,
        batchTexts: 1,
      );
      final result = await identifier.identify([
        'First paragraph',
        'Second paragraph',
        'Third paragraph',
      ]);
      expect(result.first, const [LanguageGuess('fr', 0.99)]);
      expect(result.skip(1), [isEmpty, isEmpty]);
      expect(transport.calls, hasLength(2));
      expect(identifier.isAvailable, isFalse);
      await identifier.dispose();
    },
  );

  test(
    'dispose before loading never opens or classifies and is idempotent',
    () async {
      final transport = _FakeTransport({});
      final identifier = Cld3LanguageIdentifier(
        model: _model(),
        transport: transport,
      );
      await identifier.dispose();
      await identifier.dispose();
      await identifier.load();
      expect(await identifier.detect('A paragraph with letters'), isEmpty);
      expect(transport.opened, isNull);
      expect(transport.calls, isEmpty);
      expect(transport.disposes, 1);
    },
  );

  test('late opening cannot reactivate a disposed identifier', () async {
    final opening = Completer<void>();
    final transport = _FakeTransport({})..waitOpen = opening.future;
    final identifier = Cld3LanguageIdentifier(
      model: _model(),
      transport: transport,
    );
    final result = identifier.detect('A paragraph with letters');
    expect(transport.opens, 1);
    await identifier.dispose();
    opening.complete();
    expect(await result, isEmpty);
    expect(identifier.isAvailable, isFalse);
    expect(transport.calls, isEmpty);
  });

  test('late detection cannot publish results after disposal', () async {
    final pending = Completer<List<List<(String, double)>>>();
    final started = Completer<void>();
    final transport = _FakeTransport({})
      ..respond = (_, _) {
        started.complete();
        return pending.future;
      };
    final identifier = Cld3LanguageIdentifier(
      model: _model(),
      transport: transport,
    );
    final result = identifier.detect('A paragraph with letters');
    await started.future;
    await identifier.dispose();
    pending.complete(const [
      [('en', 0.99)],
    ]);
    expect(await result, isEmpty);
    expect(identifier.isAvailable, isFalse);
    expect(transport.disposes, 1);
  });

  test(
    'disposal rejection clears results from an earlier successful batch',
    () async {
      var calls = 0;
      final pending = Completer<List<List<(String, double)>>>();
      final started = Completer<void>();
      final transport = _FakeTransport({})
        ..respond = (_, _) {
          if (++calls == 1) {
            return Future.value(const [
              [('en', 0.99)],
            ]);
          }
          started.complete();
          return pending.future;
        };
      final identifier = Cld3LanguageIdentifier(
        model: _model(),
        transport: transport,
        batchTexts: 1,
      );
      final result = identifier.identify([
        'First paragraph',
        'Second paragraph',
      ]);
      await started.future;
      await identifier.dispose();
      pending.completeError(const LanguageIdUnavailableException('disposed'));
      expect(await result, [isEmpty, isEmpty]);
      expect(identifier.isAvailable, isFalse);
      expect(transport.calls, hasLength(2));
    },
  );

  test('input identity is frozen across asynchronous model loading', () async {
    final opening = Completer<void>();
    final transport = _FakeTransport({
      'Original paragraph': [('en', 0.99)],
    })..waitOpen = opening.future;
    final identifier = Cld3LanguageIdentifier(
      model: _model(),
      transport: transport,
    );
    final texts = ['Original paragraph'];
    final result = identifier.identify(texts);
    texts
      ..clear()
      ..add('Replacement paragraph')
      ..add('Another paragraph');
    opening.complete();
    expect(await result, [
      const [LanguageGuess('en', 0.99)],
    ]);
    expect(transport.calls, [
      ['Original paragraph'],
    ]);
    await identifier.dispose();
  });
}
