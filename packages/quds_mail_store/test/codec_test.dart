import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/src/codec.dart';
import 'package:test/test.dart';

void main() {
  group('standard flag codec', () {
    test('unknown flags remain distinct from an observed empty set', () {
      expect(MailStoreCodec.encodeFlags(null), isNull);
      expect(MailStoreCodec.decodeFlags(null), isNull);
      expect(MailStoreCodec.encodeFlags(const MailMessageFlags()), 0);
      expect(MailStoreCodec.decodeFlags(0), const MailMessageFlags());
    });

    test('every durable flag survives alone and in a combined snapshot', () {
      for (final (encoded, flags) in const [
        (1, MailMessageFlags(isRead: true)),
        (2, MailMessageFlags(isFlagged: true)),
        (4, MailMessageFlags(isAnswered: true)),
        (8, MailMessageFlags(isDraft: true)),
        (16, MailMessageFlags(isDeleted: true)),
        (
          31,
          MailMessageFlags(
            isRead: true,
            isFlagged: true,
            isAnswered: true,
            isDraft: true,
            isDeleted: true,
          ),
        ),
      ]) {
        expect(MailStoreCodec.encodeFlags(flags), encoded);
        expect(MailStoreCodec.decodeFlags(encoded), flags);
      }
    });

    test('reserved flag bits and negative masks fail with redacted errors', () {
      for (final invalid in [-1, 32, 0xffffffff]) {
        expect(
          () => MailStoreCodec.decodeFlags(invalid),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Invalid persisted mail data.',
            ),
          ),
        );
      }
    });
  });

  group('metadata codec', () {
    test('envelope round trip preserves every header field and timestamp', () {
      final encoded = MailStoreCodec.encodeEnvelope(_envelope());
      final decoded = MailStoreCodec.decodeEnvelope(encoded);
      expect(MailStoreCodec.encodeEnvelope(decoded), encoded);
      expect(decoded.sentAt, _envelope().sentAt);
      expect(decoded.bcc.single.address, 'hidden@example.test');
      expect(decoded.from.single.displayName, 'مرسل Example');
      expect(decoded.references, ['<one@example.test>', '<two@example.test>']);
    });

    test(
      'nullable empty metadata and local absolute timestamps round trip',
      () {
        final empty = MailStoreCodec.encodeEnvelope(MailEnvelope());
        expect(
          MailStoreCodec.encodeEnvelope(MailStoreCodec.decodeEnvelope(empty)),
          empty,
        );
        final localTime = DateTime.utc(
          2026,
          11,
          18,
          12,
          30,
          5,
          10,
          11,
        ).toLocal();
        final decoded = MailStoreCodec.decodeEnvelope(
          MailStoreCodec.encodeEnvelope(MailEnvelope(sentAt: localTime)),
        );
        expect(decoded.sentAt!.isUtc, isFalse);
        expect(decoded.sentAt!.isAtSameMomentAs(localTime), isTrue);
      },
    );

    final corruptEnvelopes = <String, void Function(Map<String, Object?>)>{
      'unknown field': (value) => value['unknown'] = true,
      'missing nullable field': (value) => value.remove('inReplyTo'),
      'future version': (value) => value['version'] = 2,
      'wrong subject type': (value) => value['subject'] = false,
      'wrong reference type': (value) => value['references'] = [42],
      'wrong address shape': (value) => value['from'] = ['address'],
      'unknown address field': (value) =>
          _object(_array(value['from']).single)['secret'] = 'secret-marker',
      'wrong nullable address type': (value) =>
          _object(_array(value['from']).single)['displayName'] = 42,
      'normalized invalid date': (value) =>
          _object(value['sentAt'])['instant'] = '2026-02-31T12:00:00.000Z',
      'offset date instead of canonical instant': (value) =>
          _object(value['sentAt'])['instant'] = '2026-11-18T13:00:00.000+01:00',
      'wrong UTC type': (value) => _object(value['sentAt'])['utc'] = 'true',
    };
    for (final entry in corruptEnvelopes.entries) {
      test('envelope rejects ${entry.key}', () {
        final value = _json(MailStoreCodec.encodeEnvelope(_envelope()));
        entry.value(value);
        expect(
          () => MailStoreCodec.decodeEnvelope(jsonEncode(value)),
          throwsFormatException,
        );
      });
    }

    test(
      'duplicate literal and escaped keys are rejected before JSON collapse',
      () {
        final source = MailStoreCodec.encodeEnvelope(_envelope());
        for (final duplicate in [
          '"version":1,"version":1',
          r'"version":1,"\u0076ersion":1',
        ]) {
          expect(
            () => MailStoreCodec.decodeEnvelope(
              source.replaceFirst('"version":1', duplicate),
            ),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'bounded parser rejects deep nesting and redacts malformed content',
      () {
        final deep =
            '${List.filled(17, '[').join()}null${List.filled(17, ']').join()}';
        expect(
          () => MailStoreCodec.decodeEnvelope(deep),
          throwsFormatException,
        );
        try {
          MailStoreCodec.decodeEnvelope(
            '{"secret-marker":"private-body-marker"',
          );
          fail('Expected malformed metadata rejection.');
        } on FormatException catch (error) {
          expect(
            error.toString(),
            'FormatException: Invalid persisted mail data.',
          );
          expect(error.source, isNull);
          expect(error.offset, isNull);
        }
      },
    );
  });

  group('provider identity codec', () {
    test(
      'canonical IMAP key preserves UIDVALIDITY and scope is supplied separately',
      () {
        final first = MailImapIdentity(
          mailbox: MailMailboxId('Inbox/"é"', account: _account()),
          uidValidity: 0xffffffff,
          uid: 1,
        );
        final key = MailStoreCodec.encodeRemote(first);
        expect(MailStoreCodec.decodeRemote(key, account: _account()), first);
        final otherAccount = _account(host: 'other');
        final other = MailStoreCodec.decodeRemote(key, account: otherAccount);
        expect(other.account, otherAccount);
        expect(other, isNot(first));
        expect(MailStoreCodec.encodeRemote(other), key);
      },
    );

    for (final provider in [
      MailProviderKind.graph,
      MailProviderKind.gmail,
      MailProviderKind.jmap,
    ]) {
      test('${provider.name} identity preserves exact opaque value', () {
        final identity = MailOpaqueIdentity(
          account: _account(),
          provider: provider,
          value: 'id:/"value"/α',
        );
        final key = MailStoreCodec.encodeRemote(identity);
        expect(MailStoreCodec.decodeRemote(key, account: _account()), identity);
      });
    }

    test('remote codec rejects invalid provider, field set and IMAP range', () {
      for (final invalid in <Map<String, Object?>>[
        {'provider': 'local', 'value': 'id'},
        {'provider': 'other', 'value': 'id'},
        {'provider': 'gmail', 'value': 42},
        {'provider': 'gmail', 'value': 'id', 'account': 'injected'},
        {'provider': 'imap', 'mailbox': 'inbox', 'uidValidity': 0, 'uid': 1},
        {
          'provider': 'imap',
          'mailbox': 'inbox',
          'uidValidity': 1,
          'uid': 0x100000000,
        },
        {'provider': 'imap', 'mailbox': 'inbox', 'uidValidity': 1, 'uid': 1.5},
      ]) {
        expect(
          () => MailStoreCodec.decodeRemote(
            jsonEncode(invalid),
            account: _account(),
          ),
          throwsFormatException,
        );
      }
    });
  });

  group('draft payload', () {
    test(
      'body projection validates metadata without requiring payload bytes',
      () {
        final payload = MailStoreCodec.encodeDraft(_draft());
        final body = MailStoreCodec.decodeDraftBody(payload.data);
        expect(body.plainText, _draft().body.plainText);
        expect(body.html, _draft().body.html);
        expect(body.plainPartPath, '1.1');
        expect(body.htmlPartPath, '1.2');
        expect(() => _decodeDraft(payload, blobs: {}), throwsFormatException);
        for (final mutate in <void Function(Map<String, Object?>)>[
          (value) => value['version'] = 2,
          (value) => _object(value['envelope'])['subject'] = 42,
          (value) => _object(value['body'])['plainText'] = 42,
          (value) =>
              _object(_array(value['attachments']).first)['mediaType'] = 42,
          (value) =>
              _object(_array(value['attachments']).first)['inline'] = 'true',
          (value) => _object(
            _object(_array(value['attachments']).first)['blob'],
          )['hash'] = 'bad',
          (value) => _object(
            _object(_array(value['attachments']).first)['blob'],
          )['length'] = -1,
        ]) {
          final data = _json(payload.data);
          mutate(data);
          expect(
            () => MailStoreCodec.decodeDraftBody(jsonEncode(data)),
            throwsFormatException,
          );
        }
      },
    );

    test('metadata and deduplicated immutable blobs round trip separately', () {
      final draft = _draft();
      final payload = MailStoreCodec.encodeDraft(draft);
      expect(payload.blobs, hasLength(1));
      expect(() => payload.blobs.clear(), throwsUnsupportedError);
      final decoded = _decodeDraft(payload);
      final restored = MailStoreCodec.encodeDraft(decoded);
      expect(restored.data, payload.data);
      expect(restored.blobs.keys, payload.blobs.keys);
      expect(decoded.id, draft.id);
      expect(decoded.account, draft.account);
      expect(decoded.revision, draft.revision);
      expect(
        decoded.attachments.first.content.bytes,
        draft.attachments.first.content.bytes,
      );
      expect(decoded.body.html, '<p>مرحبا <b>world</b></p>');
      expect(decoded.attachments.last.contentId, 'image@example.test');
      expect(decoded.attachments.last.inline, isTrue);
      expect(
        () => decoded.attachments.first.content.bytes[0] = 1,
        throwsUnsupportedError,
      );
    });

    test(
      'draft rejects missing, corrupted or mismatched-length attachment bytes',
      () {
        final payload = MailStoreCodec.encodeDraft(_draft());
        expect(() => _decodeDraft(payload, blobs: {}), throwsFormatException);
        expect(
          () => _decodeDraft(
            payload,
            blobs: {
              payload.blobs.keys.single: MailBytes(
                Uint8List.fromList([1, 2, 3, 4, 5]),
              ),
            },
          ),
          throwsFormatException,
        );
        final metadata = _json(payload.data);
        _object(
          _object(_array(metadata['attachments']).first)['blob'],
        )['length'] = 1;
        expect(
          () => _decodeDraft(payload, data: jsonEncode(metadata)),
          throwsFormatException,
        );
      },
    );

    test(
      'draft rejects wrong metadata types, unknown fields and malformed hash',
      () {
        final payload = MailStoreCodec.encodeDraft(_draft());
        for (final mutate in <void Function(Map<String, Object?>)>[
          (value) => value['version'] = 2,
          (value) => _object(value['body'])['extra'] = true,
          (value) => _object(value['body'])['plainText'] = 42,
          (value) =>
              _object(_array(value['attachments']).first)['inline'] = 'true',
          (value) =>
              _object(_array(value['attachments']).first)['declaredSize'] = -1,
          (value) => _object(
            _object(_array(value['attachments']).first)['blob'],
          )['hash'] = 'bad',
          (value) =>
              _object(_array(value['attachments']).first).remove('contentId'),
        ]) {
          final data = _json(payload.data);
          mutate(data);
          expect(
            () => _decodeDraft(payload, data: jsonEncode(data)),
            throwsFormatException,
          );
        }
      },
    );
  });

  group('outbox payload', () {
    test(
      'every state round trips frozen bytes, recipients, result and attempt',
      () {
        final queued = _queued();
        final pending = queued.beginAttempt(
          attemptId: 'attempt-1',
          now: _later(1),
        );
        final entries = [
          queued,
          pending,
          queued.cancel(now: _later(1)),
          for (final outcome in MailSubmissionOutcome.values)
            pending.complete(_result(outcome), now: _later(2)),
        ];
        for (final entry in entries) {
          final payload = MailStoreCodec.encodeOutbox(entry);
          final restored = _decodeOutbox(payload);
          expect(MailStoreCodec.encodeOutbox(restored).data, payload.data);
          expect(restored.prepared.wire.bytes, entry.prepared.wire.bytes);
          expect(
            restored.prepared.envelope.recipients,
            entry.prepared.envelope.recipients,
          );
          expect(restored.prepared.draftRevision, 7);
          expect(restored.state, entry.state);
        }
      },
    );

    test('restored in-flight entry becomes uncertain and never retryable', () {
      final pending = _queued().beginAttempt(
        attemptId: 'attempt-1',
        now: _later(1),
      );
      final restored = _decodeOutbox(MailStoreCodec.encodeOutbox(pending));
      final recovered = restored.recoverInterrupted(now: _later(2));
      expect(recovered.state, MailOutboxState.uncertain);
      expect(recovered.attemptId, 'attempt-1');
      expect(recovered.canBeginAttempt, isFalse);
      expect(MailStoreCodec.validOutboxTransition(restored, recovered), isTrue);
    });

    test(
      'wire integrity and internal result/state consistency are enforced',
      () {
        final pending = _queued().beginAttempt(
          attemptId: 'attempt-1',
          now: _later(1),
        );
        final submitted = pending.complete(
          _result(MailSubmissionOutcome.accepted),
          now: _later(2),
        );
        final payload = MailStoreCodec.encodeOutbox(submitted);
        expect(() => _decodeOutbox(payload, blobs: {}), throwsFormatException);
        for (final mutate in <void Function(Map<String, Object?>)>[
          (value) => value['state'] = 'invented',
          (value) => value['attemptNumber'] = -1,
          (value) => value['draftRevision'] = false,
          (value) => value['state'] = 'queued',
          (value) => value['result'] = null,
          (value) => _object(value['result'])['outcome'] = 'rejected',
          (value) => _object(value['result'])['attemptId'] = 'stale',
          (value) =>
              _object(_object(value['result'])['problem'])['code'] = 'invented',
          (value) => _object(
            _object(value['result'])['problem'],
          )['retryAfterMicroseconds'] = -1,
          (value) => _object(
            _array(_object(value['result'])['recipients']).first,
          )['recipient'] = 'outsider@example.test',
          (value) => _object(
            _array(_object(value['result'])['recipients']).first,
          )['responseCode'] = 550,
          (value) => _object(value['envelope'])['recipients'] = [],
          (value) =>
              _object(value['envelope'])['sender'] = 'sender\r\nsecret-marker',
          (value) => _object(value['wire'])['length'] = 0,
          (value) => _object(value['createdAt'])['instant'] =
              '2027-01-01T00:00:00.000Z',
        ]) {
          final data = _json(payload.data);
          mutate(data);
          expect(
            () => _decodeOutbox(payload, data: jsonEncode(data)),
            throwsFormatException,
          );
        }
      },
    );
  });

  group('outbox persistence transitions', () {
    test(
      'new entries must be initial queued and all legitimate transitions pass',
      () {
        final queued = _queued();
        final pending = queued.beginAttempt(
          attemptId: 'attempt-1',
          now: _later(1),
        );
        expect(MailStoreCodec.validOutboxTransition(null, queued), isTrue);
        expect(MailStoreCodec.validOutboxTransition(null, pending), isFalse);
        expect(MailStoreCodec.validOutboxTransition(queued, pending), isTrue);
        expect(
          MailStoreCodec.validOutboxTransition(
            queued,
            queued.cancel(now: _later(1)),
          ),
          isTrue,
        );
        for (final outcome in MailSubmissionOutcome.values) {
          final finished = pending.complete(_result(outcome), now: _later(2));
          expect(
            MailStoreCodec.validOutboxTransition(pending, finished),
            isTrue,
          );
          expect(
            MailStoreCodec.validOutboxTransition(finished, finished),
            isTrue,
          );
        }
        final failed = pending.complete(
          _result(MailSubmissionOutcome.retryableFailure),
          now: _later(2),
        );
        expect(
          MailStoreCodec.validOutboxTransition(
            failed,
            failed.beginAttempt(attemptId: 'attempt-2', now: _later(3)),
          ),
          isTrue,
        );
        expect(
          MailStoreCodec.validOutboxTransition(
            failed,
            failed.cancel(now: _later(3)),
          ),
          isTrue,
        );
      },
    );

    test(
      'prepared bytes, envelope, revision, creation and ownership cannot change',
      () {
        final queued = _queued();
        final pending = queued.beginAttempt(
          attemptId: 'attempt-1',
          now: _later(1),
        );
        for (final prepared in [
          _prepared(account: _account(host: 'other')),
          _prepared(wire: MailBytes(Uint8List.fromList([1, 2, 3]))),
          _prepared(draftId: 'other-draft'),
          _prepared(draftRevision: 8),
          _prepared(sender: 'other@example.test'),
          _prepared(recipients: ['hidden@example.test', 'one@example.test']),
          _prepared(recipients: ['one@example.test']),
        ]) {
          expect(
            MailStoreCodec.validOutboxTransition(
              queued,
              _copy(pending, prepared: prepared),
            ),
            isFalse,
          );
        }
        expect(
          MailStoreCodec.validOutboxTransition(
            queued,
            _copy(pending, id: 'other'),
          ),
          isFalse,
        );
        expect(
          MailStoreCodec.validOutboxTransition(
            queued,
            _copy(pending, createdAt: _later(1)),
          ),
          isFalse,
        );
      },
    );

    test(
      'attempt numbers, fresh identity and monotonic time are mandatory',
      () {
        final queued = _queued();
        final pending = queued.beginAttempt(
          attemptId: 'attempt-1',
          now: _later(1),
        );
        expect(
          MailStoreCodec.validOutboxTransition(
            queued,
            _copy(pending, attemptNumber: 2),
          ),
          isFalse,
        );
        expect(
          MailStoreCodec.validOutboxTransition(
            queued,
            queued.beginAttempt(attemptId: 'a', now: _later(-1)),
          ),
          isFalse,
        );
        final failed = pending.complete(
          _result(MailSubmissionOutcome.retryableFailure),
          now: _later(2),
        );
        final retry = failed.beginAttempt(
          attemptId: 'attempt-2',
          now: _later(3),
        );
        expect(
          MailStoreCodec.validOutboxTransition(
            failed,
            _copy(retry, attemptId: 'attempt-1'),
          ),
          isFalse,
        );
        expect(
          MailStoreCodec.validOutboxTransition(
            failed,
            _copy(retry, attemptNumber: 3),
          ),
          isFalse,
        );
        expect(
          MailStoreCodec.validOutboxTransition(
            failed,
            _copy(retry, updatedAt: _later(1)),
          ),
          isFalse,
        );
        final submitted = retry.complete(
          _result(MailSubmissionOutcome.accepted, attemptId: 'attempt-2'),
          now: _later(4),
        );
        expect(
          MailStoreCodec.validOutboxTransition(
            retry,
            _copy(submitted, attemptNumber: 3),
          ),
          isFalse,
        );
      },
    );

    test(
      'same-state saves are exact idempotence and terminal rewrites fail',
      () {
        final queued = _queued();
        expect(
          MailStoreCodec.validOutboxTransition(
            queued,
            _copy(queued, updatedAt: _later(1)),
          ),
          isFalse,
        );
        final pending = queued.beginAttempt(
          attemptId: 'attempt-1',
          now: _later(1),
        );
        for (final terminal in [
          queued.cancel(now: _later(1)),
          pending.complete(
            _result(MailSubmissionOutcome.accepted),
            now: _later(2),
          ),
          pending.complete(
            _result(MailSubmissionOutcome.rejected),
            now: _later(2),
          ),
          pending.complete(
            _result(MailSubmissionOutcome.uncertain),
            now: _later(2),
          ),
        ]) {
          expect(
            MailStoreCodec.validOutboxTransition(terminal, _copy(terminal)),
            isTrue,
          );
          expect(
            MailStoreCodec.validOutboxTransition(terminal, queued),
            isFalse,
          );
          expect(
            MailStoreCodec.validOutboxTransition(terminal, pending),
            isFalse,
          );
          expect(
            MailStoreCodec.validOutboxTransition(
              terminal,
              _copy(terminal, updatedAt: _later(3)),
            ),
            isFalse,
          );
        }
      },
    );

    test('cancellation must retain the previous definite failure result', () {
      final pending = _queued().beginAttempt(
        attemptId: 'attempt-1',
        now: _later(1),
      );
      final failed = pending.complete(
        _result(MailSubmissionOutcome.retryableFailure),
        now: _later(2),
      );
      final cancelled = failed.cancel(now: _later(3));
      final differentResult = MailSubmissionResult(
        attemptId: 'attempt-1',
        outcome: MailSubmissionOutcome.retryableFailure,
        problem: const MailProblem(MailProblemCode.permissionDenied),
      );
      expect(
        MailStoreCodec.validOutboxTransition(
          failed,
          _copy(cancelled, result: differentResult),
        ),
        isFalse,
      );
      expect(MailStoreCodec.validOutboxTransition(failed, cancelled), isTrue);
    });
  });
}

MailAccountId _account({String host = 'office'}) =>
    MailAccountId('account', profile: MailProfileId('profile', hostId: host));

DateTime _later(int seconds) =>
    DateTime.utc(2026, 11, 18).add(Duration(seconds: seconds));

MailEnvelope _envelope() => MailEnvelope(
  subject: 'مرحبا — exact subject',
  from: const [MailAddress('sender@example.test', displayName: 'مرسل Example')],
  to: const [MailAddress('one@example.test', displayName: '')],
  cc: const [MailAddress('copy@example.test')],
  bcc: const [MailAddress('hidden@example.test')],
  replyTo: const [MailAddress('reply@example.test')],
  sentAt: DateTime.utc(2026, 11, 18, 12, 30, 5, 10, 11),
  messageId: '<current@example.test>',
  inReplyTo: '<two@example.test>',
  references: const ['<one@example.test>', '<two@example.test>'],
);

MailDraft _draft() {
  final content = MailBytes(Uint8List.fromList([0, 255, 10, 13, 128]));
  return MailDraft(
    id: 'draft',
    account: _account(),
    revision: 7,
    envelope: _envelope(),
    body: const MailBody(
      plainText: 'مرحبا world\r\n',
      html: '<p>مرحبا <b>world</b></p>',
      plainPartPath: '1.1',
      htmlPartPath: '1.2',
    ),
    attachments: [
      MailAttachment(
        partPath: '2',
        mediaType: 'application/octet-stream',
        displayName: 'binary.bin',
        content: content,
        declaredSize: 10,
      ),
      MailAttachment(
        partPath: '3',
        mediaType: 'image/png',
        displayName: 'image.png',
        content: content,
        contentId: 'image@example.test',
        inline: true,
      ),
    ],
  );
}

MailPreparedMessage _prepared({
  MailAccountId? account,
  MailBytes? wire,
  String draftId = 'draft',
  int draftRevision = 7,
  String sender = 'sender@example.test',
  List<String> recipients = const ['one@example.test', 'hidden@example.test'],
}) => MailPreparedMessage(
  account: account ?? _account(),
  draftId: draftId,
  draftRevision: draftRevision,
  wire:
      wire ??
      MailBytes(
        Uint8List.fromList(ascii.encode('Subject: exact\r\n\r\nBody\r\n')),
      ),
  envelope: MailTransportEnvelope(sender: sender, recipients: recipients),
);

MailOutboxEntry _queued() =>
    MailOutboxEntry.queued(id: 'queue', prepared: _prepared(), now: _later(0));

MailSubmissionResult _result(
  MailSubmissionOutcome outcome, {
  String attemptId = 'attempt-1',
}) => MailSubmissionResult(
  attemptId: attemptId,
  outcome: outcome,
  recipients: const [
    MailRecipientResponse(
      recipient: 'one@example.test',
      acceptance: MailRecipientAcceptance.accepted,
      responseCode: 250,
    ),
  ],
  problem: const MailProblem(
    MailProblemCode.unavailable,
    retryAfter: Duration(seconds: 1, microseconds: 5),
  ),
);

MailOutboxEntry _copy(
  MailOutboxEntry entry, {
  String? id,
  MailPreparedMessage? prepared,
  DateTime? createdAt,
  DateTime? updatedAt,
  int? attemptNumber,
  String? attemptId,
  MailSubmissionResult? result,
}) => MailOutboxEntry.restore(
  id: id ?? entry.id,
  prepared: prepared ?? entry.prepared,
  state: entry.state,
  createdAt: createdAt ?? entry.createdAt,
  updatedAt: updatedAt ?? entry.updatedAt,
  attemptNumber: attemptNumber ?? entry.attemptNumber,
  attemptId: attemptId ?? entry.attemptId,
  result: result ?? entry.result,
);

MailDraft _decodeDraft(
  MailStorePayload payload, {
  String? data,
  Map<String, MailBytes>? blobs,
}) => MailStoreCodec.decodeDraft(
  data ?? payload.data,
  account: _account(),
  id: 'draft',
  revision: 7,
  blobs: blobs ?? payload.blobs,
);

MailOutboxEntry _decodeOutbox(
  MailStorePayload payload, {
  String? data,
  Map<String, MailBytes>? blobs,
}) => MailStoreCodec.decodeOutbox(
  data ?? payload.data,
  account: _account(),
  id: 'queue',
  blobs: blobs ?? payload.blobs,
);

Map<String, Object?> _json(String data) {
  final Object? value = jsonDecode(data);
  return _object(value);
}

Map<String, Object?> _object(Object? value) => value as Map<String, Object?>;
List<Object?> _array(Object? value) => value as List<Object?>;
