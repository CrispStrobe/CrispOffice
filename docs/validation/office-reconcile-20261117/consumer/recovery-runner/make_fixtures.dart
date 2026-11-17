import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:quds_office_engine/quds_office_engine.dart';
import '../runner-source/make_fixtures.dart' as historical;

void main(List<String> arguments) {
  // The prior 24 fixtures and all their numerical expectations are unchanged.
  historical.main(arguments);
  final directory = Directory(arguments.single);
  final manifest = File('${directory.path}/fixtures.json');
  final records = (jsonDecode(manifest.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  void save(String name, WmlDocument document, Map<String, Object?> spec) {
    File(
      '${directory.path}/$name.odt',
    ).writeAsBytesSync(OdtDocumentWriter.writeBytes(document));
    records.add({'name': name, 'file': '$name.odt', ...spec});
  }

  const size = WmlPageSize(width: 400, height: 500);
  const margins = WmlPageMargins(top: 36, bottom: 36, left: 36, right: 36);
  WmlParagraph painted(String text, String? fill, String? border) =>
      WmlParagraph(
        properties: WmlParagraphProps(shadingFill: fill, borderColor: border),
        inlines: [WmlRun(text: text)],
      );
  save(
    'paragraph-distinct-shading-borders',
    WmlDocument(
      sections: [
        WmlSection(
          pageSize: size,
          margins: margins,
          blocks: [
            painted('RedShade', 'FF0000', '0000FF'),
            painted('GreenShade', '00FF00', 'FF00FF'),
            painted('PlainUnshaded', null, null),
          ],
        ),
      ],
    ),
    {
      'page_sizes_pt': [
        [400, 500],
      ],
      'word_pages': {'RedShade': 1, 'GreenShade': 1, 'PlainUnshaded': 1},
      'vertical_order': ['RedShade', 'GreenShade', 'PlainUnshaded'],
      'paragraph_decorations': {
        'RedShade': {'fill': 'FF0000', 'border': '0000FF'},
        'GreenShade': {'fill': '00FF00', 'border': 'FF00FF'},
        'PlainUnshaded': {'fill': null, 'border': null},
      },
      'scope':
          'Adjacent paragraphs retain independent fills and borders; '
          'unshaded content stays unshaded in independently reopened DOCX.',
    },
  );
  save(
    'page-field-styled-footer',
    WmlDocument(
      sections: [
        WmlSection(
          pageSize: size,
          margins: margins,
          linkToPrevious: false,
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: 'FirstBody')]),
            WmlParagraph(
              properties: WmlParagraphProps(pageBreakBefore: true),
              inlines: [WmlRun(text: 'SecondBody')],
            ),
          ],
          footer: [
            WmlParagraph(
              properties: WmlParagraphProps(pageNumberField: true),
              inlines: [
                WmlRun(
                  text: '1  |  Al Tahreer Neighborhood Profile',
                  properties: WmlRunProps(
                    bold: true,
                    color: '0000FF',
                    fontSizeHalfPoints: 28,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    {
      'page_sizes_pt': [
        [400, 500],
        [400, 500],
      ],
      'word_pages': {'FirstBody': 1, 'SecondBody': 2},
      'styled_footer': {
        'suffix': '| Al Tahreer Neighborhood Profile',
        'page_numbers': [1, 2],
        'bold': true,
        'color': '0000FF',
        'font_size_half_points': 28,
      },
      'scope':
          'Live footer PAGE field renders 1 and 2 with the entire authored '
          'title suffix; field and suffix retain bold blue 14pt styling.',
    },
  );
  WmlParagraph text(String value) => WmlParagraph(inlines: [WmlRun(text: value)]);
  save(
    'custom-tabs-independent-positions',
    WmlDocument(sections: [WmlSection(pageSize: size, margins: margins, blocks: [
      text('TabsSection'),
      WmlParagraph(properties: WmlParagraphProps(tabs: [WmlTabStop(position: 72)]), inlines: [WmlRun(text: 'NearLabel\tNearValue')]),
      WmlParagraph(properties: WmlParagraphProps(tabs: [WmlTabStop(position: 144)]), inlines: [WmlRun(text: 'FarLabel\tFarValue')]),
    ])]),
    {
      'page_sizes_pt': [[400, 500]],
      'word_pages': {'TabsSection': 1, 'NearLabel': 1, 'NearValue': 1, 'FarLabel': 1, 'FarValue': 1},
      'vertical_order': ['TabsSection', 'NearValue', 'FarValue'],
      'tab_positions': {
        'NearValue': {'position_pt': 72, 'page_left_pt': 108},
        'FarValue': {'position_pt': 144, 'page_left_pt': 180},
      },
      'scope': 'Independent PDF text placement and reopened DOCX retain distinct authored custom tabs for otherwise equal paragraphs.',
    },
  );
  save(
    'table-minimum-row-grows',
    WmlDocument(sections: [WmlSection(pageSize: size, margins: margins, blocks: [
      text('MinimumSection'),
      WmlTable(grid: [328], rows: [WmlTableRow(height: 6, cells: [WmlTableCell(
        fillColor: 'cCeEfF', borderTop: true, borderBottom: true, borderLeft: true, borderRight: true,
        blocks: [text('RowTop'), text('RowMiddle'), text('RowBottom')],
      )])]),
      text('AfterTable'),
    ])]),
    {
      'page_sizes_pt': [[400, 500]],
      'word_pages': {'MinimumSection': 1, 'RowTop': 1, 'RowMiddle': 1, 'RowBottom': 1, 'AfterTable': 1},
      'vertical_order': ['MinimumSection', 'RowTop', 'RowMiddle', 'RowBottom', 'AfterTable'],
      'minimum_row': {'minimum_pt': 6, 'words': ['RowTop', 'RowMiddle', 'RowBottom']},
      'scope': 'A six-point minimum row grows around three authored lines in an independent consumer and remains non-fixed in reopened DOCX.',
    },
  );
  save(
    'table-invalid-properties-preserve-content',
    WmlDocument(sections: [WmlSection(pageSize: size, margins: margins, blocks: [
      text('InvalidSection'),
      WmlTable(grid: [double.nan], rows: [
        WmlTableRow(height: double.nan, cells: [WmlTableCell(fillColor: 'auto', borderRight: true, blocks: [text('InvalidOne')])]),
        WmlTableRow(height: -1, cells: [WmlTableCell(fillColor: 'invalid"color', borderRight: true, blocks: [text('InvalidTwo')])]),
        WmlTableRow(height: double.infinity, cells: [WmlTableCell(fillColor: '#FF0000', borderRight: true, blocks: [text('InvalidThree')])]),
      ]),
    ])]),
    {
      'page_sizes_pt': [[400, 500]],
      'word_pages': {'InvalidSection': 1, 'InvalidOne': 1, 'InvalidTwo': 1, 'InvalidThree': 1},
      'vertical_order': ['InvalidSection', 'InvalidOne', 'InvalidTwo', 'InvalidThree'],
      'invalid_cells': ['InvalidOne', 'InvalidTwo', 'InvalidThree'],
      'scope': 'Invalid dimensions and fill strings are omitted while source cell text and valid right borders remain visible and the ODF package validates.',
    },
  );
  manifest.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(records)}\n',
  );
  print(
    'Generated ${records.length} ODT fixtures including five recovery and reconciliation controls.',
  );
}
