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
  manifest.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(records)}\n',
  );
  print(
    'Generated ${records.length} ODT fixtures including two recovery controls.',
  );
}
