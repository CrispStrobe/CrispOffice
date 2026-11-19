import 'package:quds_office_engine/quds_office_engine.dart';

/// Neutral product brief used by the Studio sample workspace.
abstract final class CrispOfficeSample {
  static WmlDocument build() {
    WmlParagraph paragraph(String text, {String? style, bool bold = false}) {
      final result = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(
            text: text,
            properties: WmlRunProps(bold: bold),
          ),
        ],
      );
      if (style != null) WordStyles.apply(result, style);
      return result;
    }

    return WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            paragraph('CrispOffice product brief', style: 'Title'),
            paragraph(
              'A sample document for the CrispOffice workspace. '
              'It demonstrates headings, body text and editable paragraphs '
              'without third-party content.',
            ),
            paragraph('Overview', style: 'Heading1'),
            paragraph(
              'CrispOffice opens and edits OOXML documents locally. The '
              'document surface, ribbon and save path are shared across '
              'documents, spreadsheets and presentations.',
            ),
            paragraph('Workflow', style: 'Heading1'),
            paragraph('1. Open a local or connected document.'),
            paragraph('2. Edit with the ribbon and context menus.'),
            paragraph('3. Save back to the original file or export a copy.'),
            paragraph('Notes', style: 'Heading1'),
            paragraph(
              'All names and examples in this document are fictional. '
              'CrispOffice is independent software and is not affiliated '
              'with any office-suite vendor.',
            ),
          ],
        ),
      ],
    );
  }
}
