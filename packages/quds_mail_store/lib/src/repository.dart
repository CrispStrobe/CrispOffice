import 'dart:async';

import 'package:drift/drift.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'codec.dart';
import 'errors.dart';
import 'flag_journal_models.dart';
import 'models.dart';
import 'schema/database.dart';

part 'search_journal.dart';
part 'local_accounts.dart';
part 'mailbox_views.dart';
part 'sync_mailboxes.dart';
part 'cached_header_search.dart';
part 'saved_header_searches.dart';
part 'flag_journal.dart';
part 'flag_reconciliation.dart';

/// One profile in one database, with native/browser setup in separate entries.
///
/// An injected executor must have exclusive ownership for the lifetime of this
/// repository. The supplied platform openers enforce that ownership. Ordinary
/// SQLite stores are not encrypted; the host owns the app container and vault.
final class SqliteMailRepository implements MailRepository {
  SqliteMailRepository._(this._db, this.profile, this.limits, this._clock);

  final MailStoreDatabase _db;
  @override
  final MailProfileId profile;
  final MailStoreLimits limits;
  final DateTime Function() _clock;
  final Map<(String, String), String> _interrupted = {};
  final Object _flagJournalOwner = Object();
  final Object _cachedSearchOwner = Object();
  Object _cachedSearchRevision = Object();
  bool _closed = false;

  static Future<MailResult<SqliteMailRepository>> open({
    required QueryExecutor executor,
    required MailProfileId profile,
    MailStoreLimits limits = const MailStoreLimits(),
    DateTime Function()? clock,
    MailStoreFaultInjector? faultInjector,
  }) async {
    final database = MailStoreDatabase(executor, faultInjector: faultInjector);
    final repository = SqliteMailRepository._(
      database,
      profile,
      limits,
      clock ?? DateTime.now,
    );
    try {
      if (!limits.isValid) _fail(MailProblemCode.invalidInput);
      repository._id(profile.hostId);
      repository._id(profile.value);
      // Finish migrations before the profile transaction. Otherwise a failed
      // schema open can be obscured by an outer transaction rollback error.
      await database.customSelect('SELECT 1 AS ready').getSingle();
      await database.transaction(() async {
        final rows = await repository._rows('SELECT * FROM store_profile');
        if (rows.isEmpty) {
          await database.customStatement(
            'INSERT INTO store_profile(singleton,host_id,profile_id) VALUES(1,?,?)',
            [profile.hostId, profile.value],
          );
        } else {
          final row = rows.single;
          if (row.read<String>('host_id') != profile.hostId ||
              row.read<String>('profile_id') != profile.value) {
            _fail(MailProblemCode.permissionDenied);
          }
          // A retired profile opens only to read/acknowledge durable vault
          // cleanup intents. Its account markers and createAccount guard
          // prevent any content writes or accidental identity reuse.
        }
        // Recovery candidates are captured at open. A later call must never
        // relabel an attempt started by this live owner as interrupted.
        for (final row in await repository._rows(
          "SELECT account,id,attempt_id FROM outbox WHERE state='submitting'",
        )) {
          repository._interrupted[(
            row.read<String>('account'),
            row.read<String>('id'),
          )] = row.read<String>(
            'attempt_id',
          );
        }
        await database.customStatement(
          "UPDATE pending_operations SET state='reconcile',revision=revision+1 "
          "WHERE state='applying'",
        );
        await repository._recoverFlagBatches();
      });
      return MailSuccess(repository);
    } on Object catch (error) {
      try {
        await database.close();
      } on Object {
        // Preserve the original typed failure without emitting database text.
      }
      return MailFailure(mailStoreProblem(error));
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _db.close();
  }

  static Never _fail(MailProblemCode code) =>
      throw MailStoreStorageException(code);

  Future<MailResult<T>> _run<T>(Future<T> Function() body) async {
    if (_closed) {
      return const MailFailure(MailProblem(MailProblemCode.unavailable));
    }
    try {
      return MailSuccess(await body());
    } on Object catch (error) {
      return MailFailure(mailStoreProblem(error));
    }
  }

  Future<MailResult<T>> _write<T>(Future<T> Function() body) => _run(
    () => _commit(() async {
      final value = await body();
      await _db.fault(MailStoreCheckpoint.beforeCommit);
      return value;
    }),
  );

  Future<T> _commit<T>(Future<T> Function() body) async {
    final value = await _db.transaction(body);
    // Drift also invalidates query streams after a rollback. Emit our domain
    // notification only after the transaction has successfully committed.
    _notify();
    return value;
  }

  Future<List<QueryRow>> _rows(
    String sql, [
    List<Object?> arguments = const [],
  ]) => _db
      .customSelect(
        sql,
        variables: [
          for (final value in arguments)
            switch (value) {
              final String v => Variable<String>(v),
              final int v => Variable<int>(v),
              final double v => Variable<double>(v),
              final Uint8List v => Variable<Uint8List>(v),
              null => const Variable<String>(null),
              _ => throw const MailStoreStorageException(
                MailProblemCode.invalidInput,
              ),
            },
        ],
      )
      .get();

  void _scope(MailAccountId account) {
    if (account.profile != profile) _fail(MailProblemCode.permissionDenied);
    _id(account.value);
  }

  String _remoteKey(MailRemoteIdentity identity) {
    _scope(identity.account);
    switch (identity) {
      case MailImapIdentity(:final mailbox):
        _id(mailbox.value);
      case MailOpaqueIdentity(:final value):
        _id(value);
    }
    return MailStoreCodec.encodeRemote(identity);
  }

  void _id(String value) {
    if (value.isEmpty ||
        value.length > 1024 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      _fail(MailProblemCode.invalidInput);
    }
  }

  Future<QueryRow> _account(
    MailAccountId account, {
    bool active = false,
  }) async {
    _scope(account);
    final rows = await _rows('SELECT * FROM accounts WHERE id=?', [
      account.value,
    ]);
    if (rows.isEmpty || rows.single.read<String>('state') == 'removed') {
      _fail(MailProblemCode.unavailable);
    }
    if (active && rows.single.read<String>('state') != 'active') {
      _fail(MailProblemCode.authenticationRequired);
    }
    return rows.single;
  }

  void _notify() {
    _cachedSearchRevision = Object();
    _db.notifyUpdates({const TableUpdate('mail_domain')});
  }

  /// Registration is explicit. Removed IDs are permanently retired, preventing
  /// stale callbacks from attaching to a newly created account with the same ID.
  Future<MailResult<MailUnit>> createAccount(
    MailStoreAccount account,
  ) => _write(() async {
    _scope(account.id);
    _id(account.id.value);
    if (account.state != MailStoredAccountState.active ||
        account.displayName.length > 1024 ||
        (account.credentialReference?.length ?? 0) > 1024) {
      _fail(MailProblemCode.invalidInput);
    }
    if (account.credentialReference case final reference?) _id(reference);
    final marker = (await _rows('SELECT removed FROM store_profile')).single;
    if (marker.read<int>('removed') != 0) _fail(MailProblemCode.unavailable);
    await _db.customStatement(
      'INSERT INTO accounts(id,provider,display_name,credential_ref,state) VALUES(?,?,?,?,?)',
      [
        account.id.value,
        account.provider.name,
        account.displayName,
        account.credentialReference,
        'active',
      ],
    );
    await _quota(account.id);
    return MailUnit.value;
  });

  Future<MailResult<List<MailStoreAccount>>> listAccounts() => _run(
    () async => [
      for (final row in await _rows(
        "SELECT * FROM accounts WHERE state!='removed' ORDER BY id",
      ))
        MailStoreAccount(
          id: MailAccountId(row.read<String>('id'), profile: profile),
          provider: MailProviderKind.values.byName(
            row.read<String>('provider'),
          ),
          displayName: row.read<String>('display_name'),
          credentialReference: row.readNullable<String>('credential_ref'),
          state: MailStoredAccountState.values.byName(
            row.read<String>('state'),
          ),
        ),
    ],
  );

  Future<MailResult<MailUnit>> saveMailbox(
    MailMailbox mailbox,
  ) => _write(() async {
    await _account(mailbox.id.account);
    _id(mailbox.id.value);
    if (mailbox.displayName.length > 4096) _fail(MailProblemCode.invalidInput);
    await _db.customStatement(
      'INSERT INTO mailboxes(account,id,display_name,is_label) VALUES(?,?,?,?) '
      'ON CONFLICT(account,id) DO UPDATE SET display_name=excluded.display_name,is_label=excluded.is_label',
      [
        mailbox.id.account.value,
        mailbox.id.value,
        mailbox.displayName,
        mailbox.isLabel ? 1 : 0,
      ],
    );
    await _quota(mailbox.id.account);
    return MailUnit.value;
  });

  Future<MailCursor?> _cursor(MailMailboxId mailbox) async {
    final rows = await _rows(
      'SELECT cursor FROM cursors WHERE account=? AND mailbox=?',
      [mailbox.account.value, mailbox.value],
    );
    return rows.isEmpty
        ? null
        : MailCursor(
            mailbox: mailbox,
            value: rows.single.read<String>('cursor'),
          );
  }

  @override
  Future<MailResult<MailCursor?>> readCursor(MailMailboxId mailbox) =>
      _run(() async {
        await _account(mailbox.account);
        return _cursor(mailbox);
      });

  @override
  Future<MailResult<MailUnit>> commitSyncPage(
    MailSyncPage page, {
    required MailCursor? expectedCursor,
    required MailOperationLease lease,
  }) => _run(
    () => _commit(() async {
      final account = page.mailbox.account;
      _id(page.mailbox.value);
      final row = await _account(account, active: true);
      lease.checkCurrent();
      if (lease.account != account ||
          (expectedCursor != null && expectedCursor.mailbox != page.mailbox) ||
          page.upserts.length + page.tombstones.length > limits.maxPageSize ||
          page.next.value.length > 16384) {
        _fail(MailProblemCode.invalidInput);
      }
      final current = await _cursor(page.mailbox);
      if (current?.value != expectedCursor?.value ||
          (current == null) != (expectedCursor == null)) {
        _fail(MailProblemCode.conflict);
      }
      final provider = row.read<String>('provider');
      if (page.imapRange != null && provider != MailProviderKind.imap.name) {
        _fail(MailProblemCode.invalidInput);
      }
      final remotes = <String>{};
      final ids = <String>{};
      var metadataWork = 0;
      for (final header in page.upserts) {
        _id(header.id.value);
        if (header.remote.provider.name != provider ||
            !ids.add(header.id.value) ||
            !remotes.add(_remoteKey(header.remote))) {
          _fail(MailProblemCode.invalidInput);
        }
        metadataWork += _envelopeUnits(header.envelope);
      }
      for (final identity in page.tombstones) {
        if (identity.provider.name != provider ||
            !remotes.add(_remoteKey(identity))) {
          _fail(MailProblemCode.invalidInput);
        }
      }
      if (metadataWork > limits.maxMetadataCodeUnits) {
        _fail(MailProblemCode.quotaExceeded);
      }
      final absent = <(String, String)>[];
      if (page.imapRange case final range? when !page.resetRequired) {
        // Scan stored identities, never the numeric UID space. This preflight
        // also refuses a reopened mailbox exceeding its configured work bound.
        final stored = await _rows(
          'SELECT m.id,m.remote FROM messages m JOIN memberships s '
          'ON s.account=m.account AND s.message=m.id '
          'WHERE s.account=? AND s.mailbox=? LIMIT ?',
          [account.value, page.mailbox.value, limits.maxMessagesPerAccount + 1],
        );
        if (stored.length > limits.maxMessagesPerAccount) {
          _fail(MailProblemCode.quotaExceeded);
        }
        for (final old in stored) {
          final remote = old.read<String>('remote');
          final identity = MailStoreCodec.decodeRemote(
            remote,
            account: account,
          );
          if (identity is MailImapIdentity &&
              identity.mailbox == range.mailbox &&
              identity.uidValidity == range.uidValidity &&
              identity.uid >= range.firstUid &&
              identity.uid <= range.lastUid &&
              !remotes.contains(remote)) {
            // Explicit tombstones are handled once by the ordinary loop below.
            absent.add((old.read<String>('id'), remote));
          }
        }
      }
      await _db.customStatement(
        'INSERT INTO mailboxes(account,id,display_name) VALUES(?,?,?) ON CONFLICT DO NOTHING',
        [account.value, page.mailbox.value, page.mailbox.value],
      );
      if (page.resetRequired) {
        for (final old in await _rows(
          'SELECT m.remote FROM messages m JOIN memberships s ON s.account=m.account AND s.message=m.id '
          'WHERE s.account=? AND s.mailbox=?',
          [account.value, page.mailbox.value],
        )) {
          await _recordTombstone(
            account,
            page.mailbox,
            old.read<String>('remote'),
          );
        }
        await _db.customStatement(
          'DELETE FROM memberships WHERE account=? AND mailbox=?',
          [account.value, page.mailbox.value],
        );
      }
      for (final header in page.upserts) {
        final remote = _remoteKey(header.remote);
        final existing = await _rows(
          'SELECT id,remote FROM messages WHERE account=? AND (id=? OR remote=?)',
          [account.value, header.id.value, remote],
        );
        if (existing.any(
          (v) =>
              v.read<String>('id') != header.id.value ||
              v.read<String>('remote') != remote,
        )) {
          _fail(MailProblemCode.conflict);
        }
        await _db.customStatement(
          'INSERT INTO messages(account,id,remote,envelope,flags) VALUES(?,?,?,?,?) '
          'ON CONFLICT(account,id) DO UPDATE SET envelope=excluded.envelope,'
          'flags=coalesce(excluded.flags,messages.flags)',
          [
            account.value,
            header.id.value,
            remote,
            MailStoreCodec.encodeEnvelope(header.envelope),
            MailStoreCodec.encodeFlags(header.flags),
          ],
        );
        await _db.customStatement(
          'INSERT INTO memberships(account,mailbox,message) VALUES(?,?,?) ON CONFLICT DO NOTHING',
          [account.value, page.mailbox.value, header.id.value],
        );
        await _db.customStatement(
          'DELETE FROM tombstones WHERE account=? AND mailbox=? AND remote=?',
          [account.value, page.mailbox.value, remote],
        );
        await _index(
          account,
          header.id,
          header.envelope,
          await _cachedPlain(account, header.id),
        );
      }
      for (final identity in page.tombstones) {
        final remote = _remoteKey(identity);
        await _recordTombstone(account, page.mailbox, remote);
        await _db.customStatement(
          'DELETE FROM memberships WHERE account=? AND mailbox=? AND message IN '
          '(SELECT id FROM messages WHERE account=? AND remote=?)',
          [account.value, page.mailbox.value, account.value, remote],
        );
      }
      for (final (id, remote) in absent) {
        await _recordTombstone(account, page.mailbox, remote);
        await _db.customStatement(
          'DELETE FROM memberships WHERE account=? AND mailbox=? AND message=?',
          [account.value, page.mailbox.value, id],
        );
      }
      await _db.fault(MailStoreCheckpoint.afterSyncRecords);
      await _pruneUnreferencedMessages(account);
      await _db.fault(MailStoreCheckpoint.beforeSyncCursor);
      lease.checkCurrent();
      await _db.customStatement(
        'INSERT INTO cursors(account,mailbox,cursor) VALUES(?,?,?) '
        'ON CONFLICT(account,mailbox) DO UPDATE SET cursor=excluded.cursor',
        [account.value, page.mailbox.value, page.next.value],
      );
      await _saveSyncCheckpoint(page);
      await _quota(account);
      await _db.fault(MailStoreCheckpoint.beforeCommit);
      lease.checkCurrent();
      return MailUnit.value;
    }),
  );

  Future<void> _recordTombstone(
    MailAccountId account,
    MailMailboxId mailbox,
    String remote,
  ) async {
    await _db.customStatement(
      'INSERT INTO tombstones(account,mailbox,remote,observed_at) VALUES(?,?,?,?) '
      'ON CONFLICT(account,mailbox,remote) DO UPDATE SET observed_at=excluded.observed_at',
      [
        account.value,
        mailbox.value,
        remote,
        _clock().toUtc().millisecondsSinceEpoch,
      ],
    );
    await _db.customStatement(
      "UPDATE pending_operations SET state='reconcile',revision=revision+1,updated_at=? "
      "WHERE account=? AND remote=? AND state IN ('queued','applying')",
      [_clock().toUtc().millisecondsSinceEpoch, account.value, remote],
    );
  }

  Future<void> _pruneUnreferencedMessages(MailAccountId account) async {
    for (final row in await _rows(
      'SELECT m.id FROM messages m WHERE m.account=? AND NOT EXISTS '
      '(SELECT 1 FROM memberships s WHERE s.account=m.account AND s.message=m.id) '
      'AND NOT EXISTS (SELECT 1 FROM mailbox_view_members v '
      'WHERE v.account=m.account AND v.message=m.id) '
      "AND NOT EXISTS (SELECT 1 FROM pending_operations p WHERE p.account=m.account AND p.remote=m.remote "
      "AND p.state IN ('queued','applying','reconcile'))",
      [account.value],
    )) {
      final id = row.read<String>('id');
      await _db.customStatement(
        'DELETE FROM mail_fts WHERE account=? AND message=?',
        [account.value, id],
      );
      await _db.customStatement(
        "DELETE FROM blob_refs WHERE account=? AND owner_kind='cache' AND owner_id=?",
        [account.value, id],
      );
      await _db.customStatement(
        'DELETE FROM messages WHERE account=? AND id=?',
        [account.value, id],
      );
    }
    await _collectBlobs(account);
  }

  MailHeaderRecord _header(QueryRow row, MailAccountId account) =>
      MailHeaderRecord(
        id: MailMessageId(row.read<String>('id')),
        remote: MailStoreCodec.decodeRemote(
          row.read<String>('remote'),
          account: account,
        ),
        envelope: MailStoreCodec.decodeEnvelope(row.read<String>('envelope')),
        flags: MailStoreCodec.decodeFlags(row.readNullable<int>('flags')),
      );

  Future<MailResult<List<MailHeaderRecord>>> listHeaders(
    MailMailboxId mailbox, {
    int limit = 100,
    int offset = 0,
  }) => _run(() async {
    await _account(mailbox.account);
    if (limit < 1 ||
        limit > limits.maxPageSize ||
        offset < 0 ||
        offset > limits.maxMessagesPerAccount) {
      _fail(MailProblemCode.invalidInput);
    }
    return List.unmodifiable([
      for (final row in await _rows(
        'SELECT m.* FROM messages m JOIN memberships s ON s.account=m.account AND s.message=m.id '
        'WHERE s.account=? AND s.mailbox=? ORDER BY m.id LIMIT ? OFFSET ?',
        [mailbox.account.value, mailbox.value, limit, offset],
      ))
        _header(row, mailbox.account),
    ]);
  });

  /// Bounded first page. Use listHeaders for subsequent pages.
  @override
  Stream<MailResult<List<MailHeaderRecord>>> watchHeaders(
    MailMailboxId mailbox,
  ) => Stream.multi((events) {
    var cancelled = false;
    var loading = false;
    var dirty = true;
    Future<void> refresh() async {
      dirty = true;
      if (loading || cancelled) return;
      loading = true;
      while (dirty && !cancelled) {
        dirty = false;
        final value = await listHeaders(mailbox);
        if (!cancelled) events.add(value);
      }
      loading = false;
    }

    final subscription = _db
        .tableUpdates(const TableUpdateQuery.onTableName('mail_domain'))
        .listen(
          (_) => unawaited(refresh()),
          onDone: events.close,
          onError: (Object error) =>
              events.add(MailFailure(mailStoreProblem(error))),
        );
    events.onCancel = () async {
      cancelled = true;
      await subscription.cancel();
    };
    unawaited(refresh());
  });

  int _envelopeUnits(MailEnvelope envelope) {
    var result =
        envelope.subject.length +
        (envelope.messageId?.length ?? 0) +
        (envelope.inReplyTo?.length ?? 0);
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
        result += address.address.length + (address.displayName?.length ?? 0);
      }
    }
    if (addresses > 512 || envelope.references.length > 512) {
      _fail(MailProblemCode.quotaExceeded);
    }
    for (final reference in envelope.references) {
      result += reference.length;
    }
    return result;
  }

  void _draftBudget(MailDraft draft) {
    _id(draft.id);
    var units =
        _envelopeUnits(draft.envelope) +
        (draft.body.plainText?.length ?? 0) +
        (draft.body.html?.length ?? 0) +
        (draft.body.plainPartPath?.length ?? 0) +
        (draft.body.htmlPartPath?.length ?? 0) +
        (draft.editorState?.to.length ?? 0) +
        (draft.editorState?.cc.length ?? 0) +
        (draft.editorState?.bcc.length ?? 0);
    if (draft.attachments.length > 128) _fail(MailProblemCode.quotaExceeded);
    var bytes = 0;
    final paths = <String>{};
    for (final attachment in draft.attachments) {
      _id(attachment.partPath);
      if (!paths.add(attachment.partPath) ||
          (attachment.declaredSize ?? 0) < 0) {
        _fail(MailProblemCode.invalidInput);
      }
      units +=
          attachment.displayName.length +
          attachment.mediaType.length +
          attachment.partPath.length +
          (attachment.contentId?.length ?? 0);
      bytes += attachment.observedSize;
      if (attachment.observedSize > limits.maxBlobBytes) {
        _fail(MailProblemCode.quotaExceeded);
      }
    }
    if (units > limits.maxMetadataCodeUnits ||
        bytes > limits.maxTransactionBlobBytes) {
      _fail(MailProblemCode.quotaExceeded);
    }
  }

  Future<void> _storePayload(
    MailAccountId account,
    String kind,
    String id,
    MailStorePayload payload,
  ) async {
    if (payload.data.length > limits.maxMetadataCodeUnits * 6) {
      _fail(MailProblemCode.quotaExceeded);
    }
    var total = 0;
    for (final entry in payload.blobs.entries) {
      total += entry.value.length;
      if (entry.key != entry.value.sha256 ||
          entry.value.length > limits.maxBlobBytes ||
          total > limits.maxTransactionBlobBytes) {
        _fail(MailProblemCode.quotaExceeded);
      }
      await _db.customStatement(
        'INSERT INTO blobs(account,hash,data,size) VALUES(?,?,?,?) ON CONFLICT DO NOTHING',
        [account.value, entry.key, entry.value.bytes, entry.value.length],
      );
      // Verify an existing content-addressed blob before referring to it.
      final existing = await _rows(
        'SELECT data,size FROM blobs WHERE account=? AND hash=?',
        [account.value, entry.key],
      );
      final bytes = existing.single.read<Uint8List>('data');
      if (existing.single.read<int>('size') != entry.value.length ||
          MailBytes(bytes).sha256 != entry.key) {
        _fail(MailProblemCode.storageFailure);
      }
    }
    await _db.customStatement(
      'DELETE FROM blob_refs WHERE account=? AND owner_kind=? AND owner_id=?',
      [account.value, kind, id],
    );
    for (final hash in payload.blobs.keys) {
      await _db.customStatement(
        'INSERT INTO blob_refs(account,owner_kind,owner_id,hash) VALUES(?,?,?,?)',
        [account.value, kind, id, hash],
      );
    }
  }

  Future<Map<String, MailBytes>> _blobs(
    MailAccountId account,
    String kind,
    String id,
  ) async {
    // Check metadata before SQLite transfers/copies any potentially large BLOB.
    final sizes = await _rows(
      'SELECT b.hash,b.size,length(b.data) AS actual FROM blobs b '
      'JOIN blob_refs r ON r.account=b.account AND r.hash=b.hash '
      'WHERE r.account=? AND r.owner_kind=? AND r.owner_id=?',
      [account.value, kind, id],
    );
    var total = 0;
    if (sizes.length > 129) _fail(MailProblemCode.quotaExceeded);
    for (final row in sizes) {
      final size = row.read<int>('actual');
      if (size != row.read<int>('size') ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(row.read<String>('hash'))) {
        _fail(MailProblemCode.storageFailure);
      }
      total += size;
      if (size > limits.maxBlobBytes ||
          total > limits.maxTransactionBlobBytes) {
        _fail(MailProblemCode.quotaExceeded);
      }
    }
    final blobs = <String, MailBytes>{};
    for (final row in await _rows(
      'SELECT b.hash,b.data,b.size FROM blobs b JOIN blob_refs r ON r.account=b.account AND r.hash=b.hash '
      'WHERE r.account=? AND r.owner_kind=? AND r.owner_id=?',
      [account.value, kind, id],
    )) {
      final bytes = MailBytes(row.read<Uint8List>('data'));
      final hash = row.read<String>('hash');
      if (bytes.sha256 != hash || bytes.length != row.read<int>('size')) {
        _fail(MailProblemCode.storageFailure);
      }
      blobs[hash] = bytes;
    }
    return blobs;
  }

  Future<void> _collectBlobs(MailAccountId account) => _db.customStatement(
    'DELETE FROM blobs WHERE account=? AND NOT EXISTS '
    '(SELECT 1 FROM blob_refs r WHERE r.account=blobs.account AND r.hash=blobs.hash)',
    [account.value],
  );

  Future<void> _quota(MailAccountId account) async {
    // Logical stored bytes include identity, cursor, tombstone, pending-operation
    // and reference metadata, not only visible message bodies. Per-row allowance
    // bounds empty/tiny journal rows as well. SQLite page/index overhead remains
    // subject to the platform's physical quota and explicit FULL failures.
    var bytes = 0;
    for (final (table, columns) in <(String, List<String>)>[
      (
        'accounts',
        ['id', 'provider', 'display_name', 'credential_ref', 'state'],
      ),
      ('mailboxes', ['id', 'display_name']),
      ('messages', ['id', 'remote', 'envelope', 'flags']),
      ('memberships', ['mailbox', 'message']),
      (
        'mailbox_views',
        ['mailbox', 'revision', 'captured_at', 'header_count', 'has_more'],
      ),
      ('mailbox_view_members', ['mailbox', 'position', 'message']),
      ('mailbox_sync_state', ['mailbox', 'revision', 'updated_at', 'has_more']),
      ('cursors', ['mailbox', 'cursor']),
      ('tombstones', ['mailbox', 'remote']),
      ('blobs', ['hash', 'data']),
      ('blob_refs', ['owner_kind', 'owner_id', 'hash']),
      ('cached_messages', ['message', 'raw_hash', 'data']),
      ('drafts', ['id', 'data']),
      ('outbox', ['id', 'state', 'attempt_id', 'data']),
      ('outbox_attempts', ['outbox', 'attempt_id']),
      ('pending_operations', ['id', 'remote', 'kind', 'argument', 'state']),
      // Reserve fixed typed outcome metadata before dispatch, so recording a
      // reply does not need new logical-byte admission after the remote write.
      ('flag_batches', ['id', 'mailbox', 'provider', 'action']),
      ('flag_batch_items', ['batch', 'remote', 'subject']),
      ('flag_item_resolutions', ['batch', 'position', 'kind', 'checked_at']),
      ('credential_cleanup', ['reference']),
      ('mail_fts', ['message', 'content']),
      ('index_state', ['message']),
    ]) {
      final expression = [
        table.startsWith('flag_') ? '256' : '64',
        for (final column in columns)
          'coalesce(length(CAST($column AS BLOB)),0)',
      ].join('+');
      final key = table == 'accounts' ? 'id' : 'account';
      bytes += (await _rows(
        'SELECT coalesce(sum($expression),0) AS n FROM $table WHERE $key=?',
        [account.value],
      )).single.read<int>('n');
      if (bytes > limits.maxAccountBytes) _fail(MailProblemCode.quotaExceeded);
    }
    final count = (await _rows(
      'SELECT count(*) AS n FROM messages WHERE account=?',
      [account.value],
    )).single.read<int>('n');
    if (count > limits.maxMessagesPerAccount) {
      _fail(MailProblemCode.quotaExceeded);
    }
  }

  @override
  Future<MailResult<MailUnit>> saveDraft(
    MailDraft draft, {
    required int? expectedRevision,
    int? maxActiveDrafts,
  }) => _write(() async {
    await _account(draft.account);
    _draftBudget(draft);
    if (maxActiveDrafts != null &&
        (maxActiveDrafts < 1 || maxActiveDrafts > 1000)) {
      _fail(MailProblemCode.invalidInput);
    }
    final existing = await _rows(
      'SELECT revision,data FROM drafts WHERE account=? AND id=?',
      [draft.account.value, draft.id],
    );
    final revision = existing.isEmpty
        ? null
        : existing.single.read<int>('revision');
    if (revision != expectedRevision ||
        (revision != null && draft.revision != revision + 1)) {
      _fail(MailProblemCode.conflict);
    }
    if (maxActiveDrafts != null && draft.editorState?.isCleared != true) {
      final previous = existing.isEmpty
          ? null
          : MailStoreCodec.decodeDraftSummary(
              existing.single.read<String>('data'),
              account: draft.account,
              id: draft.id,
              revision: revision!,
            );
      if (previous == null || previous.editorState?.isCleared == true) {
        final count = (await _rows(
          'SELECT count(*) AS n FROM drafts WHERE account=? AND data<>?',
          [draft.account.value, _clearedDraftData(draft.account)],
        )).single.read<int>('n');
        if (count >= maxActiveDrafts) _fail(MailProblemCode.quotaExceeded);
      }
    }
    final payload = MailStoreCodec.encodeDraft(draft);
    await _storePayload(draft.account, 'draft', draft.id, payload);
    await _db.fault(MailStoreCheckpoint.afterDraftBlobs);
    await _db.customStatement(
      'INSERT INTO drafts(account,id,revision,data) VALUES(?,?,?,?) '
      'ON CONFLICT(account,id) DO UPDATE SET revision=excluded.revision,data=excluded.data',
      [draft.account.value, draft.id, draft.revision, payload.data],
    );
    await _collectBlobs(draft.account);
    await _quota(draft.account);
    return MailUnit.value;
  });

  // A normal tombstone has exactly this canonical metadata, independent of its
  // row ID/revision. Exclude only those known-valid empty records in SQL. Any
  // noncanonical or malformed record is still validated before being skipped,
  // so an unsupported version cannot masquerade as discarded content.
  String _clearedDraftData(MailAccountId account) => MailStoreCodec.encodeDraft(
    MailDraft(
      id: 'catalog-tombstone',
      account: account,
      revision: 0,
      envelope: MailEnvelope(),
      body: const MailBody(),
      editorState: MailDraftEditorState(isCleared: true),
    ),
  ).data;

  /// Lists bounded draft metadata without loading attachment blobs.
  /// Canonical cleared revision markers are skipped by the database. A rare
  /// noncanonical cleared row may produce an empty page with a continuation;
  /// callers must follow [MailDraftPage.nextAfterId] rather than infer EOF.
  Future<MailResult<MailDraftPage>> listDrafts(
    MailAccountId account, {
    String? afterId,
    int limit = 100,
  }) => _run(
    () => _db.transaction(() async {
      await _account(account);
      if (limit < 1 || limit > 100 || limit > limits.maxPageSize) {
        _fail(MailProblemCode.invalidInput);
      }
      if (afterId != null) _id(afterId);
      final rows = await _rows(
        'SELECT id,revision,data FROM drafts '
        'WHERE account=? AND data<>? AND id>? ORDER BY id LIMIT ?',
        [account.value, _clearedDraftData(account), afterId ?? '', limit + 1],
      );
      final drafts = <MailDraftSummary>[];
      for (final row in rows.take(limit)) {
        final summary = MailStoreCodec.decodeDraftSummary(
          row.read<String>('data'),
          account: account,
          id: row.read<String>('id'),
          revision: row.read<int>('revision'),
        );
        if (summary.editorState?.isCleared != true) drafts.add(summary);
      }
      return MailDraftPage(
        drafts: drafts,
        nextAfterId: rows.length > limit
            ? rows[limit - 1].read<String>('id')
            : null,
      );
    }),
  );

  @override
  Future<MailResult<MailDraft?>> loadDraft(
    MailAccountId account,
    String draftId,
  ) => _run(
    () => _db.transaction(() async {
      await _account(account);
      final rows = await _rows(
        'SELECT revision,data FROM drafts WHERE account=? AND id=?',
        [account.value, draftId],
      );
      if (rows.isEmpty) return null;
      return MailStoreCodec.decodeDraft(
        rows.single.read<String>('data'),
        account: account,
        id: draftId,
        revision: rows.single.read<int>('revision'),
        blobs: await _blobs(account, 'draft', draftId),
      );
    }),
  );

  Future<MailOutboxEntry?> _outbox(MailAccountId account, String id) async {
    final rows = await _rows(
      'SELECT data,state,attempt_id FROM outbox WHERE account=? AND id=?',
      [account.value, id],
    );
    if (rows.isEmpty) return null;
    final entry = MailStoreCodec.decodeOutbox(
      rows.single.read<String>('data'),
      account: account,
      id: id,
      blobs: await _blobs(account, 'outbox', id),
    );
    if (entry.state.name != rows.single.read<String>('state') ||
        entry.attemptId != rows.single.readNullable<String>('attempt_id')) {
      _fail(MailProblemCode.storageFailure);
    }
    return entry;
  }

  @override
  Future<MailResult<MailUnit>> saveOutbox(
    MailOutboxEntry entry, {
    required MailOutboxState? expectedState,
    required String? expectedAttemptId,
  }) => _write(() async {
    final account = entry.prepared.account;
    await _account(account, active: entry.state == MailOutboxState.submitting);
    _outboxBudget(entry);
    final previous = await _outbox(account, entry.id);
    if (previous?.state != expectedState ||
        previous?.attemptId != expectedAttemptId ||
        !MailStoreCodec.validOutboxTransition(previous, entry)) {
      _fail(MailProblemCode.conflict);
    }
    await _putOutbox(entry);
    if (entry.state == MailOutboxState.submitting &&
        previous?.attemptId != entry.attemptId) {
      _id(entry.attemptId!);
      await _db.customStatement(
        'INSERT INTO outbox_attempts(account,outbox,attempt_id) VALUES(?,?,?)',
        [account.value, entry.id, entry.attemptId],
      );
    }
    await _db.fault(MailStoreCheckpoint.afterOutboxWrite);
    await _quota(account);
    return MailUnit.value;
  });

  void _outboxBudget(MailOutboxEntry entry) {
    _id(entry.id);
    _id(entry.prepared.draftId);
    if (entry.prepared.wire.length > limits.maxBlobBytes ||
        entry.prepared.envelope.recipients.length > 512) {
      _fail(MailProblemCode.quotaExceeded);
    }
    if (entry.attemptId case final attempt?) _id(attempt);
    var envelopeUnits = entry.prepared.envelope.sender.length;
    for (final recipient in entry.prepared.envelope.recipients) {
      envelopeUnits += recipient.length;
    }
    if (envelopeUnits > limits.maxMetadataCodeUnits) {
      _fail(MailProblemCode.quotaExceeded);
    }
  }

  /// Atomically transfers one saved draft revision into a new frozen outbox
  /// item, retaining the next empty draft revision to reject stale autosaves.
  /// The host must prepare [entry] from that exact saved revision and validate
  /// its MIME/envelope before calling. This storage boundary checks ownership,
  /// revision, initial state, uncertainty, immutable bytes and storage limits;
  /// it does not parse or regenerate MIME. Failure preserves the entire draft.
  Future<MailResult<MailUnit>> enqueueDraft(
    MailOutboxEntry entry, {
    required int expectedDraftRevision,
  }) => _write(() async {
    final prepared = entry.prepared;
    final account = prepared.account;
    await _account(account);
    _outboxBudget(entry);
    if (prepared.draftRevision != expectedDraftRevision ||
        !MailStoreCodec.validOutboxTransition(null, entry) ||
        await _outbox(account, entry.id) != null) {
      _fail(MailProblemCode.conflict);
    }
    final rows = await _rows(
      'SELECT revision,data FROM drafts WHERE account=? AND id=?',
      [account.value, prepared.draftId],
    );
    if (rows.isEmpty ||
        rows.single.read<int>('revision') != expectedDraftRevision) {
      _fail(MailProblemCode.conflict);
    }
    final draft = MailStoreCodec.decodeDraft(
      rows.single.read<String>('data'),
      account: account,
      id: prepared.draftId,
      revision: expectedDraftRevision,
      blobs: await _blobs(account, 'draft', prepared.draftId),
    );
    if ((draft.editorState?.isCleared ?? false) ||
        (draft.editorState?.submissionUncertain ?? false) !=
            entry.priorSubmissionUncertain) {
      _fail(MailProblemCode.conflict);
    }
    await _putOutbox(entry);
    await _db.fault(MailStoreCheckpoint.afterOutboxWrite);
    final cleared = MailDraft(
      id: draft.id,
      account: account,
      revision: expectedDraftRevision + 1,
      envelope: MailEnvelope(),
      body: const MailBody(),
      editorState: MailDraftEditorState(isCleared: true),
    );
    final payload = MailStoreCodec.encodeDraft(cleared);
    await _storePayload(account, 'draft', draft.id, payload);
    await _db.fault(MailStoreCheckpoint.afterDraftBlobs);
    await _db.customStatement(
      'UPDATE drafts SET revision=?,data=? WHERE account=? AND id=?',
      [cleared.revision, payload.data, account.value, draft.id],
    );
    await _collectBlobs(account);
    await _quota(account);
    return MailUnit.value;
  });

  /// Removes a reviewed terminal local record and releases unreferenced bytes.
  /// It never recalls a message or resolves the risk of an earlier duplicate.
  /// Queued, active, retryable and open uncertain items cannot be removed. A
  /// closed uncertain record may be removed after explicit local resolution.
  /// A definite rejection is removable only without older uncertainty; later
  /// acceptance permits explicit local cleanup while ordinary retry stays off.
  /// Cleanup is allowed even when the account now exceeds a lowered quota.
  Future<MailResult<MailUnit>> removeOutbox(
    MailAccountId account,
    String id, {
    required MailOutboxState expectedState,
    required String? expectedAttemptId,
  }) => _write(() async {
    await _account(account);
    _id(id);
    final entry = await _outbox(account, id);
    if (entry == null ||
        entry.state != expectedState ||
        entry.attemptId != expectedAttemptId ||
        !entry.canRemove) {
      _fail(MailProblemCode.conflict);
    }
    await _db.customStatement(
      'DELETE FROM blob_refs WHERE account=? AND owner_kind=? AND owner_id=?',
      [account.value, 'outbox', id],
    );
    await _db.customStatement('DELETE FROM outbox WHERE account=? AND id=?', [
      account.value,
      id,
    ]);
    await _collectBlobs(account);
    await _db.fault(MailStoreCheckpoint.afterOutboxWrite);
    return MailUnit.value;
  });

  /// Atomically retires one safely cancellable queued item and creates a new
  /// editable draft. The caller reconstructs and validates the composer data
  /// from [original]'s frozen bytes/envelope; this boundary never parses MIME.
  ///
  /// The complete source snapshot is compared, including its attempt and frozen
  /// payload. A concurrent send or a second edit cannot leave two resendable
  /// copies. The original remains cancelled with unchanged bytes for review.
  /// Admission, blob ownership and cancellation all roll back together.
  Future<MailResult<MailUnit>> editOutboxAsDraft(
    MailOutboxEntry original,
    MailDraft draft, {
    required DateTime now,
    int maxActiveDrafts = 100,
  }) => _write(() async {
    final account = original.prepared.account;
    await _account(account);
    if (draft.account != account) _fail(MailProblemCode.permissionDenied);
    _outboxBudget(original);
    _draftBudget(draft);
    if (draft.revision != 0 ||
        draft.editorState == null ||
        draft.editorState!.isCleared ||
        draft.editorState!.submissionUncertain ||
        maxActiveDrafts < 1 ||
        maxActiveDrafts > 1000) {
      _fail(MailProblemCode.invalidInput);
    }
    final previous = await _outbox(account, original.id);
    if (!original.canCancel ||
        previous == null ||
        previous.state != original.state ||
        previous.attemptId != original.attemptId ||
        !MailStoreCodec.validOutboxTransition(previous, original) ||
        draft.id == original.prepared.draftId ||
        (await _rows('SELECT id FROM drafts WHERE account=? AND id=?', [
          account.value,
          draft.id,
        ])).isNotEmpty) {
      _fail(MailProblemCode.conflict);
    }
    final cancelled = original.cancel(now: now);
    if (!MailStoreCodec.validOutboxTransition(previous, cancelled)) {
      _fail(MailProblemCode.conflict);
    }
    final count = (await _rows(
      'SELECT count(*) AS n FROM drafts WHERE account=? AND data<>?',
      [account.value, _clearedDraftData(account)],
    )).single.read<int>('n');
    if (count >= maxActiveDrafts) _fail(MailProblemCode.quotaExceeded);
    await _putOutbox(cancelled);
    await _db.fault(MailStoreCheckpoint.afterOutboxWrite);
    final payload = MailStoreCodec.encodeDraft(draft);
    await _storePayload(account, 'draft', draft.id, payload);
    await _db.fault(MailStoreCheckpoint.afterDraftBlobs);
    await _db.customStatement(
      'INSERT INTO drafts(account,id,revision,data) VALUES(?,?,?,?)',
      [account.value, draft.id, draft.revision, payload.data],
    );
    await _collectBlobs(account);
    await _quota(account);
    return MailUnit.value;
  });

  Future<void> _putOutbox(MailOutboxEntry entry) async {
    final account = entry.prepared.account;
    final payload = MailStoreCodec.encodeOutbox(entry);
    await _storePayload(account, 'outbox', entry.id, payload);
    await _db.customStatement(
      'INSERT INTO outbox(account,id,state,attempt_id,data) VALUES(?,?,?,?,?) '
      'ON CONFLICT(account,id) DO UPDATE SET state=excluded.state,attempt_id=excluded.attempt_id,data=excluded.data',
      [
        account.value,
        entry.id,
        entry.state.name,
        entry.attemptId,
        payload.data,
      ],
    );
  }

  @override
  Future<MailResult<List<MailOutboxEntry>>> recoverOutbox(
    MailAccountId account,
  ) => _write(() async {
    await _account(account);
    final result = <MailOutboxEntry>[];
    for (final row in await _rows(
      'SELECT id FROM outbox WHERE account=? ORDER BY id',
      [account.value],
    )) {
      final id = row.read<String>('id');
      var entry = (await _outbox(account, id))!;
      if (entry.state == MailOutboxState.submitting &&
          _interrupted[(account.value, id)] == entry.attemptId) {
        final now = _clock();
        entry = entry.recoverInterrupted(
          now: now.isBefore(entry.updatedAt) ? entry.updatedAt : now,
        );
        await _putOutbox(entry);
      }
      result.add(entry);
    }
    return List.unmodifiable(result);
  });

  @override
  Future<MailResult<MailUnit>> removeAccount(MailAccountId account) =>
      removeLocalAccount(account);
}
