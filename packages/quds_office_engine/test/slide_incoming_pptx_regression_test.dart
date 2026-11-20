import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/pdf_alias_fixture.dart';

PmlShape _textShape(
  String text, {
  double width = 300,
  double height = 100,
  bool rightToLeft = false,
  List<PmlTextRun>? runs,
}) => PmlShape(
  id: 2,
  name: 'Imported text',
  text: text,
  fillColor: '',
  fontSizePt: 20,
  rightToLeft: rightToLeft,
  transform: PmlTransform(
    x: 20 * 12700,
    y: 30 * 12700,
    cx: (width * 12700).round(),
    cy: (height * 12700).round(),
  ),
  richText: [
    PmlTextParagraph(
      rightToLeft: rightToLeft,
      runs: runs ?? [PmlTextRun(text: text, fontSizePt: 20)],
    ),
  ],
);

void main() {
  final SfntFont font = aliasTestFont();
  PdfFile export(PmlShape shape) => PdfFile.open(
    OfficePdfExport.presentation(
      PmlPresentation(
        slides: [
          PmlSlide(id: 256, shapes: [shape]),
        ],
      ),
      font: font,
    ),
  );

  for (final PmlShapePreset preset in [
    PmlShapePreset.downArrow,
    PmlShapePreset.upArrow,
    PmlShapePreset.leftArrow,
    PmlShapePreset.rightArrow,
  ]) {
    test('unfilled $preset retains its outline in PDF and PPTX', () {
      final PmlShape arrow = PmlShape(
        id: 2,
        name: 'Arrow',
        preset: preset,
        fillColor: '',
        strokeColor: 'FF0000',
        strokeWidth: 2,
        transform: const PmlTransform(
          x: 10 * 12700,
          y: 20 * 12700,
          cx: 100 * 12700,
          cy: 80 * 12700,
        ),
      );
      final PdfStrokePath stroke = export(
        arrow,
      ).displayList(0).ops.whereType<PdfStrokePath>().single;
      expect(stroke.color, 0xFFFF0000);
      expect(stroke.width, closeTo(2, 0.001));
      expect(
        stroke.points.where((point) => point.kind == PdfPathKind.line),
        hasLength(6),
      );
      expect(stroke.points.last.kind, PdfPathKind.close);
      final PmlPresentation saved = SlideDeserializer().readBytes(
        SlideSerializer().writeBytes(
          PmlPresentation(
            slides: [
              PmlSlide(id: 256, shapes: [arrow]),
            ],
          ),
        ),
      );
      expect(saved.slides.single.shapes.single.preset, preset);
      expect(saved.slides.single.shapes.single.strokeColor, 'FF0000');
    });
  }

  test('fitted mixed explicit and inherited font sizes scale once', () {
    const String text = 'Heading PartTwo';
    final PdfFile file = export(
      _textShape(
        text,
        width: 80,
        height: 30,
        runs: [
          PmlTextRun(text: 'Heading ', fontSizePt: 20, color: 'FF0000'),
          PmlTextRun(text: 'PartTwo', color: '0000FF'),
        ],
      ),
    );
    final List<PdfDrawText> painted = file
        .displayList(0)
        .ops
        .whereType<PdfDrawText>()
        .toList();
    final List<PdfDrawText> red = painted
        .where((op) => op.color == 0xFFFF0000)
        .toList();
    final List<PdfDrawText> blue = painted
        .where((op) => op.color == 0xFF0000FF)
        .toList();
    expect(red, isNotEmpty);
    expect(blue, isNotEmpty);
    expect(red.first.size, lessThan(20));
    for (final PdfDrawText op in blue) {
      expect(op.size, closeTo(red.first.size, 0.001));
    }
  });

  test('numeric single-line text preserves authored LTR order', () {
    const String text = '12-34/56';
    final PdfFile file = export(_textShape(text));
    expect(PdfExtract.pageText(file, 0), text);
    final List<PdfDrawText> painted = file
        .displayList(0)
        .ops
        .whereType<PdfDrawText>()
        .toList();
    expect(painted.map((op) => op.text).join(), text);
    expect(painted.map((op) => op.y).toSet(), hasLength(1));
    for (var i = 1; i < painted.length; i++) {
      expect(painted[i].x, greaterThan(painted[i - 1].x));
    }
  });

  test('numeric explicit line breaks retain separate painted baselines', () {
    final PdfFile file = export(_textShape('12\n34'));
    final List<PdfDrawText> painted = file
        .displayList(0)
        .ops
        .whereType<PdfDrawText>()
        .toList();
    expect(painted.map((op) => op.text).join(), '1234');
    expect(painted.map((op) => op.y).toSet(), hasLength(2));
    expect(painted.first.x, closeTo(painted[2].x, 0.001));
  });

  test('numeric content still wraps inside a narrow text box', () {
    final PdfFile file = export(_textShape('12 34 56 78', width: 50));
    final List<PdfDrawText> painted = file
        .displayList(0)
        .ops
        .whereType<PdfDrawText>()
        .toList();
    expect(painted.map((op) => op.y).toSet().length, greaterThan(1));
    expect(painted.map((op) => op.text).join().replaceAll(' ', ''), '12345678');
    expect(painted.every((op) => op.x < 70), isTrue);
  });

  test(
    'hidden master shapes stay absent in PDF with an empty decoration list',
    () {
      final PmlPresentation deck = PmlPresentation(
        master: PmlMaster(
          name: 'Master',
          shapes: [_textShape('Hidden master')],
        ),
        slides: [PmlSlide(id: 256, showMasterShapes: false)],
      );
      for (final PdfSlideExportMode mode in PdfSlideExportMode.values) {
        final PdfFile file = PdfFile.open(
          OfficePdfExport.presentation(deck, mode: mode, font: font),
        );
        expect(PdfExtract.documentText(file), isNot(contains('Hidden master')));
      }
      final PdfFile pair = PdfFile.open(
        OfficePdfExport.presentation(deck, slidesPerPage: 2, font: font),
      );
      expect(PdfExtract.documentText(pair), isNot(contains('Hidden master')));
    },
  );
}
