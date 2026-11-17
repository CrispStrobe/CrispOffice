import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';

// Run from the activated repository: dart run <this file> <output directory>.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Expected one output directory');
  }
  final output = Directory(arguments.single)..createSync(recursive: true);
  void save(String name, List<int> bytes) =>
      File('${output.path}/$name').writeAsBytesSync(bytes);
  WmlParagraph paragraph(String text, WmlParagraphProps properties) =>
      WmlParagraph(
        properties: properties,
        inlines: [WmlRun(text: text)],
      );

  save(
    'word-paragraph-layout.odt',
    OdtDocumentWriter.writeBytes(
      WmlDocument(
        sections: [
          WmlSection(
            header: [
              WmlParagraph(
                inlines: [
                  WmlRun(
                    text: 'Blue report header',
                    properties: WmlRunProps(bold: true, color: '1234AB'),
                  ),
                  WmlBreak(WmlBreakType.textWrapping),
                  WmlRun(text: 'Second header line'),
                ],
              ),
            ],
            footer: [
              WmlParagraph(
                inlines: [
                  WmlRun(
                    text: 'Green footer',
                    properties: WmlRunProps(color: '118833'),
                  ),
                ],
              ),
            ],
            blocks: [
              paragraph(
                'Centered heading',
                WmlParagraphProps(
                  headingLevel: 2,
                  justification: WmlJustification.center,
                  lineSpacingRule: WmlLineSpacingRule.exact,
                  lineSpacing: 24,
                  spacingBefore: 12,
                  spacingAfter: 0,
                ),
              ),
              paragraph(
                'Automatic line one\nAutomatic line two',
                WmlParagraphProps(lineSpacing: 1.125, spacingAfter: 12),
              ),
              paragraph(
                'Exact line one\nExact line two\nExact line three',
                WmlParagraphProps(
                  lineSpacingRule: WmlLineSpacingRule.exact,
                  lineSpacing: 18,
                  spacingAfter: 12,
                ),
              ),
              paragraph(
                'Minimum line one\nMinimum line two',
                WmlParagraphProps(
                  lineSpacingRule: WmlLineSpacingRule.atLeast,
                  lineSpacing: 24,
                  spacingAfter: 12,
                ),
              ),
              paragraph(
                'فقرة عربية',
                WmlParagraphProps(
                  rightToLeft: true,
                  justification: WmlJustification.right,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
  );
  save(
    'word-list-integration.odt',
    OdtDocumentWriter.writeBytes(
      WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              for (var index = 1; index <= 3; index++)
                paragraph(
                  'Numbered item $index',
                  WmlParagraphProps(
                    numId: 1,
                    listLabel: '$index. ',
                    lineSpacingRule: WmlLineSpacingRule.exact,
                    lineSpacing: 18,
                  ),
                ),
              paragraph('Bullet group', WmlParagraphProps()),
              for (var index = 1; index <= 2; index++)
                paragraph(
                  'Bullet item $index',
                  WmlParagraphProps(numId: 2, listLabel: '•'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  save(
    'slide-image.odp',
    OdpPresentationWriter.writeBytes(
      PmlPresentation(
        slides: [
          PmlSlide(
            id: 1,
            shapes: [
              PmlShape(
                id: 2,
                name: 'Picture',
                transform: const PmlTransform(
                  x: 914400,
                  y: 914400,
                  cx: 914400,
                  cy: 914400,
                ),
                visual: OfficeVisual(
                  kind: OfficeVisualKind.picture,
                  imageBytes: png,
                  width: 72,
                  height: 72,
                ),
              ),
              PmlShape(
                id: 3,
                name: 'Caption',
                text: 'Picture export',
                transform: const PmlTransform(
                  x: 914400,
                  y: 2286000,
                  cx: 3657600,
                  cy: 914400,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  save(
    'word-empty-tables.odt',
    OdtDocumentWriter.writeBytes(
      WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlTable(),
              WmlTable(
                grid: [100, 100],
                rows: [
                  WmlTableRow(),
                  WmlTableRow(
                    cells: [
                      WmlTableCell(
                        blocks: [paragraph('Visible', WmlParagraphProps())],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
