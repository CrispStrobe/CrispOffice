import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_outbox_content.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';
import 'package:quds_office_studio/studio_mail_threading.dart';

const _sender = 'writer@example.test';
const _recipient = 'reader@example.test';
final _account = MailAccountId(
  'private-account-key',
  profile: MailProfileId('private-profile', hostId: 'test-host'),
);
final _now = DateTime.utc(2026, 11, 20, 15);

MailOutboxEntry _entry(
  StudioMailDraft draft, {
  String Function(String)? mutate,
  String sender = _sender,
  List<String>? recipients,
}) => _rawEntry(
  (mutate ?? (value) => value)(
    buildStudioMailMessage(draft, _sender).renderMessage(),
  ),
  sender: sender,
  recipients: recipients ?? draft.recipients.envelope,
);

MailOutboxEntry _rawEntry(
  String wire, {
  String sender = _sender,
  List<String> recipients = const [_recipient],
  bool uncertain = false,
}) => MailOutboxEntry.queued(
  id: 'outbox-test',
  prepared: MailPreparedMessage(
    account: _account,
    draftId: 'original-draft-tombstone',
    draftRevision: 4,
    wire: MailBytes(utf8.encode(wire)),
    envelope: MailTransportEnvelope(sender: sender, recipients: recipients),
  ),
  now: _now,
  priorSubmissionUncertain: uncertain,
);

const _draft = StudioMailDraft(
  to: _recipient,
  subject: 'Review me',
  body: 'Frozen body',
);

String _headers([String extra = '']) =>
    'From: $_sender\r\nTo: $_recipient\r\nSubject: Review me\r\n$extra';

String _alternative(
  List<String> parts, {
  String preamble = '',
  String epilogue = '',
}) =>
    '${_headers()}Content-Type: multipart/alternative; boundary="safe-boundary"\r\n\r\n'
    '$preamble${parts.map((part) => '--safe-boundary\r\n$part\r\n').join()}'
    '--safe-boundary--\r\n$epilogue';

String _plain([String text = 'Frozen body']) =>
    'Content-Type: text/plain; charset=utf-8\r\n\r\n$text';

String _html([String text = '<p>Frozen body</p>']) =>
    'Content-Type: text/html; charset=utf-8\r\n\r\n$text';

void _refused(MailOutboxEntry entry) => expect(
  () => StudioMailOutboxContent.fromEntry(entry),
  throwsA(isA<StudioMailOutboxContentException>()),
);

void main() {
  test(
    'generated Unicode message retains complete content, threading and hidden recipients',
    () {
      final bytes = Uint8List.fromList([0, 13, 128, 255, 10]);
      final original = StudioMailDraft(
        to: 'first@example.test, second@example.test',
        cc: 'copy@example.test',
        bcc: 'hidden@example.test',
        subject: 'Grüße — رسالة',
        body: 'Hallo & <Welt> "مرحبا"\r\nSecond line\nThird line',
        thread: StudioMailThread.replyTo(
          MailEnvelope(
            messageId: '<parent@example.test>',
            references: const ['<root@example.test>'],
          ),
        ),
        attachments: StudioMailAttachments.from([
          StudioMailAttachment(
            name: '.résumé-رسالة.txt',
            bytes: bytes,
            mediaType: 'text/plain',
          ),
        ]),
      );
      final entry = _entry(original);
      final content = StudioMailOutboxContent.fromEntry(entry);
      expect(content.draft.subject, original.subject);
      expect(
        content.draft.body.replaceAll('\r\n', '\n'),
        original.body.replaceAll('\r\n', '\n'),
      );
      expect(content.draft.to, original.to);
      expect(content.draft.cc, original.cc);
      expect(content.draft.bcc, original.bcc);
      expect(content.draft.thread.inReplyTo, original.thread.inReplyTo);
      expect(content.draft.thread.references, original.thread.references);
      expect(content.draft.attachments.items.single.name, '.résumé-رسالة.txt');
      expect(
        content.message.attachments.single.displayName,
        '.résumé-رسالة.txt',
      );
      expect(content.draft.attachments.items.single.mediaType, 'text/plain');
      expect(content.draft.attachments.items.single.content.copyBytes(), bytes);
      expect(content.message.raw.bytes, entry.prepared.wire.bytes);
      expect(content.message.envelope.bcc, isEmpty);
      expect(content.message.envelope.messageId, isNotEmpty);
      expect(content.message.envelope.sentAt, isNotNull);
    },
  );

  test('Bcc-only message recovers every hidden transport recipient', () {
    final entry = _entry(
      const StudioMailDraft(
        to: '',
        bcc: 'first@example.test; second@example.test',
        subject: '',
        body: '',
      ),
    );
    final content = StudioMailOutboxContent.fromEntry(entry);
    expect(content.draft.to, isEmpty);
    expect(content.draft.cc, isEmpty);
    expect(content.draft.bcc, 'first@example.test, second@example.test');
    expect(content.draft.body, isEmpty);
  });

  test(
    'canonical cross-group deduplication and case-sensitive local parts survive',
    () {
      final original = StudioMailDraft(
        to: 'One@EXAMPLE.test, One@example.test',
        cc: 'one@example.test; One@EXAMPLE.test',
        bcc: 'hidden@example.test, one@EXAMPLE.test',
        subject: '',
        body: '',
      );
      final content = StudioMailOutboxContent.fromEntry(_entry(original));
      expect(content.draft.to, 'One@EXAMPLE.test');
      expect(content.draft.cc, 'one@example.test');
      expect(content.draft.bcc, 'hidden@example.test');
      expect(content.draft.recipients.envelope, original.recipients.envelope);
    },
  );

  test(
    'legacy complete plain MIME remains editable without invented HTML or headers',
    () {
      final content = StudioMailOutboxContent.fromEntry(
        _rawEntry('${_headers()}${_plain()}'),
      );
      expect(content.draft.body, 'Frozen body');
      expect(content.message.body.html, isNull);
      expect(content.draft.thread.inReplyTo, isNull);
    },
  );

  test('empty and final-newline plain bodies retain their semantic text', () {
    for (final body in ['', 'line\n', 'line\r\n\r\n', 'line\rline']) {
      final content = StudioMailOutboxContent.fromEntry(
        _entry(StudioMailDraft(to: _recipient, subject: '', body: body)),
      );
      expect(
        content.draft.body.replaceAll('\r\n', '\n'),
        body.replaceAll('\r\n', '\n'),
      );
    }
  });

  for (final kind in ['plain', 'ampersands', 'quotes', 'line breaks']) {
    test('maximum admitted composer body remains editable: $kind', () {
      final body = switch (kind) {
        'plain' => 'a' * StudioMailDraft.maxBodyBytes,
        'ampersands' => '&' * StudioMailDraft.maxBodyBytes,
        'quotes' => '"' * StudioMailDraft.maxBodyBytes,
        _ => '${'x' * 63}\n' * (StudioMailDraft.maxBodyBytes ~/ 64),
      };
      final original = StudioMailDraft(to: _recipient, subject: '', body: body);
      expect(original.problem, isNull);
      expect(utf8.encode(body), hasLength(StudioMailDraft.maxBodyBytes));
      final entry = _entry(original);
      final content = StudioMailOutboxContent.fromEntry(entry);
      expect(content.draft.subject, isEmpty);
      expect(content.draft.body, body);
      expect(content.draft.problem, isNull);
      expect(content.message.raw.bytes, entry.prepared.wire.bytes);
      if (kind == 'line breaks') {
        expect(content.message.body.plainText, body.replaceAll('\n', '\r\n'));
        expect(
          content.message.body.plainText!.length,
          greaterThan(StudioMailDraft.maxBodyBytes),
        );
      }
    }, timeout: const Timeout(Duration(seconds: 90)));
  }

  test(
    'projected and original attachment bytes are independently immutable',
    () {
      final initial = Uint8List.fromList([1, 2, 3, 255]);
      final entry = _entry(
        StudioMailDraft(
          to: _recipient,
          subject: '',
          body: '',
          attachments: StudioMailAttachments.from([
            StudioMailAttachment(name: 'opaque.bin', bytes: initial),
          ]),
        ),
      );
      final hash = entry.prepared.wireHash;
      initial.fillRange(0, initial.length, 0);
      final content = StudioMailOutboxContent.fromEntry(entry);
      content.draft.attachments.items.single.content.copyBytes().fillRange(
        0,
        4,
        0,
      );
      content.message.raw.copyBytes().fillRange(
        0,
        content.message.raw.length,
        0,
      );
      expect(content.draft.attachments.items.single.content.copyBytes(), [
        1,
        2,
        3,
        255,
      ]);
      expect(entry.prepared.wireHash, hash);
    },
  );

  test('custom HTML is refused rather than silently flattened or rendered', () {
    for (final html in [
      '<p><b>Frozen body</b></p>',
      '<img src="https://example.test/tracker">',
      '<script>alert(1)</script>',
    ]) {
      _refused(_rawEntry(_alternative([_plain(), _html(html)])));
    }
    _refused(_rawEntry('${_headers()}${_html()}'));
  });

  test(
    'additional alternatives and reversed body order cannot be silently dropped',
    () {
      _refused(
        _rawEntry(
          _alternative([_plain('hidden earlier content'), _plain(), _html()]),
        ),
      );
      _refused(_rawEntry(_alternative([_html(), _plain()])));
      _refused(_rawEntry(_alternative([_plain()])));
    },
  );

  test('nonempty MIME preamble and epilogue are refused', () {
    _refused(
      _rawEntry(
        _alternative([_plain(), _html()], preamble: 'hidden introduction\r\n'),
      ),
    );
    _refused(
      _rawEntry(_alternative([_plain(), _html()], epilogue: 'hidden ending')),
    );
  });

  test('wire Bcc headers are refused even when empty', () {
    for (final bcc in ['', 'hidden@example.test']) {
      _refused(_entry(_draft, mutate: (wire) => 'Bcc: $bcc\r\n$wire'));
    }
  });

  test('address group labels and comments cannot be silently discarded', () {
    for (final to in [
      'undisclosed-recipients:;',
      'Team: $_recipient;',
      '$_recipient (comment)',
    ]) {
      _refused(
        _entry(
          _draft,
          mutate: (wire) => wire.replaceFirst('To: $_recipient', 'To: $to'),
        ),
      );
    }
  });

  test(
    'long supported attachment filenames retain their original spelling',
    () {
      final name = '${'n' * 246}.data';
      final content = StudioMailOutboxContent.fromEntry(
        _entry(
          StudioMailDraft(
            to: _recipient,
            subject: '',
            body: '',
            attachments: StudioMailAttachments.from([
              StudioMailAttachment(name: name, bytes: Uint8List.fromList([1])),
            ]),
          ),
        ),
      );
      expect(content.draft.attachments.items.single.name, name);
      expect(content.message.attachments.single.displayName, name);
    },
  );

  test('sender mismatch and unrepresentable display names are refused', () {
    _refused(_entry(_draft, sender: 'other@example.test'));
    _refused(
      _entry(
        _draft,
        mutate: (wire) => wire.replaceFirst(_sender, 'Named Writer <$_sender>'),
      ),
    );
    _refused(
      _entry(
        _draft,
        mutate: (wire) =>
            wire.replaceFirst(_recipient, 'Named Reader <$_recipient>'),
      ),
    );
  });

  test(
    'visible recipients must exactly occupy the ordered envelope prefix',
    () {
      const draft = StudioMailDraft(
        to: 'a@example.test',
        cc: 'b@example.test',
        bcc: 'c@example.test',
        subject: '',
        body: '',
      );
      for (final recipients in [
        ['b@example.test', 'a@example.test', 'c@example.test'],
        ['a@example.test', 'c@example.test', 'b@example.test'],
        ['a@example.test'],
        ['a@example.test', 'b@EXAMPLE.test', 'c@example.test'],
      ]) {
        _refused(_entry(draft, recipients: recipients));
      }
    },
  );

  test(
    'canonical duplicate envelope recipients cannot be hidden by deduplication',
    () {
      _refused(_entry(_draft, recipients: [_recipient, 'reader@EXAMPLE.test']));
      _refused(
        _entry(_draft, recipients: [_recipient, '"quoted"@example.test']),
      );
    },
  );

  test(
    'unsupported and duplicate root headers do not disappear in an editable copy',
    () {
      for (final header in [
        'Reply-To: alternate@example.test',
        'Sender: $_sender',
        'Subject: another subject',
        'To: hidden@example.test',
        'Disposition-Notification-To: $_sender',
        'X-Custom-Meaning: retain-me',
      ]) {
        _refused(_entry(_draft, mutate: (wire) => '$header\r\n$wire'));
      }
    },
  );

  test('unsupported threading cannot be repaired by dropping references', () {
    for (final header in [
      'References: <orphan@example.test>',
      'In-Reply-To: malformed',
      'In-Reply-To: <parent@example.test>\r\nReferences: (comment) <parent@example.test>',
      'In-Reply-To: <parent@example.test>\r\nReferences: <parent@example.test> <other@example.test>',
    ]) {
      _refused(_entry(_draft, mutate: (wire) => '$header\r\n$wire'));
    }
  });

  test(
    'inline attachment identity and unsupported attachment metadata are refused',
    () {
      final draft = StudioMailDraft(
        to: _recipient,
        subject: '',
        body: '',
        attachments: StudioMailAttachments.from([
          StudioMailAttachment(
            name: 'file.bin',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ]),
      );
      for (final transform in <String Function(String)>[
        (wire) => wire.replaceFirst(
          'Content-Disposition: attachment',
          'Content-ID: <inline-id>\r\nContent-Disposition: attachment',
        ),
        (wire) => wire.replaceFirst(
          'Content-Disposition: attachment',
          'Content-Disposition: inline',
        ),
        (wire) => wire.replaceFirst('size=3', 'size=4'),
        (wire) => wire.replaceFirst(
          'Content-Disposition: attachment',
          'Content-Location: secret/location\r\nContent-Disposition: attachment',
        ),
      ]) {
        _refused(_entry(draft, mutate: transform));
      }
    },
  );

  test(
    'reader filename sanitization cannot silently rename unsafe originals',
    () {
      const attachment =
          'Content-Type: application/octet-stream; name="../private.bin"\r\n'
          'Content-Disposition: attachment; filename="../private.bin"\r\n'
          'Content-Transfer-Encoding: base64\r\n\r\nAQID';
      final wire =
          '${_headers()}Content-Type: multipart/mixed; boundary=x\r\n\r\n'
          '--x\r\n${_plain()}\r\n--x\r\n$attachment\r\n--x--\r\n';
      _refused(_rawEntry(wire));
      _refused(
        _rawEntry(
          wire
              .replaceAll('../private.bin', 'file.bin')
              .replaceFirst('name="file.bin"', 'name="other.bin"'),
        ),
      );
    },
  );

  test(
    'partial, malformed and incomplete MIME are refused while original remains available',
    () {
      for (final wire in [
        '${_headers()}Content-Type: text/plain; charset=unrecognized\r\n\r\nbody',
        '${_headers()}Content-Transfer-Encoding: base64\r\n\r\n%%%bad',
        'not a header\r\n\r\nbody',
        _alternative([
          _plain(),
          _html(),
        ]).replaceFirst('--safe-boundary--', '--missing-end'),
        'From: $_sender',
      ]) {
        final entry = _rawEntry(wire);
        _refused(entry);
        expect(utf8.decode(entry.prepared.wire.bytes), wire);
        expect(() => studioMailOutboxEnvelopeBytes(entry), returnsNormally);
      }
    },
  );

  test('parse budgets reject rather than presenting a truncated success', () {
    final entry = _entry(_draft);
    for (final budget in [
      const MailReadBudget(maxRawBytes: 8),
      const MailReadBudget(maxDecodedBytes: 2),
      const MailReadBudget(maxBodyBytes: 2),
      const MailReadBudget(maxParts: 1),
      const MailReadBudget(maxNestingDepth: 1),
      const MailReadBudget(maxHeaderBytes: 8),
      const MailReadBudget(maxHeaderFieldBytes: 8),
      const MailReadBudget(maxRawBytes: 0),
    ]) {
      expect(
        () => StudioMailOutboxContent.fromEntry(entry, budget: budget),
        throwsA(isA<StudioMailOutboxContentException>()),
      );
    }
  });

  test(
    'oversized composer content is refused even under a loose read budget',
    () {
      final entry = _rawEntry(
        '${_headers()}${_plain('a' * (StudioMailDraft.maxBodyBytes + 1))}',
      );
      expect(
        () => StudioMailOutboxContent.fromEntry(
          entry,
          budget: const MailReadBudget(
            maxRawBytes: 64 * 1024 * 1024,
            maxBodyBytes: 64 * 1024 * 1024,
            maxParts: 10000,
            maxNestingDepth: 10000,
          ),
        ),
        throwsA(isA<StudioMailOutboxContentException>()),
      );
    },
  );

  test(
    'private companion retains frozen envelope and risk without credentials or a send',
    () {
      final queued = _entry(
        const StudioMailDraft(
          to: _recipient,
          bcc: 'hidden@example.test',
          subject: '',
          body: '',
        ),
      );
      final entry = queued
          .beginAttempt(attemptId: 'local-attempt', now: _now)
          .complete(
            MailSubmissionResult(
              attemptId: 'local-attempt',
              outcome: MailSubmissionOutcome.uncertain,
            ),
            now: _now,
          );
      final json = utf8.decode(studioMailOutboxEnvelopeBytes(entry).bytes);
      final data = jsonDecode(json) as Map<String, dynamic>;
      expect(data['version'], 1);
      expect(data['kind'], 'quds-mail-private-outbox-envelope');
      expect(data['sender'], _sender);
      expect(data['recipients'], [_recipient, 'hidden@example.test']);
      expect(data['messageSha256'], entry.prepared.wireHash);
      expect(data['messageId'], isNotEmpty);
      expect(data['messageDateUtc'], isNotEmpty);
      expect(data['state'], 'uncertain');
      expect(data['latestOutcome'], 'uncertain');
      expect(data['attemptCount'], 1);
      expect(data['deliveryEstablished'], isFalse);
      expect(json, isNot(contains('private-account-key')));
      expect(json, isNot(contains('private-profile')));
      expect(json, isNot(contains('local-attempt')));
      expect(json, isNot(contains('original-draft-tombstone')));
      expect(entry.state, MailOutboxState.uncertain);
    },
  );

  test(
    'private companion remains available for unrepresentable custom MIME',
    () {
      final entry = _rawEntry(
        _alternative([_plain(), _html('<b>Different HTML</b>')]),
        uncertain: true,
      );
      _refused(entry);
      final data =
          jsonDecode(utf8.decode(studioMailOutboxEnvelopeBytes(entry).bytes))
              as Map<String, dynamic>;
      expect(data['priorSubmissionUncertain'], isTrue);
      expect(data['recipients'], [_recipient]);
      expect(data['messageSha256'], entry.prepared.wireHash);
    },
  );
}
