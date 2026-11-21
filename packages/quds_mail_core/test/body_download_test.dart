import 'dart:async';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

void main() {
  late MailAccountId account;
  late MailMailboxId inbox;
  late MailAccountSession session;
  late _Provider provider;
  late _Cache cache;

  MailBodyDownloadRunner runner({
    int maxMessages = 100,
    int maxRetainedBytes = 64 * 1024 * 1024,
    MailReadBudget budget = const MailReadBudget(),
  }) => MailBodyDownloadRunner(
    provider: provider,
    cache: cache,
    session: session,
    maxMessages: maxMessages,
    maxRetainedBytes: maxRetainedBytes,
    budget: budget,
  );

  List<MailHeaderRecord> headers([int count = 2]) => [
    for (var index = 1; index <= count; index++) _header(inbox, index),
  ];

  setUp(() {
    account = MailAccountId('a', profile: MailProfileId('p', hostId: 'office'));
    inbox = MailMailboxId('INBOX', account: account);
    session = MailAccountSession(account);
    provider = _Provider(account);
    cache = _Cache(account);
  });

  test('retains exact payloads with canonical IDs and one run lease', () async {
    final input = headers();
    final original = _message(
      input.first.remote,
      body: const MailBody(plainText: 'ä😀', html: '<b>x</b>'),
      attachments: [_attachment(1, 2)],
    );
    provider.responses[input.first.remote] = MailSuccess(original);
    final progress = <MailBodyDownloadProgress>[];
    final report = await runner().run(
      mailbox: inbox,
      headers: input,
      onProgress: progress.add,
    );

    expect(report.status, MailBodyDownloadStatus.completed);
    expect(report.problem, isNull);
    expect(report.mailbox, inbox);
    expect(report.total, 2);
    expect(report.downloaded, 2);
    expect(report.alreadyCached, 0);
    expect(report.processed, 2);
    expect(report.remaining, 0);
    // First: 3 raw + 6 plain UTF-8 + 8 HTML + 2 attachment = 19.
    // Second: 3 raw + 4 plain UTF-8 = 7.
    expect(report.retainedBytes, 26);
    expect(progress.map((value) => value.downloaded), [1, 2]);
    expect(progress.first.retainedBytes, 19);
    expect(progress.first.remaining, 1);
    expect(cache.messages.keys, input.map((header) => header.id));
    final saved = cache.messages[input.first.id]!;
    expect(saved.localId, input.first.id);
    expect(saved.remoteIdentity, input.first.remote);
    expect(identical(saved.raw, original.raw), isTrue);
    expect(identical(saved.body, original.body), isTrue);
    expect(
      identical(saved.attachments.first, original.attachments.first),
      isTrue,
    );
    expect(original.localId, MailMessageId('provider-id'));
    expect(provider.requests, input.map((header) => header.remote));
    expect(provider.otherCalls, 0);
    expect(provider.leases.toSet(), hasLength(1));
    expect(cache.leases, provider.leases);
  });

  test('skips exact complete cache snapshots without provider work', () async {
    final input = headers();
    for (final header in input) {
      cache.messages[header.id] = _message(header.remote, localId: header.id);
    }
    final report = await runner(maxRetainedBytes: 1)
        .run(mailbox: inbox, headers: input);
    expect(report.status, MailBodyDownloadStatus.completed);
    expect(report.alreadyCached, 2);
    expect(report.downloaded, 0);
    expect(report.retainedBytes, 0);
    expect(provider.requests, isEmpty);
    expect(cache.saves, 0);
  });

  test('message allowance pauses and resume skips the saved prefix', () async {
    final input = headers(3);
    final download = runner(maxMessages: 1);
    final first = await download.run(mailbox: inbox, headers: input);
    expect(first.status, MailBodyDownloadStatus.paused);
    expect(first.downloaded, 1);
    expect(first.remaining, 2);
    expect(provider.requests, [input[0].remote]);

    final second = await download.run(mailbox: inbox, headers: input);
    expect(second.status, MailBodyDownloadStatus.paused);
    expect(second.downloaded, 1);
    expect(second.alreadyCached, 1);
    expect(second.remaining, 1);

    final third = await download.run(mailbox: inbox, headers: input);
    expect(third.status, MailBodyDownloadStatus.completed);
    expect(third.downloaded, 1);
    expect(third.alreadyCached, 2);
    expect(provider.requests, input.map((header) => header.remote));
  });

  test(
    'cumulative payload bound pauses before saving an oversized tail',
    () async {
      final input = headers();
      final download = runner(maxRetainedBytes: 10);
      final first = await download.run(mailbox: inbox, headers: input);
      expect(first.status, MailBodyDownloadStatus.paused);
      expect(first.downloaded, 1);
      expect(first.retainedBytes, 7);
      expect(cache.messages.keys, [input.first.id]);

      final second = await download.run(mailbox: inbox, headers: input);
      expect(second.status, MailBodyDownloadStatus.completed);
      expect(second.alreadyCached, 1);
      expect(second.downloaded, 1);
      expect(second.retainedBytes, 7);
      expect(provider.requests, [
        input.first.remote,
        input.last.remote,
        input.last.remote,
      ]);
    },
  );

  test(
    'exact byte boundary saves once and avoids fetching the next body',
    () async {
      final input = headers();
      final report = await runner(maxRetainedBytes: 7)
          .run(mailbox: inbox, headers: input);
      expect(report.status, MailBodyDownloadStatus.paused);
      expect(report.retainedBytes, 7);
      expect(provider.requests, [input.first.remote]);
    },
  );

  test(
    'one message larger than the full byte budget is a quota failure',
    () async {
      final report = await runner(maxRetainedBytes: 6)
          .run(mailbox: inbox, headers: headers(1));
      expect(report.status, MailBodyDownloadStatus.failed);
      expect(report.problem!.code, MailProblemCode.quotaExceeded);
      expect(report.downloaded, 0);
      expect(cache.saves, 0);
    },
  );

  test('freezes the caller selection before awaited work', () async {
    final input = headers();
    final frozenSecond = input.last.remote;
    provider.pending = Completer<MailResult<MailMessage>>();
    final run = runner().run(mailbox: inbox, headers: input);
    await provider.started.future;
    input[1] = _header(inbox, 99);
    provider.pending!.complete(MailSuccess(_message(input.first.remote)));
    final report = await run;
    expect(report.status, MailBodyDownloadStatus.completed);
    expect(provider.requests, [input.first.remote, frozenSecond]);
  });

  test('rejects provider identity substitution before caching', () async {
    final input = headers(1);
    provider.responses[input.first.remote] = MailSuccess(
      _message(_header(inbox, 99).remote),
    );
    final report = await runner().run(mailbox: inbox, headers: input);
    expect(report.problem!.code, MailProblemCode.providerFailure);
    expect(cache.saves, 0);
  });

  test('rejects a provider snapshot without a remote identity', () async {
    final input = headers(1);
    provider.responses[input.first.remote] = MailSuccess(
      MailMessage(raw: MailBytes(Uint8List(3)), envelope: MailEnvelope()),
    );
    final report = await runner().run(mailbox: inbox, headers: input);
    expect(report.problem!.code, MailProblemCode.providerFailure);
    expect(cache.saves, 0);
  });

  for (final wrongPart in ['remote', 'local', 'raw']) {
    test('rejects cached $wrongPart mismatch without fetching', () async {
      final input = headers(1);
      cache.messages[input.first.id] = _message(
        wrongPart == 'remote' ? _header(inbox, 99).remote : input.first.remote,
        localId: wrongPart == 'local' ? MailMessageId('wrong') : input.first.id,
        rawBytes: wrongPart == 'raw' ? 0 : 3,
      );
      final report = await runner().run(mailbox: inbox, headers: input);
      expect(report.problem!.code, MailProblemCode.storageFailure);
      expect(report.alreadyCached, 0);
      expect(provider.requests, isEmpty);
      expect(cache.saves, 0);
    });
  }

  test('pre-cancelled requests access no cache or provider', () async {
    final cancellation = MailCancellationSource()..cancel();
    final report = await runner().run(
      mailbox: inbox,
      headers: headers(),
      cancellation: cancellation.token,
    );
    expect(report.status, MailBodyDownloadStatus.cancelled);
    expect(report.problem!.code, MailProblemCode.cancelled);
    expect(cache.loads, 0);
    expect(provider.requests, isEmpty);
  });

  test('cancel during cache read prevents provider fetch', () async {
    final cancellation = MailCancellationSource();
    cache.afterLoad = cancellation.cancel;
    final report = await runner().run(
      mailbox: inbox,
      headers: headers(),
      cancellation: cancellation.token,
    );
    expect(report.status, MailBodyDownloadStatus.cancelled);
    expect(provider.requests, isEmpty);
    expect(cache.saves, 0);
  });

  test('cancellation during provider fetch rejects its late body', () async {
    final cancellation = MailCancellationSource();
    final input = headers();
    provider.pending = Completer<MailResult<MailMessage>>();
    final run = runner().run(
      mailbox: inbox,
      headers: input,
      cancellation: cancellation.token,
    );
    await provider.started.future;
    cancellation.cancel();
    provider.pending!.complete(MailSuccess(_message(input.first.remote)));
    final report = await run;
    expect(report.status, MailBodyDownloadStatus.cancelled);
    expect(cache.saves, 0);
    expect(provider.requests, [input.first.remote]);
  });

  test('stale session cannot cache a late same-account completion', () async {
    final input = headers();
    provider.pending = Completer<MailResult<MailMessage>>();
    final run = runner().run(mailbox: inbox, headers: input);
    await provider.started.future;
    session.invalidate();
    provider.pending!.complete(MailSuccess(_message(input.first.remote)));
    final report = await run;
    expect(report.status, MailBodyDownloadStatus.cancelled);
    expect(report.problem!.code, MailProblemCode.staleOperation);
    expect(cache.saves, 0);
  });

  test(
    'folder retirement prevents late provider data from reaching cache',
    () async {
      final input = headers();
      var current = true;
      provider.onFetch = () => current = false;
      final report = await runner().run(
        mailbox: inbox,
        headers: input,
        isCurrent: () => current,
      );
      expect(report.status, MailBodyDownloadStatus.cancelled);
      expect(report.problem!.code, MailProblemCode.staleOperation);
      expect(cache.saves, 0);
    },
  );

  test('a true host guard cannot revive the session it invalidated', () async {
    final report = await runner().run(
      mailbox: inbox,
      headers: headers(),
      isCurrent: () {
        session.invalidate();
        return true;
      },
    );
    expect(report.status, MailBodyDownloadStatus.cancelled);
    expect(cache.loads, 0);
    expect(provider.requests, isEmpty);
  });

  test('a throwing host guard is a content-redacted stale result', () async {
    final report = await runner().run(
      mailbox: inbox,
      headers: headers(),
      isCurrent: () => throw StateError('private host state'),
    );
    expect(report.status, MailBodyDownloadStatus.cancelled);
    expect(report.problem!.code, MailProblemCode.staleOperation);
    expect(cache.loads, 0);
  });

  test('provider account changes during a run stop before storage', () async {
    provider.onFetch = () => provider.account = _otherAccount(account);
    final report = await runner().run(mailbox: inbox, headers: headers());
    expect(report.problem!.code, MailProblemCode.staleOperation);
    expect(cache.saves, 0);
  });

  test('cache account changes during a read stop before fetching', () async {
    cache.afterLoad = () => cache.account = _otherAccount(account);
    final report = await runner().run(mailbox: inbox, headers: headers());
    expect(report.problem!.code, MailProblemCode.staleOperation);
    expect(provider.requests, isEmpty);
  });

  test('atomic save lease rejects cancellation before committing', () async {
    final cancellation = MailCancellationSource();
    cache.beforeSave = cancellation.cancel;
    final report = await runner().run(
      mailbox: inbox,
      headers: headers(),
      cancellation: cancellation.token,
    );
    expect(report.status, MailBodyDownloadStatus.cancelled);
    expect(report.downloaded, 0);
    expect(cache.messages, isEmpty);
  });

  test(
    'acknowledged save survives cancellation without late progress',
    () async {
      final cancellation = MailCancellationSource();
      cache.afterSave = cancellation.cancel;
      final progress = <MailBodyDownloadProgress>[];
      final input = headers();
      final report = await runner().run(
        mailbox: inbox,
        headers: input,
        cancellation: cancellation.token,
        onProgress: progress.add,
      );
      expect(report.status, MailBodyDownloadStatus.cancelled);
      expect(report.downloaded, 1);
      expect(report.retainedBytes, 7);
      expect(cache.messages.keys, [input.first.id]);
      expect(progress, isEmpty);
      expect(provider.requests, [input.first.remote]);
    },
  );

  test(
    'observer cancellation stops following fetches but retains the save',
    () async {
      final cancellation = MailCancellationSource();
      final report = await runner().run(
        mailbox: inbox,
        headers: headers(),
        cancellation: cancellation.token,
        onProgress: (_) => cancellation.cancel(),
      );
      expect(report.status, MailBodyDownloadStatus.cancelled);
      expect(report.downloaded, 1);
      expect(provider.requests, hasLength(1));
    },
  );

  test('observer exception does not change storage outcomes', () async {
    final report = await runner().run(
      mailbox: inbox,
      headers: headers(),
      onProgress: (_) => throw StateError('private observer details'),
    );
    expect(report.status, MailBodyDownloadStatus.completed);
    expect(report.downloaded, 2);
    expect(cache.saves, 2);
  });

  for (final code in [
    MailProblemCode.quotaExceeded,
    MailProblemCode.storageFailure,
  ]) {
    test(
      'failed $code save preserves prefix and resumes without refetch',
      () async {
        final input = headers(3);
        cache.failSaveAt = 2;
        cache.saveProblem = MailProblem(code);
        final download = runner();
        final first = await download.run(mailbox: inbox, headers: input);
        expect(first.status, MailBodyDownloadStatus.failed);
        expect(first.problem!.code, code);
        expect(first.downloaded, 1);
        expect(first.retainedBytes, 7);
        expect(cache.messages.keys, [input.first.id]);
        expect(provider.requests, input.take(2).map((header) => header.remote));

        cache.failSaveAt = null;
        final second = await download.run(mailbox: inbox, headers: input);
        expect(second.status, MailBodyDownloadStatus.completed);
        expect(second.alreadyCached, 1);
        expect(second.downloaded, 2);
        expect(
          provider.requests.where((remote) => remote == input.first.remote),
          hasLength(1),
        );
      },
    );
  }

  test(
    'typed provider failure stops later requests and retains retry guidance',
    () async {
      final input = headers(3);
      const problem = MailProblem(
        MailProblemCode.authenticationRequired,
        retryAfter: Duration(seconds: 30),
      );
      provider.responses[input[1].remote] = const MailFailure(problem);
      final report = await runner().run(mailbox: inbox, headers: input);
      expect(report.status, MailBodyDownloadStatus.failed);
      expect(identical(report.problem, problem), isTrue);
      expect(report.downloaded, 1);
      expect(provider.requests, input.take(2).map((header) => header.remote));
    },
  );

  test('cache read failures do not cause a provider fallback', () async {
    cache.loadProblem = const MailProblem(MailProblemCode.unavailable);
    final report = await runner().run(mailbox: inbox, headers: headers());
    expect(report.problem!.code, MailProblemCode.unavailable);
    expect(provider.requests, isEmpty);
  });

  for (final boundary in ['provider', 'cache-read', 'cache-save']) {
    test(
      'raw $boundary exceptions become typed content-free failures',
      () async {
        final exception = StateError('private email content or credential');
        if (boundary == 'provider') provider.exception = exception;
        if (boundary == 'cache-read') cache.loadException = exception;
        if (boundary == 'cache-save') cache.saveException = exception;
        final report = await runner().run(mailbox: inbox, headers: headers());
        expect(report.status, MailBodyDownloadStatus.failed);
        expect(
          report.problem!.code,
          boundary == 'provider'
              ? MailProblemCode.providerFailure
              : MailProblemCode.storageFailure,
        );
        expect(report.downloaded, 0);
        expect(cache.messages, isEmpty);
      },
    );
  }

  test(
    'empty selection completes without cache or provider operations',
    () async {
      final report = await runner().run(mailbox: inbox, headers: const []);
      expect(report.status, MailBodyDownloadStatus.completed);
      expect(report.total, 0);
      expect(report.remaining, 0);
      expect(cache.loads, 0);
      expect(provider.requests, isEmpty);
    },
  );

  for (final invalid in [
    'duplicate-id',
    'duplicate-remote',
    'account',
    'mailbox',
    'generation',
    'provider',
  ]) {
    test('invalid selection $invalid has no cache or provider work', () async {
      final first = headers(1).first;
      final otherBox = MailMailboxId('OTHER', account: account);
      final second = switch (invalid) {
        'duplicate-id' => MailHeaderRecord(
          id: first.id,
          remote: _header(inbox, 2).remote,
          envelope: MailEnvelope(),
        ),
        'duplicate-remote' => MailHeaderRecord(
          id: MailMessageId('another-id'),
          remote: first.remote,
          envelope: MailEnvelope(),
        ),
        'account' => _header(
          MailMailboxId('INBOX', account: _otherAccount(account)),
          2,
        ),
        'mailbox' => _header(otherBox, 2),
        'generation' => _header(inbox, 2, uidValidity: 2),
        _ => MailHeaderRecord(
          id: MailMessageId('other-provider'),
          remote: MailOpaqueIdentity(
            account: account,
            provider: MailProviderKind.gmail,
            value: 'm2',
          ),
          envelope: MailEnvelope(),
        ),
      };
      final report = await runner().run(
        mailbox: inbox,
        headers: [first, second],
      );
      expect(report.problem!.code, MailProblemCode.invalidInput);
      expect(cache.loads, 0);
      expect(provider.requests, isEmpty);
    });
  }

  for (final wrong in ['session', 'provider', 'cache', 'mailbox']) {
    test('initial $wrong account mismatch fails before operations', () async {
      final other = _otherAccount(account);
      final input = headers(1);
      if (wrong == 'session') session = MailAccountSession(other);
      if (wrong == 'provider') provider.account = other;
      if (wrong == 'cache') cache.account = other;
      final report = await runner().run(
        mailbox: wrong == 'mailbox'
            ? MailMailboxId('INBOX', account: other)
            : inbox,
        headers: input,
      );
      expect(report.problem!.code, MailProblemCode.invalidInput);
      expect(cache.loads, 0);
      expect(provider.requests, isEmpty);
    });
  }

  test('disposed session fails before any cache access', () async {
    session.dispose();
    final report = await runner().run(mailbox: inbox, headers: headers());
    expect(report.problem!.code, MailProblemCode.staleOperation);
    expect(cache.loads, 0);
  });

  test('input count over 100 is rejected without partial work', () async {
    final report = await runner().run(mailbox: inbox, headers: headers(101));
    expect(report.problem!.code, MailProblemCode.invalidInput);
    expect(cache.loads, 0);
  });

  test('maximum selection and message bounds complete', () async {
    final report = await runner().run(mailbox: inbox, headers: headers(100));
    expect(report.status, MailBodyDownloadStatus.completed);
    expect(report.downloaded, 100);
    expect(provider.requests, hasLength(100));
  });

  for (final limit in [-1, 0, 101]) {
    test('invalid message budget $limit fails before operations', () async {
      final report = await runner(maxMessages: limit)
          .run(mailbox: inbox, headers: headers());
      expect(report.problem!.code, MailProblemCode.invalidInput);
      expect(cache.loads, 0);
      expect(provider.requests, isEmpty);
    });
  }

  for (final limit in [-1, 0, 256 * 1024 * 1024 + 1]) {
    test(
      'invalid retained-byte budget $limit fails before operations',
      () async {
        final report = await runner(maxRetainedBytes: limit)
            .run(mailbox: inbox, headers: headers());
        expect(report.problem!.code, MailProblemCode.invalidInput);
        expect(cache.loads, 0);
      },
    );
  }

  test('invalid per-message budget fails before operations', () async {
    final report = await runner(budget: const MailReadBudget(maxRawBytes: 0))
        .run(mailbox: inbox, headers: headers());
    expect(report.problem!.code, MailProblemCode.invalidInput);
    expect(cache.loads, 0);
  });

  for (final limit in [
    'raw',
    'body',
    'render',
    'decoded',
    'attachment',
    'count',
  ]) {
    test('provider result must honor actual $limit payload bounds', () async {
      final input = headers(1);
      provider.responses[input.first.remote] = MailSuccess(
        _message(
          input.first.remote,
          body: const MailBody(plainText: 'ä😀'),
          attachments: [_attachment(1, 2), _attachment(2, 2)],
        ),
      );
      final readBudget = switch (limit) {
        'raw' => const MailReadBudget(maxRawBytes: 2),
        'body' => const MailReadBudget(maxBodyBytes: 5),
        'render' => const MailReadBudget(maxRenderTextBytes: 5),
        'decoded' => const MailReadBudget(maxDecodedBytes: 9),
        'attachment' => const MailReadBudget(maxAttachmentBytes: 1),
        _ => const MailReadBudget(maxAttachments: 1),
      };
      final report = await runner(budget: readBudget)
          .run(mailbox: inbox, headers: input);
      expect(report.problem!.code, MailProblemCode.quotaExceeded);
      expect(cache.saves, 0);
      expect(identical(provider.budgets.single, readBudget), isTrue);
    });
  }

  test(
    'one runner refuses overlapping requests until the first finishes',
    () async {
      final input = headers(1);
      final download = runner();
      provider.pending = Completer<MailResult<MailMessage>>();
      final first = download.run(mailbox: inbox, headers: input);
      await provider.started.future;
      final overlapping = await download.run(mailbox: inbox, headers: input);
      expect(overlapping.problem!.code, MailProblemCode.conflict);
      expect(provider.requests, hasLength(1));
      provider.pending!.complete(MailSuccess(_message(input.first.remote)));
      expect((await first).status, MailBodyDownloadStatus.completed);
      final repeated = await download.run(mailbox: inbox, headers: input);
      expect(repeated.status, MailBodyDownloadStatus.completed);
      expect(repeated.alreadyCached, 1);
    },
  );

  for (final kind in [
    MailProviderKind.gmail,
    MailProviderKind.graph,
    MailProviderKind.ews,
  ]) {
    test(
      '$kind opaque identity stays exact while local ID is rebound',
      () async {
        final header = MailHeaderRecord(
          id: MailMessageId('canonical'),
          remote: MailOpaqueIdentity(
            account: account,
            provider: kind,
            value: 'opaque',
          ),
          envelope: MailEnvelope(),
        );
        final report = await runner().run(mailbox: inbox, headers: [header]);
        expect(report.status, MailBodyDownloadStatus.completed);
        expect(cache.messages[header.id]!.remoteIdentity, header.remote);
        expect(cache.messages[header.id]!.localId, header.id);
      },
    );
  }
}

MailAccountId _otherAccount(MailAccountId account) =>
    MailAccountId('other', profile: account.profile);

MailHeaderRecord _header(
  MailMailboxId mailbox,
  int uid, {
  int uidValidity = 1,
}) => MailHeaderRecord(
  id: MailMessageId('canonical-$uid'),
  remote: MailImapIdentity(
    mailbox: mailbox,
    uidValidity: uidValidity,
    uid: uid,
  ),
  envelope: MailEnvelope(subject: 'Fixture $uid'),
);

MailMessage _message(
  MailRemoteIdentity identity, {
  MailMessageId? localId,
  int rawBytes = 3,
  MailBody body = const MailBody(plainText: 'body'),
  List<MailAttachment> attachments = const [],
}) => MailMessage(
  raw: MailBytes(Uint8List(rawBytes)),
  envelope: MailEnvelope(subject: 'Fixture message'),
  body: body,
  attachments: attachments,
  localId: localId ?? MailMessageId('provider-id'),
  remoteIdentity: identity,
);

MailAttachment _attachment(int part, int bytes) => MailAttachment(
  partPath: '$part',
  mediaType: 'application/octet-stream',
  displayName: 'fixture-$part.bin',
  content: MailBytes(Uint8List(bytes)),
);

final class _Provider implements MailProvider {
  _Provider(this.account);

  @override
  MailAccountId account;
  final Map<MailRemoteIdentity, MailResult<MailMessage>> responses = {};
  final List<MailRemoteIdentity> requests = [];
  final List<MailReadBudget> budgets = [];
  final List<MailOperationLease> leases = [];
  final Completer<void> started = Completer<void>();
  Completer<MailResult<MailMessage>>? pending;
  void Function()? onFetch;
  Object? exception;
  int otherCalls = 0;

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    lease.checkCurrent();
    requests.add(identity);
    budgets.add(budget);
    leases.add(lease);
    if (!started.isCompleted) started.complete();
    onFetch?.call();
    if (exception case final error?) throw error;
    // Only the first request is deliberately held; later calls are ordinary.
    if (pending != null && requests.length == 1) return pending!.future;
    return responses[identity] ?? MailSuccess(_message(identity));
  }

  Future<MailResult<T>> _unsupported<T>() async {
    otherCalls++;
    return const MailFailure(MailProblem(MailProblemCode.unsupported));
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(MailOperationLease lease) =>
      _unsupported();

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) => _unsupported();

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) => _unsupported();

  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) => _unsupported();

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) => _unsupported();
}

final class _Cache implements MailBodyDownloadCache {
  _Cache(this.account);

  @override
  MailAccountId account;
  final Map<MailMessageId, MailMessage> messages = {};
  final List<MailOperationLease> leases = [];
  int loads = 0;
  int saves = 0;
  int? failSaveAt;
  MailProblem saveProblem = const MailProblem(MailProblemCode.storageFailure);
  MailProblem? loadProblem;
  Object? loadException;
  Object? saveException;
  void Function()? afterLoad;
  void Function()? beforeSave;
  void Function()? afterSave;

  @override
  Future<MailResult<MailMessage?>> load(MailHeaderRecord header) async {
    loads++;
    if (loadException case final error?) throw error;
    afterLoad?.call();
    if (loadProblem case final problem?) return MailFailure(problem);
    return MailSuccess(messages[header.id]);
  }

  @override
  Future<MailResult<MailUnit>> save(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  }) async {
    saves++;
    leases.add(lease);
    if (saveException case final error?) throw error;
    beforeSave?.call();
    lease.checkCurrent();
    if (saves == failSaveAt) return MailFailure(saveProblem);
    messages[header.id] = message;
    afterSave?.call();
    return const MailSuccess(MailUnit.value);
  }
}
