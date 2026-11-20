import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';

import 'errors.dart';
import 'models.dart';

typedef _JsonObject = Map<String, Object?>;

/// Serialized metadata and the immutable, content-addressed bytes it owns.
///
/// Account/profile ownership belongs to the enclosing database rows. A hash
/// establishes blob integrity and never substitutes for that ownership check.
final class MailStorePayload {
  MailStorePayload({required this.data, required Map<String, MailBytes> blobs})
    : blobs = Map.unmodifiable(blobs);

  final String data;
  final Map<String, MailBytes> blobs;
}

/// Validated internal persistence boundary. Invalid data produces a fixed,
/// content-redacted FormatException; callers translate it to storageFailure.
abstract final class MailStoreCodec {
  /// Schema-v3 bitset. Null preserves the distinction between an unknown state
  /// and an observed empty set. Reserved bits are rejected on every read.
  static int? encodeFlags(MailMessageFlags? flags) => flags == null
      ? null
      : (flags.isRead ? 1 : 0) |
            (flags.isFlagged ? 2 : 0) |
            (flags.isAnswered ? 4 : 0) |
            (flags.isDraft ? 8 : 0) |
            (flags.isDeleted ? 16 : 0);

  static MailMessageFlags? decodeFlags(int? flags) => _guard(() {
    if (flags == null) return null;
    if (flags < 0 || flags > 31) _invalid();
    return MailMessageFlags(
      isRead: flags & 1 != 0,
      isFlagged: flags & 2 != 0,
      isAnswered: flags & 4 != 0,
      isDraft: flags & 8 != 0,
      isDeleted: flags & 16 != 0,
    );
  });

  static String encodeEnvelope(MailEnvelope envelope) =>
      jsonEncode(_envelopeToJson(envelope));

  static MailEnvelope decodeEnvelope(String data) =>
      _guard(() => _envelopeFromJson(_parse(data)));

  /// Canonical key within one account; scope is supplied by the database row.
  static String encodeRemote(MailRemoteIdentity identity) =>
      jsonEncode(switch (identity) {
        MailImapIdentity() => <String, Object?>{
          'provider': identity.provider.name,
          'mailbox': identity.mailbox.value,
          'uidValidity': identity.uidValidity,
          'uid': identity.uid,
        },
        MailOpaqueIdentity() => <String, Object?>{
          'provider': identity.provider.name,
          'value': identity.value,
        },
      });

  static MailRemoteIdentity decodeRemote(
    String data, {
    required MailAccountId account,
  }) => _guard(() {
    final value = _parse(data);
    if (value is! _JsonObject) _invalid();
    final provider = _enum(value['provider'], MailProviderKind.values);
    if (provider == MailProviderKind.imap) {
      final object = _object(value, const [
        'provider',
        'mailbox',
        'uidValidity',
        'uid',
      ]);
      return MailImapIdentity(
        mailbox: MailMailboxId(_string(object['mailbox']), account: account),
        uidValidity: _integer(object['uidValidity']),
        uid: _integer(object['uid']),
      );
    }
    final object = _object(value, const ['provider', 'value']);
    return MailOpaqueIdentity(
      account: account,
      provider: provider,
      value: _string(object['value']),
    );
  });

  static MailStorePayload encodeDraft(MailDraft draft) {
    final blobs = <String, MailBytes>{};
    final attachments = <_JsonObject>[];
    for (final attachment in draft.attachments) {
      if (attachment.declaredSize != null && attachment.declaredSize! < 0) {
        _invalid();
      }
      blobs[attachment.content.sha256] = attachment.content;
      attachments.add({
        'partPath': attachment.partPath,
        'mediaType': attachment.mediaType,
        'displayName': attachment.displayName,
        'contentId': attachment.contentId,
        'declaredSize': attachment.declaredSize,
        'inline': attachment.inline,
        'blob': _blobToJson(attachment.content),
      });
    }
    return MailStorePayload(
      data: jsonEncode(<String, Object?>{
        'version': draft.editorState == null ? 1 : 2,
        'envelope': _envelopeToJson(draft.envelope),
        'body': <String, Object?>{
          'plainText': draft.body.plainText,
          'html': draft.body.html,
          'plainPartPath': draft.body.plainPartPath,
          'htmlPartPath': draft.body.htmlPartPath,
        },
        'attachments': attachments,
        if (draft.editorState case final editor?)
          'editorState': <String, Object?>{
            'to': editor.to,
            'cc': editor.cc,
            'bcc': editor.bcc,
            'submissionUncertain': editor.submissionUncertain,
            'isCleared': editor.isCleared,
          },
      }),
      blobs: blobs,
    );
  }

  static MailDraft decodeDraft(
    String data, {
    required MailAccountId account,
    required String id,
    required int revision,
    required Map<String, MailBytes> blobs,
  }) => _guard(() {
    final object = _draftObject(_parse(data));
    final attachments = <MailAttachment>[];
    for (final value in _list(object['attachments'])) {
      final item = _attachmentObject(value);
      attachments.add(
        MailAttachment(
          partPath: _string(item['partPath']),
          mediaType: _string(item['mediaType']),
          displayName: _string(item['displayName']),
          contentId: _nullableString(item['contentId']),
          declaredSize: item['declaredSize'] == null
              ? null
              : _nonnegative(item['declaredSize']),
          inline: _boolean(item['inline']),
          content: _blobFromJson(item['blob'], blobs),
        ),
      );
    }
    return MailDraft(
      id: id,
      account: account,
      revision: revision,
      envelope: _envelopeFromJson(object['envelope']),
      body: _bodyFromJson(object['body']),
      attachments: attachments,
      editorState: object['version'] == 2
          ? _editorStateFromJson(object['editorState'])
          : null,
    );
  });

  /// Reads a validated body projection without loading raw/attachment blobs.
  ///
  /// Local indexing validates all metadata and reference shapes, while actual
  /// byte integrity remains the responsibility of a full payload read. No blob
  /// bytes are needed merely to update a header or index decoded local text.
  static MailBody decodeDraftBody(String data, {MailStoreLimits? limits}) =>
      _guard(() {
        final object = _draftObject(_parse(data));
        final envelope = _envelopeFromJson(object['envelope']);
        final body = _bodyFromJson(object['body']);
        final attachments = [
          for (final value in _list(object['attachments']))
            _attachmentObject(value),
        ];
        if (limits != null) {
          _draftMetadataBudget(object, envelope, body, attachments, limits);
        }
        return body;
      });

  /// Validates the complete metadata shape without resolving attachment blobs.
  /// Catalog navigation never needs to materialize retained file contents.
  static MailDraftSummary decodeDraftSummary(
    String data, {
    required MailAccountId account,
    required String id,
    required int revision,
  }) => _guard(() {
    if (id.isEmpty || revision < 0) _invalid();
    final object = _draftObject(_parse(data));
    final envelope = _envelopeFromJson(object['envelope']);
    final body = _bodyFromJson(object['body']);
    final attachments = _list(object['attachments']);
    for (final value in attachments) {
      _attachmentObject(value);
    }
    final editor = object['version'] == 2
        ? _editorStateFromJson(object['editorState'])
        : null;
    if (editor?.isCleared == true &&
        (envelope.subject.isNotEmpty ||
            envelope.from.isNotEmpty ||
            envelope.to.isNotEmpty ||
            envelope.cc.isNotEmpty ||
            envelope.bcc.isNotEmpty ||
            envelope.replyTo.isNotEmpty ||
            envelope.sentAt != null ||
            envelope.messageId != null ||
            envelope.inReplyTo != null ||
            envelope.references.isNotEmpty ||
            body.plainText != null ||
            body.html != null ||
            body.plainPartPath != null ||
            body.htmlPartPath != null ||
            attachments.isNotEmpty)) {
      _invalid();
    }
    return MailDraftSummary(
      id: id,
      account: account,
      revision: revision,
      envelope: envelope,
      attachmentCount: attachments.length,
      editorState: editor,
    );
  });

  static MailStorePayload encodeOutbox(MailOutboxEntry entry) {
    _validateOutbox(entry);
    return MailStorePayload(
      data: jsonEncode(_outboxToJson(entry)),
      blobs: {entry.prepared.wireHash: entry.prepared.wire},
    );
  }

  static MailOutboxEntry decodeOutbox(
    String data, {
    required MailAccountId account,
    required String id,
    required Map<String, MailBytes> blobs,
  }) => _guard(() {
    final object = _outboxObject(_parse(data));
    final envelope = _object(object['envelope'], const [
      'sender',
      'recipients',
    ]);
    final entry = MailOutboxEntry.restore(
      id: id,
      prepared: MailPreparedMessage(
        account: account,
        draftId: _string(object['draftId']),
        draftRevision: _nonnegative(object['draftRevision']),
        wire: _blobFromJson(object['wire'], blobs),
        envelope: MailTransportEnvelope(
          sender: _string(envelope['sender']),
          recipients: _strings(envelope['recipients']),
        ),
      ),
      state: _enum(object['state'], MailOutboxState.values),
      createdAt: _dateFromJson(object['createdAt']),
      updatedAt: _dateFromJson(object['updatedAt']),
      attemptNumber: _nonnegative(object['attemptNumber']),
      attemptId: _nullableString(object['attemptId']),
      result: object['result'] == null
          ? null
          : _resultFromJson(object['result']),
      priorSubmissionUncertain: object['version'] == 2
          ? _boolean(object['priorSubmissionUncertain'])
          : false,
    );
    _validateOutbox(entry);
    return entry;
  });

  /// Validates a proposed persistence mutation in addition to row-level CAS.
  ///
  /// Historical attempt-ID uniqueness needs the repository's durable attempt
  /// journal; an entry retains only its most recent attempt identity.
  static bool validOutboxTransition(
    MailOutboxEntry? previous,
    MailOutboxEntry next,
  ) {
    try {
      _validateOutbox(next);
      if (previous == null) {
        return next.state == MailOutboxState.queued &&
            _sameDate(next.createdAt, next.updatedAt);
      }
      _validateOutbox(previous);
      if (previous.id != next.id ||
          !_samePrepared(previous.prepared, next.prepared) ||
          !_sameDate(previous.createdAt, next.createdAt) ||
          next.updatedAt.isBefore(previous.updatedAt)) {
        return false;
      }
      if (previous.state == next.state) {
        return jsonEncode(_outboxToJson(previous)) ==
            jsonEncode(_outboxToJson(next));
      }
      if (next.state == MailOutboxState.submitting) {
        final ordinary = previous.canBeginAttempt;
        final acknowledged = previous.canBeginAcknowledgedAttempt;
        return (ordinary || acknowledged) &&
            next.attemptNumber == previous.attemptNumber + 1 &&
            next.attemptId != previous.attemptId &&
            next.priorSubmissionUncertain == acknowledged &&
            next.result == null;
      }
      if (next.priorSubmissionUncertain != previous.priorSubmissionUncertain) {
        return false;
      }
      if (next.state == MailOutboxState.closedUncertain) {
        return previous.canCloseUncertain &&
            next.attemptNumber == previous.attemptNumber &&
            next.attemptId == previous.attemptId &&
            jsonEncode(_nullableResult(previous.result)) ==
                jsonEncode(_nullableResult(next.result));
      }
      switch (previous.state) {
        case MailOutboxState.queued:
        case MailOutboxState.retryableFailure:
          if (next.state == MailOutboxState.cancelled) {
            return previous.canCancel &&
                next.attemptNumber == previous.attemptNumber &&
                next.attemptId == previous.attemptId &&
                jsonEncode(_nullableResult(previous.result)) ==
                    jsonEncode(_nullableResult(next.result));
          }
          return false;
        case MailOutboxState.submitting:
          return const {
                MailOutboxState.submitted,
                MailOutboxState.retryableFailure,
                MailOutboxState.permanentFailure,
                MailOutboxState.uncertain,
              }.contains(next.state) &&
              next.attemptNumber == previous.attemptNumber &&
              next.attemptId == previous.attemptId;
        case MailOutboxState.submitted:
        case MailOutboxState.permanentFailure:
        case MailOutboxState.uncertain:
        case MailOutboxState.cancelled:
        case MailOutboxState.closedUncertain:
          return false;
      }
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }
}

_JsonObject _envelopeToJson(MailEnvelope envelope) => {
  'version': 1,
  'subject': envelope.subject,
  'from': _addressesToJson(envelope.from),
  'to': _addressesToJson(envelope.to),
  'cc': _addressesToJson(envelope.cc),
  'bcc': _addressesToJson(envelope.bcc),
  'replyTo': _addressesToJson(envelope.replyTo),
  'sentAt': envelope.sentAt == null ? null : _dateToJson(envelope.sentAt!),
  'messageId': envelope.messageId,
  'inReplyTo': envelope.inReplyTo,
  'references': envelope.references,
};

MailEnvelope _envelopeFromJson(Object? value) {
  final object = _object(value, const [
    'version',
    'subject',
    'from',
    'to',
    'cc',
    'bcc',
    'replyTo',
    'sentAt',
    'messageId',
    'inReplyTo',
    'references',
  ]);
  _version(object);
  return MailEnvelope(
    subject: _string(object['subject']),
    from: _addressesFromJson(object['from']),
    to: _addressesFromJson(object['to']),
    cc: _addressesFromJson(object['cc']),
    bcc: _addressesFromJson(object['bcc']),
    replyTo: _addressesFromJson(object['replyTo']),
    sentAt: object['sentAt'] == null ? null : _dateFromJson(object['sentAt']),
    messageId: _nullableString(object['messageId']),
    inReplyTo: _nullableString(object['inReplyTo']),
    references: _strings(object['references']),
  );
}

List<_JsonObject> _addressesToJson(List<MailAddress> addresses) => [
  for (final address in addresses)
    {'address': address.address, 'displayName': address.displayName},
];

List<MailAddress> _addressesFromJson(Object? value) => [
  for (final address in _list(value)) _addressFromJson(address),
];

MailAddress _addressFromJson(Object? value) {
  final object = _object(value, const ['address', 'displayName']);
  return MailAddress(
    _string(object['address']),
    displayName: _nullableString(object['displayName']),
  );
}

_JsonObject _blobToJson(MailBytes content) => {
  'hash': content.sha256,
  'length': content.length,
};

_JsonObject _draftObject(Object? value) {
  if (value is! _JsonObject) _invalid();
  final version = _integer(value['version']);
  if (version != 1 && version != 2) _invalid();
  final object = _object(value, [
    'version',
    'envelope',
    'body',
    'attachments',
    if (version == 2) 'editorState',
  ]);
  if (version == 2) _editorStateFromJson(object['editorState']);
  return object;
}

MailDraftEditorState _editorStateFromJson(Object? value) {
  final state = _object(value, const [
    'to',
    'cc',
    'bcc',
    'submissionUncertain',
    'isCleared',
  ]);
  return MailDraftEditorState(
    to: _string(state['to']),
    cc: _string(state['cc']),
    bcc: _string(state['bcc']),
    submissionUncertain: _boolean(state['submissionUncertain']),
    isCleared: _boolean(state['isCleared']),
  );
}

MailBody _bodyFromJson(Object? value) {
  final body = _object(value, const [
    'plainText',
    'html',
    'plainPartPath',
    'htmlPartPath',
  ]);
  return MailBody(
    plainText: _nullableString(body['plainText']),
    html: _nullableString(body['html']),
    plainPartPath: _nullableString(body['plainPartPath']),
    htmlPartPath: _nullableString(body['htmlPartPath']),
  );
}

// Validate decoded work before any raw or attachment payload is read. This
// mirrors the writer's semantic metadata/attachment budgets, including on a
// store reopened with lower limits. JSON punctuation and escaping are excluded.
void _draftMetadataBudget(
  _JsonObject object,
  MailEnvelope envelope,
  MailBody body,
  List<_JsonObject> attachments,
  MailStoreLimits limits,
) {
  Never exceeded() =>
      throw const MailStoreStorageException(MailProblemCode.quotaExceeded);
  var units =
      envelope.subject.length +
      (envelope.messageId?.length ?? 0) +
      (envelope.inReplyTo?.length ?? 0) +
      (body.plainText?.length ?? 0) +
      (body.html?.length ?? 0) +
      (body.plainPartPath?.length ?? 0) +
      (body.htmlPartPath?.length ?? 0);
  var addresses = 0;
  for (final group in [
    envelope.from,
    envelope.to,
    envelope.cc,
    envelope.bcc,
    envelope.replyTo,
  ]) {
    addresses += group.length;
    for (final address in group) {
      units += address.address.length + (address.displayName?.length ?? 0);
    }
  }
  for (final reference in envelope.references) {
    units += reference.length;
  }
  if (object['version'] == 2) {
    final editor = _editorStateFromJson(object['editorState']);
    units += editor.to.length + editor.cc.length + editor.bcc.length;
  }
  if (addresses > 512 ||
      envelope.references.length > 512 ||
      attachments.length > 128) {
    exceeded();
  }
  var bytes = 0;
  final paths = <String>{};
  for (final attachment in attachments) {
    final path = _string(attachment['partPath']);
    if (path.isEmpty ||
        path.length > 1024 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
        !paths.add(path)) {
      _invalid();
    }
    units +=
        path.length +
        _string(attachment['mediaType']).length +
        _string(attachment['displayName']).length +
        (_nullableString(attachment['contentId'])?.length ?? 0);
    final (_, size) = _blobReference(attachment['blob']);
    bytes += size;
    if (size > limits.maxBlobBytes) exceeded();
  }
  if (units > limits.maxMetadataCodeUnits ||
      bytes > limits.maxTransactionBlobBytes) {
    exceeded();
  }
}

_JsonObject _attachmentObject(Object? value) {
  final item = _object(value, const [
    'partPath',
    'mediaType',
    'displayName',
    'contentId',
    'declaredSize',
    'inline',
    'blob',
  ]);
  _string(item['partPath']);
  _string(item['mediaType']);
  _string(item['displayName']);
  _nullableString(item['contentId']);
  if (item['declaredSize'] != null) _nonnegative(item['declaredSize']);
  _boolean(item['inline']);
  _blobReference(item['blob']);
  return item;
}

(String, int) _blobReference(Object? value) {
  final object = _object(value, const ['hash', 'length']);
  final hash = _string(object['hash']);
  final length = _nonnegative(object['length']);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) _invalid();
  return (hash, length);
}

MailBytes _blobFromJson(Object? value, Map<String, MailBytes> blobs) {
  final (hash, length) = _blobReference(value);
  final content = blobs[hash];
  if (content == null || content.length != length || content.sha256 != hash) {
    _invalid();
  }
  return content;
}

_JsonObject _outboxObject(Object? value) {
  if (value is! _JsonObject) _invalid();
  final version = value['version'];
  if (version != 1 && version != 2) _invalid();
  return _object(value, [
    'version',
    'draftId',
    'draftRevision',
    'wire',
    'envelope',
    'state',
    'createdAt',
    'updatedAt',
    'attemptNumber',
    'attemptId',
    'result',
    if (version == 2) 'priorSubmissionUncertain',
  ]);
}

_JsonObject _outboxToJson(MailOutboxEntry entry) => {
  'version': 2,
  'draftId': entry.prepared.draftId,
  'draftRevision': entry.prepared.draftRevision,
  'wire': _blobToJson(entry.prepared.wire),
  'envelope': <String, Object?>{
    'sender': entry.prepared.envelope.sender,
    'recipients': entry.prepared.envelope.recipients,
  },
  'state': entry.state.name,
  'createdAt': _dateToJson(entry.createdAt),
  'updatedAt': _dateToJson(entry.updatedAt),
  'attemptNumber': entry.attemptNumber,
  'attemptId': entry.attemptId,
  'priorSubmissionUncertain': entry.priorSubmissionUncertain,
  'result': _nullableResult(entry.result),
};

Object? _nullableResult(MailSubmissionResult? result) => result == null
    ? null
    : <String, Object?>{
        'attemptId': result.attemptId,
        'outcome': result.outcome.name,
        'recipients': <_JsonObject>[
          for (final recipient in result.recipients)
            {
              'recipient': recipient.recipient,
              'acceptance': recipient.acceptance.name,
              'responseCode': recipient.responseCode,
            },
        ],
        'problem': result.problem == null
            ? null
            : <String, Object?>{
                'code': result.problem!.code.name,
                'retryAfterMicroseconds':
                    result.problem!.retryAfter?.inMicroseconds,
              },
      };

MailSubmissionResult _resultFromJson(Object? value) {
  final object = _object(value, const [
    'attemptId',
    'outcome',
    'recipients',
    'problem',
  ]);
  final recipients = <MailRecipientResponse>[];
  for (final value in _list(object['recipients'])) {
    final recipient = _object(value, const [
      'recipient',
      'acceptance',
      'responseCode',
    ]);
    recipients.add(
      MailRecipientResponse(
        recipient: _string(recipient['recipient']),
        acceptance: _enum(
          recipient['acceptance'],
          MailRecipientAcceptance.values,
        ),
        responseCode: recipient['responseCode'] == null
            ? null
            : _integer(recipient['responseCode']),
      ),
    );
  }
  MailProblem? problem;
  if (object['problem'] != null) {
    final item = _object(object['problem'], const [
      'code',
      'retryAfterMicroseconds',
    ]);
    problem = MailProblem(
      _enum(item['code'], MailProblemCode.values),
      retryAfter: item['retryAfterMicroseconds'] == null
          ? null
          : Duration(
              microseconds: _nonnegative(item['retryAfterMicroseconds']),
            ),
    );
  }
  return MailSubmissionResult(
    attemptId: _string(object['attemptId']),
    outcome: _enum(object['outcome'], MailSubmissionOutcome.values),
    recipients: recipients,
    problem: problem,
  );
}

void _validateOutbox(MailOutboxEntry entry) {
  MailOutboxEntry.restore(
    id: entry.id,
    prepared: entry.prepared,
    state: entry.state,
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
    attemptNumber: entry.attemptNumber,
    attemptId: entry.attemptId,
    result: entry.result,
    priorSubmissionUncertain: entry.priorSubmissionUncertain,
  );
  if (entry.updatedAt.isBefore(entry.createdAt) ||
      (entry.result?.problem?.retryAfter?.isNegative ?? false) ||
      (entry.state == MailOutboxState.cancelled &&
          entry.attemptNumber > 0 &&
          entry.result?.outcome != MailSubmissionOutcome.retryableFailure)) {
    _invalid();
  }
}

bool _samePrepared(MailPreparedMessage a, MailPreparedMessage b) =>
    a.account == b.account &&
    a.draftId == b.draftId &&
    a.draftRevision == b.draftRevision &&
    a.wire.length == b.wire.length &&
    a.wireHash == b.wireHash &&
    a.envelope.sender == b.envelope.sender &&
    _sameStrings(a.envelope.recipients, b.envelope.recipients);

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameDate(DateTime a, DateTime b) =>
    a.isUtc == b.isUtc && a.isAtSameMomentAs(b);

_JsonObject _dateToJson(DateTime date) => {
  'instant': date.toUtc().toIso8601String(),
  'utc': date.isUtc,
};

DateTime _dateFromJson(Object? value) {
  final object = _object(value, const ['instant', 'utc']);
  final instant = _string(object['instant']);
  final utc = _boolean(object['utc']);
  final parsed = DateTime.parse(instant);
  // DateTime.parse normalizes invalid dates; only canonical encoder output is
  // accepted. Store an absolute instant even when the original used local time.
  if (!parsed.isUtc || parsed.toIso8601String() != instant) _invalid();
  return utc ? parsed : parsed.toLocal();
}

Object? _parse(String data) {
  // A persistence document is shallow and bounded. Reject oversized/deeply
  // nested corruption before letting the JSON decoder allocate a large tree.
  if (data.length > 64 * 1024 * 1024) _invalid();
  var depth = 0;
  var containers = 0;
  var quoted = false;
  var escaped = false;
  int? keyStart;
  final frames = <_JsonFrame>[];
  for (var i = 0; i < data.length; i++) {
    final unit = data.codeUnitAt(i);
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (unit == 92) {
        escaped = true;
      } else if (unit == 34) {
        quoted = false;
        if (keyStart != null) {
          final Object? decodedKey = jsonDecode(
            data.substring(keyStart, i + 1),
          );
          final key = _string(decodedKey);
          if (!frames.last.keys.add(key)) _invalid();
          frames.last.expectsKey = false;
          keyStart = null;
        }
      }
    } else if (unit == 34) {
      quoted = true;
      if (frames.isNotEmpty && frames.last.expectsKey) keyStart = i;
    } else if (unit == 123 || unit == 91) {
      depth++;
      containers++;
      if (depth > 16 || containers > 65536) _invalid();
      frames.add(_JsonFrame(isObject: unit == 123));
    } else if (unit == 125 || unit == 93) {
      depth--;
      if (depth < 0) _invalid();
      final frame = frames.removeLast();
      if (frame.isObject != (unit == 125)) _invalid();
    } else if (unit == 44 && frames.isNotEmpty && frames.last.isObject) {
      frames.last.expectsKey = true;
    }
  }
  if (depth != 0 || quoted) _invalid();
  final Object? decoded = jsonDecode(data);
  return decoded;
}

final class _JsonFrame {
  _JsonFrame({required this.isObject}) : expectsKey = isObject;
  final bool isObject;
  bool expectsKey;
  final Set<String> keys = {};
}

T _guard<T>(T Function() action) {
  try {
    return action();
  } on FormatException {
    _invalid();
  } on ArgumentError {
    _invalid();
  }
}

_JsonObject _object(Object? value, List<String> keys) {
  if (value is! _JsonObject ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    _invalid();
  }
  return value;
}

void _version(_JsonObject value) {
  if (_integer(value['version']) != 1) _invalid();
}

String _string(Object? value) {
  if (value is! String) _invalid();
  return value;
}

String? _nullableString(Object? value) => value == null ? null : _string(value);

int _integer(Object? value) {
  if (value is! int) _invalid();
  return value;
}

int _nonnegative(Object? value) {
  final result = _integer(value);
  if (result < 0) _invalid();
  return result;
}

bool _boolean(Object? value) {
  if (value is! bool) _invalid();
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) _invalid();
  return value;
}

List<String> _strings(Object? value) => [
  for (final item in _list(value)) _string(item),
];

T _enum<T extends Enum>(Object? value, List<T> values) {
  final name = _string(value);
  for (final option in values) {
    if (option.name == name) return option;
  }
  _invalid();
}

Never _invalid() => throw const FormatException('Invalid persisted mail data.');
