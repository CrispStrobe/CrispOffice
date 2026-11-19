part of 'archive_repository.dart';

extension _ArchiveExportPlanning on SqliteMailArchive {
  Future<MailArchiveExportPlan> _createExportPlan(
    MailArchiveSearchRequest request,
    MailArchiveExportLimits exportLimits,
    MailCancellationToken? cancellation,
    _ArchiveTrace trace,
  ) => _db.transaction(() async {
    cancellation?.throwIfCancelled();
    if (!exportLimits.isValid) {
      SqliteMailArchive._fail(MailProblemCode.invalidInput);
    }
    // A bulk export is all matching messages, independent of the visible page.
    final (where, values) = _where(request.page(offset: 0, limit: 1));
    final selected = 'FROM archive_items a WHERE $where';
    final sizes = (await _rows(
      'SELECT count(*) AS n, coalesce(sum(raw_size),0) AS bytes, '
      'coalesce(max(raw_size),0) AS largest, '
      'coalesce(sum(CASE WHEN raw_size<=0 OR length(raw)<>raw_size '
      'OR length(CAST(a.id AS BLOB))<>64 THEN 1 ELSE 0 END),0) AS invalid '
      '$selected',
      values,
    )).single;
    cancellation?.throwIfCancelled();
    final count = sizes.read<int>('n');
    if (sizes.read<int>('invalid') != 0) {
      SqliteMailArchive._fail(MailProblemCode.storageFailure);
    }
    if (count > exportLimits.maxMessages ||
        count > limits.maxMessages ||
        sizes.read<int>('bytes') > exportLimits.maxTotalBytes ||
        sizes.read<int>('largest') > exportLimits.maxMessageBytes ||
        sizes.read<int>('largest') > limits.maxMessageBytes) {
      SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
    }
    final originTail =
        'FROM archive_origins o JOIN archive_items a ON a.id=o.message '
        'WHERE $where';
    // Preflight byte lengths before materializing untrusted persisted TEXT.
    // SQLite length(TEXT) stops at NUL; BLOB lengths also cover that case.
    final originSizes = (await _rows(
      'SELECT count(*) AS n, '
      'coalesce(sum(length(CAST(o.source AS BLOB))+'
      'length(CAST(o.folder AS BLOB))+'
      'length(CAST(o.source_message_id AS BLOB))),0) AS bytes, '
      'coalesce(max(length(CAST(o.source AS BLOB))),0) AS source_bytes, '
      'coalesce(max(length(CAST(o.folder AS BLOB))),0) AS folder_bytes, '
      'coalesce(max(length(CAST(o.source_message_id AS BLOB))),0) AS id_bytes '
      '$originTail',
      values,
    )).single;
    cancellation?.throwIfCancelled();
    if (originSizes.read<int>('n') > exportLimits.maxOrigins ||
        originSizes.read<int>('n') > limits.maxOrigins ||
        originSizes.read<int>('bytes') > exportLimits.maxManifestBytes ||
        originSizes.read<int>('source_bytes') > 3 * 1024 ||
        originSizes.read<int>('folder_bytes') > 3 * 4096 ||
        originSizes.read<int>('id_bytes') > 3 * 1024) {
      SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
    }
    final originsById = <String, List<MailArchiveOrigin>>{};
    final originRows = await _rows(
      'SELECT o.message,o.source,o.folder,o.source_message_id $originTail '
      'ORDER BY o.message,o.source,o.folder,o.source_message_id',
      values,
    );
    for (final row in originRows) {
      cancellation?.throwIfCancelled();
      final id = row.read<String>('message');
      final source = row.read<String>('source');
      final folder = row.read<String>('folder');
      final sourceId = row.read<String>('source_message_id');
      _id(id);
      _label(source);
      _label(sourceId, empty: true);
      if (_folder(folder) != folder) {
        SqliteMailArchive._fail(MailProblemCode.storageFailure);
      }
      (originsById[id] ??= []).add(
        MailArchiveOrigin(
          source: source,
          folder: folder,
          sourceMessageId: sourceId,
        ),
      );
    }
    final rows = await _rows(
      'SELECT a.id,a.raw_size $selected ORDER BY ${_searchOrder(request.sort)}',
      values,
    );
    cancellation?.throwIfCancelled();
    final items = <MailArchiveExportItem>[];
    for (final row in rows) {
      cancellation?.throwIfCancelled();
      final id = row.read<String>('id');
      _id(id);
      final origins = originsById[id];
      if (origins == null || origins.isEmpty) {
        SqliteMailArchive._fail(MailProblemCode.storageFailure);
      }
      items.add(
        MailArchiveExportItem(
          id: id,
          byteLength: row.read<int>('raw_size'),
          origins: origins,
        ),
      );
    }
    final plan = MailArchiveExportPlan(
      profile: profile,
      createdAt: _clock().toUtc(),
      items: items,
    );
    // Shared canonical validation includes JSON escaping overhead and prevents
    // a plan that the exporter could not subsequently persist or resume.
    encodeMailArchiveExportManifest(plan, exportLimits);
    cancellation?.throwIfCancelled();
    trace.items = plan.items.length;
    trace.bytes = plan.totalBytes;
    return plan;
  });
}
