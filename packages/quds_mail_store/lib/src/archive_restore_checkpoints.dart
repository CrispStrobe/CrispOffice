part of 'archive_repository.dart';

// Restore plans are final, decoded through a validating factory and contain
// immutable item/origin lists. Cache their derived totals weakly so importing
// every ordinal does not repeatedly scan the whole manifest.
final _restorePlanIdentities = Expando<_RestorePlanIdentity>();

// Management reads must still expose retained progress after a host lowers
// write quotas. These match MailArchiveLimits' absolute supported maxima.
const _restoreReadMaxJobs = 10000;
const _restoreReadMaxReceipts = 1000000;

final class _RestorePlanIdentity {
  const _RestorePlanIdentity(this.planned, this.totalBytes);
  final int planned;
  final int totalBytes;
}

extension MailArchiveRestoreCheckpoints on SqliteMailArchive {
  _RestorePlanIdentity _restoreIdentity(MailArchiveRestorePlan plan) {
    _id(plan.manifestSha256);
    final cached = _restorePlanIdentities[plan];
    if (cached != null) return cached;
    final items = plan.exportPlan.items;
    if (items.length > 100000) {
      SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
    }
    var totalBytes = 0;
    final ids = <String>{};
    for (final item in items) {
      _id(item.id);
      if (!ids.add(item.id) || item.byteLength <= 0 || item.origins.isEmpty) {
        SqliteMailArchive._fail(MailProblemCode.invalidInput);
      }
      totalBytes += item.byteLength;
      if (item.byteLength > 256 * 1024 * 1024 ||
          totalBytes > 4 * 1024 * 1024 * 1024 * 1024) {
        SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
      }
    }
    final identity = _RestorePlanIdentity(items.length, totalBytes);
    _restorePlanIdentities[plan] = identity;
    return identity;
  }

  MailArchiveExportItem _restoreItem(MailArchiveRestorePlan plan, int ordinal) {
    final identity = _restoreIdentity(plan);
    if (ordinal < 1 || ordinal > identity.planned) {
      SqliteMailArchive._fail(MailProblemCode.invalidInput);
    }
    return plan.exportPlan.items[ordinal - 1];
  }

  Future<QueryRow?> _restoreJob(MailArchiveRestorePlan plan) async {
    final identity = _restoreIdentity(plan);
    final rows = await _rows(
      'SELECT planned,total_bytes,stored_size FROM archive_restore_jobs WHERE manifest=?',
      [plan.manifestSha256],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    if (row.read<int>('planned') != identity.planned ||
        row.read<int>('total_bytes') != identity.totalBytes ||
        row.read<int>('stored_size') != 192) {
      SqliteMailArchive._fail(MailProblemCode.conflict);
    }
    return row;
  }

  void _matchRestoreReceipt(QueryRow row, MailArchiveExportItem item) {
    if (row.read<String>('message') != item.id ||
        row.read<int>('byte_length') != item.byteLength ||
        !const [0, 1].contains(row.read<int>('index_warning')) ||
        row.read<int>('stored_size') != 256) {
      SqliteMailArchive._fail(MailProblemCode.conflict);
    }
  }

  Future<List<QueryRow>> _restoreReceiptRows(
    String manifest, {
    int? ordinal,
  }) async {
    final where = 'manifest=?${ordinal == null ? '' : ' AND ordinal=?'}';
    final values = <Object?>[manifest, ?ordinal];
    final maximum = ordinal == null ? limits.maxRestoreReceipts : 1;
    final sizes = await _rows(
      'SELECT length(CAST(message AS BLOB)) AS message_bytes '
      'FROM archive_restore_receipts WHERE $where LIMIT ?',
      [...values, maximum + 1],
    );
    if (sizes.length > maximum) {
      SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
    }
    if (sizes.any((row) => row.read<int>('message_bytes') != 64)) {
      SqliteMailArchive._fail(MailProblemCode.storageFailure);
    }
    return _rows(
      'SELECT ordinal,message,byte_length,index_warning,stored_size '
      'FROM archive_restore_receipts WHERE $where ORDER BY ordinal LIMIT ?',
      [...values, maximum + 1],
    );
  }

  /// Read committed progress for this exact manifest in this destination.
  /// Receipt identities/sizes are checked against the immutable selection;
  /// original bytes and provenance are rechecked by [loadRestoreReceipt].
  Future<MailResult<MailArchiveRestoreCheckpoint?>> restoreCheckpoint(
    MailArchiveRestorePlan plan, {
    MailCancellationToken? cancellation,
  }) => _run(
    MailArchiveOperation.restoreCheckpoint,
    (trace) => _db.transaction(() async {
      cancellation?.throwIfCancelled();
      final identity = _restoreIdentity(plan);
      if (await _restoreJob(plan) == null) return null;
      final receipts = await _restoreReceiptRows(plan.manifestSha256);
      var completedBytes = 0;
      for (final row in receipts) {
        cancellation?.throwIfCancelled();
        final ordinal = row.read<int>('ordinal');
        if (ordinal < 1 || ordinal > identity.planned) {
          SqliteMailArchive._fail(MailProblemCode.conflict);
        }
        _matchRestoreReceipt(row, plan.exportPlan.items[ordinal - 1]);
        completedBytes += row.read<int>('byte_length');
      }
      cancellation?.throwIfCancelled();
      trace.items = receipts.length;
      trace.bytes = completedBytes;
      return MailArchiveRestoreCheckpoint(
        manifestSha256: plan.manifestSha256,
        planned: identity.planned,
        totalBytes: identity.totalBytes,
        completedMessages: receipts.length,
        completedBytes: completedBytes,
      );
    }),
  );

  /// List a bounded set of saved progress records for explicit management.
  /// This summary does not certify destination originals; resumption verifies
  /// each receipt separately. Progress is never silently shortened or evicted.
  Future<MailResult<List<MailArchiveRestoreCheckpoint>>>
  listRestoreCheckpoints({MailCancellationToken? cancellation}) => _run(
    MailArchiveOperation.listRestoreCheckpoints,
    (trace) => _db.transaction(() async {
      cancellation?.throwIfCancelled();
      final sizes = await _rows(
        'SELECT length(CAST(manifest AS BLOB)) AS manifest_bytes '
        'FROM archive_restore_jobs LIMIT ?',
        [_restoreReadMaxJobs + 1],
      );
      if (sizes.length > _restoreReadMaxJobs) {
        SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
      }
      if (sizes.any((row) => row.read<int>('manifest_bytes') != 64)) {
        SqliteMailArchive._fail(MailProblemCode.storageFailure);
      }
      final receiptCount = (await _rows(
        'SELECT count(*) AS n FROM '
        '(SELECT 1 FROM archive_restore_receipts LIMIT ?)',
        [_restoreReadMaxReceipts + 1],
      )).single.read<int>('n');
      if (receiptCount > _restoreReadMaxReceipts) {
        SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
      }
      final rows = await _rows(
        'SELECT j.manifest,j.planned,j.total_bytes,j.stored_size,'
        'count(r.ordinal) AS completed_messages,'
        'coalesce(sum(r.byte_length),0) AS completed_bytes,'
        'coalesce(min(r.ordinal),1) AS first_ordinal,'
        'coalesce(max(r.ordinal),0) AS last_ordinal '
        'FROM archive_restore_jobs j LEFT JOIN archive_restore_receipts r '
        'ON r.manifest=j.manifest GROUP BY j.manifest ORDER BY j.manifest LIMIT ?',
        [_restoreReadMaxJobs + 1],
      );
      final result = <MailArchiveRestoreCheckpoint>[];
      var totalReceipts = 0;
      for (final row in rows) {
        cancellation?.throwIfCancelled();
        final manifest = row.read<String>('manifest');
        final planned = row.read<int>('planned');
        final totalBytes = row.read<int>('total_bytes');
        final completed = row.read<int>('completed_messages');
        final bytes = row.read<int>('completed_bytes');
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(manifest) ||
            row.read<int>('stored_size') != 192 ||
            planned < 0 ||
            planned > 100000 ||
            totalBytes < planned ||
            totalBytes > 4 * 1024 * 1024 * 1024 * 1024 ||
            completed < 0 ||
            completed > planned ||
            bytes < completed ||
            bytes > totalBytes ||
            row.read<int>('first_ordinal') < 1 ||
            row.read<int>('last_ordinal') > planned) {
          SqliteMailArchive._fail(MailProblemCode.storageFailure);
        }
        totalReceipts += completed;
        if (totalReceipts > _restoreReadMaxReceipts) {
          SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
        }
        result.add(
          MailArchiveRestoreCheckpoint(
            manifestSha256: manifest,
            planned: planned,
            totalBytes: totalBytes,
            completedMessages: completed,
            completedBytes: bytes,
          ),
        );
      }
      cancellation?.throwIfCancelled();
      trace.items = result.length;
      return List.unmodifiable(result);
    }),
  );

  /// A receipt authorizes skipping MIME parsing only after the destination's
  /// original, projection and search index are verified. Missing expected
  /// provenance returns null so normal import can atomically repair it. A
  /// damaged original, metadata or index is a failure, never a successful skip.
  Future<MailResult<MailArchiveRestoreReceipt?>> loadRestoreReceipt(
    MailArchiveRestorePlan plan,
    int ordinal, {
    MailCancellationToken? cancellation,
  }) => _run(
    MailArchiveOperation.loadRestoreReceipt,
    (trace) => _db.transaction(() async {
      cancellation?.throwIfCancelled();
      final item = _restoreItem(plan, ordinal);
      if (await _restoreJob(plan) == null) return null;
      final receipts = await _restoreReceiptRows(
        plan.manifestSha256,
        ordinal: ordinal,
      );
      if (receipts.isEmpty) return null;
      final receipt = receipts.single;
      _matchRestoreReceipt(receipt, item);
      cancellation?.throwIfCancelled();
      final original = await _original(item.id);
      if (original == null || original.length != item.byteLength) {
        SqliteMailArchive._fail(MailProblemCode.storageFailure);
      }
      final sizes = (await _rows(
        'SELECT ${_archiveSizeSql(_archiveMetadataColumns)} AS n, '
        '${_archiveSizeSql(_archiveMetadataColumns, bytes: true)} AS bytes '
        'FROM archive_items WHERE id=?',
        [item.id],
      )).single;
      if (_archiveExceedsSize(sizes, limits.maxMetadataCodeUnits)) {
        SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
      }
      final metadata = await _metadata(item.id);
      if (_archiveRowSize(metadata, _archiveMetadataColumns) >
          limits.maxMetadataCodeUnits) {
        SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
      }
      final fields = _verifiedFields(metadata);
      if (fields == null) {
        SqliteMailArchive._fail(MailProblemCode.storageFailure);
      }
      final indexSizes = await _rows(
        'SELECT ${_archiveSizeSql(_archiveIndexColumns)} AS n, '
        '${_archiveSizeSql(_archiveIndexColumns, bytes: true)} AS bytes '
        'FROM archive_fts WHERE id=? LIMIT 2',
        [item.id],
      );
      if (indexSizes.length != 1 ||
          _archiveExceedsSize(indexSizes.single, limits.maxIndexCodeUnits)) {
        SqliteMailArchive._fail(MailProblemCode.conflict);
      }
      final indexed = (await _rows(
        'SELECT subject,sender,recipients_to,recipients_cc,recipients_bcc,'
        'body,attachment_names,attachment_text FROM archive_fts WHERE id=? LIMIT 2',
        [item.id],
      )).single;
      if (_archiveRowSize(indexed, _archiveIndexColumns) >
              limits.maxIndexCodeUnits ||
          !_sameFields(indexed, fields)) {
        SqliteMailArchive._fail(MailProblemCode.conflict);
      }
      for (final origin in _normalizedOrigins(
        item.origins,
        cancellation: cancellation,
      )) {
        cancellation?.throwIfCancelled();
        final present = await _rows(
          'SELECT 1 FROM archive_origins WHERE message=? AND source=? AND folder=? '
          'AND source_message_id=?',
          [item.id, origin.source, origin.folder, origin.sourceMessageId],
        );
        if (present.isEmpty) return null;
      }
      cancellation?.throwIfCancelled();
      trace.items = 1;
      trace.bytes = original.length;
      return MailArchiveRestoreReceipt(
        ordinal: ordinal,
        byteLength: item.byteLength,
        indexWarning: receipt.read<int>('index_warning') != 0,
      );
    }),
  );

  /// Retain an original, its index, every manifest origin and its completion
  /// receipt in one transaction. Any cancellation/failure rolls all four back.
  /// The write retains [MailArchiveOperation.archive] diagnostics so existing
  /// completion observers still see confirmed archival work.
  Future<MailResult<MailArchiveImportResult>> archiveRestoreMessage(
    MailMessage message, {
    required MailArchiveRestorePlan plan,
    required int ordinal,
    bool indexAttachmentText = false,
    bool indexWarning = false,
    MailCancellationToken? cancellation,
  }) => _run(MailArchiveOperation.archive, (trace) async {
    cancellation?.throwIfCancelled();
    final item = _restoreItem(plan, ordinal);
    final identity = _restoreIdentity(plan);
    if (message.raw.length != item.byteLength ||
        message.raw.sha256 != item.id) {
      SqliteMailArchive._fail(MailProblemCode.conflict);
    }
    return _archiveMessageWithOrigins(
      message,
      origins: item.origins,
      trace: trace,
      indexAttachmentText: indexAttachmentText,
      cancellation: cancellation,
      afterArchive: (result) async {
        cancellation?.throwIfCancelled();
        if (await _restoreJob(plan) == null) {
          await _db.customStatement(
            'INSERT INTO archive_restore_jobs(manifest,planned,total_bytes) VALUES(?,?,?)',
            [plan.manifestSha256, identity.planned, identity.totalBytes],
          );
        }
        final previous = await _restoreReceiptRows(
          plan.manifestSha256,
          ordinal: ordinal,
        );
        if (previous.isNotEmpty) _matchRestoreReceipt(previous.single, item);
        final warning =
            indexWarning ||
            result.entry.indexTruncated ||
            result.entry.attachmentTextSkipped > 0 ||
            (previous.isNotEmpty &&
                previous.single.read<int>('index_warning') != 0);
        await _db.customStatement(
          'INSERT INTO archive_restore_receipts(manifest,ordinal,message,byte_length,index_warning) '
          'VALUES(?,?,?,?,?) ON CONFLICT(manifest,ordinal) DO UPDATE SET '
          'index_warning=excluded.index_warning',
          [
            plan.manifestSha256,
            ordinal,
            item.id,
            item.byteLength,
            warning ? 1 : 0,
          ],
        );
      },
    );
  });

  /// Delete progress metadata only. Originals, origins, archive dates and FTS
  /// remain unchanged. Cleanup is permitted under tighter reopened quotas so
  /// the owner can deliberately recover checkpoint capacity without eviction.
  Future<MailResult<MailUnit>> forgetRestoreCheckpoint(
    String manifestSha256, {
    MailCancellationToken? cancellation,
  }) => _run(
    MailArchiveOperation.forgetRestoreCheckpoint,
    (_) => _db.transaction(() async {
      _id(manifestSha256);
      cancellation?.throwIfCancelled();
      await _db.customStatement(
        'DELETE FROM archive_restore_jobs WHERE manifest=?',
        [manifestSha256],
      );
      await _fault?.call(MailArchiveCheckpoint.beforeCommit);
      cancellation?.throwIfCancelled();
      return MailUnit.value;
    }),
  );
}
