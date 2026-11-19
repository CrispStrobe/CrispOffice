@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:test/test.dart';

final _owner = MailProfileId('archive', hostId: 'archive-runner-tests');
final _liveProfile = MailProfileId('mail', hostId: 'mail-runner-tests');
final _account = MailAccountId('connected', profile: _liveProfile);
final _otherAccount = MailAccountId('other', profile: _liveProfile);
final _mailboxId = MailMailboxId('inbox', account: _account);
final _mailbox = MailMailbox(id: _mailboxId, displayName: 'Inbox');
const _profile = MailArchiveProfile(
  id: 'mailbox-profile',
  name: 'Archive inbox',
  source: 'Personal mail',
  kind: MailArchiveProfileKind.mailbox,
  folder: '/Inbox',
  includeSubfolders: false,
);

MailOpaqueIdentity _remote(
  int number, {
  MailAccountId? account,
  MailProviderKind provider = MailProviderKind.ews,
}) => MailOpaqueIdentity(
  account: account ?? _account,
  provider: provider,
  value: 'Remote-$number',
);

MailHeaderRecord _header(
  int number, {
  MailRemoteIdentity? remote,
  String? id,
}) => MailHeaderRecord(
  id: MailMessageId(id ?? 'message-$number'),
  remote: remote ?? _remote(number),
  envelope: MailEnvelope(subject: 'Listing projection $number'),
);

MailMessage _message(
  int number, {
  String? wire,
  String? subject,
  MailRemoteIdentity? remote,
  MailMessageId? localId,
  bool omitLocalId = false,
  bool omitRemote = false,
}) => MailMessage(
  raw: MailBytes(
    Uint8List.fromList(
      utf8.encode(
        wire ?? 'Subject: Full content $number\r\n\r\nOriginal bytes $number',
      ),
    ),
  ),
  envelope: MailEnvelope(subject: subject ?? 'Full content $number'),
  body: MailBody(plainText: 'Original bytes $number'),
  localId: omitLocalId ? null : localId ?? MailMessageId('message-$number'),
  remoteIdentity: omitRemote ? null : remote ?? _remote(number),
);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void main() {
  late SqliteMailArchive archive;
  late _Provider provider;
  late MailAccountSession session;
  late MailArchiveRunner runner;
  MailArchiveFaultInjector? fault;

  Future<void> open({
    MailArchiveLimits limits = const MailArchiveLimits(),
  }) async {
    archive = _value(
      await SqliteMailArchive.open(
        executor: NativeDatabase.memory(),
        profile: _owner,
        limits: limits,
        faultInjector: (point) async => fault?.call(point),
      ),
    );
    runner = MailArchiveRunner(
      archive: archive,
      provider: provider,
      session: session,
    );
  }

  void configure(int count) {
    provider.pages[null] = MailHeaderPage(
      messages: [
        for (var number = 1; number <= count; number++) _header(number),
      ],
    );
    for (var number = 1; number <= count; number++) {
      provider.messages[_remote(number)] = _message(number);
    }
  }

  Future<MailArchiveStats> stats() async => _value(await archive.statistics());

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    fault = null;
    provider = _Provider(_account);
    session = MailAccountSession(_account);
    await open();
  });

  tearDown(() async {
    expect(
      provider.otherCalls,
      0,
      reason: 'Archiving must only fetch headers and MIME.',
    );
    await archive.close();
  });

  test(
    'archives full originals across pages without mutating the provider',
    () async {
      configure(3);
      provider.pages[null] = MailHeaderPage(
        messages: [_header(1), _header(2)],
        next: MailCursor(mailbox: _mailboxId, value: 'page-2'),
      );
      provider.pages['page-2'] = MailHeaderPage(messages: [_header(3)]);
      final progress = <MailArchiveRunProgress>[];
      final report = await runner.archiveMailbox(
        _mailbox,
        profile: _profile,
        pageSize: 2,
        onProgress: progress.add,
      );
      expect(report.status, MailArchiveRunStatus.completed);
      expect(
        (
          report.pages,
          report.processed,
          report.saved,
          report.duplicates,
          report.failed,
        ),
        (2, 3, 3, 0, 0),
      );
      expect(provider.headers.map((call) => call.cursor?.value), [
        null,
        'page-2',
      ]);
      expect(provider.headers.map((call) => call.limit), [2, 2]);
      expect(
        report.bytes,
        provider.messages.values.fold<int>(
          0,
          (sum, message) => sum + message.raw.length,
        ),
      );
      for (final message in provider.messages.values) {
        expect(
          _value(await archive.loadOriginal(message.raw.sha256))!.bytes,
          message.raw.bytes,
        );
        final source = _value(
          await archive.listOrigins(message.raw.sha256),
        ).single;
        expect(source.source, _profile.source);
        expect(source.folder, '/Inbox');
        expect(source.sourceMessageId, matches(r'^[0-9a-f]{64}$'));
      }
      expect((await stats()).messages, 3);
      expect(
        _value(
          await archive.search(
            const MailArchiveSearchRequest(query: 'subject:Full'),
          ),
        ).total,
        3,
      );
      expect(
        _value(
          await archive.search(
            const MailArchiveSearchRequest(query: 'subject:Listing'),
          ),
        ).total,
        0,
      );
      expect(progress.first.phase, MailArchiveRunPhase.started);
      expect(progress.last.phase, MailArchiveRunPhase.finished);
      expect(progress.last.status, MailArchiveRunStatus.completed);
    },
  );

  test(
    'reruns start from page one and deduplicate persistent raw originals',
    () async {
      configure(2);
      final first = await runner.archiveMailbox(_mailbox, profile: _profile);
      final second = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect(first.saved, 2);
      expect((second.saved, second.duplicates, second.bytes), (0, 2, 0));
      expect(second.status, MailArchiveRunStatus.completed);
      expect(provider.headers.map((call) => call.cursor), [null, null]);
      expect((await stats()).messages, 2);
      expect((await stats()).origins, 2);
    },
  );

  test(
    'reconnecting with a fresh live account reuses stable profile provenance',
    () async {
      configure(1);
      final initial = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect(initial.saved, 1);
      final reconnectedAccount = MailAccountId(
        'fresh-session-id',
        profile: _liveProfile,
      );
      final reconnectedMailboxId = MailMailboxId(
        'inbox',
        account: reconnectedAccount,
      );
      final reconnectedRemote = _remote(1, account: reconnectedAccount);
      final reconnected = _Provider(reconnectedAccount);
      reconnected.pages[null] = MailHeaderPage(
        messages: [_header(1, remote: reconnectedRemote)],
      );
      reconnected.messages[reconnectedRemote] = _message(
        1,
        remote: reconnectedRemote,
      );
      final repeat =
          await MailArchiveRunner(
            archive: archive,
            provider: reconnected,
            session: MailAccountSession(reconnectedAccount),
          ).archiveMailbox(
            MailMailbox(id: reconnectedMailboxId, displayName: 'Inbox'),
            profile: _profile,
          );
      expect(
        (repeat.status, repeat.saved, repeat.duplicates),
        (MailArchiveRunStatus.completed, 0, 1),
      );
      expect((await stats()).messages, 1);
      expect((await stats()).origins, 1);
      expect(reconnected.otherCalls, 0);
    },
  );

  test(
    'distinct stable profiles cannot collapse the same remote provenance',
    () async {
      configure(1);
      await runner.archiveMailbox(_mailbox, profile: _profile);
      final otherProfile = MailArchiveProfile(
        id: 'different-source-profile',
        name: 'Different source',
        source: _profile.source,
        kind: MailArchiveProfileKind.mailbox,
        folder: _profile.folder,
        includeSubfolders: false,
      );
      final repeat = await runner.archiveMailbox(
        _mailbox,
        profile: otherProfile,
      );
      expect((repeat.saved, repeat.duplicates), (0, 1));
      expect((await stats()).origins, 2);
    },
  );

  test(
    'provider namespace and case-sensitive opaque identity remain in provenance',
    () async {
      const wire = 'Subject: same\r\n\r\nsame original';
      for (final remote in [
        _remote(1),
        _remote(1, provider: MailProviderKind.graph),
        MailOpaqueIdentity(
          account: _account,
          provider: MailProviderKind.ews,
          value: 'remote-1',
        ),
      ]) {
        provider.pages[null] = MailHeaderPage(
          messages: [_header(1, remote: remote)],
        );
        provider.messages[remote] = _message(1, remote: remote, wire: wire);
        final report = await runner.archiveMailbox(_mailbox, profile: _profile);
        expect(report.status, MailArchiveRunStatus.completed);
      }
      expect((await stats()).messages, 1);
      expect((await stats()).origins, 3);
    },
  );

  test('IMAP provenance retains both UIDVALIDITY and UID', () async {
    const wire = 'Subject: same\r\n\r\nsame original';
    for (final (validity, uid) in [(1, 1), (2, 1), (2, 2)]) {
      final remote = MailImapIdentity(
        mailbox: _mailboxId,
        uidValidity: validity,
        uid: uid,
      );
      provider.pages[null] = MailHeaderPage(
        messages: [_header(1, remote: remote)],
      );
      provider.messages[remote] = _message(1, remote: remote, wire: wire);
      final report = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect(report.status, MailArchiveRunStatus.completed);
    }
    expect((await stats()).messages, 1);
    expect((await stats()).origins, 3);
  });

  test(
    'equal originals in different remote items retain separate origins',
    () async {
      configure(2);
      provider.messages[_remote(1)] = _message(
        1,
        wire: 'Subject: same\r\n\r\nbytes',
      );
      provider.messages[_remote(2)] = _message(
        2,
        wire: 'Subject: same\r\n\r\nbytes',
      );
      final report = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect((report.saved, report.duplicates), (1, 1));
      expect((await stats()).messages, 1);
      final origins = _value(
        await archive.listOrigins(provider.messages[_remote(1)]!.raw.sha256),
      );
      expect(origins, hasLength(2));
      expect(
        origins.map((origin) => origin.sourceMessageId).toSet(),
        hasLength(2),
      );
    },
  );

  test(
    'same source identity with changed raw bytes creates another original',
    () async {
      configure(1);
      final first = await runner.archiveMailbox(_mailbox, profile: _profile);
      provider.messages[_remote(1)] = _message(
        1,
        wire: 'Subject: changed\r\n\r\nnew bytes',
      );
      final second = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect((first.saved, second.saved, second.duplicates), (1, 1, 0));
      expect((await stats()).messages, 2);
    },
  );

  test(
    'valid empty mailbox completes without pretending an unsupported call succeeded',
    () async {
      configure(0);
      final report = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect(
        (report.status, report.pages, report.processed),
        (MailArchiveRunStatus.completed, 1, 0),
      );
      expect(provider.fetches, isEmpty);
    },
  );

  test('a failed item is isolated and later originals are saved', () async {
    configure(3);
    provider.failures[_remote(2)] = const MailProblem(
      MailProblemCode.unavailable,
    );
    final report = await runner.archiveMailbox(_mailbox, profile: _profile);
    expect(report.status, MailArchiveRunStatus.partial);
    expect((report.saved, report.failed, report.processed), (2, 1, 3));
    expect(report.failures.single.ordinal, 2);
    expect(report.failures.single.stage, MailArchiveRunStage.fetch);
    expect(report.failures.single.code, MailProblemCode.unavailable);
    expect((await stats()).messages, 2);
  });

  test(
    'provider exceptions are redacted and a later item can succeed',
    () async {
      configure(2);
      provider.onFetch = (identity, _, _) async {
        if (identity == _remote(1)) {
          throw StateError('SECRET_PROVIDER_RESPONSE');
        }
        return MailSuccess(provider.messages[identity]!);
      };
      final report = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect((report.saved, report.failed), (1, 1));
      expect(report.failures.single.code, MailProblemCode.providerFailure);
      expect(report.status, MailArchiveRunStatus.partial);
    },
  );

  test(
    'consecutive provider failures abort before unbounded requests',
    () async {
      configure(8);
      for (var number = 1; number <= 8; number++) {
        provider.failures[_remote(number)] = const MailProblem(
          MailProblemCode.unavailable,
        );
      }
      final report = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect(report.status, MailArchiveRunStatus.failed);
      expect(report.failed, 3);
      expect(report.problem?.code, MailProblemCode.unavailable);
      expect(provider.fetches, hasLength(3));
    },
  );

  test('successful fetches reset the consecutive-failure bound', () async {
    configure(4);
    provider.failures[_remote(1)] = const MailProblem(
      MailProblemCode.providerFailure,
    );
    provider.failures[_remote(3)] = const MailProblem(
      MailProblemCode.providerFailure,
    );
    final report = await runner.archiveMailbox(
      _mailbox,
      profile: _profile,
      maxConsecutiveProviderFailures: 2,
    );
    expect((report.saved, report.failed), (2, 2));
    expect(provider.fetches, hasLength(4));
    expect(report.status, MailArchiveRunStatus.partial);
  });

  test(
    'failure detail retention is bounded independently from counters',
    () async {
      configure(6);
      for (var number = 1; number <= 6; number++) {
        provider.failures[_remote(number)] = const MailProblem(
          MailProblemCode.providerFailure,
        );
      }
      final report = await runner.archiveMailbox(
        _mailbox,
        profile: _profile,
        maxFailures: 2,
        maxConsecutiveProviderFailures: 10,
      );
      expect(
        (report.failed, report.failures.length, report.droppedFailures),
        (6, 2, 4),
      );
      expect(() => report.failures.clear(), throwsUnsupportedError);
    },
  );

  test(
    'authentication, permission and throttling failures stop without retry',
    () async {
      for (final problem in [
        const MailProblem(MailProblemCode.authenticationRequired),
        const MailProblem(MailProblemCode.permissionDenied),
        const MailProblem(
          MailProblemCode.unavailable,
          retryAfter: Duration(seconds: 30),
        ),
      ]) {
        configure(2);
        provider.fetches.clear();
        provider.failures[_remote(1)] = problem;
        final report = await runner.archiveMailbox(_mailbox, profile: _profile);
        expect(report.problem, same(problem));
        expect(provider.fetches, hasLength(1));
        expect(report.failed, 1);
      }
    },
  );

  test(
    'a page error after a committed page retains the exact prior counts',
    () async {
      configure(1);
      provider.pages[null] = MailHeaderPage(
        messages: [_header(1)],
        next: MailCursor(mailbox: _mailboxId, value: 'second'),
      );
      provider.onHeaders = (_, cursor, _, _) async {
        if (cursor != null) throw StateError('SECRET_PAGE_ERROR');
        return MailSuccess(provider.pages[null]!);
      };
      final report = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect(report.status, MailArchiveRunStatus.partial);
      expect((report.saved, report.failed, report.processed), (1, 0, 1));
      expect(report.problem?.code, MailProblemCode.providerFailure);
      expect((await stats()).messages, 1);
    },
  );

  test('unsupported headers fail explicitly and fetch no messages', () async {
    provider.onHeaders = (_, _, _, _) async =>
        const MailFailure(MailProblem(MailProblemCode.unsupported));
    final report = await runner.archiveMailbox(_mailbox, profile: _profile);
    expect(report.status, MailArchiveRunStatus.failed);
    expect(report.problem?.code, MailProblemCode.unsupported);
    expect(provider.fetches, isEmpty);
  });

  group('ownership and page validation before any write', () {
    final badPages = <String, MailHeaderPage Function()>{
      'wrong account in a later header': () => MailHeaderPage(
        messages: [
          _header(1),
          _header(2, remote: _remote(2, account: _otherAccount)),
        ],
      ),
      'wrong IMAP mailbox': () => MailHeaderPage(
        messages: [
          _header(
            1,
            remote: MailImapIdentity(
              mailbox: MailMailboxId('other-folder', account: _account),
              uidValidity: 1,
              uid: 1,
            ),
          ),
        ],
      ),
      'duplicate local identifier': () => MailHeaderPage(
        messages: [
          _header(1),
          _header(2, id: 'message-1'),
        ],
      ),
      'duplicate remote identifier': () => MailHeaderPage(
        messages: [
          _header(1),
          _header(2, remote: _remote(1)),
        ],
      ),
      'mixed provider namespaces': () => MailHeaderPage(
        messages: [
          _header(1),
          _header(2, remote: _remote(2, provider: MailProviderKind.graph)),
        ],
      ),
      'wrong cursor mailbox': () => MailHeaderPage(
        messages: [_header(1)],
        next: MailCursor(
          mailbox: MailMailboxId('other', account: _account),
          value: 'next',
        ),
      ),
      'wrong cursor account': () => MailHeaderPage(
        messages: [_header(1)],
        next: MailCursor(
          mailbox: MailMailboxId('inbox', account: _otherAccount),
          value: 'next',
        ),
      ),
      'empty cursor': () => MailHeaderPage(
        messages: [_header(1)],
        next: MailCursor(mailbox: _mailboxId, value: ''),
      ),
      'control-bearing cursor': () => MailHeaderPage(
        messages: [_header(1)],
        next: MailCursor(mailbox: _mailboxId, value: 'secret\u0000cursor'),
      ),
      'oversized cursor': () => MailHeaderPage(
        messages: [_header(1)],
        next: MailCursor(mailbox: _mailboxId, value: 'x' * 65537),
      ),
    };
    for (final entry in badPages.entries) {
      test(entry.key, () async {
        configure(2);
        provider.pages[null] = entry.value();
        final report = await runner.archiveMailbox(_mailbox, profile: _profile);
        expect(report.status, MailArchiveRunStatus.failed);
        expect(report.problem?.code, MailProblemCode.providerFailure);
        expect(report.processed, 0);
        expect(provider.fetches, isEmpty);
        expect((await stats()).messages, 0);
      });
    }

    test('page exceeding the requested limit is rejected whole', () async {
      configure(2);
      final report = await runner.archiveMailbox(
        _mailbox,
        profile: _profile,
        pageSize: 1,
      );
      expect(report.problem?.code, MailProblemCode.providerFailure);
      expect(provider.fetches, isEmpty);
      expect((await stats()).messages, 0);
    });

    test('provider namespace cannot change between pages', () async {
      configure(2);
      provider.pages[null] = MailHeaderPage(
        messages: [_header(1)],
        next: MailCursor(mailbox: _mailboxId, value: 'next'),
      );
      provider.pages['next'] = MailHeaderPage(
        messages: [
          _header(2, remote: _remote(2, provider: MailProviderKind.gmail)),
        ],
      );
      final report = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect((report.status, report.saved), (MailArchiveRunStatus.partial, 1));
      expect(provider.fetches, [_remote(1)]);
    });

    test(
      'repeated cursor rejects its page before storing any of that page',
      () async {
        configure(2);
        final next = MailCursor(mailbox: _mailboxId, value: 'repeated');
        provider.pages[null] = MailHeaderPage(
          messages: [_header(1)],
          next: next,
        );
        provider.pages['repeated'] = MailHeaderPage(
          messages: [_header(2)],
          next: next,
        );
        final report = await runner.archiveMailbox(_mailbox, profile: _profile);
        expect(
          (report.status, report.saved, report.pages),
          (MailArchiveRunStatus.partial, 1, 1),
        );
        expect(provider.fetches, [_remote(1)]);
        expect(report.problem?.code, MailProblemCode.providerFailure);
      },
    );

    test('cursor cycles are rejected even when not consecutive', () async {
      configure(3);
      provider.pages[null] = MailHeaderPage(
        messages: [_header(1)],
        next: MailCursor(mailbox: _mailboxId, value: 'a'),
      );
      provider.pages['a'] = MailHeaderPage(
        messages: [_header(2)],
        next: MailCursor(mailbox: _mailboxId, value: 'b'),
      );
      provider.pages['b'] = MailHeaderPage(
        messages: [_header(3)],
        next: MailCursor(mailbox: _mailboxId, value: 'a'),
      );
      final report = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect((report.saved, report.pages), (2, 2));
      expect(provider.fetches, [_remote(1), _remote(2)]);
      expect(report.problem?.code, MailProblemCode.providerFailure);
    });
  });

  test(
    'fetched message must retain exact requested remote and optional local ID',
    () async {
      configure(4);
      provider.messages[_remote(1)] = _message(
        1,
        remote: _remote(1, account: _otherAccount),
      );
      provider.messages[_remote(2)] = _message(
        2,
        localId: MailMessageId('wrong'),
      );
      provider.messages[_remote(3)] = _message(3, omitRemote: true);
      provider.messages[_remote(4)] = _message(4, omitLocalId: true);
      final report = await runner.archiveMailbox(
        _mailbox,
        profile: _profile,
        maxConsecutiveProviderFailures: 4,
      );
      expect((report.saved, report.failed), (1, 3));
      expect(
        report.failures.every(
          (failure) => failure.stage == MailArchiveRunStage.identity,
        ),
        isTrue,
      );
      expect((await stats()).messages, 1);
    },
  );

  test(
    'empty originals are never represented as a successful archive',
    () async {
      configure(1);
      provider.messages[_remote(1)] = _message(1, wire: '');
      final report = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect((report.saved, report.failed), (0, 1));
      expect(report.failures.single.code, MailProblemCode.providerFailure);
      expect((await stats()).messages, 0);
    },
  );

  test(
    'provider raw-budget violation is isolated from the next smaller item',
    () async {
      configure(2);
      provider.messages[_remote(1)] = _message(1, wire: 'x' * 101);
      final report = await runner.archiveMailbox(
        _mailbox,
        profile: _profile,
        budget: const MailReadBudget(maxRawBytes: 100),
      );
      expect((report.saved, report.failed), (1, 1));
      expect(report.failures.single.code, MailProblemCode.quotaExceeded);
    },
  );

  test(
    'provider raw budget is clamped to archive capacity and preserves MIME limits',
    () async {
      await archive.close();
      await open(limits: const MailArchiveLimits(maxMessageBytes: 512));
      configure(1);
      final report = await runner.archiveMailbox(
        _mailbox,
        profile: _profile,
        budget: const MailReadBudget(maxRawBytes: 5000, maxParts: 17),
      );
      expect(report.saved, 1);
      expect(provider.budgets.single.maxRawBytes, 512);
      expect(provider.budgets.single.maxParts, 17);
    },
  );

  test(
    'archive total quota stops further fetching and preserves the earlier commit',
    () async {
      await archive.close();
      await open(limits: const MailArchiveLimits(maxMessages: 1));
      configure(3);
      final report = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect(report.status, MailArchiveRunStatus.limited);
      expect((report.saved, report.failed, report.processed), (1, 1, 2));
      expect(report.problem?.code, MailProblemCode.quotaExceeded);
      expect(provider.fetches, hasLength(2));
      expect((await stats()).messages, 1);
    },
  );

  test(
    'archive write error rolls back and stops further provider work',
    () async {
      configure(3);
      fault = (point) async {
        if (point == MailArchiveCheckpoint.afterContent) {
          throw StateError('SECRET_SQL_DETAILS');
        }
      };
      final report = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect(
        (report.status, report.saved, report.failed),
        (MailArchiveRunStatus.failed, 0, 1),
      );
      expect(report.problem?.code, MailProblemCode.storageFailure);
      expect(provider.fetches, hasLength(1));
      expect((await stats()).messages, 0);
    },
  );

  test(
    'closed archive fails once without repeatedly downloading originals',
    () async {
      configure(3);
      await archive.close();
      final report = await runner.archiveMailbox(_mailbox, profile: _profile);
      expect(report.problem?.code, MailProblemCode.unavailable);
      expect(report.failed, 1);
      expect(provider.fetches, hasLength(1));
    },
  );

  test(
    'message and page limits report limited without an extra request',
    () async {
      configure(3);
      provider.pages[null] = MailHeaderPage(
        messages: [_header(1)],
        next: MailCursor(mailbox: _mailboxId, value: 'next'),
      );
      provider.pages['next'] = MailHeaderPage(
        messages: [_header(2)],
        next: MailCursor(mailbox: _mailboxId, value: 'last'),
      );
      provider.pages['last'] = MailHeaderPage(messages: [_header(3)]);
      final first = await runner.archiveMailbox(
        _mailbox,
        profile: _profile,
        maxMessages: 1,
      );
      expect((first.status, first.saved), (MailArchiveRunStatus.limited, 1));
      expect(provider.headers, hasLength(1));
      expect(provider.headers.single.limit, 1);
      provider.headers.clear();
      final second = await runner.archiveMailbox(
        _mailbox,
        profile: _profile,
        maxPages: 1,
      );
      expect(
        (second.status, second.duplicates),
        (MailArchiveRunStatus.limited, 1),
      );
      expect(provider.headers, hasLength(1));
    },
  );

  test('exact count limit can complete if no continuation exists', () async {
    configure(1);
    final report = await runner.archiveMailbox(
      _mailbox,
      profile: _profile,
      maxMessages: 1,
      maxPages: 1,
    );
    expect(report.status, MailArchiveRunStatus.completed);
  });

  test('empty advancing pages are still bounded by maxPages', () async {
    provider.onHeaders = (_, _, _, _) async => MailSuccess(
      MailHeaderPage(
        messages: [],
        next: MailCursor(
          mailbox: _mailboxId,
          value: 'next-${provider.headers.length}',
        ),
      ),
    );
    final report = await runner.archiveMailbox(
      _mailbox,
      profile: _profile,
      maxPages: 2,
    );
    expect(
      (report.status, report.pages, report.processed),
      (MailArchiveRunStatus.limited, 2, 0),
    );
    expect(provider.headers, hasLength(2));
  });

  test(
    'invalid request limits, folder and profile scope perform no I/O',
    () async {
      final reports = await Future.wait([
        runner.archiveMailbox(_mailbox, profile: _profile, pageSize: 0),
      ]);
      expect(reports.single.problem?.code, MailProblemCode.invalidInput);
      for (final call in <Future<MailArchiveRunReport> Function()>[
        () => runner.archiveMailbox(_mailbox, profile: _profile, maxPages: 0),
        () =>
            runner.archiveMailbox(_mailbox, profile: _profile, maxMessages: 0),
        () =>
            runner.archiveMailbox(_mailbox, profile: _profile, maxFailures: -1),
        () => runner.archiveMailbox(
          _mailbox,
          profile: _profile,
          maxConsecutiveProviderFailures: 0,
        ),
        () => runner.archiveMailbox(
          _mailbox,
          profile: _profile,
          budget: const MailReadBudget(maxParts: 0),
        ),
        () => runner.archiveMailbox(
          _mailbox,
          profile: const MailArchiveProfile(
            id: 'a',
            name: 'a',
            source: 'a',
            kind: MailArchiveProfileKind.mailbox,
            folder: '/../bad',
            includeSubfolders: false,
          ),
        ),
      ]) {
        expect((await call()).problem?.code, MailProblemCode.invalidInput);
      }
      for (final profile in [
        const MailArchiveProfile(
          id: 'a',
          name: 'a',
          source: 'a',
          includeSubfolders: false,
        ),
        const MailArchiveProfile(
          id: 'a',
          name: 'a',
          source: 'a',
          kind: MailArchiveProfileKind.mailbox,
        ),
      ]) {
        expect(
          (await runner.archiveMailbox(
            _mailbox,
            profile: profile,
          )).problem?.code,
          MailProblemCode.unsupported,
        );
      }
      expect(provider.headers, isEmpty);
    },
  );

  test(
    'canonical folder overflow is rejected before any provider fetch',
    () async {
      configure(1);
      final report = await runner.archiveMailbox(
        _mailbox,
        profile: MailArchiveProfile(
          id: _profile.id,
          name: _profile.name,
          source: _profile.source,
          kind: MailArchiveProfileKind.mailbox,
          includeSubfolders: false,
          folder: 'x' * 4096,
        ),
      );
      expect(report.status, MailArchiveRunStatus.failed);
      expect(report.problem?.code, MailProblemCode.invalidInput);
      expect(report.processed, 0);
      expect(provider.headers, isEmpty);
      expect(provider.fetches, isEmpty);
      expect((await stats()).messages, 0);
    },
  );

  test(
    'exact canonical folder boundary remains archivable and searchable',
    () async {
      configure(1);
      final relative = 'x' * 4095;
      final canonical = '/$relative';
      for (final folder in [relative, canonical]) {
        final report = await runner.archiveMailbox(
          _mailbox,
          profile: MailArchiveProfile(
            id: _profile.id,
            name: _profile.name,
            source: _profile.source,
            kind: MailArchiveProfileKind.mailbox,
            includeSubfolders: false,
            folder: folder,
          ),
        );
        expect(report.status, MailArchiveRunStatus.completed);
        expect(report.saved + report.duplicates, 1);
      }
      final result = _value(
        await archive.search(
          MailArchiveSearchRequest(folder: canonical, includeSubfolders: false),
        ),
      );
      expect(result.total, 1);
      expect(
        _value(
          await archive.listOrigins(result.hits.single.entry.id),
        ).single.folder,
        canonical,
      );
      expect((await stats()).origins, 1);
    },
  );

  test('account mismatch is rejected before provider calls', () async {
    final otherMailbox = MailMailbox(
      id: MailMailboxId('inbox', account: _otherAccount),
      displayName: 'Other',
    );
    expect(
      (await runner.archiveMailbox(
        otherMailbox,
        profile: _profile,
      )).problem?.code,
      MailProblemCode.invalidInput,
    );
    final otherSession = MailAccountSession(_otherAccount);
    final wrongRunner = MailArchiveRunner(
      archive: archive,
      provider: provider,
      session: otherSession,
    );
    expect(
      (await wrongRunner.archiveMailbox(
        _mailbox,
        profile: _profile,
      )).problem?.code,
      MailProblemCode.invalidInput,
    );
    expect(provider.headers, isEmpty);
  });

  test(
    'one provider cannot have concurrent runs through different runner instances',
    () async {
      configure(1);
      final entered = Completer<void>();
      final release = Completer<MailResult<MailHeaderPage>>();
      provider.onHeaders = (_, _, _, _) {
        entered.complete();
        return release.future;
      };
      final first = runner.archiveMailbox(_mailbox, profile: _profile);
      await entered.future;
      expect(runner.isRunning, isTrue);
      final other = MailArchiveRunner(
        archive: archive,
        provider: provider,
        session: session,
      );
      final busy = await other.archiveMailbox(_mailbox, profile: _profile);
      expect(busy.problem?.code, MailProblemCode.conflict);
      expect(provider.headers, hasLength(1));
      release.complete(MailSuccess(provider.pages[null]!));
      expect((await first).saved, 1);
      expect(runner.isRunning, isFalse);
      provider.onHeaders = null;
      expect(
        (await other.archiveMailbox(_mailbox, profile: _profile)).duplicates,
        1,
      );
    },
  );

  test(
    'throwing progress observers cannot interrupt committed work or leak data',
    () async {
      configure(2);
      final events = <MailArchiveRunProgress>[];
      final report = await runner.archiveMailbox(
        _mailbox,
        profile: _profile,
        onProgress: (event) {
          events.add(event);
          throw StateError('SECRET_LOGGER_CONTENT');
        },
      );
      expect(
        (report.status, report.saved, report.failed),
        (MailArchiveRunStatus.completed, 2, 0),
      );
      expect(report.observerErrors, events.length);
      final logged = jsonEncode(events.map((event) => event.toJson()).toList());
      for (final secret in [
        'Remote-',
        'SECRET',
        'Personal mail',
        'Inbox',
        'Full content',
        'Original bytes',
        'connected',
      ]) {
        expect(logged, isNot(contains(secret)));
      }
    },
  );

  group('lease and cancellation boundaries', () {
    test(
      'pre-cancellation and disposed sessions make no provider calls',
      () async {
        final cancellation = MailCancellationSource()..cancel();
        final cancelled = await runner.archiveMailbox(
          _mailbox,
          profile: _profile,
          cancellation: cancellation.token,
        );
        expect(cancelled.status, MailArchiveRunStatus.cancelled);
        expect(cancelled.problem?.code, MailProblemCode.cancelled);
        session.dispose();
        final stale = await runner.archiveMailbox(_mailbox, profile: _profile);
        expect(stale.status, MailArchiveRunStatus.cancelled);
        expect(stale.problem?.code, MailProblemCode.staleOperation);
        expect(provider.headers, isEmpty);
      },
    );

    test(
      'stale header response is rejected before any message fetch',
      () async {
        configure(1);
        provider.onHeaders = (_, _, _, _) async {
          session.invalidate();
          return MailSuccess(provider.pages[null]!);
        };
        final report = await runner.archiveMailbox(_mailbox, profile: _profile);
        expect(report.status, MailArchiveRunStatus.cancelled);
        expect(report.problem?.code, MailProblemCode.staleOperation);
        expect(provider.fetches, isEmpty);
        expect((await stats()).messages, 0);
      },
    );

    test('cancelled fetched message is not committed', () async {
      configure(1);
      final cancellation = MailCancellationSource();
      provider.onFetch = (identity, _, _) async {
        cancellation.cancel();
        return MailSuccess(provider.messages[identity]!);
      };
      final report = await runner.archiveMailbox(
        _mailbox,
        profile: _profile,
        cancellation: cancellation.token,
      );
      expect(
        (report.status, report.processed),
        (MailArchiveRunStatus.cancelled, 0),
      );
      expect((await stats()).messages, 0);
    });

    test(
      'cancellation during archive transaction rolls back all of the item',
      () async {
        configure(1);
        final cancellation = MailCancellationSource();
        fault = (point) async {
          if (point == MailArchiveCheckpoint.beforeCommit) {
            cancellation.cancel();
          }
        };
        final report = await runner.archiveMailbox(
          _mailbox,
          profile: _profile,
          cancellation: cancellation.token,
        );
        expect(
          (report.status, report.saved, report.failed),
          (MailArchiveRunStatus.cancelled, 0, 0),
        );
        expect((await stats()).messages, 0);
      },
    );

    test(
      'session invalidation during archive transaction rolls back the item',
      () async {
        configure(1);
        fault = (point) async {
          if (point == MailArchiveCheckpoint.beforeCommit) session.invalidate();
        };
        final report = await runner.archiveMailbox(_mailbox, profile: _profile);
        expect(
          (report.status, report.saved, report.failed),
          (MailArchiveRunStatus.cancelled, 0, 0),
        );
        expect(report.problem?.code, MailProblemCode.staleOperation);
        expect((await stats()).messages, 0);
      },
    );

    test(
      'cancellation immediately after a committed item retains its counts',
      () async {
        configure(2);
        final cancellation = MailCancellationSource();
        final report = await runner.archiveMailbox(
          _mailbox,
          profile: _profile,
          cancellation: cancellation.token,
          onProgress: (progress) {
            if (progress.phase == MailArchiveRunPhase.message &&
                progress.saved == 1) {
              cancellation.cancel();
            }
          },
        );
        expect(
          (report.status, report.saved, report.processed),
          (MailArchiveRunStatus.cancelled, 1, 1),
        );
        expect(provider.fetches, hasLength(1));
        expect((await stats()).messages, 1);
      },
    );

    test(
      'provider-reported cancellation stops without counting a failed item',
      () async {
        configure(2);
        provider.failures[_remote(1)] = const MailProblem(
          MailProblemCode.cancelled,
        );
        final report = await runner.archiveMailbox(_mailbox, profile: _profile);
        expect(
          (report.status, report.processed, report.failed),
          (MailArchiveRunStatus.cancelled, 0, 0),
        );
        expect(provider.fetches, hasLength(1));
      },
    );
  });
}

typedef _Headers =
    Future<MailResult<MailHeaderPage>> Function(
      MailMailboxId mailbox,
      MailCursor? cursor,
      int limit,
      MailOperationLease lease,
    );
typedef _Fetch =
    Future<MailResult<MailMessage>> Function(
      MailRemoteIdentity identity,
      MailReadBudget budget,
      MailOperationLease lease,
    );

final class _HeaderCall {
  const _HeaderCall(this.mailbox, this.cursor, this.limit);
  final MailMailboxId mailbox;
  final MailCursor? cursor;
  final int limit;
}

final class _Provider implements MailProvider {
  _Provider(this.account);
  @override
  final MailAccountId account;
  final Map<String?, MailHeaderPage> pages = {};
  final Map<MailRemoteIdentity, MailMessage> messages = {};
  final Map<MailRemoteIdentity, MailProblem> failures = {};
  final List<_HeaderCall> headers = [];
  final List<MailRemoteIdentity> fetches = [];
  final List<MailReadBudget> budgets = [];
  _Headers? onHeaders;
  _Fetch? onFetch;
  int otherCalls = 0;

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    headers.add(_HeaderCall(mailbox, cursor, limit));
    if (onHeaders case final handler?) {
      return handler(mailbox, cursor, limit, lease);
    }
    return MailSuccess(pages[cursor?.value]!);
  }

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    fetches.add(identity);
    budgets.add(budget);
    if (onFetch case final handler?) return handler(identity, budget, lease);
    if (failures[identity] case final problem?) return MailFailure(problem);
    return MailSuccess(messages[identity]!);
  }

  Never _forbidden() {
    otherCalls++;
    throw StateError('Archiving attempted a non-read operation.');
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async => _forbidden();

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => _forbidden();

  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async => _forbidden();

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) async => _forbidden();
}
