// Reconstructed bounded consumer fixtures after the workspace reset.
// New harness revision: these outputs do not claim byte continuity with lost artifacts.
import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';

const size = WmlPageSize(width: 420, height: 420);
const margins = WmlPageMargins(top: 54, bottom: 54, left: 36, right: 36);

WmlParagraph paragraph(String text, {bool pageBreak = false}) => WmlParagraph(
  properties: WmlParagraphProps(pageBreakBefore: pageBreak),
  inlines: [WmlRun(text: text)],
);

List<WmlInline> field(String instruction, List<WmlInline> cache) => [
  WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
  WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: instruction),
  WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
  ...cache,
  WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
];

WmlParagraph range(String name, String text) => WmlParagraph(
  inlines: [
    WmlBookmarkBoundary(id: '1', isStart: true, name: name),
    WmlRun(text: text),
    WmlBookmarkBoundary(id: '1', isStart: false),
  ],
);

void main(List<String> arguments) {
  final output = Directory(arguments.single)..createSync(recursive: true);
  final manifest = <Map<String, Object?>>[];
  void save(String name, WmlDocument document, Map<String, Object?> expected) {
    File(output.path + '/' + name + '.odt').writeAsBytesSync(
      OdtDocumentWriter.writeBytes(document),
    );
    manifest.add({'name': name, ...expected});
  }

  final native = WmlDocument(
    sections: [
      WmlSection(
        pageSize: size,
        margins: margins,
        blocks: [
          for (final (kind, cache) in [
            ('PAGE', '37'),
            ('NUMPAGES', '121'),
            ('DATE', '17.11.2026'),
            ('TIME', '12:34:56'),
            ('TITLE', 'Authored title'),
          ])
            WmlParagraph(
              inlines: [
                WmlRun(text: kind + 'Label '),
                ...field(kind, [
                  WmlRun(
                    text: cache,
                    properties: WmlRunProps(bold: true, color: '123456'),
                    hyperlink: WmlHyperlink(
                      url: 'https://example.test/' + kind.toLowerCase(),
                    ),
                  ),
                ]),
                WmlRun(text: ' EndLabel'),
              ],
            ),
        ],
      ),
    ],
  );
  native.properties.title = 'Consumer title';
  save('native-fields', native, {
    'pages': 1,
    'source_fields': {
      'page-number': '37',
      'page-count': '121',
      'date': '17.11.2026',
      'time': '12:34:56',
      'title': 'Authored title',
    },
    'field_types': ['PAGE', 'NUMPAGES', 'DATE', 'TIME', 'TITLE'],
    'links': [
      for (final kind in ['page', 'numpages', 'date', 'time', 'title'])
        'https://example.test/' + kind,
    ],
    'source_bold': true,
    'source_color': '123456',
  });

  save(
    'malformed-fields',
    WmlDocument(
      sections: [
        WmlSection(
          pageSize: size,
          margins: margins,
          blocks: [
            WmlParagraph(
              inlines: [
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
                WmlFieldBoundary(
                  kind: WmlFieldBoundaryKind.instruction,
                  text: 'PAGE',
                ),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
                WmlRun(text: 'KeepFirst'),
              ],
            ),
            paragraph('KeepNext'),
            WmlParagraph(
              inlines: [
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
                ...field('PAGE', [
                  WmlRun(text: 'OuterCache '),
                  ...field('NUMPAGES', [WmlRun(text: 'InnerCache')]),
                  WmlRun(text: ' TailCache'),
                ]),
              ],
            ),
            WmlParagraph(
              inlines: field(r'PAGE \* ROMAN', [WmlRun(text: 'RomanCache')]),
            ),
            paragraph('AfterCache'),
          ],
        ),
      ],
    ),
    {
      'pages': 1,
      'native_field_count': 0,
      'visible_words': [
        'KeepFirst',
        'KeepNext',
        'OuterCache',
        'InnerCache',
        'TailCache',
        'RomanCache',
        'AfterCache',
      ],
    },
  );

  save(
    'header-variants',
    WmlDocument(
      sections: [
        WmlSection(
          pageSize: size,
          margins: margins,
          differentFirstPage: true,
          differentOddEven: true,
          linkToPrevious: false,
          header: [paragraph('DefaultHeader')],
          footer: [paragraph('DefaultFooter')],
          firstHeader: [paragraph('FirstHeader')],
          firstFooter: [paragraph('FirstFooter')],
          evenHeader: [paragraph('EvenHeader')],
          evenFooter: [paragraph('EvenFooter')],
          blocks: [
            paragraph('BodyFirst'),
            paragraph('BodySecond', pageBreak: true),
            paragraph('BodyThird', pageBreak: true),
          ],
        ),
      ],
    ),
    {
      'pages': 3,
      'page_words': [
        ['FirstHeader', 'BodyFirst', 'FirstFooter'],
        ['EvenHeader', 'BodySecond', 'EvenFooter'],
        ['DefaultHeader', 'BodyThird', 'DefaultFooter'],
      ],
    },
  );

  save(
    'bookmark-ranges',
    WmlDocument(
      sections: [
        WmlSection(
          pageSize: size,
          margins: margins,
          header: [range('HeaderMark', 'HeaderBookmark')],
          blocks: [
            WmlParagraph(
              inlines: [
                WmlBookmarkBoundary(id: '1', isStart: true, name: 'BodyMark'),
                WmlRun(text: 'BeginBody'),
              ],
            ),
            WmlTable(
              grid: [200],
              rows: [
                WmlTableRow(
                  cells: [
                    WmlTableCell(blocks: [paragraph('MiddleBody')]),
                  ],
                ),
              ],
            ),
            WmlParagraph(
              inlines: [
                WmlRun(text: 'EndBody'),
                WmlBookmarkBoundary(id: '1', isStart: false),
              ],
            ),
            WmlFrame(
              x: 36,
              y: 190,
              width: 210,
              height: 35,
              blocks: [range('FrameMark', 'FrameBookmark')],
            ),
            WmlToc(
              title: 'TocTitle',
              titleParagraph: WmlParagraph(
                inlines: [
                  WmlBookmarkBoundary(id: '8', isStart: true, name: 'TocMark'),
                  WmlRun(text: 'TocTitle'),
                ],
              ),
            ),
            WmlParagraph(
              inlines: [
                WmlRun(text: 'TocTail'),
                WmlBookmarkBoundary(id: '8', isStart: false),
              ],
            ),
          ],
        ),
      ],
    ),
    {
      'pages': 1,
      'visible_words': [
        'HeaderBookmark',
        'BeginBody',
        'MiddleBody',
        'EndBody',
        'FrameBookmark',
        'TocTitle',
        'TocTail',
      ],
      'bookmark_text': {
        'BodyMark': 'BeginBodyMiddleBodyEndBody',
        'HeaderMark': 'HeaderBookmark',
        'FrameMark': 'FrameBookmark',
        'TocMark': 'TocTitleTocTail',
      },
    },
  );

  save(
    'empty-field-column',
    WmlDocument(
      sections: [
        WmlSection(
          pageSize: size,
          margins: margins,
          columnCount: 2,
          columnSpace: 24,
          blocks: [
            WmlParagraph(
              inlines: [
                ...field('PAGE', []),
                WmlBreak(WmlBreakType.column),
                WmlRun(text: 'RightColumn'),
              ],
            ),
          ],
        ),
      ],
    ),
    {
      'pages': 1,
      'source_native_fields_by_paragraph': [1, 0],
      'right_column_label': 'RightColumn',
      'minimum_column_separation_pt': 150,
    },
  );
  File(output.path + '/fixtures.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest) + '\n',
  );
}
