import 'package:quds_proofing_harper/src/harper_source_text.dart';
import 'package:test/test.dart';

void main() {
  test('soft hyphens do not split checked words or shift source findings', () {
    const source = '😀 hy\u00adphen\u00adation.';
    final projected = HarperSourceText(source);
    expect(projected.text, '😀 hyphenation.');
    expect(projected.scalarLength, 14);
    final range = projected.sourceRange(2, 13)!;
    expect(range, (start: 3, end: 16));
    expect(source.substring(range.start, range.end), 'hy\u00adphen\u00adation');
    expect(source, '😀 hy\u00adphen\u00adation.');
  });

  test('word ranges own internal controls without swallowing adjacent ones', () {
    const source = '\u00adab\u00adcd\u00ad';
    final projected = HarperSourceText(source);
    expect(projected.text, 'abcd');
    expect(projected.sourceRange(0, 2), (start: 1, end: 3));
    expect(projected.sourceRange(2, 4), (start: 4, end: 6));
    expect(projected.sourceRange(0, 4), (start: 1, end: 6));
    expect(projected.sourceRange(2, 2), (start: 4, end: 4));
    expect(projected.sourceRange(4, 4), (start: 7, end: 7));
  });

  test('empty input and control-only text have explicit insertion ownership', () {
    expect(HarperSourceText('').sourceRange(0, 0), (start: 0, end: 0));
    final projected = HarperSourceText('\u00ad\u00ad');
    expect(projected.text, '');
    expect(projected.sourceRange(0, 0), (start: 2, end: 2));
  });

  test('punctuation, no-break controls and authored line endings stay literal', () {
    const source = 'can’t co\u2011operate\u2060.\u00a0Next\r\nline.';
    final projected = HarperSourceText(source);
    expect(projected.text, source);
    expect(
      projected.sourceRange(0, projected.scalarLength),
      (start: 0, end: source.length),
    );
  });

  test('never exposes partial source or projected graphemes', () {
    for (final source in <String>['e\u0301', 'e\u00ad\u0301']) {
      final projected = HarperSourceText(source);
      expect(projected.sourceRange(0, 1), isNull);
      expect(projected.sourceRange(1, 1), isNull);
      expect(
        projected.sourceRange(0, 2),
        (start: 0, end: source.length),
      );
    }
    final joined = HarperSourceText('👩‍💻x');
    expect(joined.sourceRange(0, 1), isNull);
    expect(joined.sourceRange(1, 2), isNull);
    expect(joined.sourceRange(0, 3), (start: 0, end: 5));
    expect(joined.sourceRange(3, 4), (start: 5, end: 6));
  });

  test('rejects negative, reversed and out-of-bounds backend ranges', () {
    final projected = HarperSourceText('ab\u00adcd');
    for (final range in <(int, int)>[(-1, 1), (2, 1), (0, 5), (5, 5)]) {
      expect(
        () => projected.sourceRange(range.$1, range.$2),
        throwsRangeError,
      );
    }
  });

  test('many findings keep exact positions after supplementary characters', () {
    final source = List<String>.filled(2000, '😀 ab\u00adcd ').join();
    final projected = HarperSourceText(source);
    for (var i = 0; i < 2000; i++) {
      final range = projected.sourceRange(i * 7 + 2, i * 7 + 6)!;
      expect(range, (start: i * 9 + 3, end: i * 9 + 8));
      expect(source.substring(range.start, range.end), 'ab\u00adcd');
    }
  });
}
