import 'package:quds_mail_core/quds_mail_core.dart';

/// A bounded view of an immutable authored body. Clipping never changes the
/// draft or frozen message and never returns half of a UTF-16 surrogate pair.
final class StudioMailRichPreviewData {
  factory StudioMailRichPreviewData(MailComposeBody body) {
    final paragraphs = <MailComposeParagraph>[];
    var bytes = 0;
    var count = 0;
    var truncated = false;
    for (final paragraph in body.paragraphs) {
      if (paragraphs.length == maxParagraphs ||
          count == maxRuns ||
          bytes == maxTextBytes) {
        truncated = true;
        break;
      }
      if (paragraphs.isNotEmpty) bytes++;
      final runs = <MailComposeRun>[];
      for (final run in paragraph.runs) {
        if (count == maxRuns) {
          truncated = true;
          break;
        }
        final prefix = _prefix(run.text, maxTextBytes - bytes);
        bytes += prefix.bytes;
        count++;
        runs.add(
          prefix.truncated
              ? MailComposeRun(
                  text: prefix.text,
                  bold: run.bold,
                  italic: run.italic,
                  underline: run.underline,
                  strike: run.strike,
                  link: run.link,
                )
              : run,
        );
        if (prefix.truncated) {
          truncated = true;
          break;
        }
      }
      paragraphs.add(
        MailComposeParagraph(
          runs: runs,
          alignment: paragraph.alignment,
          rightToLeft: paragraph.rightToLeft,
        ),
      );
      if (truncated) break;
    }
    return StudioMailRichPreviewData._(
      List<MailComposeParagraph>.unmodifiable(paragraphs),
      bytes,
      count,
      truncated,
    );
  }

  const StudioMailRichPreviewData._(
    this.paragraphs,
    this.visibleTextBytes,
    this.visibleRuns,
    this.truncated,
  );

  static const maxTextBytes = 64 * 1024;
  static const maxParagraphs = 256;
  static const maxRuns = 2048;

  final List<MailComposeParagraph> paragraphs;
  final int visibleTextBytes;
  final int visibleRuns;
  final bool truncated;
}

/// The existing plain review uses the same scalar-safe visible text budget.
({String text, bool truncated}) studioMailPlainPreviewText(String text) {
  final prefix = _prefix(text, StudioMailRichPreviewData.maxTextBytes);
  return (text: prefix.text, truncated: prefix.truncated);
}

({String text, int bytes, bool truncated}) _prefix(String text, int limit) {
  var bytes = 0;
  var end = 0;
  while (end < text.length) {
    final unit = text.codeUnitAt(end);
    final paired =
        unit >= 0xd800 &&
        unit <= 0xdbff &&
        end + 1 < text.length &&
        text.codeUnitAt(end + 1) >= 0xdc00 &&
        text.codeUnitAt(end + 1) <= 0xdfff;
    final size = paired
        ? 4
        : unit < 0x80
        ? 1
        : unit < 0x800
        ? 2
        : 3;
    if (size > limit - bytes) break;
    bytes += size;
    end += paired ? 2 : 1;
  }
  return (
    text: end == text.length ? text : text.substring(0, end),
    bytes: bytes,
    truncated: end != text.length,
  );
}
