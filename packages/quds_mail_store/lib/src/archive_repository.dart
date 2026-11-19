import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'archive_database.dart';
import 'archive_models.dart';
import 'archive_query.dart';
import 'archive_text.dart';
import 'codec.dart';
import 'errors.dart';

part 'archive_maintenance.dart';
part 'archive_settings.dart';

/// Durable, profile-scoped original messages, independent of live mail caches.
/// An injected executor must be exclusively owned for this object's lifetime.
/// The native opener enforces ownership. No network/provider is used here.
final class SqliteMailArchive {
  SqliteMailArchive._(
    this._db,
    this.profile,
    this.limits,
    this._clock,
    this.diagnostics,
    this._fault,
  );

  final MailArchiveDatabase _db;
  final MailProfileId profile;
  final MailArchiveLimits limits;
  final DateTime Function() _clock;
  final MailArchiveFaultInjector? _fault;
  MailArchiveDiagnostics? diagnostics;
  int _sequence = 0;
  int _active = 0;
  bool _closed = false;
  Completer<void>? _drained;
  Future<void>? _closing;

  static Future<MailResult<SqliteMailArchive>> open({
    required QueryExecutor executor,
    required MailProfileId profile,
    MailArchiveLimits limits = const MailArchiveLimits(),
    DateTime Function()? clock,
    MailArchiveDiagnostics? diagnostics,
    MailArchiveFaultInjector? faultInjector,
  }) async {
    final archive = SqliteMailArchive._(
      MailArchiveDatabase(executor),
      profile,
      limits,
      clock ?? DateTime.now,
      diagnostics,
      faultInjector,
    );
    final opened = await archive._run(MailArchiveOperation.open, (_) async {
      if (!limits.isValid) _fail(MailProblemCode.invalidInput);
      archive._label(profile.hostId);
      archive._label(profile.value);
      await archive._db.customSelect('SELECT 1').getSingle();
      await archive._db.transaction(() async {
        final rows = await archive._rows('SELECT * FROM archive_owner');
        if (rows.isEmpty) {
          await archive._db.customStatement(
            'INSERT INTO archive_owner(singleton,host_id,profile_id) VALUES(1,?,?)',
            [profile.hostId, profile.value],
          );
        } else if (rows.single.read<String>('host_id') != profile.hostId ||
            rows.single.read<String>('profile_id') != profile.value) {
          _fail(MailProblemCode.permissionDenied);
        }
      });
      return archive;
    });
    if (opened is MailFailure<SqliteMailArchive>) {
      try {
        await archive.close();
      } on Object {
        // Preserve the original failure, never a cleanup/database message.
      }
    }
    return opened;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    final trace = _ArchiveTrace(
      ++_sequence,
      MailArchiveOperation.close,
      diagnostics,
    );
    trace.emit(MailArchivePhase.started);
    try {
      if (_active > 0) {
        _drained ??= Completer<void>();
        await _drained!.future;
      }
      await _db.close();
      trace.emit(MailArchivePhase.completed);
    } on Object catch (error) {
      final problem = mailStoreProblem(error);
      trace.emit(MailArchivePhase.failed, problem: problem.code);
      throw MailStoreStorageException(problem.code);
    }
  }

  static Never _fail(MailProblemCode code) =>
      throw MailStoreStorageException(code);

  Future<MailResult<T>> _run<T>(
    MailArchiveOperation operation,
    Future<T> Function(_ArchiveTrace trace) body,
  ) async {
    final trace = _ArchiveTrace(++_sequence, operation, diagnostics);
    trace.emit(MailArchivePhase.started);
    if (_closed) {
      trace.emit(MailArchivePhase.failed, problem: MailProblemCode.unavailable);
      return const MailFailure(MailProblem(MailProblemCode.unavailable));
    }
    _active++;
    try {
      final value = await body(trace);
      trace.emit(MailArchivePhase.completed);
      return MailSuccess(value);
    } on Object catch (error) {
      final problem = error is MailArchiveQueryException
          ? const MailProblem(MailProblemCode.invalidInput)
          : mailStoreProblem(error);
      trace.emit(MailArchivePhase.failed, problem: problem.code);
      return MailFailure(problem);
    } finally {
      _active--;
      if (_active == 0 && _drained != null && !_drained!.isCompleted) {
        _drained!.complete();
      }
    }
  }

  Future<T> _write<T>(
    Future<T> Function() body, {
    MailCancellationToken? cancellation,
    MailOperationLease? lease,
  }) => _db.transaction(() async {
    cancellation?.throwIfCancelled();
    lease?.checkCurrent();
    final value = await body();
    await _fault?.call(MailArchiveCheckpoint.beforeCommit);
    cancellation?.throwIfCancelled();
    await _quota();
    cancellation?.throwIfCancelled();
    lease?.checkCurrent();
    return value;
  });

  Future<List<QueryRow>> _rows(String sql, [List<Object?> values = const []]) =>
      _db
          .customSelect(
            sql,
            variables: [
              for (final value in values)
                switch (value) {
                  final String value => Variable<String>(value),
                  final int value => Variable<int>(value),
                  final Uint8List value => Variable<Uint8List>(value),
                  null => const Variable<String>(null),
                  _ => throw const MailStoreStorageException(
                    MailProblemCode.invalidInput,
                  ),
                },
            ],
          )
          .get();

  void _label(String value, {int max = 1024, bool empty = false}) {
    if ((!empty && value.trim().isEmpty) ||
        value.length > max ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      _fail(MailProblemCode.invalidInput);
    }
  }

  void _id(String id) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(id)) {
      _fail(MailProblemCode.invalidInput);
    }
  }

  String _folder(String input) {
    _label(input, max: 4096);
    final parts = input.replaceAll('\\', '/').split('/');
    if (parts.any((part) => part == '.' || part == '..')) {
      _fail(MailProblemCode.invalidInput);
    }
    return '/${parts.where((part) => part.isNotEmpty).join('/')}';
  }

  Future<void> _quota() async {
    final row = (await _rows('SELECT * FROM archive_totals')).single;
    if (row.read<int>('messages') > limits.maxMessages ||
        row.read<int>('origins') > limits.maxOrigins ||
        row.read<int>('logical_bytes') > limits.maxArchiveBytes) {
      _fail(MailProblemCode.quotaExceeded);
    }
  }

  /// Copies are committed together with their index and provenance. Repeated
  /// bytes share one immutable record; a reused Message-ID never deduplicates
  /// different content. No source mail is removed or changed.
  Future<MailResult<MailArchiveImportResult>> archiveMessage(
    MailMessage message, {
    required MailArchiveOrigin origin,
    bool indexAttachmentText = false,
    MailCancellationToken? cancellation,
    MailOperationLease? lease,
  }) => _run(MailArchiveOperation.archive, (trace) async {
    cancellation?.throwIfCancelled();
    lease?.checkCurrent();
    _label(origin.source);
    _label(origin.sourceMessageId, empty: true);
    final folder = _folder(origin.folder);
    if (message.raw.length == 0) _fail(MailProblemCode.invalidInput);
    if (message.raw.length > limits.maxMessageBytes) {
      _fail(MailProblemCode.quotaExceeded);
    }
    final id = message.raw.sha256;
    return _write(
      () async {
        final existing = await _rows(
          'SELECT id FROM archive_items WHERE id=?',
          [id],
        );
        final duplicate = existing.isNotEmpty;
        if (!duplicate) {
          final projection = _projection(message, indexAttachmentText);
          _projectionSize(projection);
          final archivedAt = _clock().toUtc().millisecondsSinceEpoch;
          final metadataHash = _metadataHash(
            projection.envelope,
            projection.data,
            message.raw.length,
            archivedAt,
            projection.attachmentCount,
            projection.truncated,
            projection.textIndexed,
            projection.textSkipped,
            indexAttachmentText,
          );
          final storedSize = _storedSize(message.raw.length, projection);
          await _db.customStatement(
            'INSERT INTO archive_items(id,raw,raw_size,envelope,index_data,metadata_hash,'
            'stored_size,archived_at,sent_at,subject,preview,attachment_count,'
            'index_truncated,text_indexed,text_skipped,text_enabled) '
            'VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
            [
              id,
              message.raw.bytes,
              message.raw.length,
              projection.envelope,
              projection.data,
              metadataHash,
              storedSize,
              archivedAt,
              message.envelope.sentAt?.toUtc().millisecondsSinceEpoch,
              message.envelope.subject,
              archiveTextPrefix(projection.fields[5], 240),
              projection.attachmentCount,
              projection.truncated ? 1 : 0,
              projection.textIndexed,
              projection.textSkipped,
              indexAttachmentText ? 1 : 0,
            ],
          );
          await _fault?.call(MailArchiveCheckpoint.afterContent);
          trace.bytes = message.raw.length;
          trace.emit(MailArchivePhase.progress);
          cancellation?.throwIfCancelled();
          await _index(id, projection.fields);
          await _fault?.call(MailArchiveCheckpoint.afterIndex);
        } else {
          // A corrupt existing copy must never turn an import into a false
          // successful duplicate. Keep the original row for explicit diagnosis.
          final original = await _original(id);
          if (original == null) _fail(MailProblemCode.storageFailure);
          final size = (await _rows(
            'SELECT ${_archiveSizeSql(_archiveMetadataColumns)} AS n, '
            '${_archiveSizeSql(_archiveMetadataColumns, bytes: true)} AS bytes '
            'FROM archive_items WHERE id=?',
            [id],
          )).single;
          if (_archiveExceedsSize(size, limits.maxMetadataCodeUnits)) {
            _fail(MailProblemCode.quotaExceeded);
          }
          final metadata = await _metadata(id);
          if (_archiveRowSize(metadata, _archiveMetadataColumns) >
              limits.maxMetadataCodeUnits) {
            _fail(MailProblemCode.quotaExceeded);
          }
          final fields = _verifiedFields(metadata);
          if (fields == null) _fail(MailProblemCode.storageFailure);
          // Retrying an interrupted import repairs an absent/stale index from
          // its existing, integrity-checked projection, without changing MIME.
          await _index(id, fields);
          await _fault?.call(MailArchiveCheckpoint.afterIndex);
        }
        cancellation?.throwIfCancelled();
        final before = await _rows(
          'SELECT 1 FROM archive_origins WHERE message=? AND source=? AND folder=? '
          'AND source_message_id=?',
          [id, origin.source, folder, origin.sourceMessageId],
        );
        if (before.isEmpty) {
          await _db.customStatement(
            'INSERT INTO archive_origins(message,source,folder,source_message_id,stored_size) '
            'VALUES(?,?,?,?,?)',
            [
              id,
              origin.source,
              folder,
              origin.sourceMessageId,
              utf8
                      .encode(origin.source + folder + origin.sourceMessageId)
                      .length +
                  128,
            ],
          );
        }
        final row = (await _rows(
          'SELECT $_entryColumns FROM archive_items WHERE id=?',
          [id],
        )).single;
        trace.items = 1;
        return MailArchiveImportResult(
          entry: _entry(row),
          duplicate: duplicate,
          originAdded: before.isEmpty,
        );
      },
      cancellation: cancellation,
      lease: lease,
    );
  });

  _ArchiveProjection _projection(MailMessage message, bool attachmentText) {
    final envelope = message.envelope;
    if (envelope.references.length > 1024) _fail(MailProblemCode.quotaExceeded);
    var metadataSize = envelope.subject.length;
    for (final value in [
      envelope.messageId,
      envelope.inReplyTo,
      ...envelope.references,
    ]) {
      metadataSize += value?.length ?? 0;
    }
    for (final group in [
      envelope.from,
      envelope.to,
      envelope.cc,
      envelope.bcc,
      envelope.replyTo,
    ]) {
      if (group.length > 1024) _fail(MailProblemCode.quotaExceeded);
      for (final address in group) {
        metadataSize +=
            address.address.length + (address.displayName?.length ?? 0);
      }
    }
    if (metadataSize > limits.maxMetadataCodeUnits ||
        message.attachments.length > 1024) {
      _fail(MailProblemCode.quotaExceeded);
    }
    final encodedEnvelope = MailStoreCodec.encodeEnvelope(envelope);
    if (encodedEnvelope.length > limits.maxMetadataCodeUnits) {
      _fail(MailProblemCode.quotaExceeded);
    }
    final budget = _ArchiveTextBudget(limits.maxIndexCodeUnits);
    String addresses(List<MailAddress> values) => budget.join([
      for (final address in values) ...[
        address.displayName ?? '',
        address.address,
      ],
    ]);
    final fields = <String>[
      budget.take(envelope.subject),
      addresses(envelope.from),
      addresses(envelope.to),
      addresses(envelope.cc),
      addresses(envelope.bcc),
    ];
    final plain = message.body.plainText;
    final html = message.body.html;
    if (plain != null) {
      fields.add(budget.take(plain));
    } else if (html != null) {
      final bounded = archiveTextPrefix(html, limits.maxMetadataCodeUnits);
      budget.truncated |= bounded.length != html.length;
      fields.add(budget.take(archiveHtmlText(bounded)));
    } else {
      fields.add('');
    }
    fields.add(
      budget.join(message.attachments.map((part) => part.displayName)),
    );
    final text = StringBuffer();
    var indexed = 0;
    var skipped = 0;
    var decodedWork = 0;
    for (final part in message.attachments) {
      final type = part.mediaType.split(';').first.trim().toLowerCase();
      if (!attachmentText ||
          !const {
            'text/plain',
            'text/csv',
            'text/tab-separated-values',
            'text/html',
            'text/xml',
            'application/xml',
            'application/json',
          }.contains(type) ||
          part.content.length > limits.maxAttachmentTextBytes ||
          decodedWork + part.content.length > limits.maxAttachmentTextBytes ||
          budget.remaining == 0) {
        skipped++;
        continue;
      }
      decodedWork += part.content.length;
      try {
        var value = decodeArchiveTextAttachment(part.content.bytes);
        if (type == 'text/html') value = archiveHtmlText(value);
        if (text.isNotEmpty) text.write(budget.take(' '));
        text.write(budget.take(value));
        indexed++;
      } on FormatException {
        skipped++;
      }
    }
    fields.add(text.toString());
    return _ArchiveProjection(
      encodedEnvelope,
      envelope.subject,
      fields,
      message.attachments.length,
      budget.truncated,
      indexed,
      skipped,
    );
  }

  static String _metadataHash(
    String envelope,
    String data,
    int rawSize,
    int archivedAt,
    int attachments,
    bool truncated,
    int indexed,
    int skipped,
    bool enabled,
  ) => crypto.sha256
      .convert(
        utf8.encode(
          jsonEncode([
            envelope,
            data,
            rawSize,
            archivedAt,
            attachments,
            truncated,
            indexed,
            skipped,
            enabled,
          ]),
        ),
      )
      .toString();

  void _projectionSize(_ArchiveProjection projection) {
    if (projection.envelope.length +
            projection.data.length +
            projection.subject.length +
            archiveTextPrefix(projection.fields[5], 240).length >
        limits.maxMetadataCodeUnits) {
      _fail(MailProblemCode.quotaExceeded);
    }
  }

  int _storedSize(int rawSize, _ArchiveProjection projection) =>
      rawSize +
      2 * utf8.encode(projection.envelope).length +
      2 * utf8.encode(projection.data).length +
      512;

  Future<void> _index(String id, List<String> fields) async {
    // Reusing a verified projection under tighter reopened limits must still
    // honor the current index budget before deleting the existing index row.
    if (fields.fold<int>(0, (total, field) => total + field.length) >
        limits.maxIndexCodeUnits) {
      _fail(MailProblemCode.quotaExceeded);
    }
    await _db.customStatement('DELETE FROM archive_fts WHERE id=?', [id]);
    await _db.customStatement(
      'INSERT INTO archive_fts(id,subject,sender,recipients_to,recipients_cc,'
      'recipients_bcc,body,attachment_names,attachment_text) VALUES(?,?,?,?,?,?,?,?,?)',
      [id, ...fields],
    );
  }

  static const _entryColumns =
      'id,envelope,archived_at,raw_size,attachment_count,'
      'index_truncated,text_indexed,text_skipped';

  MailArchiveEntry _entry(QueryRow row) => MailArchiveEntry(
    id: row.read<String>('id'),
    envelope: MailStoreCodec.decodeEnvelope(row.read<String>('envelope')),
    archivedAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('archived_at'),
      isUtc: true,
    ),
    byteLength: row.read<int>('raw_size'),
    attachmentCount: row.read<int>('attachment_count'),
    indexTruncated: row.read<int>('index_truncated') != 0,
    attachmentTextIndexed: row.read<int>('text_indexed'),
    attachmentTextSkipped: row.read<int>('text_skipped'),
  );

  (String, List<Object?>) _where(MailArchiveSearchRequest request) {
    if (request.limit < 1 ||
        request.limit > limits.maxPageSize ||
        request.offset < 0 ||
        request.offset > limits.maxMessages ||
        (request.minBytes != null && request.minBytes! < 0) ||
        (request.maxBytes != null && request.maxBytes! < 0) ||
        (request.minBytes != null &&
            request.maxBytes != null &&
            request.minBytes! > request.maxBytes!)) {
      _fail(MailProblemCode.invalidInput);
    }
    final parsed = MailArchiveQuery.parse(request.query);
    final conditions = <String>[parsed.predicateSql];
    final values = <Object?>[...parsed.parameters];
    for (final date in [
      ('sent_at', request.sentSince, request.sentBefore),
      ('archived_at', request.archivedSince, request.archivedBefore),
    ]) {
      if (date.$2 != null && date.$3 != null && !date.$2!.isBefore(date.$3!)) {
        _fail(MailProblemCode.invalidInput);
      }
      if (date.$2 != null) {
        conditions.add('a.${date.$1}>=?');
        values.add(date.$2!.toUtc().millisecondsSinceEpoch);
      }
      if (date.$3 != null) {
        conditions.add('a.${date.$1}<?');
        values.add(date.$3!.toUtc().millisecondsSinceEpoch);
      }
    }
    if (request.minBytes != null) {
      conditions.add('a.raw_size>=?');
      values.add(request.minBytes);
    }
    if (request.maxBytes != null) {
      conditions.add('a.raw_size<=?');
      values.add(request.maxBytes);
    }
    if (request.hasAttachments != null) {
      conditions.add(
        request.hasAttachments!
            ? 'a.attachment_count>0'
            : 'a.attachment_count=0',
      );
    }
    if (request.source != null || request.folder != null) {
      final origin = <String>['o.message=a.id'];
      if (request.source != null) {
        _label(request.source!);
        origin.add('o.source=?');
        values.add(request.source);
      }
      if (request.folder != null) {
        final folder = _folder(request.folder!);
        if (request.includeSubfolders) {
          origin.add('(o.folder=? OR instr(o.folder,?)=1)');
          values.addAll([folder, folder == '/' ? '/' : '$folder/']);
        } else {
          origin.add('o.folder=?');
          values.add(folder);
        }
      }
      conditions.add(
        'EXISTS (SELECT 1 FROM archive_origins o WHERE ${origin.join(' AND ')})',
      );
    }
    return (conditions.map((value) => '($value)').join(' AND '), values);
  }

  Future<MailResult<MailArchiveSearchPage>> search(
    MailArchiveSearchRequest request,
  ) => _run(
    MailArchiveOperation.search,
    (trace) => _db.transaction(() async {
      final (where, values) = _where(request);
      final order = switch (request.sort) {
        MailArchiveSort.archivedNewest => 'a.archived_at DESC,a.id',
        MailArchiveSort.sentNewest => 'a.sent_at IS NULL,a.sent_at DESC,a.id',
        MailArchiveSort.sentOldest => 'a.sent_at IS NULL,a.sent_at,a.id',
        MailArchiveSort.subject => 'a.subject COLLATE NOCASE,a.id',
      };
      final total = (await _rows(
        'SELECT count(*) AS n FROM archive_items a WHERE $where',
        values,
      )).single.read<int>('n');
      final tail =
          'FROM archive_items a WHERE $where ORDER BY $order LIMIT ? OFFSET ?';
      final args = <Object?>[...values, request.limit, request.offset];
      final sizes = await _rows(
        'SELECT ${_archiveSizeSql(const ['envelope', 'preview'])} AS n, '
        '${_archiveSizeSql(const ['envelope', 'preview'], bytes: true)} AS bytes $tail',
        args,
      );
      if (_archivePageExceedsSize(sizes, limits.maxMetadataCodeUnits)) {
        _fail(MailProblemCode.quotaExceeded);
      }
      final rows = await _rows('SELECT $_entryColumns,preview $tail', args);
      if (rows.fold<int>(
            0,
            (total, row) =>
                total + _archiveRowSize(row, const ['envelope', 'preview']),
          ) >
          limits.maxMetadataCodeUnits) {
        _fail(MailProblemCode.quotaExceeded);
      }
      trace.items = rows.length;
      return MailArchiveSearchPage(
        hits: [
          for (final row in rows)
            MailArchiveSearchHit(
              entry: _entry(row),
              preview: row.read<String>('preview'),
            ),
        ],
        total: total,
        offset: request.offset,
      );
    }),
  );

  Future<MailBytes?> _original(String id) async {
    _id(id);
    final rows = await _rows(
      'SELECT raw_size,length(raw) AS actual FROM archive_items WHERE id=?',
      [id],
    );
    if (rows.isEmpty) return null;
    final size = rows.single.read<int>('raw_size');
    if (size != rows.single.read<int>('actual') || size < 0) {
      _fail(MailProblemCode.storageFailure);
    }
    if (size > limits.maxMessageBytes) _fail(MailProblemCode.quotaExceeded);
    final raw = MailBytes(
      (await _rows('SELECT raw FROM archive_items WHERE id=?', [
        id,
      ])).single.read<Uint8List>('raw'),
    );
    if (raw.sha256 != id) _fail(MailProblemCode.storageFailure);
    return raw;
  }

  Future<MailResult<MailBytes?>> loadOriginal(String id) => _run(
    MailArchiveOperation.load,
    (trace) => _db.transaction(() async {
      final result = await _original(id);
      trace.items = result == null ? 0 : 1;
      trace.bytes = result?.length ?? 0;
      return result;
    }),
  );

  Future<MailResult<List<MailArchiveOrigin>>> listOrigins(
    String id, {
    int limit = 200,
    int offset = 0,
  }) => _run(
    MailArchiveOperation.origins,
    (trace) => _db.transaction(() async {
      _id(id);
      if (limit < 1 ||
          limit > limits.maxPageSize ||
          offset < 0 ||
          offset > limits.maxOrigins) {
        _fail(MailProblemCode.invalidInput);
      }
      final originSizes = await _rows(
        'SELECT ${_archiveSizeSql(_archiveOriginColumns)} AS n, '
        '${_archiveSizeSql(_archiveOriginColumns, bytes: true)} AS bytes FROM archive_origins '
        'WHERE message=? ORDER BY source,folder,source_message_id LIMIT ? OFFSET ?',
        [id, limit, offset],
      );
      if (_archivePageExceedsSize(originSizes, limits.maxMetadataCodeUnits)) {
        _fail(MailProblemCode.quotaExceeded);
      }
      final rows = await _rows(
        'SELECT source,folder,source_message_id FROM archive_origins '
        'WHERE message=? ORDER BY source,folder,source_message_id LIMIT ? OFFSET ?',
        [id, limit, offset],
      );
      if (rows.fold<int>(
            0,
            (total, row) => total + _archiveRowSize(row, _archiveOriginColumns),
          ) >
          limits.maxMetadataCodeUnits) {
        _fail(MailProblemCode.quotaExceeded);
      }
      trace.items = rows.length;
      return List.unmodifiable([
        for (final row in rows)
          MailArchiveOrigin(
            source: row.read<String>('source'),
            folder: row.read<String>('folder'),
            sourceMessageId: row.read<String>('source_message_id'),
          ),
      ]);
    }),
  );

  Future<MailResult<MailArchiveStats>> statistics() => _run(
    MailArchiveOperation.statistics,
    (_) => _db.transaction(() async {
      final totals = (await _rows('SELECT * FROM archive_totals')).single;
      final indexed = (await _rows(
        'SELECT count(DISTINCT f.id) AS n FROM archive_fts f '
        'JOIN archive_items a ON a.id=f.id',
      )).single.read<int>('n');
      return MailArchiveStats(
        messages: totals.read<int>('messages'),
        rawBytes: totals.read<int>('raw_bytes'),
        indexedMessages: indexed,
        origins: totals.read<int>('origins'),
      );
    }),
  );
}

// Only fixed internal column names enter these SQL expressions. SQLite's TEXT
// length stops at NUL and counts code points, so it is not an allocation guard.
// UTF-8 needs at most three bytes per UTF-16 code unit. A byte preflight bounds
// decoding without rejecting valid Arabic/CJK/astral text, followed by the exact
// Dart code-unit check before parsing or returning any hydrated text.
const _archiveMetadataColumns = [
  'envelope',
  'index_data',
  'subject',
  'preview',
];
const _archiveOriginColumns = ['source', 'folder', 'source_message_id'];
const _archiveIndexColumns = [
  'subject',
  'sender',
  'recipients_to',
  'recipients_cc',
  'recipients_bcc',
  'body',
  'attachment_names',
  'attachment_text',
];

String _archiveSizeSql(List<String> columns, {bool bytes = false}) => columns
    .map(
      (column) => bytes ? 'length(CAST($column AS BLOB))' : 'length($column)',
    )
    .join('+');

int _archiveRowSize(QueryRow row, List<String> columns) =>
    columns.fold(0, (total, column) => total + row.read<String>(column).length);

bool _archiveExceedsSize(QueryRow row, int limit) =>
    row.read<int>('n') > limit || row.read<int>('bytes') > 3 * limit;

bool _archivePageExceedsSize(List<QueryRow> rows, int limit) =>
    rows.fold<int>(0, (total, row) => total + row.read<int>('n')) > limit ||
    rows.fold<int>(0, (total, row) => total + row.read<int>('bytes')) >
        3 * limit;

final class _ArchiveProjection {
  _ArchiveProjection(
    this.envelope,
    this.subject,
    this.fields,
    this.attachmentCount,
    this.truncated,
    this.textIndexed,
    this.textSkipped,
  );
  final String envelope;
  final String subject;
  final List<String> fields;
  final int attachmentCount;
  final bool truncated;
  final int textIndexed;
  final int textSkipped;
  String get data => jsonEncode(fields);
}

final class _ArchiveTextBudget {
  _ArchiveTextBudget(this.remaining);
  int remaining;
  bool truncated = false;
  String take(String value) {
    final result = archiveTextPrefix(value, remaining);
    truncated |= result.length != value.length;
    remaining -= result.length;
    return result;
  }

  String join(Iterable<String> parts) {
    final out = StringBuffer();
    for (final value in parts) {
      if (out.isNotEmpty) out.write(take(' '));
      out.write(take(value));
    }
    return out.toString();
  }
}

final class _ArchiveTrace {
  _ArchiveTrace(this.id, this.operation, this.diagnostics);
  final int id;
  final MailArchiveOperation operation;
  final MailArchiveDiagnostics? diagnostics;
  final Stopwatch watch = Stopwatch()..start();
  int items = 0;
  int bytes = 0;
  void emit(MailArchivePhase phase, {MailProblemCode? problem}) {
    final target = diagnostics;
    if (target == null ||
        (!target.verbose && phase != MailArchivePhase.failed)) {
      return;
    }
    try {
      target.sink(
        MailArchiveDiagnostic(
          operationId: id,
          operation: operation,
          phase: phase,
          elapsedMicroseconds: watch.elapsedMicroseconds,
          items: items,
          bytes: bytes,
          problem: problem,
        ),
      );
    } on Object {
      // An observational logger cannot break archival correctness or cleanup.
    }
  }
}
