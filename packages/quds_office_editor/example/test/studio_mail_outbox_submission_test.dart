import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_outbox.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';
import 'package:quds_office_studio/studio_mail_threading.dart';
import 'package:test/fake.dart';
import 'package:test/test.dart';

const _sender = 'writer@example.test';
final _account = MailAccountId(
  'account',
  profile: MailProfileId('profile', hostId: 'outbox-submission-fixture'),
);
final _now = DateTime.utc(2026, 11, 20);

MailPreparedMessage _prepared({StudioMailDraft? draft, String? raw}) {
  final snapshot =
      draft ??
      const StudioMailDraft(
        to: 'reader@example.test',
        subject: 'Frozen message',
        body: 'The original body.',
      );
  return MailPreparedMessage(
    account: _account,
    draftId: 'draft',
    draftRevision: 7,
    wire: MailBytes(
      utf8.encode(
        raw ?? buildStudioMailMessage(snapshot, _sender).renderMessage(),
      ),
    ),
    envelope: MailTransportEnvelope(
      sender: _sender,
      recipients: snapshot.recipients.envelope,
    ),
  );
}

MailOutboxEntry _queued([MailPreparedMessage? prepared]) =>
    MailOutboxEntry.queued(
      id: 'outbox',
      prepared: prepared ?? _prepared(),
      now: _now,
    );

final class _Store extends Fake implements StudioMailOutboxStore {
  _Store(this.current);

  MailOutboxEntry current;
  final calls = <String>[];
  final acknowledged = <bool>[];
  final results = <MailSubmissionResult>[];
  Completer<void>? beginGate;
  Object? beginError;
  Object? completionError;
  int attempts = 0;

  @override
  MailAccountId get account => current.prepared.account;

  @override
  Future<MailOutboxEntry> beginOutboxAttempt(
    MailOutboxEntry entry, {
    bool acknowledgeUncertain = false,
  }) async {
    calls.add('begin requested');
    acknowledged.add(acknowledgeUncertain);
    await beginGate?.future;
    if (beginError case final error?) throw error;
    if (entry.id != current.id ||
        entry.state != current.state ||
        entry.attemptId != current.attemptId) {
      throw StateError('Stale fixture entry.');
    }
    final id = 'attempt-${++attempts}';
    current = acknowledgeUncertain && entry.canBeginAcknowledgedAttempt
        ? entry.beginAcknowledgedAttempt(attemptId: id, now: _now)
        : entry.beginAttempt(attemptId: id, now: _now);
    calls.add('begin persisted');
    return current;
  }

  @override
  Future<MailOutboxEntry> completeOutboxAttempt(
    MailOutboxEntry entry,
    MailSubmissionResult result,
  ) async {
    calls.add('complete requested');
    results.add(result);
    if (completionError case final error?) throw error;
    current = entry.complete(result, now: _now);
    calls.add('complete persisted');
    return current;
  }
}

final class _Client extends Fake implements mail.MailClient {
  final wires = <String>[];
  final messages = <mail.MimeMessage>[];
  final senders = <String?>[];
  final recipients = <List<String>?>[];
  final appendRequests = <bool>[];
  final unicodeRequests = <bool>[];
  final eightBitRequests = <bool>[];
  Future<void> Function(mail.MimeMessage message)? onSend;

  @override
  Future<void> sendMessage(
    mail.MimeMessage message, {
    mail.MailAddress? from,
    bool appendToSent = true,
    bool supportUnicode = false,
    mail.Mailbox? sentMailbox,
    bool use8BitEncoding = false,
    List<mail.MailAddress>? recipients,
  }) async {
    wires.add(message.renderMessage());
    messages.add(message);
    senders.add(from?.email);
    this.recipients.add(
      recipients?.map((recipient) => recipient.email).toList(),
    );
    appendRequests.add(appendToSent);
    unicodeRequests.add(supportUnicode);
    eightBitRequests.add(use8BitEncoding);
    await onSend?.call(message);
  }
}

void main() {
  test(
    'durable begin completes before the provider sees frozen bytes',
    () async {
      final queued = _queued();
      final gate = Completer<void>();
      final store = _Store(queued)..beginGate = gate;
      var callbacks = 0;
      final submitting = submitStudioMailOutbox(
        store: store,
        entry: queued,
        isCurrent: () => true,
        onAttemptPersisted: (attempt) {
          expect(identical(attempt, store.current), isTrue);
          expect(attempt.state, MailOutboxState.submitting);
          expect(store.calls, ['begin requested', 'begin persisted']);
          store.calls.add('status notified');
        },
        submit: (prepared, {required attemptId}) async {
          callbacks++;
          expect(store.current.state, MailOutboxState.submitting);
          expect(store.current.attemptId, attemptId);
          expect(store.calls, [
            'begin requested',
            'begin persisted',
            'status notified',
          ]);
          expect(identical(prepared, queued.prepared), isTrue);
          store.calls.add('provider called');
          return MailSubmissionResult(
            attemptId: attemptId,
            outcome: MailSubmissionOutcome.accepted,
          );
        },
      );
      await Future<void>.value();
      expect(callbacks, 0);
      expect(store.current.state, MailOutboxState.queued);
      gate.complete();
      final completed = await submitting;
      expect(callbacks, 1);
      expect(completed.state, MailOutboxState.submitted);
      expect(store.calls, [
        'begin requested',
        'begin persisted',
        'status notified',
        'provider called',
        'complete requested',
        'complete persisted',
      ]);
    },
  );

  for (final callback in ['status notification', 'session check']) {
    test(
      '$callback failure completes uncertainty without contacting provider',
      () async {
        final queued = _queued();
        final store = _Store(queued);
        var providers = 0;
        final completed = await submitStudioMailOutbox(
          store: store,
          entry: queued,
          onAttemptPersisted: (_) {
            if (callback == 'status notification') {
              throw StateError('private-status-callback');
            }
          },
          isCurrent: () {
            if (callback == 'session check') {
              throw StateError('private-session-callback');
            }
            return true;
          },
          submit: (_, {required attemptId}) async {
            providers++;
            return MailSubmissionResult(
              attemptId: attemptId,
              outcome: MailSubmissionOutcome.accepted,
            );
          },
        );
        expect(providers, 0);
        expect(completed.state, MailOutboxState.uncertain);
        expect(store.results, hasLength(1));
        expect(store.results.single.attemptId, completed.attemptId);
        expect(store.results.single.problem, isNull);
      },
    );
  }

  test(
    'begin persistence failure never invokes the provider or records a result',
    () async {
      final queued = _queued();
      final error = StateError('private-begin-error');
      final store = _Store(queued)..beginError = error;
      var callbacks = 0;
      await expectLater(
        submitStudioMailOutbox(
          store: store,
          entry: queued,
          isCurrent: () => true,
          submit: (_, {required attemptId}) async {
            callbacks++;
            return MailSubmissionResult(
              attemptId: attemptId,
              outcome: MailSubmissionOutcome.accepted,
            );
          },
        ),
        throwsA(same(error)),
      );
      expect(callbacks, 0);
      expect(store.results, isEmpty);
      expect(store.current.state, MailOutboxState.queued);
    },
  );

  test(
    'a session invalidated while begin persists cannot reach the provider',
    () async {
      final queued = _queued();
      final gate = Completer<void>();
      final store = _Store(queued)..beginGate = gate;
      var current = true;
      var callbacks = 0;
      final submitting = submitStudioMailOutbox(
        store: store,
        entry: queued,
        isCurrent: () => current,
        submit: (_, {required attemptId}) async {
          callbacks++;
          return MailSubmissionResult(
            attemptId: attemptId,
            outcome: MailSubmissionOutcome.accepted,
          );
        },
      );
      current = false;
      gate.complete();
      final completed = await submitting;
      expect(callbacks, 0);
      expect(completed.state, MailOutboxState.retryableFailure);
      expect(store.results.single.attemptId, store.current.attemptId);
      expect(completed.canBeginAttempt, isTrue);
    },
  );

  test(
    'stale-session rejection preserves uncertainty from an earlier attempt',
    () async {
      final first = _queued().beginAttempt(attemptId: 'earlier', now: _now);
      final uncertain = first.recoverInterrupted(now: _now);
      final store = _Store(uncertain);
      var callbacks = 0;
      final completed = await submitStudioMailOutbox(
        store: store,
        entry: uncertain,
        acknowledgeUncertain: true,
        isCurrent: () => false,
        submit: (_, {required attemptId}) async {
          callbacks++;
          return MailSubmissionResult(
            attemptId: attemptId,
            outcome: MailSubmissionOutcome.accepted,
          );
        },
      );
      expect(callbacks, 0);
      expect(store.acknowledged, [true]);
      expect(completed.state, MailOutboxState.retryableFailure);
      expect(completed.priorSubmissionUncertain, isTrue);
      expect(completed.canBeginAttempt, isFalse);
      expect(completed.canBeginAcknowledgedAttempt, isTrue);
    },
  );

  for (final malformed in ['foreign attempt', 'foreign recipient']) {
    test(
      '$malformed response becomes uncertainty for the actual attempt',
      () async {
        final queued = _queued();
        final store = _Store(queued);
        final completed = await submitStudioMailOutbox(
          store: store,
          entry: queued,
          isCurrent: () => true,
          submit: (_, {required attemptId}) async => MailSubmissionResult(
            attemptId: malformed == 'foreign attempt'
                ? 'other-attempt'
                : attemptId,
            outcome: MailSubmissionOutcome.accepted,
            recipients: malformed == 'foreign recipient'
                ? [
                    const MailRecipientResponse(
                      recipient: 'other@example.test',
                      acceptance: MailRecipientAcceptance.accepted,
                    ),
                  ]
                : const [],
          ),
        );
        expect(completed.state, MailOutboxState.uncertain);
        expect(store.results.single.attemptId, completed.attemptId);
        expect(store.results.single.recipients, isEmpty);
        expect(store.results.single.problem, isNull);
        expect(completed.canBeginAttempt, isFalse);
      },
    );
  }

  for (final synchronous in [false, true]) {
    test(
      '${synchronous ? 'synchronous' : 'asynchronous'} provider error is uncertain',
      () async {
        final queued = _queued();
        final store = _Store(queued);
        final completed = await submitStudioMailOutbox(
          store: store,
          entry: queued,
          isCurrent: () => true,
          submit: (_, {required attemptId}) {
            final error = StateError('private-provider-error');
            if (synchronous) throw error;
            return Future<MailSubmissionResult>.error(error);
          },
        );
        expect(completed.state, MailOutboxState.uncertain);
        expect(store.results.single.problem, isNull);
        expect(store.results.single.recipients, isEmpty);
      },
    );
  }

  test(
    'a late matching acceptance still completes the old durable attempt',
    () async {
      final queued = _queued();
      final store = _Store(queued);
      final entered = Completer<void>();
      final gate = Completer<MailSubmissionResult>();
      var current = true;
      final submitting = submitStudioMailOutbox(
        store: store,
        entry: queued,
        isCurrent: () => current,
        submit: (_, {required attemptId}) {
          entered.complete();
          return gate.future;
        },
      );
      await entered.future;
      current = false;
      gate.complete(
        MailSubmissionResult(
          attemptId: store.current.attemptId!,
          outcome: MailSubmissionOutcome.accepted,
        ),
      );
      expect((await submitting).state, MailOutboxState.submitted);
      expect(store.results, hasLength(1));
    },
  );

  test(
    'completion failure propagates after acceptance without a fabricated retry',
    () async {
      final queued = _queued();
      final error = StateError('private-result-write-error');
      final store = _Store(queued)..completionError = error;
      var callbacks = 0;
      await expectLater(
        submitStudioMailOutbox(
          store: store,
          entry: queued,
          isCurrent: () => true,
          submit: (_, {required attemptId}) async {
            callbacks++;
            return MailSubmissionResult(
              attemptId: attemptId,
              outcome: MailSubmissionOutcome.accepted,
            );
          },
        ),
        throwsA(same(error)),
      );
      expect(callbacks, 1);
      expect(store.current.state, MailOutboxState.submitting);
      expect(store.results, hasLength(1));
      expect(store.results.single.outcome, MailSubmissionOutcome.accepted);
      expect(
        store.calls.where((call) => call == 'complete requested'),
        hasLength(1),
      );
    },
  );

  test(
    'explicit native retry preserves exact MIME, Unicode content and Bcc envelope',
    () async {
      final source = Uint8List.fromList([0, 13, 10, 128, 255, 42]);
      final draft = StudioMailDraft(
        to: 'primary@Example.test; second@example.test',
        cc: 'primary@example.test, copy@example.test',
        bcc: 'copy@example.test; hidden@example.test',
        subject: 'München مرحبا',
        body: 'مرحبا\nRésumé <reader> & team.',
        thread: StudioMailThread.replyTo(
          MailEnvelope(
            messageId: '<parent@example.test>',
            references: ['<root@example.test>'],
          ),
        ),
        attachments: StudioMailAttachments.from([
          StudioMailAttachment(name: 'résumé-ملف.bin', bytes: source),
        ]),
      );
      source.fillRange(0, source.length, 99);
      final prepared = _prepared(draft: draft);
      final frozen = ascii.decode(prepared.wire.bytes);
      final store = _Store(_queued(prepared));
      final client = _Client()
        ..onSend = (message) async {
          // A provider-side mutation cannot alter the persisted snapshot or a
          // later parse of that snapshot for the explicitly acknowledged retry.
          message.addHeader('X-Provider-Mutation', 'transient');
          throw StateError('private-native-error');
        };
      final uncertain = await submitStudioMailOutbox(
        store: store,
        entry: store.current,
        isCurrent: () => true,
        submit: (message, {required attemptId}) =>
            submitStudioMailNativeOutbox(client, message, attemptId: attemptId),
      );
      expect(uncertain.state, MailOutboxState.uncertain);
      expect(client.wires, hasLength(1));
      await expectLater(
        submitStudioMailOutbox(
          store: store,
          entry: uncertain,
          isCurrent: () => true,
          submit: (message, {required attemptId}) =>
              submitStudioMailNativeOutbox(
                client,
                message,
                attemptId: attemptId,
              ),
        ),
        throwsStateError,
      );
      expect(client.wires, hasLength(1));
      client.onSend = null;
      final accepted = await submitStudioMailOutbox(
        store: store,
        entry: uncertain,
        acknowledgeUncertain: true,
        isCurrent: () => true,
        submit: (message, {required attemptId}) =>
            submitStudioMailNativeOutbox(client, message, attemptId: attemptId),
      );
      expect(accepted.state, MailOutboxState.submitted);
      expect(accepted.attemptId, isNot(uncertain.attemptId));
      expect(client.wires, [frozen, frozen]);
      expect(client.senders, [_sender, _sender]);
      expect(client.appendRequests, [false, false]);
      expect(client.unicodeRequests, [false, false]);
      expect(client.eightBitRequests, [false, false]);
      expect(frozen.codeUnits.every((unit) => unit < 128), isTrue);
      expect(frozen, isNot(contains('hidden@example.test')));
      expect(frozen, isNot(contains('X-Provider-Mutation')));
      for (var index = 0; index < client.wires.length; index++) {
        expect(client.recipients[index], [
          'primary@Example.test',
          'second@example.test',
          'copy@example.test',
          'hidden@example.test',
        ]);
        final parsed = const QudsMimeCodec().parse(
          utf8.encode(client.wires[index]),
        );
        expect(parsed.status, MailParseStatus.complete);
        final message = parsed.message!;
        expect(message.envelope.subject, draft.subject);
        expect(message.body.plainText, draft.body);
        expect(message.envelope.bcc, isEmpty);
        expect(message.envelope.inReplyTo, '<parent@example.test>');
        expect(message.envelope.to.map((recipient) => recipient.address), [
          'primary@Example.test',
          'second@example.test',
        ]);
        expect(message.envelope.cc.single.address, 'copy@example.test');
        expect(message.attachments.single.displayName, 'résumé-ملف.bin');
        expect(message.attachments.single.content.bytes, [
          0,
          13,
          10,
          128,
          255,
          42,
        ]);
      }
      final first = mail.MimeMessage.parseFromText(client.wires.first);
      final second = mail.MimeMessage.parseFromText(client.wires.last);
      expect(first.getHeaderValue('Date'), isNotNull);
      expect(first.getHeaderValue('Message-ID'), isNotNull);
      expect(second.getHeaderValue('Date'), first.getHeaderValue('Date'));
      expect(
        second.getHeaderValue('Message-ID'),
        first.getHeaderValue('Message-ID'),
      );
      expect(
        second.getHeaderValue('Content-Type'),
        first.getHeaderValue('Content-Type'),
      );
      expect(prepared.wire.bytes, utf8.encode(frozen));
    },
  );

  for (final followUp in ['sent copy', 'connection cleanup']) {
    test(
      'matching native $followUp error preserves confirmed acceptance',
      () async {
        final client = _Client();
        client.onSend = (_) async => throw mail.MailSendPostSubmissionException(
          client,
          sentCopyError: followUp == 'sent copy'
              ? StateError('private-copy')
              : null,
          cleanupError: followUp == 'connection cleanup'
              ? StateError('private-cleanup')
              : null,
        );
        final result = await submitStudioMailNativeOutbox(
          client,
          _prepared(),
          attemptId: 'current-attempt',
        );
        expect(client.wires, hasLength(1));
        expect(result.attemptId, 'current-attempt');
        expect(result.outcome, MailSubmissionOutcome.accepted);
        expect(result.problem, isNull);
      },
    );
  }

  test(
    'post-submission error from another client cannot prove acceptance',
    () async {
      final foreign = _Client();
      final client = _Client()
        ..onSend = (_) async => throw mail.MailSendPostSubmissionException(
          foreign,
          cleanupError: StateError('another-account-cleanup'),
        );
      final result = await submitStudioMailNativeOutbox(
        client,
        _prepared(),
        attemptId: 'current-attempt',
      );
      expect(result.outcome, MailSubmissionOutcome.uncertain);
      expect(result.attemptId, 'current-attempt');
      expect(client.wires, hasLength(1));
      expect(foreign.wires, isEmpty);
    },
  );

  for (final fixture in <String, String>{
    'raw non-ASCII': 'From: $_sender\r\nTo: reader@example.test\r\n\r\nمرحبا',
    'normalization would change frozen bytes':
        'From: $_sender\nTo: reader@example.test\n\nBody\n',
  }.entries) {
    test(
      '${fixture.key} is rejected before any native network callback',
      () async {
        final client = _Client();
        final result = await submitStudioMailNativeOutbox(
          client,
          _prepared(raw: fixture.value),
          attemptId: 'invalid-wire-attempt',
        );
        expect(result.attemptId, 'invalid-wire-attempt');
        expect(result.outcome, MailSubmissionOutcome.rejected);
        expect(client.wires, isEmpty);
        expect(result.problem, isNull);
      },
    );
  }
}
