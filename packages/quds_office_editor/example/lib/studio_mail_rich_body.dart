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
      final format = run.properties;
      runs.add(
        MailComposeRun(
          text: run.text,
          bold: format.bold,
          italic: format.italic,
          underline: format.underline == WmlUnderline.single,
          strike: format.strike,
          link: run.hyperlink?.url,
        ),
      );
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
    for (final inline in paragraph.inlines) {
      final run = _checkedRun(inline);
      final format = run.properties;
      formatted |=
          format.bold ||
          format.italic ||
          format.underline != WmlUnderline.none ||
          format.strike ||
          run.hyperlink != null;
    }
  }
  return formatted ? studioMailRichBodyFromDocument(document) : null;
}

List<WmlBlock> _checkedBlocks(WmlDocument document) {
  if (document.sections.length != 1 ||
      document.package != null ||
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
  _checkRun(inline.properties, linked: link != null);
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
                    color: run.link == null ? '000000' : WordLink.color,
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
      props.importedParagraphMark != null ||
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
}

void _checkRun(WmlRunProps props, {required bool linked}) {
  if (props.sourcePropertiesXml != null ||
      props.importedValues != null ||
      props.hasEmptyFormattingRevision ||
      props.styleId != null ||
      props.allCaps ||
      props.smallCaps ||
      (props.color.toUpperCase() != '000000' &&
          !(linked && props.color.toUpperCase() == WordLink.color)) ||
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
