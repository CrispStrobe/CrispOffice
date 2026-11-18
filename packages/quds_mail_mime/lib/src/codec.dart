import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/mime_core.dart' as mime;
import 'package:quds_mail_core/quds_mail_core.dart';

part 'scan.dart';
part 'transfer.dart';

/// A bounded, account-free EML reader over the public portable MIME surface.
///
/// The range scanner admits header blocks and MIME parts before allocation.
/// enough_mail owns header, parameter, address and date parsing; payloads use
/// strict transfer validation against original byte ranges. In particular, the
/// upstream text serializer is never used to export originals or attachments.
/// This is synchronous bounded work, not a streaming or background parser.
final class QudsMimeCodec implements MailCodec {
  const QudsMimeCodec();

  @override
  MailParseResult parse(
    Uint8List bytes, {
    MailReadBudget budget = const MailReadBudget(),
    MailCancellationToken? cancellation,
  }) {
    budget.validate();
    if (cancellation?.isCancelled ?? false) {
      return MailParseResult(
        status: MailParseStatus.cancelled,
        diagnostics: const [
          MailDiagnostic(
            code: MailDiagnosticCode.cancelled,
            message: 'Message reading was cancelled.',
          ),
        ],
      );
    }
    if (bytes.length > budget.maxRawBytes) {
      return MailParseResult(
        status: MailParseStatus.rejected,
        diagnostics: [
          MailDiagnostic(
            code: MailDiagnosticCode.rawLimit,
            message: 'The original message exceeds the input limit.',
            severity: MailDiagnosticSeverity.error,
            observed: bytes.length,
            limit: budget.maxRawBytes,
          ),
        ],
      );
    }
    final raw = MailBytes(bytes);
    final reader = _Reader(raw, budget, cancellation);
    return mime.MimeDiagnostics.run(() {
      try {
        final root = reader.scan(0, raw.length, '1', 1);
        final envelope = reader.envelope(root);
        final body = reader.project(root, allowBody: true);
        cancellation?.throwIfCancelled();
        final message = MailMessage(
          raw: raw,
          envelope: envelope,
          body: MailBody(
            plainText: body.plain,
            html: body.html,
            plainPartPath: body.plainPath,
            htmlPartPath: body.htmlPath,
          ),
          attachments: reader.attachments,
        );
        final unsupported = reader.diagnostics.any(
          (d) =>
              d.code == MailDiagnosticCode.unsupportedCharset ||
              d.code == MailDiagnosticCode.unsupportedTransferEncoding,
        );
        return MailParseResult(
          status: reader.diagnostics.isEmpty
              ? MailParseStatus.complete
              : unsupported && body.plain == null && body.html == null
              ? MailParseStatus.unsupported
              : MailParseStatus.partial,
          message: message,
          diagnostics: reader.diagnostics,
        );
      } on _Stop catch (stop) {
        return MailParseResult(
          status: stop.status,
          original: raw,
          diagnostics: reader.diagnostics,
        );
      } on MailCancelled {
        reader.note(
          MailDiagnosticCode.cancelled,
          'Message reading was cancelled.',
        );
        return MailParseResult(
          status: MailParseStatus.cancelled,
          original: raw,
          diagnostics: reader.diagnostics,
        );
      } on FormatException {
        reader.note(
          MailDiagnosticCode.malformedMime,
          'The MIME structure could not be decoded safely.',
        );
        return MailParseResult(
          status: MailParseStatus.failed,
          original: raw,
          diagnostics: reader.diagnostics,
        );
      } on RangeError {
        reader.note(
          MailDiagnosticCode.malformedMime,
          'The MIME structure contains an invalid range.',
        );
        return MailParseResult(
          status: MailParseStatus.failed,
          original: raw,
          diagnostics: reader.diagnostics,
        );
      }
    }, onDiagnostic: reader.upstreamDiagnostic);
  }
}

final class _Stop implements Exception {
  const _Stop(this.status);
  final MailParseStatus status;
}

final class _Part {
  _Part(this.path, this.headers, this.bodyStart, this.end);
  final String path;
  final mime.MimeMessage headers;
  final int bodyStart;
  final int end;
  final List<_Part> children = [];
  final Set<String> invalidHeaders = {};
  String get mediaType =>
      headers.getHeaderContentType()?.value.toLowerCase() ?? 'text/plain';
  String? get cid => _cleanCid(headers.getHeaderValue('content-id'));
  bool get isAttachment =>
      headers.getHeaderContentDisposition()?.disposition ==
          mime.ContentDisposition.attachment ||
      headers.getHeaderContentDisposition()?.filename != null ||
      headers.getHeaderContentType()?.parameters['name'] != null;
}

final class _Body {
  const _Body({this.plain, this.html, this.plainPath, this.htmlPath});
  final String? plain;
  final String? html;
  final String? plainPath;
  final String? htmlPath;
  bool get isEmpty => plain == null && html == null;
}

String? _cleanCid(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.startsWith('<') && trimmed.endsWith('>')
      ? trimmed.substring(1, trimmed.length - 1)
      : trimmed;
}

final class _Reader {
  _Reader(this.raw, this.budget, this.cancellation);
  final MailBytes raw;
  final MailReadBudget budget;
  final MailCancellationToken? cancellation;
  final List<MailDiagnostic> diagnostics = [];
  final List<MailAttachment> attachments = [];
  int partCount = 0;
  int headerBytes = 0;
  int decodedBytes = 0;
  int bodyBytes = 0;
  int attachmentCount = 0;
  String currentPath = '1';
  Uint8List get bytes => raw.bytes;

  void note(
    MailDiagnosticCode code,
    String message, {
    int? observed,
    int? limit,
  }) {
    // At most one diagnostic per code/part: hostile repeated headers cannot
    // allocate an unbounded diagnostic list or leak source through messages.
    if (diagnostics.any((d) => d.code == code && d.partPath == currentPath)) {
      return;
    }
    diagnostics.add(
      MailDiagnostic(
        code: code,
        message: message,
        partPath: currentPath,
        observed: observed,
        limit: limit,
      ),
    );
  }

  Never reject(
    MailDiagnosticCode code,
    String message,
    int observed,
    int limit,
  ) {
    note(code, message, observed: observed, limit: limit);
    throw const _Stop(MailParseStatus.rejected);
  }

  Never malformed(String message) {
    note(MailDiagnosticCode.malformedMime, message);
    throw const _Stop(MailParseStatus.failed);
  }

  void upstreamDiagnostic(mime.MimeDiagnosticCode code) {
    switch (code) {
      case mime.MimeDiagnosticCode.unsupportedCharset:
        note(
          MailDiagnosticCode.unsupportedCharset,
          'A declared character set is unsupported; use original source.',
        );
      case mime.MimeDiagnosticCode.unsupportedTransferEncoding:
        note(
          MailDiagnosticCode.unsupportedTransferEncoding,
          'A transfer encoding is unsupported; use original source.',
        );
      case mime.MimeDiagnosticCode.malformedCharacterData:
      case mime.MimeDiagnosticCode.malformedEncodedWord:
      case mime.MimeDiagnosticCode.malformedTransferPayload:
        note(
          MailDiagnosticCode.malformedEncoding,
          'Encoded content is malformed; use original source.',
        );
      case mime.MimeDiagnosticCode.invalidDate:
        note(
          MailDiagnosticCode.invalidDate,
          'The message date is not reliable.',
        );
      case mime.MimeDiagnosticCode.malformedAddress:
        note(
          MailDiagnosticCode.invalidAddress,
          'An address could not be decoded.',
        );
      case mime.MimeDiagnosticCode.unrecognizedMediaSubtype:
        // Unknown registered/custom media types remain opaque attachments.
        break;
      case mime.MimeDiagnosticCode.invalidPartReference:
      case mime.MimeDiagnosticCode.malformedMetadata:
      case mime.MimeDiagnosticCode.malformedHeader:
        note(
          MailDiagnosticCode.malformedHeader,
          'A header could not be decoded without approximation.',
        );
    }
  }

  MailEnvelope envelope(_Part root) {
    currentPath = root.path;
    final headers = root.headers;
    List<MailAddress> addresses(String name) {
      if (root.invalidHeaders.contains(name)) return const [];
      final parsed = headers.decodeHeaderMailAddressValue(name) ?? [];
      return parsed
          .map(
            (value) =>
                MailAddress(value.email, displayName: value.personalName),
          )
          .toList(growable: false);
    }

    final date = headers.getHeaderValue('date');
    DateTime? sentAt;
    if (date != null && !root.invalidHeaders.contains('date')) {
      sentAt = headers.decodeDate();
      if (sentAt == null ||
          diagnostics.any(
            (d) =>
                d.partPath == currentPath &&
                d.code == MailDiagnosticCode.invalidDate,
          )) {
        sentAt = null;
        note(
          MailDiagnosticCode.invalidDate,
          'The message date is not reliable.',
        );
      }
    }
    return MailEnvelope(
      subject: root.invalidHeaders.contains('subject')
          ? ''
          : headers.decodeSubject() ?? '',
      from: addresses('from'),
      to: addresses('to'),
      cc: addresses('cc'),
      bcc: addresses('bcc'),
      replyTo: addresses('reply-to'),
      sentAt: sentAt,
      messageId: headers.getHeaderValue('message-id'),
      inReplyTo: headers.getHeaderValue('in-reply-to'),
      references:
          headers
              .getHeaderValue('references')
              ?.split(RegExp(r'\s+'))
              .where((v) => v.isNotEmpty)
              .toList() ??
          const [],
    );
  }

  _Body project(_Part part, {required bool allowBody}) {
    cancellation?.throwIfCancelled();
    currentPath = part.path;
    if (part.children.isNotEmpty && !part.isAttachment) {
      var result = const _Body();
      final isAlternative = part.mediaType == 'multipart/alternative';
      final isRelated = part.mediaType == 'multipart/related';
      final start = _cleanCid(
        part.headers.getHeaderContentType()?.parameters['start'],
      );
      final relatedRoot = isRelated && start != null
          ? part.children.indexWhere((child) => child.cid == start)
          : 0;
      if (isRelated && relatedRoot == -1) {
        note(
          MailDiagnosticCode.malformedMime,
          'The related message root is missing; the first part is used.',
        );
      }
      for (var i = 0; i < part.children.length; i++) {
        final child = part.children[i];
        final useBody =
            allowBody &&
            (isRelated
                ? i == (relatedRoot < 0 ? 0 : relatedRoot)
                : isAlternative || result.isEmpty);
        final next = project(child, allowBody: useBody);
        if (isAlternative) {
          result = _Body(
            plain: next.plain ?? result.plain,
            plainPath: next.plainPath ?? result.plainPath,
            html: next.html ?? result.html,
            htmlPath: next.htmlPath ?? result.htmlPath,
          );
        } else if (result.isEmpty && !next.isEmpty) {
          result = next;
        }
      }
      return result;
    }
    final media = part.mediaType;
    final isBody =
        allowBody &&
        !part.isAttachment &&
        (media == 'text/plain' || media == 'text/html');
    if (!isBody && ++attachmentCount > budget.maxAttachments) {
      reject(
        MailDiagnosticCode.attachmentCountLimit,
        'The message exceeds the attachment count limit.',
        attachmentCount,
        budget.maxAttachments,
      );
    }
    final data = payload(part, isBody: isBody);
    if (data == null) return const _Body();
    if (isBody) {
      final charset =
          part.headers.getHeaderContentType()?.charset ?? 'us-ascii';
      final text = mime.MailCodec.decodeCharsetStrict(data, charset);
      if (text == null) return const _Body();
      // UTF-8 rendered text can be larger than its legacy encoded source.
      var renderBytes = 0;
      for (final rune in text.runes) {
        renderBytes += rune < 0x80
            ? 1
            : rune < 0x800
            ? 2
            : rune < 0x10000
            ? 3
            : 4;
        if (renderBytes > budget.maxRenderTextBytes) {
          reject(
            MailDiagnosticCode.renderLimit,
            'Decoded text exceeds the rendering limit.',
            renderBytes,
            budget.maxRenderTextBytes,
          );
        }
      }
      return media == 'text/plain'
          ? _Body(plain: text, plainPath: part.path)
          : _Body(html: text, htmlPath: part.path);
    }
    final disposition = part.headers.getHeaderContentDisposition();
    attachments.add(
      MailAttachment(
        partPath: part.path,
        mediaType: media,
        displayName: safeFileName(part.headers.decodeFileName(), part.path),
        content: MailBytes(data),
        contentId: part.cid,
        declaredSize: disposition?.size,
        inline:
            disposition?.disposition == mime.ContentDisposition.inline ||
            part.cid != null,
      ),
    );
    return const _Body();
  }

  static String safeFileName(String? original, String partPath) {
    if (original == null || original.trim().isEmpty) {
      return 'attachment-$partPath';
    }
    final last = original.replaceAll('\\', '/').split('/').last;
    final clean = last
        .replaceAll(RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]'), '')
        .trim()
        .replaceAll(RegExp(r'^\.+'), '');
    if (clean.isEmpty) return 'attachment-$partPath';
    return String.fromCharCodes(clean.runes.take(240));
  }
}
