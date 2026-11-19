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

  @override
  Future<void> open(Uint8List model) async => opened = model;

  @override
  Future<List<List<(String, double)>>> detect(List<String> texts, int k) async {
    calls.add(texts);
    if (failDetect) throw const LanguageIdUnavailableException('stopped');
    return [for (final t in texts) answers[t] ?? const []];
  }

  @override
  Future<void> dispose() async => disposed = true;
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
    expect(transport.calls, hasLength(3));
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
}
