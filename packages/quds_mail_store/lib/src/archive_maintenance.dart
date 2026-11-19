part of 'archive_repository.dart';

extension MailArchiveMaintenance on SqliteMailArchive {
  void _maintenancePage(String? afterId, int limit) {
    if (afterId != null) _id(afterId);
    if (limit < 1 || limit > limits.maxPageSize) {
      SqliteMailArchive._fail(MailProblemCode.invalidInput);
    }
  }

  Future<List<QueryRow>> _maintenanceRows(String? afterId, int limit) => _rows(
    'SELECT id,raw_size,length(raw) AS actual,'
    'length(envelope)+length(index_data)+length(subject)+length(preview) AS metadata_size '
    'FROM archive_items WHERE id>? ORDER BY id LIMIT ?',
    [afterId ?? '', limit + 1],
  );

  Future<QueryRow> _metadata(String id) async => (await _rows(
    'SELECT $_maintenanceColumns FROM archive_items WHERE id=?',
    [id],
  )).single;

  static const _maintenanceColumns =
      'id,raw_size,envelope,index_data,metadata_hash,archived_at,'
      'sent_at,subject,preview,attachment_count,index_truncated,text_indexed,text_skipped,text_enabled';

  List<String>? _verifiedFields(QueryRow row) {
    try {
      final envelope = row.read<String>('envelope');
      final data = row.read<String>('index_data');
      final hash = SqliteMailArchive._metadataHash(
        envelope,
        data,
        row.read<int>('raw_size'),
        row.read<int>('archived_at'),
        row.read<int>('attachment_count'),
        row.read<int>('index_truncated') != 0,
        row.read<int>('text_indexed'),
        row.read<int>('text_skipped'),
        row.read<int>('text_enabled') != 0,
      );
      if (hash != row.read<String>('metadata_hash')) return null;
      final decoded = jsonDecode(data);
      if (decoded is! List<Object?> ||
          decoded.length != 8 ||
          decoded.any((value) => value is! String)) {
        return null;
      }
      final fields = decoded.cast<String>();
      final header = MailStoreCodec.decodeEnvelope(envelope);
      if (header.sentAt?.toUtc().millisecondsSinceEpoch !=
              row.readNullable<int>('sent_at') ||
          header.subject != row.read<String>('subject') ||
          archiveTextPrefix(fields[5], 240) != row.read<String>('preview')) {
        return null;
      }
      return fields;
    } on Object {
      return null;
    }
  }

  /// Read-only verification. Each page is a consistent snapshot, bounded by
  /// count and per-message byte limits. Call again with nextAfterId to continue.
  Future<MailResult<MailArchiveMaintenancePage>> verifyIntegrity({
    String? afterId,
    int limit = 50,
    MailCancellationToken? cancellation,
  }) => _run(
    MailArchiveOperation.verify,
    (trace) => _db.transaction(() async {
      _maintenancePage(afterId, limit);
      cancellation?.throwIfCancelled();
      final candidates = await _maintenanceRows(afterId, limit);
      final rows = candidates.take(limit).toList();
      final issues = <MailArchiveIntegrityIssue>[];
      for (final candidate in rows) {
        cancellation?.throwIfCancelled();
        final id = candidate.read<String>('id');
        void issue(MailArchiveIntegrityCode code) =>
            issues.add(MailArchiveIntegrityIssue(id: id, code: code));
        if (candidate.read<int>('raw_size') > limits.maxMessageBytes ||
            candidate.read<int>('metadata_size') >
                limits.maxMetadataCodeUnits) {
          issue(MailArchiveIntegrityCode.exceedsReadLimit);
          trace.items++;
          continue;
        }
        if (candidate.read<int>('actual') != candidate.read<int>('raw_size')) {
          issue(MailArchiveIntegrityCode.rawHashMismatch);
        } else {
          final bytes = (await _rows(
            'SELECT raw FROM archive_items WHERE id=?',
            [id],
          )).single.read<Uint8List>('raw');
          if (crypto.sha256.convert(bytes).toString() != id) {
            issue(MailArchiveIntegrityCode.rawHashMismatch);
          }
          trace.bytes += bytes.length;
        }
        final fields = _verifiedFields(await _metadata(id));
        if (fields == null) {
          issue(MailArchiveIntegrityCode.metadataHashMismatch);
        }
        final indexSizes = await _rows(
          'SELECT length(subject)+length(sender)+length(recipients_to)+length(recipients_cc)+'
          'length(recipients_bcc)+length(body)+length(attachment_names)+length(attachment_text) AS n '
          'FROM archive_fts WHERE id=? LIMIT 2',
          [id],
        );
        if (indexSizes.any(
          (row) => row.read<int>('n') > limits.maxIndexCodeUnits,
        )) {
          issue(MailArchiveIntegrityCode.indexMismatch);
          trace.items++;
          trace.emit(MailArchivePhase.progress);
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        final indexed = await _rows(
          'SELECT subject,sender,recipients_to,recipients_cc,recipients_bcc,'
          'body,attachment_names,attachment_text FROM archive_fts WHERE id=? LIMIT 2',
          [id],
        );
        if (indexed.isEmpty) {
          issue(MailArchiveIntegrityCode.missingIndex);
        } else if (indexed.length != 1 ||
            (fields != null && !_sameFields(indexed.single, fields))) {
          issue(MailArchiveIntegrityCode.indexMismatch);
        }
        if ((await _rows(
          'SELECT 1 FROM archive_origins WHERE message=? LIMIT 1',
          [id],
        )).isEmpty) {
          issue(MailArchiveIntegrityCode.missingOrigin);
        }
        trace.items++;
        trace.emit(MailArchivePhase.progress);
        await Future<void>.delayed(Duration.zero);
      }
      cancellation?.throwIfCancelled();
      return MailArchiveMaintenancePage(
        processed: rows.length,
        nextAfterId: rows.isEmpty ? afterId : rows.last.read<String>('id'),
        hasMore: candidates.length > limit,
        issues: issues,
      );
    }),
  );

  /// Replaces one bounded page atomically. Cancellation/failure preserves every
  /// previous index row in that page. Original MIME bytes are never rewritten.
  /// Without [codec], verified stored projections are reused. A supplied codec
  /// can refresh extraction and attachment policy from the original bytes.
  Future<MailResult<MailArchiveMaintenancePage>> rebuildIndex({
    String? afterId,
    int limit = 50,
    MailCancellationToken? cancellation,
    MailCodec? codec,
    bool? indexAttachmentText,
  }) => _run(
    MailArchiveOperation.rebuild,
    (trace) => _write(() async {
      _maintenancePage(afterId, limit);
      if (indexAttachmentText != null && codec == null) {
        SqliteMailArchive._fail(MailProblemCode.invalidInput);
      }
      final candidates = await _maintenanceRows(afterId, limit);
      final rows = candidates.take(limit).toList();
      final issues = <MailArchiveIntegrityIssue>[];
      if (afterId == null) {
        await _db.customStatement(
          'DELETE FROM archive_fts WHERE id NOT IN (SELECT id FROM archive_items)',
        );
      }
      for (final candidate in rows) {
        cancellation?.throwIfCancelled();
        final id = candidate.read<String>('id');
        MailArchiveIntegrityCode? issue;
        if (candidate.read<int>('raw_size') > limits.maxMessageBytes ||
            candidate.read<int>('metadata_size') >
                limits.maxMetadataCodeUnits) {
          issue = MailArchiveIntegrityCode.exceedsReadLimit;
        } else {
          final row = await _metadata(id);
          var fields = _verifiedFields(row);
          if (fields == null) {
            issue = MailArchiveIntegrityCode.metadataHashMismatch;
          } else {
            final bytes = (await _rows(
              'SELECT raw FROM archive_items WHERE id=?',
              [id],
            )).single.read<Uint8List>('raw');
            if (bytes.length != candidate.read<int>('raw_size') ||
                crypto.sha256.convert(bytes).toString() != id) {
              issue = MailArchiveIntegrityCode.rawHashMismatch;
            } else {
              trace.bytes += bytes.length;
              if (codec != null) {
                final parsed = codec.parse(
                  bytes,
                  budget: MailReadBudget(maxRawBytes: limits.maxMessageBytes),
                  cancellation: cancellation,
                );
                cancellation?.throwIfCancelled();
                final message = parsed.message;
                if (message == null ||
                    message.raw.sha256 != id ||
                    (parsed.status != MailParseStatus.complete &&
                        parsed.status != MailParseStatus.partial)) {
                  SqliteMailArchive._fail(MailProblemCode.invalidInput);
                }
                final enabled =
                    indexAttachmentText ?? row.read<int>('text_enabled') != 0;
                final projection = _projection(message, enabled);
                _projectionSize(projection);
                final hash = SqliteMailArchive._metadataHash(
                  projection.envelope,
                  projection.data,
                  message.raw.length,
                  row.read<int>('archived_at'),
                  projection.attachmentCount,
                  projection.truncated,
                  projection.textIndexed,
                  projection.textSkipped,
                  enabled,
                );
                await _db.customStatement(
                  'UPDATE archive_items SET envelope=?,index_data=?,metadata_hash=?,'
                  'stored_size=?,sent_at=?,subject=?,preview=?,attachment_count=?,index_truncated=?,'
                  'text_indexed=?,text_skipped=?,text_enabled=? WHERE id=?',
                  [
                    projection.envelope,
                    projection.data,
                    hash,
                    _storedSize(message.raw.length, projection),
                    message.envelope.sentAt?.toUtc().millisecondsSinceEpoch,
                    message.envelope.subject,
                    archiveTextPrefix(projection.fields[5], 240),
                    projection.attachmentCount,
                    projection.truncated ? 1 : 0,
                    projection.textIndexed,
                    projection.textSkipped,
                    enabled ? 1 : 0,
                    id,
                  ],
                );
                fields = projection.fields;
              }
              await _index(id, fields);
              await _fault?.call(MailArchiveCheckpoint.afterIndex);
            }
          }
        }
        if (issue != null) {
          issues.add(MailArchiveIntegrityIssue(id: id, code: issue));
        }
        trace.items++;
        trace.emit(MailArchivePhase.progress);
        await Future<void>.delayed(Duration.zero);
      }
      return MailArchiveMaintenancePage(
        processed: rows.length,
        nextAfterId: rows.isEmpty ? afterId : rows.last.read<String>('id'),
        hasMore: candidates.length > limit,
        issues: issues,
      );
    }, cancellation: cancellation),
  );
}

bool _sameFields(QueryRow row, List<String> fields) {
  const columns = [
    'subject',
    'sender',
    'recipients_to',
    'recipients_cc',
    'recipients_bcc',
    'body',
    'attachment_names',
    'attachment_text',
  ];
  for (var i = 0; i < columns.length; i++) {
    if (row.read<String>(columns[i]) != fields[i]) return false;
  }
  return true;
}
