import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';

void main(List<String> args) {
  final document = WmlDocument(sections: [
    WmlSection(blocks: [
      WmlParagraph(inlines: [WmlRun(text: 'FIRST SECTION')]),
      WmlParagraph(inlines: [
        WmlRun(text: 'Page '),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: 'PAGE'),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
        WmlRun(text: '17', hyperlink: const WmlHyperlink(url: 'https://example.test/page')),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
        WmlRun(text: ' of '),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: 'NUMPAGES'),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
        WmlRun(text: '99'),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
      ]),
      WmlParagraph(inlines: [
        WmlRun(text: 'LOCKED '),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin, sourceXml: '<w:fldChar xmlns:w="${OfficeNamespaces.w}" w:fldCharType="begin" w:fldLock="1"/>'),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: 'PAGE'),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
        WmlRun(text: '23'),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
      ]),
    ]),
    WmlSection(
      pageSize: const WmlPageSize(width: 600, height: 400),
      blocks: [WmlToc(title: 'CONTENTS ON SECOND PAGE', entries: [
        WmlTocEntry(text: 'Introduction', level: 1, headingParagraphIndex: 0, pageNumber: 3),
        WmlTocEntry(text: 'Details', level: 2, headingParagraphIndex: 1, pageNumber: 4),
      ])],
    ),
  ]);
  File(args.single).writeAsBytesSync(OdtDocumentWriter.writeBytes(document));
}
