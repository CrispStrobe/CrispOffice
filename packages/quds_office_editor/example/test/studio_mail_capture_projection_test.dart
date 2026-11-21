import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';

MailAccountId _account(String value) =>
    MailAccountId(value, profile: MailProfileId('capture', hostId: 'test'));

final class _Store extends Fake implements StudioMailMailboxStore {
  @override
  final account = _account('persistent');
  int revision = 0;
  bool fail = false;
  Completer<void>? gate;
  MailCachedMailboxView? saved;

  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) async {
    await gate?.future;
    lease.checkCurrent();
    if (fail) throw StateError('Failed durable save');
    return saved = MailCachedMailboxView(
      mailbox: mailbox,
      revision: ++revision,
      capturedAt: DateTime.utc(2026, 11, 21),
      headers: headers,
      hasMore: hasMore,
    );
  }
}

MailHeaderRecord _header(
  MailProviderKind provider,
  MailAccountId account,
  int uid, {
  int validity = 7,
  String folder = 'inbox',
}) => MailHeaderRecord(
  id: MailMessageId('${account.value}-$uid'),
  remote: provider == MailProviderKind.imap
      ? MailImapIdentity(
          mailbox: MailMailboxId(folder, account: account),
          uidValidity: validity,
          uid: uid,
        )
      : MailOpaqueIdentity(
          account: account,
          provider: provider,
          value: 'provider-$uid',
        ),
  envelope: MailEnvelope(subject: 'Message $uid'),
  flags: uid == 1 ? const MailMessageFlags() : null,
);

MailCachedMailboxView _view(
  MailCachedMailboxView saved, {
  List<MailHeaderRecord>? headers,
  int? revision,
  MailMailbox? mailbox,
}) => MailCachedMailboxView(
  mailbox: mailbox ?? saved.mailbox,
  revision: revision ?? saved.revision,
  capturedAt: saved.capturedAt,
  headers: headers ?? saved.headers,
  hasMore: saved.hasMore,
);

MailHeaderRecord _cachedHeader(
  MailHeaderRecord header, {
  MailMessageId? id,
  MailRemoteIdentity? remote,
  MailMessageFlags? flags,
}) => MailHeaderRecord(
  id: id ?? header.id,
  remote: remote ?? header.remote,
  envelope: header.envelope,
  flags: flags ?? header.flags,
);

void main() {
  for (final provider in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    late _Store store;
    late StudioMailMailboxCapture capture;
    late List<MailHeaderRecord> sources;
    final source = _account('connection');
    final mailbox = MailMailbox(
      id: MailMailboxId('inbox', account: source),
      displayName: 'Inbox',
    );

    setUp(() {
      store = _Store();
      capture = StudioMailMailboxCapture(
        store: store,
        sourceAccount: source,
        provider: provider,
        isCurrent: () => true,
      );
      sources = [_header(provider, source, 1), _header(provider, source, 2)];
    });
    tearDown(() => capture.dispose());

    test(
      '${provider.name} projects flags onto original command identities',
      () async {
        final saved = await capture.saveView(mailbox, sources, hasMore: true);
        final changed = _view(
          saved,
          headers: [
            _cachedHeader(
              saved.headers.last,
              flags: const MailMessageFlags(isRead: true),
            ),
            _cachedHeader(
              saved.headers.first,
              flags: const MailMessageFlags(isFlagged: true),
            ),
          ],
        );
        final projected = capture.projectView(changed);
        expect(
          projected.map((header) => header.id),
          sources.reversed.map((header) => header.id),
        );
        expect(
          projected.map((header) => header.remote),
          sources.reversed.map((header) => header.remote),
        );
        expect(projected.first.flags!.isRead, isTrue);
        expect(projected.last.flags!.isFlagged, isTrue);
        expect(saved.headers.first.id, isNot(sources.first.id));
        expect(saved.headers.first.remote.account, store.account);
        expect(projected.first.remote.account, source);
        expect(() => projected.clear(), throwsUnsupportedError);
      },
    );

    test(
      '${provider.name} requires exact saved membership and valid revision',
      () async {
        final saved = await capture.saveView(mailbox, sources, hasMore: true);
        final invalid = [
          _view(saved, headers: [saved.headers.first]),
          _view(saved, headers: [saved.headers.first, saved.headers.first]),
          _view(saved, headers: [...saved.headers, saved.headers.first]),
          _view(
            saved,
            headers: [
              _cachedHeader(
                saved.headers.first,
                id: MailMessageId('unobserved'),
              ),
              saved.headers.last,
            ],
          ),
          _view(
            saved,
            headers: [
              _cachedHeader(saved.headers.first, remote: sources.first.remote),
              saved.headers.last,
            ],
          ),
          _view(saved, revision: 0),
          _view(saved, revision: 9007199254740992),
          _view(
            saved,
            mailbox: MailMailbox(
              id: MailMailboxId('other-folder', account: store.account),
              displayName: 'Other',
            ),
          ),
        ];
        for (final view in invalid) {
          expect(
            () => capture.projectView(view),
            throwsA(isA<StudioMailMailboxStoreException>()),
          );
        }
        expect(capture.projectView(saved).length, 2);
        capture.projectView(_view(saved, revision: saved.revision + 1));
        expect(
          () => capture.projectView(saved),
          throwsA(isA<StudioMailMailboxStoreException>()),
        );
      },
    );

    test(
      '${provider.name} invalidated and failed saves cannot reuse old bindings',
      () async {
        final saved = await capture.saveView(mailbox, sources, hasMore: false);
        capture.invalidateView();
        expect(
          () => capture.projectView(saved),
          throwsA(isA<StudioMailMailboxStoreException>()),
        );
        await capture.saveView(mailbox, sources, hasMore: false);
        store.fail = true;
        await expectLater(
          capture.saveView(mailbox, sources, hasMore: false),
          throwsStateError,
        );
        expect(
          () => capture.projectView(saved),
          throwsA(isA<StudioMailMailboxStoreException>()),
        );
      },
    );

    test(
      '${provider.name} an invalidated pending save never authorizes a window',
      () async {
        final gate = store.gate = Completer<void>();
        final saving = capture.saveView(mailbox, sources, hasMore: false);
        final rejected = expectLater(
          saving,
          throwsA(isA<StudioMailMailboxStoreException>()),
        );
        capture.invalidateView();
        gate.complete();
        await rejected;
        expect(
          () => capture.projectView(store.saved!),
          throwsA(isA<StudioMailMailboxStoreException>()),
        );
      },
    );

    test(
      '${provider.name} reconnect binds only fresh source identities',
      () async {
        final old = await capture.saveView(mailbox, sources, hasMore: false);
        capture.dispose();
        final nextAccount = _account('reconnected');
        capture = StudioMailMailboxCapture(
          store: store,
          sourceAccount: nextAccount,
          provider: provider,
          isCurrent: () => true,
        );
        expect(
          () => capture.projectView(old),
          throwsA(isA<StudioMailMailboxStoreException>()),
        );
        final nextSources = [
          _header(provider, nextAccount, 1),
          _header(provider, nextAccount, 2),
        ];
        final saved = await capture.saveView(
          MailMailbox(
            id: MailMailboxId('inbox', account: nextAccount),
            displayName: 'Inbox',
          ),
          nextSources,
          hasMore: false,
        );
        expect(
          saved.headers.map((header) => header.id),
          old.headers.map((header) => header.id),
        );
        expect(
          () => capture.projectView(old),
          throwsA(isA<StudioMailMailboxStoreException>()),
        );
        expect(
          capture.projectView(saved).map((header) => header.id),
          nextSources.map((header) => header.id),
        );
        expect(capture.projectView(saved).first.remote.account, nextAccount);
      },
    );
  }

  test(
    'IMAP capture refuses mixed mailbox generations before persistence',
    () async {
      final store = _Store();
      final source = _account('imap');
      final capture = StudioMailMailboxCapture(
        store: store,
        sourceAccount: source,
        provider: MailProviderKind.imap,
        isCurrent: () => true,
      );
      addTearDown(capture.dispose);
      final mailbox = MailMailbox(
        id: MailMailboxId('inbox', account: source),
        displayName: 'Inbox',
      );
      for (final second in [
        _header(MailProviderKind.imap, source, 2, validity: 8),
        _header(MailProviderKind.imap, source, 2, folder: 'other'),
      ]) {
        await expectLater(
          capture.saveView(mailbox, [
            _header(MailProviderKind.imap, source, 1),
            second,
          ], hasMore: false),
          throwsA(isA<StudioMailMailboxStoreException>()),
        );
      }
      expect(store.revision, 0);
    },
  );
}
