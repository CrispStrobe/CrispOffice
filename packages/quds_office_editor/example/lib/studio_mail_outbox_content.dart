import 'dart:convert';
import 'dart:math' as math;

import 'package:enough_mail/mime_core.dart' as mime;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';

import 'studio_mail_draft.dart';
import 'studio_mail_recipients.dart';
import 'studio_mail_threading.dart';

/// Content-redacted refusal. The exact frozen EML remains independently
/// exportable when a message cannot be represented by the current composer.
final class StudioMailOutboxContentException implements Exception {
  const StudioMailOutboxContentException();

  @override
  String toString() => 'This Outbox message cannot be opened as a draft.';
}

/// A complete, local projection of a frozen message into the plain-text
/// composer. No HTML is rendered, no resource is loaded, and no send is begun.
/// This does not grant permission to copy or retry an uncertain submission.
final class StudioMailOutboxContent {
  const StudioMailOutboxContent._(this.message, this.draft);

  factory StudioMailOutboxContent.fromEntry(
    MailOutboxEntry entry, {
    MailReadBudget budget = readBudget,
  }) {
    try {
      final effectiveBudget = _boundedBudget(budget);
      final wire = entry.prepared.wire;
      if (wire.length > effectiveBudget.maxRawBytes) {
        _unsupported();
      }
      final parsed = const QudsMimeCodec().parse(
        wire.bytes,
        budget: effectiveBudget,
      );
      if (parsed.status != MailParseStatus.complete ||
          parsed.message == null ||
          parsed.diagnostics.isNotEmpty) {
        _unsupported();
      }
      final source = parsed.message!;
      final envelope = source.envelope;
      final transport = entry.prepared.envelope;
      if (!StudioMailDraft.isSupportedAddress(transport.sender) ||
          envelope.from.length != 1 ||
          envelope.from.single.address != transport.sender ||
          _hasNames(envelope.from) ||
          _hasNames(envelope.to) ||
          _hasNames(envelope.cc) ||
          envelope.bcc.isNotEmpty ||
          envelope.replyTo.isNotEmpty ||
          transport.recipients.length > StudioMailRecipients.maxRecipients) {
        _unsupported();
      }

      // The codec intentionally chooses display alternatives and safe filenames.
      // Independently admit the complete bounded MIME shape so extra body parts,
      // hidden headers, inline content and renamed files cannot disappear here.
      final root = mime.MimeMessage.parseFromText(utf8.decode(wire.bytes));
      final files = _Shape(source).validate(root);
      _addressHeader(root, 'from', envelope.from);
      _addressHeader(root, 'to', envelope.to);
      _addressHeader(root, 'cc', envelope.cc);
      final visible = [...envelope.to, ...envelope.cc];
      if (visible.length > transport.recipients.length) _unsupported();
      for (var index = 0; index < visible.length; index++) {
        if (visible[index].address != transport.recipients[index]) {
          _unsupported();
        }
      }
      final recipients = StudioMailRecipients.tryParse(
        to: envelope.to.map((address) => address.address).join(', '),
        cc: envelope.cc.map((address) => address.address).join(', '),
        bcc: transport.recipients.skip(visible.length).join(', '),
      );
      if (recipients == null ||
          !_sameStrings(recipients.envelope, transport.recipients) ||
          recipients.to.length != envelope.to.length ||
          recipients.cc.length != envelope.cc.length) {
        _unsupported();
      }

      final plain = source.body.plainText;
      if (plain == null ||
          source.body.html != null && source.body.html != _plainHtml(plain)) {
        _unsupported();
      }
      final thread = envelope.inReplyTo == null
          ? const StudioMailThread.empty()
          : StudioMailThread.replyTo(
              MailEnvelope(
                messageId: envelope.inReplyTo,
                references: envelope.references,
              ),
            );
      if (thread.inReplyTo != envelope.inReplyTo ||
          (thread.references ?? '') != envelope.references.join(' ')) {
        _unsupported();
      }
      final draft = StudioMailDraft(
        to: recipients.to.join(', '),
        cc: recipients.cc.join(', '),
        bcc: recipients.bcc.join(', '),
        subject: envelope.subject,
        // MIME normalizes editor LF into CRLF. Restore editor line endings so
        // a valid one-MiB draft does not exceed its original budget solely from
        // transport line breaks. The parsed message and exact EML stay intact;
        // literal standalone CR characters remain literal.
        body: plain.replaceAll('\r\n', '\n'),
        thread: thread,
        attachments: StudioMailAttachments.forwarded(files),
      );
      if (draft.problem != null) _unsupported();
      return StudioMailOutboxContent._(
        MailMessage(
          raw: source.raw,
          envelope: source.envelope,
          body: source.body,
          attachments: files,
        ),
        draft,
      );
    } on Object {
      throw const StudioMailOutboxContentException();
    }
  }

  /// Covers every bounded Studio composition, including ten MiB of files and
  /// the escaped HTML alternative of a one-MiB plain-text body.
  static const readBudget = MailReadBudget(
    maxRawBytes: 160 * 1024 * 1024,
    maxDecodedBytes: 150 * 1024 * 1024,
    maxBodyBytes: 8 * 1024 * 1024,
    maxAttachmentBytes: StudioMailAttachments.hardMaxTotalBytes,
    maxAttachments: StudioMailAttachments.maxCount,
    maxParts: StudioMailAttachments.maxCount + 4,
    maxNestingDepth: 3,
  );

  final MailMessage message;
  final StudioMailDraft draft;
}

/// Private companion to the exact EML export. MIME intentionally omits Bcc;
/// this file preserves the complete transport envelope and local attempt risk.
/// It contains no account key, provider identity, password or access token.
MailBytes studioMailOutboxEnvelopeBytes(MailOutboxEntry entry) {
  MailEnvelope? header;
  if (entry.prepared.wire.length <=
      StudioMailOutboxContent.readBudget.maxRawBytes) {
    try {
      final parsed = const QudsMimeCodec().parse(
        entry.prepared.wire.bytes,
        budget: StudioMailOutboxContent.readBudget,
      );
      if (parsed.status == MailParseStatus.complete) {
        header = parsed.message?.envelope;
      }
    } on Object {
      // Optional decoded metadata must never prevent private envelope export.
    }
  }
  final data = <String, Object?>{
    'version': 1,
    'kind': 'quds-mail-private-outbox-envelope',
    'containsPrivateRecipients': true,
    'messageSha256': entry.prepared.wireHash,
    'messageId': header?.messageId,
    'messageDateUtc': header?.sentAt?.toUtc().toIso8601String(),
    'sender': entry.prepared.envelope.sender,
    'recipients': entry.prepared.envelope.recipients,
    'state': entry.state.name,
    'attemptCount': entry.attemptNumber,
    'latestOutcome': entry.result?.outcome.name,
    'priorSubmissionUncertain': entry.priorSubmissionUncertain,
    'deliveryEstablished': false,
    'createdAtUtc': entry.createdAt.toUtc().toIso8601String(),
    'updatedAtUtc': entry.updatedAt.toUtc().toIso8601String(),
  };
  return MailBytes(
    utf8.encode('${const JsonEncoder.withIndent('  ').convert(data)}\n'),
  );
}

Never _unsupported() => throw const StudioMailOutboxContentException();

MailReadBudget _boundedBudget(MailReadBudget requested) {
  requested.validate();
  const cap = StudioMailOutboxContent.readBudget;
  return MailReadBudget(
    maxRawBytes: math.min(requested.maxRawBytes, cap.maxRawBytes),
    maxDecodedBytes: math.min(requested.maxDecodedBytes, cap.maxDecodedBytes),
    maxBodyBytes: math.min(requested.maxBodyBytes, cap.maxBodyBytes),
    maxAttachmentBytes: math.min(
      requested.maxAttachmentBytes,
      cap.maxAttachmentBytes,
    ),
    maxAttachments: math.min(requested.maxAttachments, cap.maxAttachments),
    maxParts: math.min(requested.maxParts, cap.maxParts),
    maxNestingDepth: math.min(requested.maxNestingDepth, cap.maxNestingDepth),
    maxHeaderBytes: math.min(requested.maxHeaderBytes, cap.maxHeaderBytes),
    maxHeaderFieldBytes: math.min(
      requested.maxHeaderFieldBytes,
      cap.maxHeaderFieldBytes,
    ),
    maxHtmlNodes: math.min(requested.maxHtmlNodes, cap.maxHtmlNodes),
    maxHtmlDepth: math.min(requested.maxHtmlDepth, cap.maxHtmlDepth),
    maxRenderTextBytes: math.min(
      requested.maxRenderTextBytes,
      cap.maxRenderTextBytes,
    ),
    maxImagePixels: math.min(requested.maxImagePixels, cap.maxImagePixels),
  );
}

void _addressHeader(mime.MimePart root, String name, List<MailAddress> values) {
  final raw = root.getHeaderValue(name)?.trim() ?? '';
  final fields = raw.isEmpty
      ? <String>[]
      : raw.split(',').map((value) => value.trim()).toList();
  if (!_sameStrings(fields, values.map((value) => value.address).toList())) {
    _unsupported();
  }
}

bool _hasNames(List<MailAddress> addresses) =>
    addresses.any((address) => address.displayName?.isNotEmpty ?? false);

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _plainHtml(String plain) =>
    '<p>${plain.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('\n', '<br>')}</p>';

final class _Shape {
  _Shape(this.source);

  final MailMessage source;
  final List<MailAttachment> files = [];

  List<MailAttachment> validate(mime.MimePart root) {
    _headers(root, root: true);
    final version = root.getHeaderValue('mime-version');
    if (version != null && version.trim() != '1.0') _unsupported();
    if (_type(root) == 'multipart/mixed') {
      _container(root);
      final parts = root.parts!;
      if (parts.length < 2 ||
          parts.length > StudioMailAttachments.maxCount + 1) {
        _unsupported();
      }
      _body(parts.first, '1.1');
      for (var index = 1; index < parts.length; index++) {
        _file(parts[index], '1.${index + 1}');
      }
    } else {
      _body(root, '1', root: true);
    }
    if (files.length != source.attachments.length) _unsupported();
    return files;
  }

  void _body(mime.MimePart part, String path, {bool root = false}) {
    if (!root) _headers(part);
    switch (_type(part)) {
      case 'text/plain':
        _leaf(part, attachment: false);
        if (source.body.plainPartPath != path ||
            source.body.htmlPartPath != null) {
          _unsupported();
        }
      case 'multipart/alternative':
        _container(part);
        final children = part.parts!;
        if (children.length != 2 ||
            _type(children[0]) != 'text/plain' ||
            _type(children[1]) != 'text/html' ||
            source.body.plainPartPath != '$path.1' ||
            source.body.htmlPartPath != '$path.2') {
          _unsupported();
        }
        for (final child in children) {
          _headers(child);
          _leaf(child, attachment: false);
        }
      default:
        _unsupported();
    }
  }

  void _file(mime.MimePart part, String path) {
    _headers(part, attachment: true);
    _leaf(part, attachment: true);
    final index = files.length;
    if (index >= source.attachments.length) _unsupported();
    final attachment = source.attachments[index];
    final name = part.decodeFileName();
    final disposition = part.getHeaderContentDisposition();
    final typeName = part.getHeaderContentType()?.parameters['name'];
    if (name == null ||
        !StudioMailAttachment.isSupportedName(name) ||
        disposition?.disposition != mime.ContentDisposition.attachment ||
        typeName != null && typeName != name ||
        attachment.partPath != path ||
        attachment.mediaType != _type(part) ||
        attachment.inline ||
        attachment.contentId != null ||
        attachment.declaredSize != null &&
            attachment.declaredSize != attachment.content.length) {
      _unsupported();
    }
    // Restore an admitted original filename rather than the reader's safe
    // display projection (which strips leading dots and may shorten names).
    files.add(
      MailAttachment(
        partPath: attachment.partPath,
        mediaType: attachment.mediaType,
        displayName: name,
        content: attachment.content,
        declaredSize: attachment.declaredSize,
      ),
    );
  }

  void _headers(
    mime.MimePart part, {
    bool root = false,
    bool attachment = false,
  }) {
    part.parse();
    final seen = <String>{};
    for (final header in part.headers ?? <mime.Header>[]) {
      final name = header.lowerCaseName;
      if (!seen.add(name) ||
          !{
            'content-type',
            'content-transfer-encoding',
            if (attachment) 'content-disposition',
            if (root) ...{
              'from',
              'to',
              'cc',
              'subject',
              'date',
              'message-id',
              'in-reply-to',
              'references',
              'mime-version',
            },
          }.contains(name)) {
        _unsupported();
      }
    }
  }

  void _leaf(mime.MimePart part, {required bool attachment}) {
    if (part.parts?.isNotEmpty ?? false) _unsupported();
    final parameters =
        part.getHeaderContentType()?.parameters ?? <String, String>{};
    if (parameters.keys.any(
      (name) =>
          !(attachment ? const {'name'} : const {'charset'}).contains(name),
    )) {
      _unsupported();
    }
    if (attachment) {
      final disposition = part.getHeaderContentDisposition();
      if (disposition == null ||
          disposition.parameters.keys.any(
            (name) => !const {'filename', 'size'}.contains(name),
          )) {
        _unsupported();
      }
    }
  }

  void _container(mime.MimePart part) {
    final type = part.getHeaderContentType();
    if (type == null ||
        type.parameters.keys.any((name) => name != 'boundary') ||
        part.parts == null ||
        part.parts!.isEmpty) {
      _unsupported();
    }
    final data = part.mimeData;
    if (data is! mime.TextMimeData) _unsupported();
    final boundary = type.boundary!;
    final delimiters = RegExp(
      '(?:^|\\r\\n)--${RegExp.escape(boundary)}(--)?[ \\t]*(?:\\r\\n|\$)',
    ).allMatches(data.body).toList(growable: false);
    if (delimiters.isEmpty ||
        delimiters.first.group(1) != null ||
        delimiters.last.group(1) == null ||
        delimiters.length != part.parts!.length + 1 ||
        data.body.substring(0, delimiters.first.start).trim().isNotEmpty ||
        data.body.substring(delimiters.last.end).trim().isNotEmpty) {
      _unsupported();
    }
  }

  String _type(mime.MimePart part) =>
      part.getHeaderContentType()?.value.toLowerCase() ?? 'text/plain';
}
