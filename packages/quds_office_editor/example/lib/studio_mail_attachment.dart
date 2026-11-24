import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';

enum StudioMailAttachmentProblem {
  invalidName,
  invalidMediaType,
  tooMany,
  tooLarge,
}

/// A content-redacted attachment failure suitable for localized host feedback.
final class StudioMailAttachmentException implements Exception {
  const StudioMailAttachmentException(this.problem);

  final StudioMailAttachmentProblem problem;

  @override
  String toString() => 'StudioMailAttachmentException(${problem.name})';
}

/// An owned attachment snapshot. Its bytes never refer back to a source file.
///
/// The caller must bound file reads before constructing this value. The same
/// bound is checked again before copying bytes supplied by other host ports.
final class StudioMailAttachment {
  factory StudioMailAttachment({
    required String name,
    required Uint8List bytes,
    String? mediaType,
    int maxBytes = StudioMailAttachments.defaultMaxTotalBytes,
  }) {
    validateName(name);
    if (bytes.length > maxBytes) {
      throw const StudioMailAttachmentException(
        StudioMailAttachmentProblem.tooLarge,
      );
    }
    final type = mediaType ?? mediaTypeForName(name);
    if (!_isSupportedMediaType(type)) {
      throw const StudioMailAttachmentException(
        StudioMailAttachmentProblem.invalidMediaType,
      );
    }
    return StudioMailAttachment._(name, MailBytes(bytes), type.toLowerCase());
  }

  const StudioMailAttachment._(this.name, this.content, this.mediaType);

  final String name;
  final MailBytes content;
  final String mediaType;

  int get length => content.length;

  static const maxNameBytes = 255;

  static void validateName(String name) {
    if (!isSupportedName(name)) {
      throw const StudioMailAttachmentException(
        StudioMailAttachmentProblem.invalidName,
      );
    }
  }

  /// Accepts a filename, never a path or a header fragment. Unicode filenames
  /// are preserved exactly and encoded as RFC 2231 parameters during sending.
  static bool isSupportedName(String name) {
    if (name.isEmpty ||
        name.length > maxNameBytes ||
        name.trim() != name ||
        name == '.' ||
        name == '..' ||
        name.contains(RegExp(r'[/\\]')) ||
        name.contains(
          RegExp(
            r'[\x00-\x1f\x7f-\x9f\u200e\u200f\u2028\u2029\u202a-\u202e\u2066-\u2069]',
          ),
        )) {
      return false;
    }
    final encoded = utf8.encode(name);
    return encoded.length <= maxNameBytes && utf8.decode(encoded) == name;
  }

  static bool _isSupportedMediaType(String type) =>
      type.length <= 127 &&
      RegExp(
        r'^(application|audio|font|image|text|video)/[a-z0-9!#$&^_.+\-]+$',
        caseSensitive: false,
      ).hasMatch(type);

  /// This is a filename hint, not content sniffing or format validation.
  /// Unrecognized formats, including EML, remain opaque binary attachments.
  static String mediaTypeForName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return 'application/octet-stream';
    return switch (name.substring(dot + 1).toLowerCase()) {
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'docm' => 'application/vnd.ms-word.document.macroenabled.12',
      'xlsm' => 'application/vnd.ms-excel.sheet.macroenabled.12',
      'pptm' => 'application/vnd.ms-powerpoint.presentation.macroenabled.12',
      'doc' => 'application/msword',
      'xls' => 'application/vnd.ms-excel',
      'ppt' => 'application/vnd.ms-powerpoint',
      'odt' => 'application/vnd.oasis.opendocument.text',
      'ods' => 'application/vnd.oasis.opendocument.spreadsheet',
      'odp' => 'application/vnd.oasis.opendocument.presentation',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'csv' => 'text/csv',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
  }
}

/// Immutable bounded selection, including an allocation-free const empty value
/// so plain-text draft callers can retain their const constructors.
final class StudioMailAttachments {
  const StudioMailAttachments.empty() : items = const [], totalBytes = 0;

  factory StudioMailAttachments.from(
    Iterable<StudioMailAttachment> attachments, {
    int maxTotalBytes = defaultMaxTotalBytes,
  }) {
    final selected = <StudioMailAttachment>[];
    var bytes = 0;
    for (final attachment in attachments) {
      if (selected.length == maxCount) {
        throw const StudioMailAttachmentException(
          StudioMailAttachmentProblem.tooMany,
        );
      }
      if (attachment.length > maxTotalBytes - bytes) {
        throw const StudioMailAttachmentException(
          StudioMailAttachmentProblem.tooLarge,
        );
      }
      bytes += attachment.length;
      selected.add(attachment);
    }
    return StudioMailAttachments._(List.unmodifiable(selected), bytes);
  }

  /// Copies the complete decoded source set into ordinary outgoing files.
  ///
  /// Inline parts are included as files; no content IDs or inline rendering
  /// relationships are carried into the text draft. All names, types and byte
  /// counts are admitted before copying any payload. Nothing is silently
  /// dropped, renamed or relabeled, including unsupported message containers.
  factory StudioMailAttachments.forwarded(
    List<MailAttachment> attachments, {
    int maxTotalBytes = defaultMaxTotalBytes,
  }) {
    if (attachments.length > maxCount) {
      throw const StudioMailAttachmentException(
        StudioMailAttachmentProblem.tooMany,
      );
    }
    var bytes = 0;
    for (final attachment in attachments) {
      if (attachment.content.length > maxTotalBytes - bytes) {
        throw const StudioMailAttachmentException(
          StudioMailAttachmentProblem.tooLarge,
        );
      }
      bytes += attachment.content.length;
      StudioMailAttachment.validateName(attachment.displayName);
      if (!StudioMailAttachment._isSupportedMediaType(attachment.mediaType)) {
        throw const StudioMailAttachmentException(
          StudioMailAttachmentProblem.invalidMediaType,
        );
      }
    }
    return StudioMailAttachments.from([
      for (final attachment in attachments)
        StudioMailAttachment(
          name: attachment.displayName,
          bytes: attachment.content.bytes,
          mediaType: attachment.mediaType,
          maxBytes: maxTotalBytes,
        ),
    ], maxTotalBytes: maxTotalBytes);
  }

  const StudioMailAttachments._(this.items, this.totalBytes);

  static const maxCount = 10;

  /// Product default for an ordinary account.
  static const defaultMaxTotalBytes = 20 * 1024 * 1024;

  /// Provider-specific ceiling accepted by the UI when the host has a verified
  /// claim (currently mailbox.org's published message-size limit).
  static const hardMaxTotalBytes = 100 * 1024 * 1024;

  /// Backwards-compatible default used by older callers/tests.
  static const maxTotalBytes = defaultMaxTotalBytes;

  final List<StudioMailAttachment> items;
  final int totalBytes;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
}
