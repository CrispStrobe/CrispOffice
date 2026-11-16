import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

LaidOutGlyph _glyph(
  String source,
  int offset, {
  String color = '000000',
  int level = 0,
}) => LaidOutGlyph(
  glyph: ShapedGlyph(
    codePoint: source.substring(offset).runes.first,
    glyphId: 1,
    advance: 8,
    logicalIndex: offset,
    level: level,
  ),
  x: offset * 8.0,
  y: 0,
  color: color,
  fontSize: 14,
  bold: false,
  underline: WmlUnderline.none,
  fontFamily: 'Liberation Sans',
);

List<LaidOutGlyph> _glyphs(String source) {
  final result = <LaidOutGlyph>[];
  var offset = 0;
  for (final cp in source.runes) {
    result.add(_glyph(source, offset));
    offset += cp > 0xffff ? 2 : 1;
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test(
    'logical slices retain whole Unicode graphemes at every UTF-16 unit',
    () {
      for (final cluster in ['a\u0301', 'ب\u064e', '👩🏽‍💻', '🇩🇪', '✈️']) {
        final source = 'x${cluster}y';
        for (var index = 1; index <= cluster.length; index++) {
          expect(
            PaintRunText.logicalSlice(source, [index]),
            cluster,
            reason: 'UTF-16 unit $index within $cluster',
          );
        }
      }
      expect(PaintRunText.logicalSlice('abc', [-1, 3, 20]), isEmpty);
      expect(PaintRunText.logicalSlice('', [0]), isEmpty);
    },
  );

  test('logical slices preserve the span between selected clusters', () {
    const source = 'xa\u0301 and 👩🏽‍💻y';
    expect(
      PaintRunText.logicalSlice(source, [source.length - 2, 2]),
      'a\u0301 and 👩🏽‍💻',
    );
  });

  test(
    'paint runs preserve supplementary scalars in logical and visual order',
    () {
      for (final source in ['😀', 'A😀', '𐐨😀', '😀' * 12]) {
        final glyphs = _glyphs(source);
        expect(PaintRunText.runText(source, glyphs), source);
        expect(PaintRunText.runText(source, glyphs.reversed.toList()), source);
      }
    },
  );

  test('sparse paint runs copy complete scalars without unrelated text', () {
    const source = '😀0123456789𐐨';
    expect(
      PaintRunText.runText(source, [
        _glyph(source, source.length - 2),
        _glyph(source, 0),
        _glyph(source, 0),
      ]),
      '😀𐐨',
    );
  });

  test('paint runs normalize offsets within valid surrogate pairs', () {
    const source = '😀!';
    expect(PaintRunText.runText(source, [_glyph(source, 1)]), '😀');
    expect(
      PaintRunText.runText(source, [_glyph(source, 0), _glyph(source, 1)]),
      '😀',
    );
    const malformed = '\uD83Dxy';
    expect(PaintRunText.runText(malformed, [_glyph(malformed, 0)]), '\uD83D');
  });

  test('a paint run does not borrow a following differently styled mark', () {
    for (final source in ['ب\u064e', 'a\u0301']) {
      final base = _glyph(source, 0);
      final mark = _glyph(source, 1, color: 'ff0000');
      expect(PaintRunText.samePaintRun(base, mark), isFalse);
      final baseText = PaintRunText.runText(source, [base]);
      final markText = PaintRunText.runText(source, [mark]);
      expect(baseText, source.substring(0, 1));
      expect(markText, source.substring(1));
      expect('$baseText$markText', source);
      expect(PaintRunText.runText(source, [base, mark]), source);
    }
  });

  test('nested embeddings with equal direction keep separate paint runs', () {
    expect(
      PaintRunText.samePaintRun(_glyph('ab', 0), _glyph('ab', 1, level: 2)),
      isFalse,
    );
    expect(
      PaintRunText.samePaintRun(
        _glyph('ab', 0, level: 1),
        _glyph('ab', 1, level: 3),
      ),
      isFalse,
    );
    expect(PaintRunText.samePaintRun(_glyph('ab', 0), _glyph('ab', 1)), isTrue);
  });

  test('fitting and hit testing retain the ends of a supplementary run', () {
    const source = 'A😀';
    final glyphs = _glyphs(source);
    final line = LaidOutLine(
      glyphs: glyphs,
      x: 0,
      y: 0,
      width: 24,
      height: 16,
      pageIndex: 0,
      justification: WmlJustification.left,
      sourceText: source,
    );
    PaintRunText.fitLine(line, source);
    expect(line.width, greaterThan(0));
    expect(
      PaintRunText.hitLogicalIndexOnLine(line, -100, paragraph: source),
      0,
    );
    expect(
      PaintRunText.hitLogicalIndexOnLine(
        line,
        line.width + 100,
        paragraph: source,
      ),
      source.length,
    );
    expect(
      PaintRunText.caretXOnLine(line, source.length, paragraph: source),
      closeTo(line.width, 0.001),
    );
  });
}
