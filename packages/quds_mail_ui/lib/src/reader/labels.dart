import 'package:quds_mail_core/quds_mail_core.dart';

/// User-visible text and formatting of the reader.
///
/// The defaults are English. Hosts with other UI languages subclass this
/// and pass the instance to [MailReaderController] (header lines are part of
/// the decoded text) and through it to the message view.
class MailReaderLabels {
  const MailReaderLabels();

  String get noSubject => '(No subject)';
  String get from => 'From';
  String get to => 'To';
  String get cc => 'Cc';
  String get bcc => 'Bcc';
  String get replyTo => 'Reply-To';
  String get date => 'Date';
  String get attachments => 'Attachments';
  String get noBody => '(No supported decoded body)';

  /// The sent date in the header, local time.
  String formatDate(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${weekdays[local.weekday - 1]}, ${local.day} '
        '${months[local.month - 1]} ${local.year}, '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /// An attachment size: bytes below 1 KB, otherwise KB or MB.
  String formatSize(int bytes) {
    if (bytes < 1024) return bytes == 1 ? '1 byte' : '$bytes bytes';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Shown above the message only when it is not completely decoded.
  String status(MailParseStatus status) => switch (status) {
    MailParseStatus.complete => 'Decoded message',
    MailParseStatus.partial => 'Partially decoded message',
    MailParseStatus.rejected => 'Message rejected',
    MailParseStatus.unsupported => 'Unsupported message',
    MailParseStatus.failed => 'Message decoding failed',
    MailParseStatus.cancelled => 'Message decoding cancelled',
  };

  String get loadExternalImage => 'Load external image';
  String get loadingExternalImages => 'Loading images…';
  String get externalImageBlocked => 'External image blocked';
  String get externalImagesUnavailable =>
      'External images could not be displayed.';
  String get someExternalImagesUnavailable =>
      'Some external images could not be displayed.';

  String get displayUnavailable => 'Message display unavailable';
  String get selectAll => 'Select all';
  String get copySelection => 'Copy selection';
  String get findInMessage => 'Find in message';
  String get findField => 'Find in message';
  String get rawSource => 'Raw source';
  String get hex => 'Hex';
  String get inspectHeaders => 'Inspect headers';
  String get headers => 'Message headers';
  String get copyHeaders => 'Copy headers';
  String get headersUnavailable =>
      'Raw headers are unavailable for this message.';
  String get showPlainText => 'Show plain text';
  String get showStaticHtml => 'Show formatted';
  String matches(int count, {required bool more}) =>
      '$count${more ? '+' : ''} ${count == 1 && !more ? 'match' : 'matches'}';
  String get previousMatch => 'Previous match (Shift+F3)';
  String get nextMatch => 'Next match (F3)';
  String get openReadOnly => 'Open read only';
}
