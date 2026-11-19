import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

void main() {
  test('observed standard flags have value equality and an empty snapshot', () {
    const empty = MailMessageFlags();
    const observed = MailMessageFlags(isRead: true, isFlagged: true);
    expect(empty.isRead, isFalse);
    expect(empty.isFlagged, isFalse);
    expect(empty.isAnswered, isFalse);
    expect(empty.isDraft, isFalse);
    expect(empty.isDeleted, isFalse);
    expect(observed, const MailMessageFlags(isRead: true, isFlagged: true));
    expect(observed, isNot(empty));
    expect({
      observed,
      const MailMessageFlags(isRead: true, isFlagged: true),
    }, hasLength(1));
    for (final different in const [
      MailMessageFlags(isRead: true),
      MailMessageFlags(isFlagged: true),
      MailMessageFlags(isAnswered: true),
      MailMessageFlags(isDraft: true),
      MailMessageFlags(isDeleted: true),
    ]) {
      expect(different, isNot(empty));
    }
  });

  test('snapshots own bytes, including buffer views and export copies', () {
    final input = Uint8List.fromList([0, 13, 10, 255, 128]);
    final bytes = MailBytes(input);
    final digest = bytes.sha256;
    input[0] = 42;
    expect(bytes.bytes, [0, 13, 10, 255, 128]);
    expect(() => bytes.bytes[0] = 42, throwsUnsupportedError);
    expect(
      () => bytes.bytes.buffer.asUint8List()[0] = 42,
      throwsUnsupportedError,
    );
    final exported = bytes.copyBytes();
    exported[1] = 99;
    expect(bytes.bytes[1], 13);
    expect(bytes.sha256, digest);
    expect(
      MailBytes(Uint8List(0)).sha256,
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('message headers and attachments do not alias mutable input lists', () {
    final from = <MailAddress>[const MailAddress('author@example.test')];
    final attachments = <MailAttachment>[];
    final message = MailMessage(
      raw: MailBytes(Uint8List.fromList([13, 10])),
      envelope: MailEnvelope(from: from),
      attachments: attachments,
    );
    from.clear();
    attachments.add(
      MailAttachment(
        partPath: '1',
        mediaType: 'application/octet-stream',
        displayName: 'part.bin',
        content: MailBytes(Uint8List.fromList([9])),
      ),
    );
    expect(message.envelope.from.single.address, 'author@example.test');
    expect(message.attachments, isEmpty);
    expect(() => message.envelope.from.clear(), throwsUnsupportedError);
    expect(() => message.attachments.clear(), throwsUnsupportedError);
  });

  test('parse result cannot claim success without a message', () {
    expect(
      () => MailParseResult(status: MailParseStatus.complete),
      throwsArgumentError,
    );
    expect(
      () => MailParseResult(status: MailParseStatus.partial),
      throwsArgumentError,
    );
    final message = MailMessage(
      raw: MailBytes(Uint8List(0)),
      envelope: MailEnvelope(),
    );
    final result = MailParseResult(
      status: MailParseStatus.complete,
      message: message,
    );
    expect(identical(result.original, message.raw), isTrue);
    expect(
      () => MailParseResult(
        status: MailParseStatus.complete,
        message: message,
        diagnostics: const [
          MailDiagnostic(
            code: MailDiagnosticCode.rawLimit,
            message: 'Message exceeds the byte budget.',
            severity: MailDiagnosticSeverity.error,
          ),
        ],
      ),
      throwsArgumentError,
    );
    final rejected = MailParseResult(status: MailParseStatus.rejected);
    expect(rejected.hasMessage, isFalse);
    expect(rejected.original, isNull);
  });

  test('full and preview budgets preserve planned resource bounds', () {
    const full = MailReadBudget();
    const preview = MailReadBudget.preview();
    full.validate();
    preview.validate();
    expect(full.maxRawBytes, 32 * 1024 * 1024);
    expect(preview.maxRawBytes, 20 * 1024 * 1024);
    expect(full.maxDecodedBytes, 32 * 1024 * 1024);
    expect(full.maxBodyBytes, 8 * 1024 * 1024);
    expect(full.maxAttachmentBytes, 16 * 1024 * 1024);
    expect(full.maxAttachments, 128);
    expect(full.maxParts, 512);
    expect(full.maxNestingDepth, 20);
    expect(full.maxHeaderBytes, 256 * 1024);
    expect(full.maxHeaderFieldBytes, 64 * 1024);
    expect(
      () => const MailReadBudget(maxParts: 0).validate(),
      throwsArgumentError,
    );
  });

  test('profile and account identities cannot alias between products', () {
    final standalone = MailProfileId('personal', hostId: 'quds.office');
    final embedded = MailProfileId('personal', hostId: 'crispcloud');
    final first = MailAccountId('primary', profile: standalone);
    final second = MailAccountId('primary', profile: embedded);
    expect(first, isNot(second));
    expect({first, second}, hasLength(2));
    expect(
      MailAccountId(
        'primary',
        profile: MailProfileId('personal', hostId: 'quds.office'),
      ),
      first,
    );
    expect(() => MailProfileId('', hostId: 'quds.office'), throwsArgumentError);
  });

  test(
    'UIDVALIDITY, mailbox and account form the IMAP persistent identity',
    () {
      final account = MailAccountId(
        'a',
        profile: MailProfileId('p', hostId: 'office'),
      );
      final inbox = MailMailboxId('INBOX', account: account);
      final first = MailImapIdentity(mailbox: inbox, uidValidity: 1, uid: 42);
      expect(first, MailImapIdentity(mailbox: inbox, uidValidity: 1, uid: 42));
      expect(
        first,
        isNot(MailImapIdentity(mailbox: inbox, uidValidity: 2, uid: 42)),
      );
      expect(
        first,
        isNot(
          MailImapIdentity(
            mailbox: MailMailboxId('Archive', account: account),
            uidValidity: 1,
            uid: 42,
          ),
        ),
      );
      expect(
        () => MailImapIdentity(mailbox: inbox, uidValidity: 1, uid: 0),
        throwsArgumentError,
      );
      expect(
        () =>
            MailImapIdentity(mailbox: inbox, uidValidity: 0x100000000, uid: 1),
        throwsArgumentError,
      );
    },
  );

  test('move and sync cursor enforce account and mailbox scopes', () {
    final profile = MailProfileId('p', hostId: 'office');
    final account = MailAccountId('a', profile: profile);
    final other = MailAccountId('b', profile: profile);
    final inbox = MailMailboxId('INBOX', account: account);
    final otherInbox = MailMailboxId('INBOX', account: other);
    final remote = MailImapIdentity(mailbox: inbox, uidValidity: 1, uid: 1);
    expect(
      () => MailMove(id: 'move', message: remote, destination: otherInbox),
      throwsArgumentError,
    );
    expect(
      () => MailSyncPage(
        mailbox: inbox,
        upserts: [],
        tombstones: [],
        next: MailCursor(mailbox: otherInbox, value: 'cursor'),
        hasMore: false,
      ),
      throwsArgumentError,
    );
    final archive = MailMailboxId('Archive', account: account);
    expect(
      () => MailSyncPage(
        mailbox: archive,
        upserts: [
          MailHeaderRecord(
            id: MailMessageId('m'),
            remote: remote,
            envelope: MailEnvelope(),
          ),
        ],
        tombstones: [],
        next: MailCursor(mailbox: archive, value: 'cursor'),
        hasMore: false,
      ),
      throwsArgumentError,
    );
  });

  test('mail capability does not imply Calendar, People or sending', () {
    final capabilities = MailCapabilities([
      MailCapability.mail,
      MailCapability.folders,
    ]);
    expect(capabilities.supports(MailCapability.mail), isTrue);
    expect(capabilities.supports(MailCapability.calendar), isFalse);
    expect(capabilities.supports(MailCapability.contacts), isFalse);
    expect(capabilities.supports(MailCapability.send), isFalse);
    expect(const MailCapabilities.none().supported, isEmpty);
    expect(
      () => capabilities.supported.add(MailCapability.send),
      throwsUnsupportedError,
    );
  });
}
