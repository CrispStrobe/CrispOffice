import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Captures only the explicitly supported Mail authoring surface. Unsupported
/// objects, document stories and formatting fail instead of being flattened or
/// silently removed. The mutable Word document is never retained by the result.
MailComposeBody studioMailRichBodyFromDocument(WmlDocument document) {
  final blocks = _checkedBlocks(document);
  if (blocks.length > MailComposeBody.maxParagraphs) _unsupported();
  var runCount = 0;
  final paragraphs = <MailComposeParagraph>[];
  for (final block in blocks) {
    final paragraph = _checkedParagraph(block);
    final props = paragraph.properties;
    final runs = <MailComposeRun>[];
    for (final inline in paragraph.inlines) {
      if (++runCount > MailComposeBody.maxRuns) _unsupported();
      final run = _checkedRun(inline);
      runs.add(_composeRun(run.text, run.properties, link: run.hyperlink?.url));
    }
    if (paragraph.text.isEmpty && props.importedParagraphMark != null) {
      // Enter stores the next typing format on its paragraph mark. Retain it
      // as the final empty run; Word reads that run when the Mail body reopens.
      // It supersedes empty run placeholders; zero-width links retain their
      // metadata. Every original run was still checked before this projection.
      runs.removeWhere((run) => run.link == null);
      runs.add(_composeRun('', props.importedParagraphMark!));
    }
    paragraphs.add(
      MailComposeParagraph(
        runs: runs,
        alignment: switch (props.justification) {
          WmlJustification.left => MailComposeAlignment.left,
          WmlJustification.center => MailComposeAlignment.center,
          WmlJustification.right => MailComposeAlignment.right,
          WmlJustification.justify => MailComposeAlignment.justify,
          WmlJustification.distributed => _unsupported(),
        },
        rightToLeft: props.rightToLeft,
      ),
    );
  }
  return MailComposeBody(paragraphs: paragraphs);
}

/// Validates the editor without imposing new rich-format limits on legacy
/// unformatted drafts. In particular, large escaped text and many plain
/// paragraphs do not construct an HTML buffer. Null authorizes only the host's
/// existing plain-text snapshot path; unsupported content still fails.
MailComposeBody? studioMailOptionalRichBodyFromDocument(WmlDocument document) {
  var formatted = false;
  for (final block in _checkedBlocks(document)) {
    final paragraph = _checkedParagraph(block);
    final props = paragraph.properties;
    // The Word surface infers this pair for ordinary Arabic text. Only an
    // explicit alignment/direction command (or another authored format below)
    // opts a legacy plain draft into rich limits. Restored rich paragraphs and
    // the Mail direction toolbar explicitly mark justification.
    final inferredRtl =
        props.rightToLeft == true &&
        props.justification == WmlJustification.right &&
        !props.explicitJustification;
    formatted |=
        !inferredRtl &&
        (props.justification != WmlJustification.left ||
            props.rightToLeft != null);
    final emptyTypingMark =
        paragraph.text.isEmpty && props.importedParagraphMark != null;
    for (final inline in paragraph.inlines) {
      final run = _checkedRun(inline);
      final format = run.properties;
      formatted |=
          run.hyperlink != null ||
          (!emptyTypingMark &&
              (format.bold ||
                  format.italic ||
                  format.underline != WmlUnderline.none ||
                  format.strike ||
                  format.color.toUpperCase() == WordLink.color));
    }
    if (emptyTypingMark) {
      formatted |= _composeRun('', props.importedParagraphMark!).hasFormatting;
    }
  }
  return formatted ? studioMailRichBodyFromDocument(document) : null;
}

MailComposeRun _composeRun(String text, WmlRunProps format, {String? link}) =>
    MailComposeRun(
      text: text,
      bold: format.bold,
      italic: format.italic,
      underline: format.underline == WmlUnderline.single,
      strike: format.strike,
      link: link,
      linkBlue: format.color.toUpperCase() == WordLink.color,
    );

List<WmlBlock> _checkedBlocks(WmlDocument document) {
  if (document.sections.length != 1 ||
      (document.package != null &&
          !_isDormantEditorNumbering(document.package!)) ||
      document.comments.isNotEmpty ||
      document.footnotes.isNotEmpty ||
      document.endnotes.isNotEmpty ||
      document.revisions.isNotEmpty ||
      document.citations.isNotEmpty ||
      document.indexMarks.isNotEmpty ||
      document.styles.isNotEmpty ||
      document.importedStyles.isNotEmpty ||
      document.mailMergeRecords.isNotEmpty ||
      document.trackRevisions ||
      document.watermark.isNotEmpty ||
      document.restrictEditing) {
    _unsupported();
  }
  final section = document.sections.single;
  if (section.blocks.isEmpty ||
      section.columnCount != 1 ||
      section.columnSep ||
      section.lineNumbers ||
      section.sourceProperties != null ||
      section.preservedStories.isNotEmpty ||
      section.header.isNotEmpty ||
      section.footer.isNotEmpty ||
      section.firstHeader.isNotEmpty ||
      section.firstFooter.isNotEmpty ||
      section.evenHeader.isNotEmpty ||
      section.evenFooter.isNotEmpty ||
      section.headerVisuals.isNotEmpty ||
      section.footerVisuals.isNotEmpty ||
      section.firstHeaderVisuals.isNotEmpty ||
      section.firstFooterVisuals.isNotEmpty ||
      section.evenHeaderVisuals.isNotEmpty ||
      section.evenFooterVisuals.isNotEmpty) {
    _unsupported();
  }
  return section.blocks;
}

// Word's list command retains its reusable numbering definitions after Undo.
// Those definitions carry no authored content once all paragraph list props
// have been undone. Admit only the exact in-memory shells the editor creates;
// imported packages, extra parts and modified definitions remain unsupported.
bool _isDormantEditorNumbering(OpcPackage package) {
  if (package.sourceLength != 0 || package.partNames.length != 2) return false;
  for (final expected in _editorNumberingPackages) {
    if (!_sameStringMap(
          package.contentTypes.defaults,
          expected.contentTypes.defaults,
        ) ||
        !_sameStringMap(
          package.contentTypes.overrides,
          expected.contentTypes.overrides,
        ) ||
        !_sameRelationships(
          package.packageRelationships,
          expected.packageRelationships,
        )) {
      continue;
    }
    var matches = true;
    for (final expectedPart in expected.parts) {
      final actual = package.getPart(expectedPart.uri);
      if (actual == null ||
          actual.contentType != expectedPart.contentType ||
          actual.length != expectedPart.length ||
          !_sameRelationships(
            actual.relationships,
            expectedPart.relationships,
          ) ||
          !_sameBytes(actual.bytesView, expectedPart.bytesView)) {
        matches = false;
        break;
      }
    }
    if (matches) {
      // OPC can also contain relationships whose source part is absent. The
      // deterministic small package encoding checks that otherwise invisible
      // metadata too, after every public part has matched the bounded shell.
      return _sameBytes(
        package.save(deflateLevel: 0),
        _editorNumberingArchives[expected]!,
      );
    }
  }
  return false;
}

final List<OpcPackage> _editorNumberingPackages = [
  for (final kinds in const [
    [true],
    [false],
    [true, false],
    [false, true],
  ])
    _editorNumberingPackage(kinds),
];

final Map<OpcPackage, List<int>> _editorNumberingArchives = {
  for (final package in _editorNumberingPackages)
    package: package.save(deflateLevel: 0),
};

OpcPackage _editorNumberingPackage(List<bool> kinds) {
  final document = WmlDocument.empty();
  for (final numbered in kinds) {
    WordLists.numberingId(document, numbered: numbered);
  }
  return document.package!;
}

bool _sameStringMap(Map<String, String> actual, Map<String, String> expected) =>
    actual.length == expected.length &&
    expected.entries.every((entry) => actual[entry.key] == entry.value);

bool _sameBytes(List<int> actual, List<int> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

bool _sameRelationships(
  RelationshipCollection actual,
  RelationshipCollection expected,
) {
  if (actual.length != expected.length) return false;
  final actualItems = actual.items;
  final expectedItems = expected.items;
  for (var index = 0; index < actualItems.length; index++) {
    final item = actualItems[index];
    final expectedItem = expectedItems[index];
    if (item.id != expectedItem.id ||
        item.type != expectedItem.type ||
        item.target != expectedItem.target ||
        item.targetMode != expectedItem.targetMode) {
      return false;
    }
  }
  return true;
}

WmlParagraph _checkedParagraph(WmlBlock block) {
  if (block is! WmlParagraph || block.contentControlWrappers.isNotEmpty) {
    _unsupported();
  }
  _checkParagraph(block.properties);
  return block;
}

WmlRun _checkedRun(WmlInline inline) {
  if (inline is! WmlRun ||
      inline.commentIds.isNotEmpty ||
      inline.noteRefId != null ||
      inline.noteRefEndnote ||
      inline.noteRefCustomMark ||
      inline.fieldInstruction != null ||
      inline.fieldLocked ||
      inline.fieldDirty != null ||
      inline.inlineVisual != null) {
    _unsupported();
  }
  final link = inline.hyperlink;
  if (link != null &&
      (link.anchor != null ||
          link.file != null ||
          link.url == null ||
          !MailComposeRun.isSupportedLink(link.url!))) {
    _unsupported();
  }
  _checkRun(inline.properties);
  return inline;
}

/// Restores a fresh editable Word surface without resources, hidden stories,
/// fields or imported package state. Every invocation creates independent
/// mutable paragraphs/runs; the immutable Mail snapshot remains unchanged.
WmlDocument studioMailDocumentFromRichBody(MailComposeBody body) => WmlDocument(
  sections: [
    WmlSection(
      blocks: [
        for (final paragraph in body.paragraphs)
          WmlParagraph(
            properties: WmlParagraphProps(
              justification: switch (paragraph.alignment) {
                MailComposeAlignment.left => WmlJustification.left,
                MailComposeAlignment.center => WmlJustification.center,
                MailComposeAlignment.right => WmlJustification.right,
                MailComposeAlignment.justify => WmlJustification.justify,
              },
              explicitJustification: true,
              rightToLeft: paragraph.rightToLeft,
            ),
            inlines: [
              for (final run in paragraph.runs)
                WmlRun(
                  text: run.text,
                  properties: WmlRunProps(
                    bold: run.bold,
                    italic: run.italic,
                    underline: run.underline
                        ? WmlUnderline.single
                        : WmlUnderline.none,
                    strike: run.strike,
                    color: run.linkBlue ? WordLink.color : '000000',
                  ),
                  hyperlink: run.link == null
                      ? null
                      : WmlHyperlink(url: run.link),
                ),
            ],
          ),
      ],
    ),
  ],
);

void _checkParagraph(WmlParagraphProps props) {
  if (props.sourcePropertiesXml != null ||
      props.importedValues != null ||
      props.lineSpacing != 1.15 ||
      props.lineSpacingRule != WmlLineSpacingRule.auto ||
      props.spacingBefore != 0 ||
      props.spacingAfter != 8 ||
      props.contextualSpacing ||
      props.indent.left != 0 ||
      props.indent.right != 0 ||
      props.indent.firstLine != 0 ||
      props.indent.hanging != 0 ||
      props.tabs.isNotEmpty ||
      props.keepTogether ||
      props.keepWithNext ||
      props.widowControl != null ||
      props.pageBreakBefore ||
      props.columnBreakBefore ||
      props.numId != null ||
      props.ilvl != 0 ||
      props.listLabel != null ||
      props.listRestart != null ||
      props.pageNumberField ||
      props.headingLevel != null ||
      (props.styleId != null && props.styleId != 'Normal') ||
      (props.defaultStyleId != null && props.defaultStyleId != 'Normal') ||
      props.fieldInstruction != null ||
      props.fieldBegin ||
      props.fieldSeparate ||
      props.fieldEnd ||
      props.bookmarkName != null ||
      props.sourceBookmarkName != null ||
      props.dropCapLines != 0 ||
      props.shadingFill != null ||
      props.borderColor != null ||
      props.noteId != null ||
      props.endnoteRef) {
    _unsupported();
  }
  if (props.justification == WmlJustification.distributed) _unsupported();
  if (props.importedParagraphMark case final mark?) _checkRun(mark);
}

void _checkRun(WmlRunProps props) {
  if (props.sourcePropertiesXml != null ||
      props.importedValues != null ||
      props.hasEmptyFormattingRevision ||
      props.styleId != null ||
      props.allCaps ||
      props.smallCaps ||
      (props.color.toUpperCase() != '000000' &&
          props.color.toUpperCase() != WordLink.color) ||
      props.highlight != null ||
      props.fontSizeHalfPoints != 22 ||
      props.kerningHalfPoints != 1 ||
      props.asciiFont != 'Arial' ||
      props.csFont != 'Arial' ||
      props.vertAlign != WmlVertAlign.baseline ||
      props.positionHalfPoints != 0 ||
      (props.underline != WmlUnderline.none &&
          props.underline != WmlUnderline.single)) {
    _unsupported();
  }
}

Never _unsupported() =>
    throw const FormatException('Unsupported Mail editor content.');
