// Runs the real native library with the bundled model:
//   QUDS_LANGUAGE_ID_TEST_LIBRARY=build/native/libquds_language_id.dylib dart test
@TestOn('vm')
library;

import 'dart:io';

import 'package:quds_language_id/quds_language_id.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  final library = Platform.environment['QUDS_LANGUAGE_ID_TEST_LIBRARY'];
  final skip = library == null || library.isEmpty
      ? 'Set QUDS_LANGUAGE_ID_TEST_LIBRARY to the built library.'
      : null;
  late Cld3LanguageIdentifier identifier;

  setUpAll(() async {
    if (skip != null) return;
    identifier = Cld3LanguageIdentifier(
      model: File('assets/cld3-f16.gguf').readAsBytesSync(),
      nativeLibraryPath: library,
    );
    await identifier.load();
  });
  tearDownAll(() async {
    if (skip == null) await identifier.dispose();
  });

  test('loads the bundled model', () {
    expect(identifier.failure, isNull);
    expect(identifier.isAvailable, isTrue);
  }, skip: skip);

  test('matches the model card smoke set', () async {
    final results = await identifier.detectBatch([
      'Bonjour le monde',
      'Привет мир',
      '你好世界',
      'こんにちは世界',
      'Das ist ein ganz normaler deutscher Satz über das Wetter.',
      'Gallia est omnis divisa in partes tres.',
      'هذا نص عربي قصير',
      'این یک متن فارسی است',
      'שלום עולם',
    ]);
    expect(
      [for (final r in results) r.first.language],
      [
        'fr',
        'ru',
        'zh',
        'ja',
        'de',
        'la',
        'ar',
        'fa',
        'he', // CLD3's legacy `iw`
      ],
    );
    expect(results.first.first.confidence, closeTo(0.9994, 0.0005));
    expect(results.first, hasLength(identifier.topK));
    for (final r in results) {
      expect(r.first.confidence, greaterThanOrEqualTo(r.last.confidence));
    }
  }, skip: skip);

  test('text without letters has no answer; long text is accepted', () async {
    final results = await identifier.detectBatch([
      '',
      '12345 !?',
      'The quick brown fox jumps over the lazy dog. ' * 400,
    ]);
    expect(results[0], isEmpty);
    expect(results[1], isEmpty);
    expect(results[2].first.language, 'en');
  }, skip: skip);

  test('drives the paragraph policy end to end', () async {
    final detector = ParagraphLanguageDetector(identifier);
    final result = await detector.detect(
      'Der Bericht wurde gestern veröffentlicht und sorgte für Aufsehen. '
      'وقد نشر التقرير أمس وأثار ضجة كبيرة في الأوساط السياسية.',
    );
    expect(
      [for (final s in result.segments) (s.script, s.language)],
      [(TextScript.latin, 'de'), (TextScript.arabic, 'ar')],
    );
  }, skip: skip);
}
