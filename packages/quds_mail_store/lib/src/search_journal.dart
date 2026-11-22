part of 'repository.dart';

/// Local-only search/cache and a durable provider-intent journal. None of these
/// methods holds a provider, HTTP client, credential value or network callback.
extension MailStoreLocalOperations on SqliteMailRepository {
  // The writer permits six encoded UTF-16 units per semantic metadata unit.
  // UTF-8 uses at most three bytes per UTF-16 unit, so this preflight also
  // preserves previously valid escaped/non-ASCII JSON. The exact character and
  // decoded semantic budgets are checked after this bounded transfer.
  Future<QueryRow?> _cachedMetadata(
    MailAccountId account,
    MailMessageId message, {
    bool includeHeader = false,
  }) async {
    final columns = [
      'c.data',
      if (includeHeader) ...['c.raw_hash', 'm.envelope', 'm.remote'],
    ];
    final from =
        'FROM cached_messages c '
        '${includeHeader ? 'JOIN messages m ON m.account=c.account AND m.id=c.message ' : ''}'
        'WHERE c.account=? AND c.message=?';
    final args = [account.value, message.value];
    final sizes = await _rows(
      'SELECT ${[for (var i = 0; i < columns.length; i++) 'typeof(${columns[i]}) AS type_$i,length(CAST(${columns[i]} AS BLOB)) AS bytes_$i'].join(',')} $from',
      args,
    );
    if (sizes.isEmpty) return null;
    for (var i = 0; i < columns.length; i++) {
      if (sizes.single.read<String>('type_$i') != 'text') {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      final bytes = sizes.single.read<int>('bytes_$i');
      if ((i == 1 && bytes != 64) || (i == 3 && bytes > 16384)) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      if ((i == 0 || i == 2) && bytes > limits.maxMetadataCodeUnits * 18) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
    }
    final row = (await _rows('SELECT ${columns.join(',')} $from', args)).single;
    if (row.read<String>('data').length > limits.maxMetadataCodeUnits * 6 ||
        (includeHeader &&
            row.read<String>('envelope').length >
                limits.maxMetadataCodeUnits * 6)) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    if (includeHeader &&
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(row.read<String>('raw_hash'))) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    return row;
  }

  Future<String?> _cachedPlain(
    MailAccountId account,
    MailMessageId message,
  ) async {
    final row = await _cachedMetadata(account, message);
    if (row == null) return null;
    return MailStoreCodec.decodeDraftBody(
      row.read<String>('data'),
      limits: limits,
    ).plainText;
  }

  String _indexText(MailEnvelope envelope, String? plain) {
    final text = StringBuffer();
    var remaining = limits.maxIndexCodeUnits;
    void append(String value) {
      if (remaining == 0 || value.isEmpty) return;
      var count = value.length < remaining ? value.length : remaining;
      // Never split a UTF-16 surrogate pair at the work boundary.
      if (count < value.length &&
          count > 0 &&
          value.codeUnitAt(count - 1) >= 0xd800 &&
          value.codeUnitAt(count - 1) <= 0xdbff) {
        count--;
      }
      text.write(value.substring(0, count));
      remaining -= count;
      if (remaining > 0) {
        text.write(' ');
        remaining--;
      }
    }

    append(envelope.subject);
    for (final group in [
      envelope.from,
      envelope.to,
      envelope.cc,
      envelope.replyTo,
    ]) {
      for (final address in group) {
        append(address.displayName ?? '');
        append(address.address);
      }
    }
    append(plain ?? '');
    return text.toString();
  }

  Future<void> _index(
    MailAccountId account,
    MailMessageId message,
    MailEnvelope envelope,
    String? plain,
  ) async {
    final text = _indexText(envelope, plain);
    await _db.customStatement(
      'DELETE FROM mail_fts WHERE account=? AND message=?',
      [account.value, message.value],
    );
    await _db.customStatement(
      'INSERT INTO mail_fts(account,message,content) VALUES(?,?,?)',
      [account.value, message.value, text],
    );
    await _db.customStatement(
      'INSERT INTO index_state(account,message) VALUES(?,?) ON CONFLICT DO NOTHING',
      [account.value, message.value],
    );
  }

  Future<MailResult<List<MailSearchHit>>> search(
    MailAccountId account,
    String query, {
    int limit = 50,
    MailMailboxId? mailbox,
  }) => _run(() async {
    await _account(account);
    if (query.length > limits.maxQueryCodeUnits ||
        limit < 1 ||
        limit > limits.maxSearchResults ||
        (mailbox != null && mailbox.account != account)) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final terms = RegExp(
      r'[\p{L}\p{N}_]+',
      unicode: true,
    ).allMatches(query).map((m) => m.group(0)!).toList();
    if (terms.length > limits.maxQueryTerms) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    if (terms.isEmpty) return const <MailSearchHit>[];
    // Every token is a quoted literal joined with AND; no raw FTS grammar.
    final match = terms.map((term) => '"$term"').join(' AND ');
    final rows = await _rows(
      'SELECT m.*,snippet(mail_fts,2,\'\',\'\',\'…\',16) AS preview,bm25(mail_fts) AS rank '
      'FROM mail_fts JOIN messages m ON m.account=mail_fts.account AND m.id=mail_fts.message '
      'WHERE mail_fts MATCH ? AND mail_fts.account=? '
      '${mailbox == null ? '' : 'AND EXISTS (SELECT 1 FROM memberships s WHERE s.account=m.account AND s.message=m.id AND s.mailbox=?) '}'
      'ORDER BY rank,m.id LIMIT ?',
      [match, account.value, if (mailbox != null) mailbox.value, limit],
    );
    return List.unmodifiable([
      for (final row in rows)
        MailSearchHit(
          header: _header(row, account),
          preview: row.read<String>('preview'),
          rank: row.read<double>('rank'),
        ),
    ]);
  });

  /// Bounded, explicit backfill for v1 databases; opening never scans all mail.
  Future<MailResult<int>> reindex(
    MailAccountId account, {
    int limit = 100,
  }) => _write(() async {
    await _account(account);
    if (limit < 1 || limit > limits.maxPageSize) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final rows = await _rows(
      'SELECT m.* FROM messages m WHERE account=? AND NOT EXISTS '
      '(SELECT 1 FROM index_state i WHERE i.account=m.account AND i.message=m.id) ORDER BY id LIMIT ?',
      [account.value, limit],
    );
    for (final row in rows) {
      final header = _header(row, account);
      await _index(
        account,
        header.id,
        header.envelope,
        await _cachedPlain(account, header.id),
      );
    }
    await _quota(account);
    return rows.length;
  });

  Future<MailResult<MailUnit>> cacheMessage(
    MailAccountId account,
    MailMessageId id,
    MailMessage message, {
    MailOperationLease? lease,
  }) => _run(
    () => _commit(() async {
      await _account(account);
      if (lease != null && lease.account != account) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      lease?.checkCurrent();
      final rows = await _rows(
        'SELECT * FROM messages WHERE account=? AND id=?',
        [account.value, id.value],
      );
      if (rows.isEmpty) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      final header = _header(rows.single, account);
      if ((message.localId != null && message.localId != id) ||
          message.remoteIdentity != header.remote) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      if (message.raw.length > limits.maxBlobBytes) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final draft = MailDraft(
        id: id.value,
        account: account,
        revision: 0,
        envelope: message.envelope,
        body: message.body,
        attachments: message.attachments,
      );
      _draftBudget(draft);
      final encoded = MailStoreCodec.encodeDraft(draft);
      final blobs = <String, MailBytes>{
        ...encoded.blobs,
        message.raw.sha256: message.raw,
      };
      await _storePayload(
        account,
        'cache',
        id.value,
        MailStorePayload(data: encoded.data, blobs: blobs),
      );
      await _db.customStatement(
        'INSERT INTO cached_messages(account,message,raw_hash,data) VALUES(?,?,?,?) '
        'ON CONFLICT(account,message) DO UPDATE SET raw_hash=excluded.raw_hash,data=excluded.data',
        [account.value, id.value, message.raw.sha256, encoded.data],
      );
      await _collectBlobs(account);
      await _index(account, id, header.envelope, message.body.plainText);
      await _quota(account);
      await _db.fault(MailStoreCheckpoint.beforeCommit);
      lease?.checkCurrent();
      return MailUnit.value;
    }),
  );

  Future<MailResult<MailMessage?>> loadCachedMessage(
    MailAccountId account,
    MailMessageId id,
  ) => _run(
    () => _db.transaction(() async {
      await _account(account);
      final row = await _cachedMetadata(account, id, includeHeader: true);
      if (row == null) return null;
      MailStoreCodec.decodeDraftBody(row.read<String>('data'), limits: limits);
      final envelope = MailStoreCodec.decodeEnvelope(
        row.read<String>('envelope'),
      );
      if (_envelopeUnits(envelope) > limits.maxMetadataCodeUnits) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final blobs = await _blobs(account, 'cache', id.value);
      final body = MailStoreCodec.decodeDraft(
        row.read<String>('data'),
        account: account,
        id: id.value,
        revision: 0,
        blobs: blobs,
      );
      final raw = blobs[row.read<String>('raw_hash')];
      if (raw == null) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      return MailMessage(
        raw: raw,
        envelope: envelope,
        body: body.body,
        attachments: body.attachments,
        localId: id,
        remoteIdentity: MailStoreCodec.decodeRemote(
          row.read<String>('remote'),
          account: account,
        ),
      );
    }),
  );

  Future<MailResult<MailBlobPin>> pinBlob(
    MailAccountId account, {
    required String pinId,
    required MailBytes bytes,
  }) => _write(() async {
    await _account(account);
    _id(pinId);
    final existing = await _rows(
      "SELECT hash FROM blob_refs WHERE account=? AND owner_kind='pin' AND owner_id=?",
      [account.value, pinId],
    );
    if (existing.isNotEmpty &&
        existing.single.read<String>('hash') != bytes.sha256) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    await _storePayload(
      account,
      'pin',
      pinId,
      MailStorePayload(data: '', blobs: {bytes.sha256: bytes}),
    );
    await _quota(account);
    return MailBlobPin(account: account, id: pinId, hash: bytes.sha256);
  });

  Future<MailResult<MailUnit>> releasePin(MailBlobPin pin) => _write(() async {
    await _account(pin.account);
    await _db.customStatement(
      "DELETE FROM blob_refs WHERE account=? AND owner_kind='pin' AND owner_id=? AND hash=?",
      [pin.account.value, pin.id, pin.hash],
    );
    await _collectBlobs(pin.account);
    return MailUnit.value;
  });

  /// Eviction removes expendable cache rows, retaining every outgoing/editor ref.
  Future<MailResult<int>> evictCache(
    MailAccountId account, {
    int limit = 100,
  }) => _write(() async {
    await _account(account);
    if (limit < 1 || limit > limits.maxPageSize) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final count = await _evictCacheBodies(account, limit);
    await _collectBlobs(account);
    return count;
  });

  static const _cachePinned =
      'EXISTS (SELECT 1 FROM blob_refs r JOIN blob_refs p '
      "ON p.account=r.account AND p.hash=r.hash AND p.owner_kind='pin' "
      "WHERE r.account=c.account AND r.owner_kind='cache' AND r.owner_id=c.message)";

  static const _headerExpendable =
      'NOT EXISTS (SELECT 1 FROM memberships s '
      'WHERE s.account=m.account AND s.message=m.id) '
      'AND NOT EXISTS (SELECT 1 FROM mailbox_view_members v '
      'WHERE v.account=m.account AND v.message=m.id) '
      'AND NOT EXISTS (SELECT 1 FROM cached_messages c '
      'WHERE c.account=m.account AND c.message=m.id) '
      'AND NOT EXISTS (SELECT 1 FROM blob_refs r WHERE r.account=m.account '
      "AND r.owner_kind='cache' AND r.owner_id=m.id) "
      'AND NOT EXISTS (SELECT 1 FROM pending_operations p '
      'WHERE p.account=m.account AND p.remote=m.remote '
      "AND p.state IN ('queued','applying','reconcile'))";

  Future<List<String>> _boundedCacheIds(
    String column,
    String from,
    List<Object?> args,
  ) async {
    final sizes = await _rows(
      'SELECT typeof($column) AS type,length(CAST($column AS BLOB)) AS bytes $from',
      args,
    );
    if (sizes.any(
      (row) =>
          row.read<String>('type') != 'text' || row.read<int>('bytes') > 4096,
    )) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    return [
      for (final row in await _rows('SELECT $column AS id $from', args))
        row.read<String>('id'),
    ];
  }

  Future<int> _evictCacheBodies(
    MailAccountId account,
    int limit, {
    bool retainHeaderIndex = true,
  }) async {
    final ids = await _boundedCacheIds(
      'c.message',
      'FROM cached_messages c WHERE c.account=? AND NOT $_cachePinned '
          'ORDER BY c.message LIMIT ?',
      [account.value, limit],
    );
    for (final id in ids) {
      MailEnvelope? envelope;
      if (retainHeaderIndex) {
        // Ordinary eviction preserves header search. Explicit quota recovery
        // must instead discard the index without admitting existing metadata.
        final size = (await _rows(
          'SELECT typeof(envelope) AS type,length(CAST(envelope AS BLOB)) AS bytes '
          'FROM messages WHERE account=? AND id=?',
          [account.value, id],
        )).single;
        if (size.read<String>('type') != 'text') {
          SqliteMailRepository._fail(MailProblemCode.storageFailure);
        }
        if (size.read<int>('bytes') > limits.maxMetadataCodeUnits * 18) {
          SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
        }
        final row = (await _rows(
          'SELECT envelope FROM messages WHERE account=? AND id=?',
          [account.value, id],
        )).single;
        envelope = MailStoreCodec.decodeEnvelope(row.read<String>('envelope'));
        if (_envelopeUnits(envelope) > limits.maxMetadataCodeUnits) {
          SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
        }
      }
      await _db.customStatement(
        'DELETE FROM cached_messages WHERE account=? AND message=?',
        [account.value, id],
      );
      await _db.customStatement(
        "DELETE FROM blob_refs WHERE account=? AND owner_kind='cache' AND owner_id=?",
        [account.value, id],
      );
      if (envelope != null) {
        await _index(account, MailMessageId(id), envelope, null);
      } else {
        await _db.customStatement(
          'DELETE FROM mail_fts WHERE account=? AND message=?',
          [account.value, id],
        );
        await _db.customStatement(
          'DELETE FROM index_state WHERE account=? AND message=?',
          [account.value, id],
        );
      }
    }
    return ids.length;
  }

  /// Explicit local recovery for an account whose automatic browse cache has
  /// filled its quota. Each category removes at most [limit] rows, in one
  /// transaction. No new quota admission is required to free existing space.
  /// Folder definitions, sync cursors/memberships, active pending operations,
  /// outgoing work and editor-pinned payloads remain intact.
  /// Evicted bodies lose their entire search entry; retained authoritative
  /// headers can be indexed again by [reindex] or the next synchronization.
  Future<MailResult<MailCacheCleanupReport>> clearMailboxCache(
    MailAccountId account, {
    int limit = 1000,
  }) => _write(() async {
    await _account(account);
    if (limit < 1 || limit > 1000 || limit > limits.maxPageSize) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    await _db.customStatement(
      'DELETE FROM mailbox_views WHERE account=? AND mailbox IN '
      '(SELECT mailbox FROM mailbox_views WHERE account=? ORDER BY mailbox LIMIT ?)',
      [account.value, account.value, limit],
    );
    final removedViews = (await _rows(
      'SELECT changes() AS n',
    )).single.read<int>('n');
    final evictedBodies = await _evictCacheBodies(
      account,
      limit,
      retainHeaderIndex: false,
    );
    final ids = await _boundedCacheIds(
      'm.id',
      'FROM messages m WHERE m.account=? AND $_headerExpendable ORDER BY m.id LIMIT ?',
      [account.value, limit],
    );
    for (final id in ids) {
      await _db.customStatement(
        'DELETE FROM mail_fts WHERE account=? AND message=?',
        [account.value, id],
      );
      await _db.customStatement(
        'DELETE FROM messages WHERE account=? AND id=?',
        [account.value, id],
      );
    }
    await _collectBlobs(account);
    final retainedBodies = (await _rows(
      'SELECT count(*) AS n FROM cached_messages c WHERE c.account=? AND $_cachePinned',
      [account.value],
    )).single.read<int>('n');
    final hasMore =
        (await _rows(
          'SELECT (EXISTS (SELECT 1 FROM mailbox_views WHERE account=?) '
          'OR EXISTS (SELECT 1 FROM cached_messages c WHERE c.account=? AND NOT $_cachePinned) '
          'OR EXISTS (SELECT 1 FROM messages m WHERE m.account=? AND $_headerExpendable)) AS n',
          [account.value, account.value, account.value],
        )).single.read<int>('n') !=
        0;
    return MailCacheCleanupReport(
      removedViews: removedViews,
      evictedBodies: evictedBodies,
      removedHeaders: ids.length,
      retainedBodies: retainedBodies,
      hasMore: hasMore,
    );
  });

  Future<MailResult<MailUnit>> enqueueOperation(
    MailOperation operation,
    MailOperationLease lease,
  ) => _run(
    () => _commit(() async {
      final account = operation.message.account;
      await _account(account, active: true);
      if (lease.account != account) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      lease.checkCurrent();
      _id(operation.id);
      final remote = _remoteKey(operation.message);
      if ((await _rows(
        'SELECT 1 AS n FROM messages WHERE account=? AND remote=?',
        [account.value, remote],
      )).isEmpty) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      final (kind, argument) = switch (operation) {
        MailSetRead(:final read) => ('read', read ? '1' : '0'),
        MailSetFlagged(:final flagged) => ('flag', flagged ? '1' : '0'),
        MailMove(:final destination) => ('move', destination.value),
        MailDelete() => ('delete', null),
        MailArchive()
            when operation.message.provider == MailProviderKind.gmail =>
          ('archive', null),
        MailArchive() => throw const MailStoreStorageException(
          MailProblemCode.unsupported,
        ),
      };
      if (operation is MailMove &&
          (await _rows(
            'SELECT 1 AS n FROM mailboxes WHERE account=? AND id=?',
            [account.value, operation.destination.value],
          )).isEmpty) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      final now = _clock().toUtc().millisecondsSinceEpoch;
      await _db.customStatement(
        'INSERT INTO pending_operations(account,id,remote,kind,argument,state,revision,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)',
        [
          account.value,
          operation.id,
          remote,
          kind,
          argument,
          'queued',
          0,
          now,
          now,
        ],
      );
      await _quota(account);
      await _db.fault(MailStoreCheckpoint.beforeCommit);
      lease.checkCurrent();
      return MailUnit.value;
    }),
  );

  MailPendingOperation _pending(QueryRow row, MailAccountId account) {
    final remote = MailStoreCodec.decodeRemote(
      row.read<String>('remote'),
      account: account,
    );
    final id = row.read<String>('id');
    final argument = row.readNullable<String>('argument');
    final operation = switch (row.read<String>('kind')) {
      'read' when argument == '0' || argument == '1' => MailSetRead(
        id: id,
        message: remote,
        read: argument == '1',
      ),
      'flag' when argument == '0' || argument == '1' => MailSetFlagged(
        id: id,
        message: remote,
        flagged: argument == '1',
      ),
      'move' when argument != null => MailMove(
        id: id,
        message: remote,
        destination: MailMailboxId(argument, account: account),
      ),
      'delete' when argument == null => MailDelete(id: id, message: remote),
      'archive'
          when argument == null && remote.provider == MailProviderKind.gmail =>
        MailArchive(id: id, message: remote),
      _ => throw const MailStoreStorageException(
        MailProblemCode.storageFailure,
      ),
    };
    return MailPendingOperation(
      operation: operation,
      revision: row.read<int>('revision'),
      state: MailPendingState.values.byName(row.read<String>('state')),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
    );
  }

  Future<MailResult<List<MailPendingOperation>>> pendingOperations(
    MailAccountId account, {
    int limit = 100,
    bool includeTerminal = false,
  }) => _run(() async {
    await _account(account);
    if (limit < 1 || limit > limits.maxPageSize) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    return List.unmodifiable([
      for (final row in await _rows(
        'SELECT * FROM pending_operations WHERE account=? '
        '${includeTerminal ? '' : "AND state IN ('queued','applying','reconcile') "}ORDER BY created_at,id LIMIT ?',
        [account.value, limit],
      ))
        _pending(row, account),
    ]);
  });

  /// Reconciled operations may be acknowledged or cancelled. A fresh, separately
  /// verified intent is needed to retry; this method never auto-requeues it.
  Future<MailResult<MailUnit>> transitionOperation(
    MailAccountId account,
    String id, {
    required int expectedRevision,
    required MailPendingState state,
    required MailOperationLease lease,
  }) => _run(
    () => _commit(() async {
      await _account(account, active: true);
      if (lease.account != account) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      lease.checkCurrent();
      final rows = await _rows(
        'SELECT * FROM pending_operations WHERE account=? AND id=?',
        [account.value, id],
      );
      if (rows.isEmpty ||
          rows.single.read<int>('revision') != expectedRevision) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
      final previous = MailPendingState.values.byName(
        rows.single.read<String>('state'),
      );
      final allowed = switch (previous) {
        MailPendingState.queued =>
          state == MailPendingState.applying ||
              state == MailPendingState.cancelled,
        MailPendingState.applying =>
          state == MailPendingState.applied ||
              state == MailPendingState.reconcile,
        MailPendingState.reconcile =>
          state == MailPendingState.applied ||
              state == MailPendingState.cancelled,
        MailPendingState.applied || MailPendingState.cancelled => false,
      };
      if (!allowed) SqliteMailRepository._fail(MailProblemCode.conflict);
      await _db.customStatement(
        'UPDATE pending_operations SET state=?,revision=revision+1,updated_at=? WHERE account=? AND id=?',
        [
          state.name,
          _clock().toUtc().millisecondsSinceEpoch,
          account.value,
          id,
        ],
      );
      await _pruneUnreferencedMessages(account);
      await _quota(account);
      await _db.fault(MailStoreCheckpoint.beforeCommit);
      lease.checkCurrent();
      return MailUnit.value;
    }),
  );

  /// Logout preserves local work. Host sessions are invalidated immediately;
  /// vault deletion is an independently acknowledged durable cleanup intent.
  Future<MailResult<MailUnit>> logout(MailAccountSession session) {
    if (session.account.profile != profile) {
      return Future.value(
        const MailFailure(MailProblem(MailProblemCode.permissionDenied)),
      );
    }
    session.invalidate();
    return _write(() async {
      await _account(session.account);
      await _queueCredentialCleanup(session.account);
      await _db.customStatement(
        "UPDATE accounts SET state='loggedOut',credential_ref=NULL WHERE id=?",
        [session.account.value],
      );
      await _db.customStatement(
        "UPDATE pending_operations SET state='reconcile',revision=revision+1 WHERE account=? AND state='applying'",
        [session.account.value],
      );
      await _recoverFlagBatches(account: session.account);
      return MailUnit.value;
    });
  }

  /// The host calls this only after obtaining fresh authorization in its vault.
  Future<MailResult<MailUnit>> resumeAccount(
    MailAccountId account, {
    required String credentialReference,
  }) => _write(() async {
    final previous = await _account(account);
    _id(credentialReference);
    final cleanup = await _rows(
      'SELECT 1 AS n FROM credential_cleanup WHERE account=? AND reference=?',
      [account.value, credentialReference],
    );
    if (cleanup.isNotEmpty) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    if (previous.readNullable<String>('credential_ref') !=
        credentialReference) {
      await _queueCredentialCleanup(account);
    }
    await _db.customStatement(
      "UPDATE accounts SET state='active',credential_ref=? WHERE id=?",
      [credentialReference, account.value],
    );
    await _quota(account);
    return MailUnit.value;
  });

  Future<void> _queueCredentialCleanup(MailAccountId account) async {
    await _db.customStatement(
      'INSERT INTO credential_cleanup(account,reference) '
      'SELECT id,credential_ref FROM accounts WHERE id=? AND credential_ref IS NOT NULL ON CONFLICT DO NOTHING',
      [account.value],
    );
  }

  Future<MailResult<List<MailCredentialCleanup>>> credentialCleanup() => _run(
    () async => [
      for (final row in await _rows(
        'SELECT account,reference FROM credential_cleanup ORDER BY account,reference',
      ))
        MailCredentialCleanup(
          account: MailAccountId(row.read<String>('account'), profile: profile),
          reference: row.read<String>('reference'),
        ),
    ],
  );

  Future<MailResult<MailUnit>> acknowledgeCredentialCleanup(
    MailCredentialCleanup cleanup,
  ) => _write(() async {
    _scope(cleanup.account);
    await _db.customStatement(
      'DELETE FROM credential_cleanup WHERE account=? AND reference=?',
      [cleanup.account.value, cleanup.reference],
    );
    return MailUnit.value;
  });

  /// Explicit destructive local removal. The remote provider is never contacted.
  Future<MailResult<MailUnit>> removeLocalAccount(MailAccountId account) =>
      _write(() async {
        _scope(account);
        final existing = await _rows('SELECT state FROM accounts WHERE id=?', [
          account.value,
        ]);
        if (existing.isEmpty) {
          SqliteMailRepository._fail(MailProblemCode.unavailable);
        }
        await _removeLocalAccount(account);
        return MailUnit.value;
      });

  Future<void> _removeLocalAccount(MailAccountId account) async {
    await _queueCredentialCleanup(account);
    for (final table in [
      'mail_fts',
      'pending_operations',
      'flag_batch_items',
      'flag_batches',
      'mailbox_move_revisions',
      'tombstones',
      'cached_messages',
      'outbox_attempts',
      'outbox',
      'drafts',
      'account_quick_texts',
      'account_compose_settings',
      'account_archive_settings',
      'blob_refs',
      'blobs',
      'memberships',
      'mailbox_view_members',
      'mailbox_views',
      'mailbox_sync_state',
      'cursors',
      'index_state',
      'messages',
      'mailboxes',
    ]) {
      await _db.customStatement('DELETE FROM $table WHERE account=?', [
        account.value,
      ]);
    }
    await _db.customStatement(
      "UPDATE accounts SET state='removed',display_name='',credential_ref=NULL WHERE id=?",
      [account.value],
    );
  }

  /// Retains only retired identity markers and vault-cleanup intents, so the host
  /// can finish secure-store deletion even after a crash during profile removal.
  Future<MailResult<MailUnit>> removeProfile() => _write(() async {
    await _db.customStatement('DELETE FROM local_accounts');
    await _db.customStatement('DELETE FROM saved_header_searches');
    await _db.customStatement('DELETE FROM account_quick_texts');
    await _db.customStatement('DELETE FROM account_compose_settings');
    await _db.customStatement('DELETE FROM account_archive_settings');
    for (final row in await _rows('SELECT id FROM accounts')) {
      await _removeLocalAccount(
        MailAccountId(row.read<String>('id'), profile: profile),
      );
    }
    await _db.customStatement(
      'UPDATE store_profile SET removed=1 WHERE singleton=1',
    );
    return MailUnit.value;
  });
}
