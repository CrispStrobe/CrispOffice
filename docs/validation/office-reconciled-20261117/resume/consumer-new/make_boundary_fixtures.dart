import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:quds_office_engine/quds_office_engine.dart';

const _size = WmlPageSize(width: 612, height: 792);
const _margins = WmlPageMargins(top: 36, bottom: 36, left: 36, right: 36);

WmlParagraph _text(String text) => WmlParagraph(inlines: [WmlRun(text: text)]);

WmlSection _section(
  List<WmlBlock> blocks, {
  int columns = 1,
  WmlSectionBreakKind kind = WmlSectionBreakKind.nextPage,
}) => WmlSection(
  pageSize: _size,
  margins: _margins,
  columnCount: columns,
  columnSpace: 24,
  breakKind: kind,
  blocks: blocks,
);

Object _state(WmlDocument document) => [
  for (final section in document.sections)
    {
      'kind': section.breakKind.name,
      'columns': section.columnCount,
      'gap': section.columnSpace,
      'paragraphs': [
        for (final paragraph in section.blocks.whereType<WmlParagraph>())
          {
            'pageBefore': paragraph.properties.pageBreakBefore,
            'columnBefore': paragraph.properties.columnBreakBefore,
            'inlines': [
              for (final inline in paragraph.inlines)
                switch (inline) {
                  WmlRun() => ['text', inline.text],
                  WmlBreak() => ['break', inline.type.name],
                  WmlBookmarkBoundary() => [
                    'bookmark',
                    inline.id,
                    inline.isStart,
                    inline.name,
                  ],
                  _ => [inline.runtimeType.toString()],
                },
            ],
          },
      ],
    },
];

void main(List<String> arguments) {
  final output = Directory(arguments.single)..createSync(recursive: true);
  final specs = <Map<String, Object?>>[];

  void save(
    String name,
    String token,
    WmlSectionBreakKind? kind,
    int targetPage,
  ) {
    final target = '${token}Target';
    final bookmark = '${token}Range';
    final lead = WmlParagraph(
      properties: WmlParagraphProps(pageBreakBefore: kind == null),
      inlines: [
        WmlBookmarkBoundary(id: '17', isStart: true, name: bookmark),
        WmlBreak(WmlBreakType.column),
        WmlRun(text: target),
        WmlBookmarkBoundary(id: '17', isStart: false),
      ],
    );
    final targetBlocks = <WmlBlock>[
      lead,
      _text('${token}One'),
      _text('${token}Two'),
    ];
    final document = WmlDocument(
      sections: kind == null
          ? [
              _section([_text('${token}Before'), ...targetBlocks], columns: 2),
            ]
          : [
              _section([_text('${token}Before')]),
              _section(targetBlocks, columns: 2, kind: kind),
            ],
    );
    final before = jsonEncode(_state(document));
    File(
      '${output.path}/$name.direct.odt',
    ).writeAsBytesSync(OdtDocumentWriter.writeBytes(document));
    if (before != jsonEncode(_state(document))) {
      throw StateError('Direct ODT export changed model: $name');
    }
    final reference = WordSerializer().writeBytes(document);
    File('${output.path}/$name.source.docx').writeAsBytesSync(reference);
    final imported = WordDeserializer().read(OpcPackage.openBytes(reference));
    final importedBefore = jsonEncode(_state(imported));
    File(
      '${output.path}/$name.imported.odt',
    ).writeAsBytesSync(OdtDocumentWriter.writeBytes(imported));
    if (importedBefore != jsonEncode(_state(imported))) {
      throw StateError('Imported ODT export changed model: $name');
    }
    File('${output.path}/$name.models.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'direct': jsonDecode(before), 'imported': jsonDecode(importedBefore)})}\n',
    );
    specs.add({
      'name': name,
      'section_kind': kind?.name,
      'explicit_page_break': kind == null,
      'target_column': kind == null ? 'left' : 'right',
      'control_kind': kind == null
          ? 'retained-native-page-break-precedence'
          : 'later-section-column-break-regression',
      'bookmark': bookmark,
      'before': '${token}Before',
      'target': target,
      'followers': ['${token}One', '${token}Two'],
      'target_page': targetPage,
      'page_size_pt': [612, 792],
      'left_margin_pt': 36,
      'right_margin_pt': 36,
      'column_gap_pt': 24,
      'column_count': 2,
      'model_unchanged': true,
    });
  }

  save('later-next-page', 'Next', WmlSectionBreakKind.nextPage, 2);
  save('later-continuous', 'Continuous', WmlSectionBreakKind.continuous, 1);
  save('later-odd-page', 'Odd', WmlSectionBreakKind.oddPage, 3);
  save('later-even-page', 'Even', WmlSectionBreakKind.evenPage, 2);
  save('paragraph-page-then-column', 'Explicit', null, 2);
  File(
    '${output.path}/fixtures.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(specs)}\n');
}
