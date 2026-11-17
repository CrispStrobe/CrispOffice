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

  WmlRun reference(int id, {bool endnote = false, String? text}) => WmlRun(
    text: text ?? '$id',
    noteRefId: id,
    noteRefEndnote: endnote,
    properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
  );
  WmlNote note(int id, String text, {bool endnote = false}) => WmlNote(
    id: id,
    endnote: endnote,
    paragraphs: [paragraph(text, WmlParagraphProps())],
  );
  save(
    'word-note-stories.odt',
    OdtDocumentWriter.writeBytes(
      WmlDocument(
        sections: [
          WmlSection(
            header: [
              WmlParagraph(
                inlines: [
                  WmlRun(text: 'Header reference '),
                  reference(42),
                ],
              ),
            ],
            footer: [
              WmlParagraph(inlines: [reference(999, text: 'MISSING-REF')]),
            ],
            blocks: [
              WmlParagraph(
                inlines: [
                  WmlRun(text: 'First footnote '),
                  reference(42),
                  WmlRun(text: '; endnote '),
                  reference(77, endnote: true),
                  WmlRun(text: '; repeated footnote '),
                  reference(42),
                  WmlRun(text: '; second footnote '),
                  reference(8),
                  WmlRun(text: '; custom mark '),
                  reference(11, text: '†'),
                  WmlRun(text: '; empty authored reference '),
                  reference(12, text: ''),
                  WmlRun(text: '; explicit custom marker '),
                  reference(13)..noteRefCustomMark = true,
                  WmlRun(text: '*; repeated custom marker '),
                  reference(13)..noteRefCustomMark = true,
                  WmlRun(text: '*; custom endnote marker '),
                  reference(88, endnote: true)..noteRefCustomMark = true,
                  WmlRun(text: '*'),
                  WmlRun(text: '.'),
                ],
              ),
            ],
          ),
        ],
        footnotes: [
          WmlNote(
            id: 42,
            endnote: false,
            blocks: [
              WmlParagraph(
                properties: WmlParagraphProps(
                  lineSpacing: 18,
                  lineSpacingRule: WmlLineSpacingRule.exact,
                ),
                inlines: [
                  WmlRun(
                    text: 'Blue footnote body',
                    properties: WmlRunProps(bold: true, color: '0055AA'),
                  ),
                  WmlBreak(WmlBreakType.textWrapping),
                  WmlRun(text: 'Second footnote line '),
                  WmlRun(
                    text: 'Source',
                    hyperlink: WmlHyperlink(url: 'https://example.test/note'),
                  ),
                  WmlRun(
                    inlineVisual: WmlVisual(
                      visual: OfficeVisual(
                        kind: OfficeVisualKind.picture,
                        title: 'Note picture',
                        imageBytes: png,
                        width: 18,
                        height: 18,
                      ),
                    ),
                  ),
                ],
              ),
              WmlTable(
                grid: [90, 90],
                rows: [
                  WmlTableRow(
                    cells: [
                      WmlTableCell(
                        blocks: [
                          paragraph('Footnote cell A', WmlParagraphProps()),
                        ],
                      ),
                      WmlTableCell(
                        blocks: [
                          paragraph('Footnote cell B', WmlParagraphProps()),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          note(8, 'Second footnote body'),
          note(11, 'Custom-mark note body'),
          note(12, 'Empty-reference note body'),
          note(13, 'Explicit custom-mark body'),
        ],
        endnotes: [
          note(77, 'Endnote body on final page', endnote: true),
          note(88, 'Custom endnote body', endnote: true),
        ],
      ),
    ),
  );
  save(
    'word-note-recursion.odt',
    OdtDocumentWriter.writeBytes(
      WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlParagraph(
                inlines: [
                  WmlRun(text: 'Recursive reference A '),
                  reference(1),
                  WmlRun(text: ' and B '),
                  reference(2),
                ],
              ),
            ],
          ),
        ],
        footnotes: [
          WmlNote(
            id: 1,
            endnote: false,
            paragraphs: [
              WmlParagraph(
                inlines: [
                  WmlRun(text: 'A links to '),
                  reference(2),
                ],
              ),
            ],
          ),
          WmlNote(
            id: 2,
            endnote: false,
            paragraphs: [
              WmlParagraph(
                inlines: [
                  WmlRun(text: 'B links to '),
                  reference(1),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
  save(
    'word-covered-notes.odt',
    OdtDocumentWriter.writeBytes(
      WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlTable(
                rows: [
                  WmlTableRow(
                    cells: [
                      WmlTableCell(
                        vMerge: WmlVMerge.restart,
                        blocks: [
                          paragraph(
                            'Visible merged anchor',
                            WmlParagraphProps(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  WmlTableRow(
                    cells: [
                      WmlTableCell(
                        vMerge: WmlVMerge.cont,
                        blocks: [
                          WmlParagraph(inlines: [reference(404)]),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              WmlParagraph(
                inlines: [
                  WmlRun(text: 'First visible note '),
                  reference(8),
                ],
              ),
            ],
          ),
        ],
        footnotes: [
          note(404, 'HIDDEN_NOTE_BODY'),
          note(8, 'Visible note body'),
        ],
      ),
    ),
  );
}
