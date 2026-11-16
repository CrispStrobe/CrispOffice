import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/pdf_alias_fixture.dart';

const _output = String.fromEnvironment('QUDS_ALIAS_RENDER_OUTPUT');

void main() {
  final source = aliasTestFont();
  final aliases = withSharedGlyphAliases(source);
  const text = 'A\u{1f600}\u{20000}AZ';

  test('Word PDF preserves distinct Unicode aliases of one real glyph', () {
    final bytes = OfficePdfExport.word(
      WmlDocument.empty(text: text),
      font: aliases,
    );
    final file = PdfFile.open(bytes);
    expect(PdfExtract.pageText(file, 0), text);
    final ops = file.displayList(0).ops.whereType<PdfDrawText>().toList();
    expect(ops.map((op) => op.text).join(), text);
    for (final query in ['A', '\u{1f600}', '\u{20000}']) {
      expect(
        OfficeFind.inPdf(file, OfficeFindOptions(query: query)),
        hasLength(query == 'A' ? 2 : 1),
      );
    }
    for (final op in ops) {
      final subset = SfntFont.parse(op.fontBytes!);
      final oldId = source.glyphIdFor(op.text == 'Z' ? 0x5a : 0x41);
      final newId = subset.glyphIdFor(op.text.runes.single);
      expect(subset.advanceWidth(newId), source.advanceWidth(oldId));
    }
    if (_output.isNotEmpty) {
      Directory(_output).createSync(recursive: true);
      File('$_output/word-unicode-aliases.pdf').writeAsBytesSync(bytes);
    }
  });

  test('Word PDF preserves the bundled italic font fi aliases', () {
    final italic = aliasTestFont('LiberationSerif-Italic');
    expect(italic.glyphIdFor(0xf001), isNonZero);
    expect(italic.glyphIdFor(0xf001), italic.glyphIdFor(0xfb01));
    const authored = '\uf001\ufb01\uf001';
    final file = PdfFile.open(
      OfficePdfExport.word(WmlDocument.empty(text: authored), font: italic),
    );
    expect(PdfExtract.pageText(file, 0), authored);
    expect(
      OfficeFind.inPdf(file, const OfficeFindOptions(query: '\uf001')),
      hasLength(2),
    );
    expect(
      OfficeFind.inPdf(file, const OfficeFindOptions(query: '\ufb01')),
      hasLength(1),
    );
  });

  test('worksheet PDF preserves shared-glyph Unicode text', () {
    final book = SmlWorkbook();
    book.firstSheet.cellA1('A1').value = text;
    final file = PdfFile.open(OfficePdfExport.workbook(book, font: aliases));
    expect(PdfExtract.pageText(file, 0), contains(text));
  });

  test('presentation PDF preserves shared-glyph Unicode text', () {
    final deck = PmlPresentation(
      slides: [
        PmlSlide(
          id: 256,
          shapes: [
            PmlShape(
              id: 2,
              name: 'Aliases',
              text: text,
              transform: const PmlTransform(
                x: 200000,
                y: 200000,
                cx: 4000000,
                cy: 800000,
              ),
            ),
          ],
        ),
      ],
    );
    final file = PdfFile.open(OfficePdfExport.presentation(deck, font: aliases));
    expect(PdfExtract.pageText(file, 0), contains(text));
  });
}
