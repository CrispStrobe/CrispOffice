import 'dart:io';
import 'dart:typed_data';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';
void main() {
  test(
    'PPT autofit measures and paints numeric and blank line advances equally',
    () {
      final SfntFont exactFont = SfntFont.parse(
        File(
          '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
        ).readAsBytesSync(),
      );
      final double natural =
          10 *
          (exactFont.ascender - exactFont.descender + exactFont.lineGap) /
          exactFont.unitsPerEm;
      final double advance = natural * 1.3; // 150% paragraph leading minus 20%.
      final PmlShape shape = PmlShape(
        id: 2,
        name: 'Fitted',
        text: '11\n22\n\n33',
        fontSizePt: 20,
        textScale: 0.5,
        lineSpacingReduction: 0.2,
        textAnchor: PmlTextAnchor.center,
        fillColor: '',
        rightToLeft: false,
        transform: const PmlTransform(cx: 200 * 12700, cy: 200 * 12700),
        richText: [
          PmlTextParagraph(
            lineSpacing: 1.5,
            runs: [PmlTextRun(text: '11\n22', fontSizePt: 20)],
          ),
          PmlTextParagraph(lineSpacing: 1.5, defaultFontSizePt: 20),
          PmlTextParagraph(
            lineSpacing: 1.5,
            runs: [PmlTextRun(text: '33', fontSizePt: 20)],
          ),
        ],
      );
      final List<double> baselines = _autofitBaselines(shape, exactFont);
      final double first = (200 - 4 * advance) / 2 + 10;
      expect(baselines, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(baselines[i], closeTo(first + [0, 1, 3][i] * advance, 0.01));
      }
    },
  );

  test(
    'PPT autofit uses the same advance inside wrapped text and between paragraphs',
    () {
      final SfntFont exactFont = SfntFont.parse(
        File(
          '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
        ).readAsBytesSync(),
      );
      final double advance =
          10 *
          (exactFont.ascender - exactFont.descender + exactFont.lineGap) /
          exactFont.unitsPerEm *
          0.8;
      final PmlShape shape = PmlShape(
        id: 2,
        name: 'Fitted',
        text: 'Alpha Beta Gamma\nEnd',
        fontSizePt: 20,
        textScale: 0.5,
        lineSpacingReduction: 0.2,
        fillColor: '',
        rightToLeft: false,
        transform: const PmlTransform(cx: 45 * 12700, cy: 200 * 12700),
        richText: [
          PmlTextParagraph(
            runs: [PmlTextRun(text: 'Alpha Beta Gamma', fontSizePt: 20)],
          ),
          PmlTextParagraph(runs: [PmlTextRun(text: 'End', fontSizePt: 20)]),
        ],
      );
      final List<double> baselines = _autofitBaselines(shape, exactFont);
      expect(baselines, hasLength(4));
      for (var i = 0; i < baselines.length; i++) {
        expect(baselines[i], closeTo(13.6 + i * advance, 0.01));
      }
    },
  );


  test('native model autofit survives serialization', () {
    final deck = PmlPresentation(slides: [PmlSlide(id: 256, shapes: [
      PmlShape(id: 2, name: 'Fit', text: 'Fit', textScale: 0.75, lineSpacingReduction: 0.15),
    ])]);
    final shape = SlideDeserializer().readBytes(SlideSerializer().writeBytes(deck)).slides.single.shapes.single;
    expect(shape.textScale, 0.75);
    expect(shape.lineSpacingReduction, 0.15);
  });
}
List<String> _inflated(Uint8List pdf) {
  final List<String> out = <String>[];
  final List<int> mark = 'stream\n'.codeUnits;
  var i = 0;
  while (i < pdf.length - mark.length) {
    var hit = true;
    for (int k = 0; k < mark.length; k++) {
      if (pdf[i + k] != mark[k]) {
        hit = false;
        break;
      }
    }
    if (!hit) {
      i++;
      continue;
    }
    final int start = i + mark.length;
    final int end = _indexOf(pdf, 'endstream', start);
    if (end < 0) {
      break;
    }
    var payload = Uint8List.sublistView(pdf, start, end);
    if (payload.isNotEmpty && payload.last == 0x0A) {
      payload = Uint8List.sublistView(payload, 0, payload.length - 1);
    }
    if (payload.length >= 2 && payload[0] == 0x78) {
      try {
        out.add(String.fromCharCodes(PdfFlate.decompress(payload)));
      } catch (_) {}
    }
    i = end + 9;
  }
  return out;
}

int _indexOf(Uint8List data, String token, int from) {
  final List<int> needle = token.codeUnits;
  for (int i = from; i <= data.length - needle.length; i++) {
    var ok = true;
    for (int k = 0; k < needle.length; k++) {
      if (data[i + k] != needle[k]) {
        ok = false;
        break;
      }
    }
    if (ok) {
      return i;
    }
  }
  return -1;
}

List<double> _autofitBaselines(PmlShape shape, SfntFont font) {
  final String content = _inflated(
    OfficePdfExport.presentation(
      PmlPresentation(
        slides: [
          PmlSlide(id: 256, shapes: [shape]),
        ],
      ),
      font: font,
    ),
  ).join();
  return RegExp(r'1 0 0 -1 [-0-9.]+ ([-0-9.]+) Tm')
      .allMatches(content)
      .map((match) => double.parse(match.group(1)!))
      .toSet()
      .toList()
    ..sort();
}
