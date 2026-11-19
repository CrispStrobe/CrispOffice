part of 'archive_repository.dart';

extension MailArchiveSettings on SqliteMailArchive {
  Future<void> _settingsBudget(String table, int limit) async {
    // Table is selected only from fixed internal call sites below.
    final key = table == 'archive_profiles' ? 'id' : 'name';
    final sizes = await _rows(
      'SELECT length(data) AS n,length(CAST(data AS BLOB)) AS bytes, '
      'length($key) AS key_length,length(CAST($key AS BLOB)) AS key_bytes '
      'FROM $table LIMIT ?',
      [limit + 1],
    );
    if (sizes.length > limit ||
        sizes.any(
          (row) =>
              _archiveExceedsSize(row, 16384) ||
              row.read<int>('key_length') > 1024 ||
              row.read<int>('key_bytes') > 3 * 1024,
        )) {
      SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
    }
  }

  Future<MailResult<MailUnit>> saveSearch(MailArchiveSavedSearch search) =>
      _run(
        MailArchiveOperation.saveSearch,
        (_) => _write(() async {
          _label(search.name, max: 256);
          _where(search.request);
          final data = jsonEncode(_searchJson(search.request));
          await _db.customStatement(
            'INSERT INTO archive_saved_searches(name,data) VALUES(?,?) '
            'ON CONFLICT(name) DO UPDATE SET data=excluded.data',
            [search.name, data],
          );
          final count = (await _rows(
            'SELECT count(*) AS n FROM archive_saved_searches',
          )).single.read<int>('n');
          if (count > limits.maxSavedSearches) {
            SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
          }
          return MailUnit.value;
        }),
      );

  Future<MailResult<List<MailArchiveSavedSearch>>> listSearches() => _run(
    MailArchiveOperation.listSearches,
    (trace) => _db.transaction(() async {
      await _settingsBudget('archive_saved_searches', limits.maxSavedSearches);
      final rows = await _rows(
        'SELECT name,data FROM archive_saved_searches ORDER BY name LIMIT ?',
        [limits.maxSavedSearches + 1],
      );
      if (rows.length > limits.maxSavedSearches) {
        SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
      }
      final result = <MailArchiveSavedSearch>[];
      for (final row in rows) {
        final data = row.read<String>('data');
        if (data.length > 16384 || row.read<String>('name').length > 256) {
          SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
        }
        final request = _decodeSearch(data);
        _where(request);
        result.add(
          MailArchiveSavedSearch(
            name: row.read<String>('name'),
            request: request,
          ),
        );
      }
      trace.items = result.length;
      return List.unmodifiable(result);
    }),
  );

  Future<MailResult<MailUnit>> removeSearch(String name) => _run(
    MailArchiveOperation.removeSearch,
    (_) => _write(() async {
      _label(name, max: 256);
      await _db.customStatement(
        'DELETE FROM archive_saved_searches WHERE name=?',
        [name],
      );
      return MailUnit.value;
    }),
  );

  Future<MailResult<MailUnit>> saveProfile(MailArchiveProfile profile) => _run(
    MailArchiveOperation.saveProfile,
    (_) => _write(() async {
      _label(profile.id);
      _label(profile.name, max: 256);
      _label(profile.source);
      final folder = _folder(profile.folder);
      final data = jsonEncode({
        'version': 1,
        'name': profile.name,
        'source': profile.source,
        'kind': profile.kind.name,
        'folder': folder,
        'includeSubfolders': profile.includeSubfolders,
        'indexAttachmentText': profile.indexAttachmentText,
      });
      await _db.customStatement(
        'INSERT INTO archive_profiles(id,data) VALUES(?,?) '
        'ON CONFLICT(id) DO UPDATE SET data=excluded.data',
        [profile.id, data],
      );
      final count = (await _rows(
        'SELECT count(*) AS n FROM archive_profiles',
      )).single.read<int>('n');
      if (count > limits.maxProfiles) {
        SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
      }
      return MailUnit.value;
    }),
  );

  Future<MailResult<List<MailArchiveProfile>>> listProfiles() => _run(
    MailArchiveOperation.listProfiles,
    (trace) => _db.transaction(() async {
      await _settingsBudget('archive_profiles', limits.maxProfiles);
      final rows = await _rows(
        'SELECT id,data FROM archive_profiles ORDER BY id LIMIT ?',
        [limits.maxProfiles + 1],
      );
      if (rows.length > limits.maxProfiles) {
        SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
      }
      final result = <MailArchiveProfile>[];
      for (final row in rows) {
        final encoded = row.read<String>('data');
        if (encoded.length > 16384 || row.read<String>('id').length > 1024) {
          SqliteMailArchive._fail(MailProblemCode.quotaExceeded);
        }
        final data = _archiveObject(jsonDecode(encoded));
        _archiveVersion(data);
        final profile = MailArchiveProfile(
          id: row.read<String>('id'),
          name: _archiveString(data['name']),
          source: _archiveString(data['source']),
          kind: MailArchiveProfileKind.values.byName(
            _archiveString(data['kind']),
          ),
          folder: _archiveString(data['folder']),
          includeSubfolders: _archiveBool(data['includeSubfolders']),
          indexAttachmentText: _archiveBool(data['indexAttachmentText']),
        );
        _label(profile.id);
        _label(profile.name, max: 256);
        _label(profile.source);
        _folder(profile.folder);
        result.add(profile);
      }
      trace.items = result.length;
      return List.unmodifiable(result);
    }),
  );

  /// A profile is configuration only; all messages and provenance are retained.
  Future<MailResult<MailUnit>> removeProfile(String id) => _run(
    MailArchiveOperation.removeProfile,
    (_) => _write(() async {
      _label(id);
      await _db.customStatement('DELETE FROM archive_profiles WHERE id=?', [
        id,
      ]);
      return MailUnit.value;
    }),
  );
}

Map<String, Object?> _searchJson(MailArchiveSearchRequest request) => {
  'version': 1,
  'query': request.query,
  'source': request.source,
  'folder': request.folder,
  'includeSubfolders': request.includeSubfolders,
  'sentSince': request.sentSince?.toUtc().millisecondsSinceEpoch,
  'sentBefore': request.sentBefore?.toUtc().millisecondsSinceEpoch,
  'archivedSince': request.archivedSince?.toUtc().millisecondsSinceEpoch,
  'archivedBefore': request.archivedBefore?.toUtc().millisecondsSinceEpoch,
  'minBytes': request.minBytes,
  'maxBytes': request.maxBytes,
  'hasAttachments': request.hasAttachments,
  'sort': request.sort.name,
  'limit': request.limit,
};

MailArchiveSearchRequest _decodeSearch(String encoded) {
  final data = _archiveObject(jsonDecode(encoded));
  _archiveVersion(data);
  DateTime? date(String name) {
    final value = _archiveNullableInt(data[name]);
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  return MailArchiveSearchRequest(
    query: _archiveString(data['query']),
    source: data['source'] == null ? null : _archiveString(data['source']),
    folder: data['folder'] == null ? null : _archiveString(data['folder']),
    includeSubfolders: _archiveBool(data['includeSubfolders']),
    sentSince: date('sentSince'),
    sentBefore: date('sentBefore'),
    archivedSince: date('archivedSince'),
    archivedBefore: date('archivedBefore'),
    minBytes: _archiveNullableInt(data['minBytes']),
    maxBytes: _archiveNullableInt(data['maxBytes']),
    hasAttachments: data['hasAttachments'] == null
        ? null
        : _archiveBool(data['hasAttachments']),
    sort: MailArchiveSort.values.byName(_archiveString(data['sort'])),
    limit: _archiveNullableInt(data['limit']) ?? 50,
  );
}

Map<String, Object?> _archiveObject(Object? value) {
  if (value is! Map<String, Object?>) throw const FormatException();
  return value;
}

void _archiveVersion(Map<String, Object?> data) {
  if (data['version'] != 1) {
    SqliteMailArchive._fail(MailProblemCode.unsupported);
  }
}

String _archiveString(Object? value) {
  if (value is! String) throw const FormatException();
  return value;
}

bool _archiveBool(Object? value) {
  if (value is! bool) throw const FormatException();
  return value;
}

int? _archiveNullableInt(Object? value) {
  if (value != null && value is! int) throw const FormatException();
  return value as int?;
}
