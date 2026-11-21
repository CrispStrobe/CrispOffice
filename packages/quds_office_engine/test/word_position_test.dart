import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlRun _run(
  String text, {
  int position = 0,
  WmlVertAlign script = WmlVertAlign.baseline,
}) => WmlRun(
  text: text,
  properties: WmlRunProps(
    fontSizeHalfPoints: 24,
    positionHalfPoints: position,
    vertAlign: script,
  ),
);

WmlDocument _document(
  String text, {
  int position = 0,
  WmlVertAlign script = WmlVertAlign.baseline,
}) {
  final document = WmlDocument.empty(text: text);
  document.paragraphs.single.inlines = [
    _run(text, position: position, script: script),
  ];
  return document;
}

List<LaidOutGlyph> _glyphs(WmlDocument document) => WordLayoutEngine(font: null)
    .layout(document, updateFields: false)
    .pages
    .expand((page) => page.lines)
    .expand((line) => line.glyphs)
    .toList();

void main() {
  for (final position in [-9, 0, 8]) {
    test('position $position half-points shifts only the baseline', () {
      const text = 'Latin é😀 العربية';
      final baseline = _glyphs(_document(text));
      final document = _document(text, position: position);
      final positioned = _glyphs(document);
      expect(positioned, hasLength(baseline.length));
      for (var index = 0; index < positioned.length; index++) {
        final normal = baseline[index];
        final shifted = positioned[index];
        expect(shifted.y, closeTo(normal.y - position / 2, 1e-10));
        expect(shifted.x, normal.x);
        expect(shifted.advance, normal.advance);
        expect(shifted.fontSize, normal.fontSize);
        expect(shifted.glyph.logicalIndex, normal.glyph.logicalIndex);
        expect(shifted.logicalEnd, normal.logicalEnd);
        expect(shifted.glyph.codePoint, normal.glyph.codePoint);
        expect(shifted.positionHalfPoints, position);
      }
      expect(document.paragraphs.single.text, text);
    });
  }

  for (final script in WmlVertAlign.values) {
    test('position composes with ${script.name} without changing its size', () {
      final baseline = _glyphs(_document('abc', script: script));
      final shifted = _glyphs(_document('abc', position: 5, script: script));
      for (var index = 0; index < baseline.length; index++) {
        expect(shifted[index].y, closeTo(baseline[index].y - 2.5, 1e-10));
        expect(shifted[index].fontSize, baseline[index].fontSize);
        expect(shifted[index].advance, baseline[index].advance);
        expect(shifted[index].vertAlign, script);
      }
    });
  }

  test('mixed positions preserve individual baseline and UTF-16 ownership', () {
    final document = WmlDocument.empty();
    document.paragraphs.single.inlines = [
      _run('A'),
      _run('😀', position: 6),
      _run('C', position: -4),
    ];
    final glyphs = _glyphs(document);
    expect(glyphs.map((g) => g.glyph.logicalIndex), [0, 1, 3]);
    expect(glyphs.map((g) => g.logicalEnd), [1, 3, 4]);
    expect(glyphs[1].y, closeTo(glyphs[0].y - 3, 1e-10));
    expect(glyphs[2].y, closeTo(glyphs[0].y + 2, 1e-10));
    expect(glyphs.map((g) => g.fontSize), everyElement(12));
  });

  test(
    'incremental relayout translates cached raised and lowered glyphs consistently',
    () {
      final paragraphs = [
        for (var i = 0; i < 30; i++)
          WmlParagraph(
            inlines: [_run('Paragraph $i', position: i.isEven ? 8 : -5)],
          ),
      ];
      final document = WmlDocument(sections: [WmlSection(blocks: paragraphs)]);
      final engine = WordLayoutEngine(font: null);
      var layout = engine.layout(document, updateFields: false);
      WordIncrementalLayoutStats.reset();
      for (final spacing in [25.0, 0.0, 14.0]) {
        paragraphs[3].properties.spacingAfter = spacing;
        layout = engine.layout(
          document,
          updateFields: false,
          reuse: layout,
          dirtyParagraphs: {paragraphs[3]},
        );
        final full = WordLayoutEngine(
          font: null,
        ).layout(document, updateFields: false);
        expect(wordLayoutFingerprint(layout), wordLayoutFingerprint(full));
      }
      expect(WordIncrementalLayoutStats.incremental, 3);
      expect(WordIncrementalLayoutStats.blocksTranslated, greaterThan(0));
      paragraphs[6].inlines
              .whereType<WmlRun>()
              .single
              .properties
              .positionHalfPoints =
          0;
      layout = engine.layout(
        document,
        updateFields: false,
        reuse: layout,
        dirtyParagraphs: {paragraphs[6]},
      );
      expect(
        wordLayoutFingerprint(layout),
        wordLayoutFingerprint(
          WordLayoutEngine(font: null).layout(document, updateFields: false),
        ),
      );
    },
  );

  test('header/footer and note layout copies keep position metadata', () {
    final document = _document('Body');
    document.sections.single.header.add(
      WmlParagraph(inlines: [_run('Header', position: 4)]),
    );
    document.sections.single.footer.add(
      WmlParagraph(inlines: [_run('Footer', position: -6)]),
    );
    final note = WordNotes.insert(
      document,
      document.paragraphs.single,
      endnote: false,
      text: 'Note',
    );
    note.paragraphs.single.inlines = [_run('Note', position: 10)];
    final layout = WordLayoutEngine(
      font: null,
    ).layout(document, updateFields: false);
    final page = layout.pages.single;
    expect(
      page.header
          .expand((line) => line.glyphs)
          .map((g) => g.positionHalfPoints),
      everyElement(4),
    );
    expect(
      page.footer
          .expand((line) => line.glyphs)
          .map((g) => g.positionHalfPoints),
      everyElement(-6),
    );
    final noteGlyphs = page.notes
        .expand((line) => line.glyphs)
        .where((g) => g.positionHalfPoints == 10)
        .toList();
    expect(noteGlyphs, hasLength(4));
  });

  test(
    'PDF paints displaced baselines at unchanged size and extracts source order',
    () {
      final font = SfntFont.parse(
        File(
          '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
        ).readAsBytesSync(),
      );
      final document = WmlDocument.empty();
      document.paragraphs.single.inlines = [
        _run('A'),
        _run('B', position: 6),
        _run('C', position: -4),
      ];
      final baselineDocument = _document('ABC');
      final baseline = PdfFile.open(
        OfficePdfExport.word(baselineDocument, font: font),
      ).displayList(0).ops.whereType<PdfDrawText>().toList();
      final pdf = PdfFile.open(OfficePdfExport.word(document, font: font));
      final painted = pdf.displayList(0).ops.whereType<PdfDrawText>().toList();
      expect(painted.map((op) => op.text).join(), 'ABC');
      expect(painted, hasLength(3));
      expect(painted.map((op) => op.size), everyElement(12));
      expect(painted[0].y, closeTo(baseline[0].y, 1e-6));
      expect(painted[1].y, closeTo(baseline[1].y - 3, 1e-6));
      expect(painted[2].y, closeTo(baseline[2].y + 2, 1e-6));
      expect(PdfExtract.pageText(pdf, 0), 'ABC');
      expect(document.paragraphs.single.text, 'ABC');
    },
  );

  test(
    'comparison detects positioning as formatting without altering text',
    () {
      final before = _document('Position');
      final after = _document('Position', position: 6);
      final result = WordCompare.diff(before, after);
      expect(result.formattingCount, 1);
      expect(result.changes.single.originalText, 'Position');
      expect(result.changes.single.revisedText, 'Position');
      expect(
        WordCompare.diff(
          before,
          after,
          options: const WordComparisonOptions(includeFormatting: false),
        ).hasChanges,
        isFalse,
      );
    },
  );

  test('pending Zotero transfer detects concurrent position-only changes', () {
    final document = _document('Citation');
    final plan = WordZoteroTransfer.prepareExport(
      document,
      instructions: 'Open in the destination and refresh.',
      documentData: jsonEncode({
        'dataVersion': 4,
        'sessionID': 'position-transfer',
        'style': {'styleID': 'http://www.zotero.org/styles/apa'},
        'prefs': {'fieldType': 'Http', 'noteType': 0},
      }),
    );
    plan.assertUnchanged();
    document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .positionHalfPoints =
        2;
    expect(() => plan.assertUnchanged(), throwsStateError);
    expect(() => plan.apply(), throwsStateError);
    expect(document.paragraphs.single.text, 'Citation');
  });
}
