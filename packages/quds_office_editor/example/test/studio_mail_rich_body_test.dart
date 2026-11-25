import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_studio/studio_mail_rich_body.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Word runs, soft breaks, paragraphs, direction and links round-trip',
    () {
      final original = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlParagraph(
                inlines: [
                  WmlRun(text: 'Bold', properties: WmlRunProps(bold: true)),
                  WmlRun(
                    text: ' and\nsoft\tline',
                    properties: WmlRunProps(italic: true),
                  ),
                ],
              ),
              WmlParagraph(
                properties: WmlParagraphProps(
                  justification: WmlJustification.right,
                  rightToLeft: true,
                  explicitJustification: true,
                ),
                inlines: [
                  WordLink.linkedRun(
                    'مرحبا 📨',
                    const WmlHyperlink(url: 'https://example.test/?a=1&b=2'),
                  ),
                ],
              ),
              WmlParagraph(
                inlines: [
                  WmlRun(text: '', properties: WmlRunProps(strike: true)),
                ],
              ),
            ],
          ),
        ],
      );
      final snapshot = studioMailRichBodyFromDocument(original);
      expect(snapshot.plainText, 'Bold and\nsoft\tline\nمرحبا 📨\n');
      expect(
        snapshot.paragraphs[1].runs.single.link,
        'https://example.test/?a=1&b=2',
      );
      final restored = studioMailDocumentFromRichBody(snapshot);
      expect(studioMailRichBodyFromDocument(restored), snapshot);
      expect(restored.package, isNull);
      expect(restored.sections.single.blocks.length, 3);
      expect(
        restored.paragraphs.elementAt(1).properties.explicitJustification,
        isTrue,
      );
      final independent = studioMailDocumentFromRichBody(snapshot);
      (restored.paragraphs.first.inlines.first as WmlRun).text = 'Edited';
      expect(independent.paragraphs.first.text, 'Bold and\nsoft\tline');
      expect(snapshot.plainText, startsWith('Bold'));
    },
  );

  test('plain 1MiB HTML expansion and many paragraphs keep legacy path', () {
    final escaped = WmlDocument.empty(
      text: '&' * MailComposeBody.maxPlainTextBytes,
    );
    expect(studioMailOptionalRichBodyFromDocument(escaped), isNull);
    final many = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            for (var i = 0; i < MailComposeBody.maxParagraphs + 1; i++)
              WmlParagraph(inlines: [WmlRun(text: 'line')]),
          ],
        ),
      ],
    );
    expect(studioMailOptionalRichBodyFromDocument(many), isNull);
    (many.paragraphs.first.inlines.first as WmlRun).properties.bold = true;
    expect(
      () => studioMailOptionalRichBodyFromDocument(many),
      throwsFormatException,
    );
  });

  test('inferred Arabic direction stays plain; explicit RTL is preserved', () {
    final document = WmlDocument.empty(text: 'مرحبا');
    expect(document.paragraphs.single.properties.rightToLeft, isTrue);
    expect(studioMailOptionalRichBodyFromDocument(document), isNull);
    document.paragraphs.single.properties.explicitJustification = true;
    final rich = studioMailOptionalRichBodyFromDocument(document)!;
    expect(rich.paragraphs.single.rightToLeft, isTrue);
    expect(rich.paragraphs.single.alignment, MailComposeAlignment.right);
    expect(
      studioMailOptionalRichBodyFromDocument(
        studioMailDocumentFromRichBody(rich),
      ),
      rich,
    );
  });

  test('all supported run formats and alignments survive restoration', () {
    for (final alignment in MailComposeAlignment.values) {
      final body = MailComposeBody(
        paragraphs: [
          MailComposeParagraph(
            alignment: alignment,
            rightToLeft: false,
            runs: [
              MailComposeRun(
                text: 'Styled',
                bold: true,
                italic: true,
                underline: true,
                strike: true,
              ),
            ],
          ),
        ],
      );
      expect(
        studioMailRichBodyFromDocument(studioMailDocumentFromRichBody(body)),
        body,
      );
    }
  });

  test('empty paragraph/run stays editable with exact empty body', () {
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [WmlParagraph()]),
      ],
    );
    expect(studioMailOptionalRichBodyFromDocument(document), isNull);
    final snapshot = studioMailRichBodyFromDocument(document);
    final restored = studioMailDocumentFromRichBody(snapshot);
    expect(restored.paragraphs.single.inlines.single, isA<WmlRun>());
    expect(restored.paragraphs.single.text, isEmpty);
    expect(studioMailRichBodyFromDocument(restored), snapshot);
  });

  test('Undo of a list can retain dormant editor numbering definitions', () {
    for (final kinds in const [
      [true],
      [false],
      [true, false],
      [false, true],
    ]) {
      final document = WmlDocument.empty(text: 'Recover this body');
      final paragraph = document.paragraphs.single;
      for (final numbered in kinds) {
        final before = paragraph.properties.copy();
        paragraph.properties
          ..numId = WordLists.numberingId(document, numbered: numbered)
          ..listLabel = numbered ? '1. ' : '• ';
        expect(
          () => studioMailOptionalRichBodyFromDocument(document),
          throwsFormatException,
        );
        // applyParagraphFormat's history restores the paragraph properties,
        // retaining the reusable package definitions for redo and later lists.
        paragraph.properties = before;
        expect(document.package, isNotNull);
        expect(studioMailOptionalRichBodyFromDocument(document), isNull);
        expect(
          studioMailRichBodyFromDocument(document).plainText,
          'Recover this body',
        );
      }
      (paragraph.inlines.single as WmlRun).properties.bold = true;
      expect(
        studioMailOptionalRichBodyFromDocument(document)!
            .paragraphs
            .single
            .runs
            .single
            .bold,
        isTrue,
      );
    }
  });

  test('numbering residue cannot admit imported or modified package state', () {
    WmlDocument generated() {
      final document = WmlDocument.empty(text: 'Keep');
      WordLists.numberingId(document, numbered: true);
      return document;
    }

    final imported = generated();
    imported.package = OpcPackage.openBytes(imported.package!.save());
    final extraPart = generated();
    extraPart.package!.createPart('/word/hidden.xml', 'application/xml', [1]);
    final changedNumbering = generated();
    changedNumbering.package!
        .getPart('/word/numbering.xml')!
        .writeText('<w:numbering/>');
    final changedDocument = generated();
    changedDocument.package!.getPart('/word/document.xml')!.writeText('hidden');
    final externalRelationship = generated();
    externalRelationship.package!
        .relationshipsFor('/word/document.xml')
        .add(
          type: RelationshipTypes.hyperlink,
          target: 'https://example.test/private',
          targetMode: RelationshipTargetMode.external,
        );
    final changedTypes = generated();
    changedTypes.package!.contentTypes.setDefault('private', 'private/type');
    final orphanRelationships = generated();
    orphanRelationships.package!
        .relationshipsFor('/word/absent.xml')
        .add(
          type: RelationshipTypes.hyperlink,
          target: 'https://example.test/private',
          targetMode: RelationshipTargetMode.external,
        );
    for (final document in [
      imported,
      extraPart,
      changedNumbering,
      changedDocument,
      externalRelationship,
      changedTypes,
      orphanRelationships,
    ]) {
      expect(
        () => studioMailOptionalRichBodyFromDocument(document),
        throwsFormatException,
      );
    }
  });

  final unsupportedRuns = <String, WmlRun>{
    'field': WmlRun(text: 'cached', fieldInstruction: 'PAGE'),
    'note': WmlRun(text: 'note', noteRefId: 1),
    'comment': WmlRun(text: 'comment', commentIds: [1]),
    'local link': WmlRun(
      text: 'file',
      hyperlink: const WmlHyperlink(file: '/private'),
    ),
    'script link': WmlRun(
      text: 'script',
      hyperlink: const WmlHyperlink(url: 'javascript:alert(1)'),
    ),
    'anchor link': WmlRun(
      text: 'anchor',
      hyperlink: const WmlHyperlink(anchor: 'section'),
    ),
    'highlight': WmlRun(
      text: 'highlight',
      properties: WmlRunProps(highlight: 'FFFF00'),
    ),
    'red': WmlRun(
      text: 'red',
      properties: WmlRunProps(color: 'FF0000'),
    ),
    'font size': WmlRun(
      text: 'size',
      properties: WmlRunProps(fontSizeHalfPoints: 48),
    ),
    'caps': WmlRun(text: 'caps', properties: WmlRunProps(allCaps: true)),
    'super': WmlRun(
      text: 'super',
      properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
    ),
    'wavy underline': WmlRun(
      text: 'wavy',
      properties: WmlRunProps(underline: WmlUnderline.wavy),
    ),
  };
  for (final entry in unsupportedRuns.entries) {
    test(
      'unsupported ${entry.key} cannot silently enter plain or rich path',
      () {
        final doc = WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlParagraph(inlines: [entry.value]),
              ],
            ),
          ],
        );
        expect(
          () => studioMailRichBodyFromDocument(doc),
          throwsFormatException,
        );
        expect(
          () => studioMailOptionalRichBodyFromDocument(doc),
          throwsFormatException,
        );
      },
    );
  }

  final unsupportedParagraphs = <String, WmlParagraphProps>{
    'list': WmlParagraphProps(numId: 1, listLabel: '• '),
    'heading': WmlParagraphProps(headingLevel: 1),
    'style': WmlParagraphProps(styleId: 'Heading1'),
    'indent': WmlParagraphProps(indent: const WmlIndent(left: 18)),
    'distributed': WmlParagraphProps(
      justification: WmlJustification.distributed,
    ),
    'field': WmlParagraphProps(fieldInstruction: 'PAGE'),
    'page break': WmlParagraphProps(pageBreakBefore: true),
    'shading': WmlParagraphProps(shadingFill: 'FFFF00'),
  };
  for (final entry in unsupportedParagraphs.entries) {
    test('unsupported paragraph ${entry.key} is refused', () {
      final doc = WmlDocument(
        sections: [
          WmlSection(blocks: [WmlParagraph(properties: entry.value)]),
        ],
      );
      expect(
        () => studioMailOptionalRichBodyFromDocument(doc),
        throwsFormatException,
      );
    });
  }

  test(
    'tables, package imports, hidden stories and revision state are refused',
    () {
      final documents = [
        WmlDocument(
          sections: [
            WmlSection(blocks: [WmlTable()]),
          ],
        ),
        WmlDocument.empty()..trackRevisions = true,
        WmlDocument.empty()..package = OpcPackage.create(OpcPackageKind.word),
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [WmlParagraph()],
              header: [
                WmlParagraph(inlines: [WmlRun(text: 'hidden')]),
              ],
            ),
          ],
        ),
        WmlDocument(sections: [WmlSection(), WmlSection()]),
      ];
      for (final doc in documents) {
        expect(
          () => studioMailOptionalRichBodyFromDocument(doc),
          throwsFormatException,
        );
      }
    },
  );
}
