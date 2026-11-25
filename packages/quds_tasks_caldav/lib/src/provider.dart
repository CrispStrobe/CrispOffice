import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:xml/xml.dart';

import 'dav_http.dart';
import 'dav_uri.dart';
import 'dav_xml.dart';
import 'server_profile.dart';
import 'todo_document.dart';

/// Discovered list and operation-specific privileges for one account.
final class CalDavTaskList {
  CalDavTaskList._(
    this.list, {
    required this.canCreate,
    required this.canUpdate,
    required this.canDelete,
    required this.supportsSyncCollection,
  });

  final TaskList list;
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;
  final bool supportsSyncCollection;
  TaskListId get id => list.id;
}

typedef _Changes = ({
  Map<TaskId, String> etags,
  List<TaskId> removed,
  bool more,
});

/// Account-scoped CalDAV Tasks adapter. The host owns the supplied client and
/// retrieves the app password from secure storage. The client must honor
/// abortable requests and the no-redirect flag, and must not retry mutations.
final class CalDavTaskProvider {
  CalDavTaskProvider({
    required this.account,
    required this.settings,
    required http.Client client,
    required Future<String?> Function() appPassword,
  }) : _http = DavHttp(settings, client, appPassword);

  final TaskAccountId account;
  final CalDavConnectionSettings settings;
  final DavHttp _http;

  static const _listProperties = '''
<D:resourcetype/><D:displayname/><D:current-user-privilege-set/>
<D:supported-report-set/><C:supported-calendar-component-set/>''';

  /// Discovers the current principal, calendar homes and VTODO collections,
  /// or validates the exact collection configured by the host.
  Future<TaskResult<List<CalDavTaskList>>> discoverLists() => _run(() async {
    final exact = settings.collectionUrl;
    if (exact != null) {
      final row = await _properties(exact, _listProperties);
      final list = _taskList(row.row, row.uri);
      if (list == null) throw const DavFailure(TaskProblemCode.unsupported);
      return [list];
    }

    final start = settings.discoveryUrl;
    final entry = await _properties(
      start,
      '<D:current-user-principal/><C:calendar-home-set/>',
      discovery: true,
    );
    var homes = entry.row.property(cal, 'calendar-home-set');
    var base = entry.uri;
    if (homes == null) {
      final principal = entry.row.property(dav, 'current-user-principal');
      if (principal != null &&
          child(principal, dav, 'unauthenticated') != null) {
        throw const DavFailure(TaskProblemCode.authenticationRequired);
      }
      final href = principal == null
          ? null
          : xmlValue(child(principal, dav, 'href'));
      if (href == null) throw const DavFailure(TaskProblemCode.unsupported);
      final owner = await _properties(
        _remoteUri(base, href),
        '<C:calendar-home-set/>',
      );
      base = owner.uri;
      homes = owner.row.property(cal, 'calendar-home-set');
    }
    if (homes == null) throw const DavFailure(TaskProblemCode.unsupported);
    final homeUris = <Uri>{};
    for (final element in homes.childElements.where(
      (element) => named(element, dav, 'href'),
    )) {
      homeUris.add(_remoteUri(base, xmlValue(element)!));
    }
    if (homeUris.isEmpty || homeUris.length > 16) {
      throw const FormatException('Invalid DAV calendar homes.');
    }
    final lists = <TaskListId, CalDavTaskList>{};
    for (final home in homeUris) {
      final data = await _multi(
        'PROPFIND',
        home,
        _propfind(_listProperties),
        depth: '1',
      );
      final seen = <Uri>{};
      for (final row in data.rows) {
        final uri = _remoteUri(home, row.href);
        if (!seen.add(uri)) {
          throw const FormatException('Duplicate DAV collection.');
        }
        if (collectionUri(uri) == collectionUri(home)) continue;
        if (!directMember(home, uri) &&
            !directMember(home, withoutTrailingSlash(uri))) {
          throw const FormatException(
            'DAV collection outside its calendar home.',
          );
        }
        final list = _taskList(row, uri);
        if (list != null) lists[list.id] = list;
      }
    }
    return List<CalDavTaskList>.unmodifiable(lists.values);
  });

  CalDavTaskList? _taskList(DavRow row, Uri uri) {
    if (row.status case final status?) davStatusCode(status);
    final resourceType = row.property(dav, 'resourcetype');
    final components = row.property(cal, 'supported-calendar-component-set');
    final supportsTasks = components == null
        ? row.propertyStatus(cal, 'supported-calendar-component-set') == 404
        : components.childElements.any(
            (element) =>
                named(element, cal, 'comp') &&
                element.getAttribute('name')?.toUpperCase() == 'VTODO',
          );
    if (resourceType == null ||
        child(resourceType, cal, 'calendar') == null ||
        !supportsTasks) {
      return null;
    }
    final privileges = row.property(dav, 'current-user-privilege-set');
    final names =
        privileges?.childElements
            .where((element) => named(element, dav, 'privilege'))
            .expand((element) => element.childElements)
            .where((element) => element.namespaceUri == dav)
            .map((element) => element.name.local)
            .toSet() ??
        <String>{};
    final all = names.contains('all') || names.contains('write');
    final canCreate = all || names.contains('bind');
    final canUpdate = all || names.contains('write-content');
    final canDelete = all || names.contains('unbind');
    final reports = row.property(dav, 'supported-report-set');
    final sync =
        reports?.childElements.any(
          (element) =>
              named(element, dav, 'supported-report') &&
              element.childElements.any(
                (report) =>
                    named(report, dav, 'report') &&
                    child(report, dav, 'sync-collection') != null,
              ),
        ) ??
        false;
    final displayName = xmlValue(row.property(dav, 'displayname'))?.trim();
    return CalDavTaskList._(
      TaskList(
        id: TaskListId(uri.toString(), account: account),
        name: displayName == null || displayName.isEmpty
            ? withoutTrailingSlash(uri).pathSegments.lastOrNull ?? uri.host
            : displayName,
        readOnly: !canCreate && !canUpdate && !canDelete,
      ),
      canCreate: canCreate,
      canUpdate: canUpdate,
      canDelete: canDelete,
      supportsSyncCollection: sync,
    );
  }

  /// Pull with the persisted token, or use a complete VTODO ETag snapshot.
  /// Supply only remote IDs/ETags from the committed base of this exact list.
  /// A reset leaves those rows intact. Pass a null cursor to rebuild the base.
  Future<TaskResult<TaskSyncPage>> pull(
    CalDavTaskList list, {
    required Map<TaskId, String?> knownRevisions,
    String? cursor,
  }) => _run(() async {
    final collection = _collection(list);
    final known = Map<TaskId, String?>.of(knownRevisions);
    for (final id in known.keys) {
      _resource(list, id);
    }
    if (cursor == null) return _snapshot(list, collection, known);

    final token = _decodeCursor(list, cursor);
    if (token == null) {
      return _snapshot(list, collection, known, tryToken: false);
    }
    final response = await _xml(
      'REPORT',
      collection,
      '<D:sync-collection $namespaces><D:sync-token>${xmlText(token)}</D:sync-token>'
          '<D:sync-level>1</D:sync-level><D:limit><D:nresults>256</D:nresults></D:limit>'
          '<D:prop><D:getetag/></D:prop></D:sync-collection>',
    );
    if (const {403, 409, 410}.contains(response.statusCode) &&
        _hasDavError(response, 'valid-sync-token')) {
      return TaskSyncPage(
        list: list.id,
        upserts: [],
        tombstones: [],
        resetRequired: true,
      );
    }
    if (const {405, 501}.contains(response.statusCode) ||
        (response.statusCode == 403 &&
            _hasDavError(response, 'supported-report'))) {
      return _snapshot(list, collection, known, tryToken: false);
    }
    if (response.statusCode != 207) davStatus(response);
    final data = DavMultistatus(response.bodyBytes);
    final next = _serverToken(data.token);
    final changes = _changes(list, collection, data, incremental: true);
    if (next == null || (changes.more && next == token)) {
      throw const FormatException(
        'DAV sync report did not provide a usable token.',
      );
    }
    final fetched = await _fetch(
      list,
      collection,
      changes.etags,
      known,
      mixed: true,
    );
    final bound = _encodeCursor(list, next);
    return TaskSyncPage(
      list: list.id,
      upserts: fetched.upserts,
      tombstones: [...changes.removed, ...fetched.nonTasks],
      nextCursor: changes.more ? bound : null,
      checkpoint: changes.more ? null : bound,
    );
  });

  Future<TaskSyncPage> _snapshot(
    CalDavTaskList list,
    Uri collection,
    Map<TaskId, String?> known, {
    bool tryToken = true,
  }) async {
    // Take the token first. Changes during the snapshot can be replayed from
    // that token, so a later checkpoint never hides a concurrent change.
    String? token;
    if (tryToken && list.supportsSyncCollection) {
      final props = await _properties(collection, '<D:sync-token/>');
      token = _serverToken(
        xmlValue(props.row.property(dav, 'sync-token'))?.trim(),
      );
    }
    final data = await _multi(
      'REPORT',
      collection,
      '<C:calendar-query $namespaces><D:prop><D:getetag/></D:prop>'
          '<C:filter><C:comp-filter name="VCALENDAR"><C:comp-filter name="VTODO"/>'
          '</C:comp-filter></C:filter></C:calendar-query>',
      depth: '1',
    );
    final changes = _changes(list, collection, data, incremental: false);
    final fetched = await _fetch(
      list,
      collection,
      changes.etags,
      known,
      mixed: false,
    );
    return TaskSyncPage(
      list: list.id,
      upserts: fetched.upserts,
      tombstones: [
        for (final id in known.keys)
          if (!changes.etags.containsKey(id)) id,
      ],
      checkpoint: _encodeCursor(list, token),
    );
  }

  _Changes _changes(
    CalDavTaskList list,
    Uri collection,
    DavMultistatus data, {
    required bool incremental,
  }) {
    final etags = <TaskId, String>{};
    final removed = <TaskId>[];
    final seen = <Uri>{};
    var more = false;
    for (final row in data.rows) {
      final uri = _remoteUri(collection, row.href);
      if (!seen.add(uri)) {
        throw const FormatException('Duplicate DAV resource.');
      }
      final status = row.status;
      if (incremental &&
          status == 507 &&
          collectionUri(uri) == collectionUri(collection)) {
        more = true;
        continue;
      }
      if (!directMember(collection, uri)) {
        throw const FormatException('DAV resource outside its collection.');
      }
      final id = TaskId(uri.toString(), list: list.id);
      if (incremental && (status == 404 || status == 410)) {
        removed.add(id);
        continue;
      }
      if (status != null) davStatusCode(status);
      final tag = _etag(_requiredText(row, dav, 'getetag'));
      if (tag == null) {
        throw const FormatException('Missing CalDAV resource ETag.');
      }
      etags[id] = tag;
    }
    return (etags: etags, removed: removed, more: more);
  }

  Future<({List<RemoteTask> upserts, List<TaskId> nonTasks})> _fetch(
    CalDavTaskList list,
    Uri collection,
    Map<TaskId, String> etags,
    Map<TaskId, String?> known, {
    required bool mixed,
  }) async {
    final pending = etags.entries
        .where(
          (entry) => entry.value != known[entry.key] || !_strong(entry.value),
        )
        .toList();
    final upserts = <RemoteTask>[];
    final nonTasks = <TaskId>[];
    var calendarCharacters = 0;
    for (var offset = 0; offset < pending.length; offset += 16) {
      final batch = Map.fromEntries(pending.skip(offset).take(16));
      final hrefs = batch.keys
          .map((id) => '<D:href>${xmlText(Uri.parse(id.value).path)}</D:href>')
          .join();
      final result = await _multi(
        'REPORT',
        collection,
        '<C:calendar-multiget $namespaces><D:prop><D:getetag/><C:calendar-data/>'
            '</D:prop>$hrefs</C:calendar-multiget>',
      );
      for (final row in result.rows) {
        final uri = _remoteUri(collection, row.href);
        final id = TaskId(uri.toString(), list: list.id);
        final expected = batch.remove(id);
        if (expected == null) {
          throw const FormatException('Unexpected multiget resource.');
        }
        if (row.status case final status?) davStatusCode(status);
        final actual = _etag(_requiredText(row, dav, 'getetag'));
        if (actual == null) {
          throw const FormatException('Missing CalDAV resource ETag.');
        }
        if (actual != expected) {
          throw const DavFailure(TaskProblemCode.conflict);
        }
        final source = _requiredText(row, cal, 'calendar-data');
        calendarCharacters += source.length;
        if (calendarCharacters > 16 * 1024 * 1024) {
          throw const FormatException(
            'Calendar sync page exceeds the content limit.',
          );
        }
        final doc = _calendarDocument(source);
        if (doc != null) {
          upserts.add(doc.toRemoteTask(id, etag: actual));
        } else if (!mixed) {
          throw const FormatException(
            'Calendar query returned a non-task resource.',
          );
        } else if (known.containsKey(id)) {
          nonTasks.add(id);
        }
      }
      if (batch.isNotEmpty) {
        throw const FormatException('Incomplete calendar-multiget.');
      }
    }
    return (upserts: upserts, nonTasks: nonTasks);
  }

  /// Reads the exact resource. A missing task returns a successful null.
  Future<TaskResult<RemoteTask?>> read(CalDavTaskList list, TaskId id) =>
      _run(() async {
        final item = await _read(list, id);
        return item?.document.toRemoteTask(id, etag: item.etag);
      });

  /// The host must persist and reuse a unique operation ID for recovery.
  /// Use a UUID or another randomly generated URL-safe identifier.
  Future<TaskResult<RemoteTask>> create(
    CalDavTaskList list, {
    required String operationId,
    required TaskFields fields,
    required DateTime timestamp,
  }) => _run(() async {
    final id = _creationId(list, operationId);
    if (!list.canCreate) {
      throw const DavFailure(TaskProblemCode.permissionDenied);
    }
    final document = _validateMutation(
      () => CalDavTodoDocument.create(
        uid: _creationUid(operationId),
        fields: fields,
        timestamp: timestamp,
      ),
    );
    return _put(list, id, document, {'if-none-match': '*'});
  }, mutation: true);

  /// Read-only lookup after an uncertain create. A reused resource path with
  /// a different UID is a conflict.
  Future<TaskResult<RemoteTask?>> recoverCreate(
    CalDavTaskList list, {
    required String operationId,
  }) => _run(() async {
    final id = _creationId(list, operationId);
    final item = await _read(list, id);
    if (item == null) return null;
    if (item.document.uid != _creationUid(operationId)) {
      throw const DavFailure(TaskProblemCode.conflict);
    }
    return item.document.toRemoteTask(id, etag: item.etag);
  });

  Future<TaskResult<RemoteTask>> update(
    CalDavTaskList list,
    TaskId id, {
    required String expectedRevision,
    required TaskPatch patch,
  }) => _run(() async {
    _resource(list, id);
    if (!list.canUpdate) {
      throw const DavFailure(TaskProblemCode.permissionDenied);
    }
    final existing = await _forMutation(list, id, expectedRevision);
    if (patch.isEmpty) return existing.toRemoteTask(id, etag: expectedRevision);
    final patched = _validateMutation(() => existing.apply(patch));
    return _put(list, id, patched, {'if-match': expectedRevision});
  }, mutation: true);

  Future<TaskResult<TaskUnit>> delete(
    CalDavTaskList list,
    TaskId id, {
    required String expectedRevision,
  }) => _run(() async {
    final resource = _resource(list, id);
    if (!list.canDelete) {
      throw const DavFailure(TaskProblemCode.permissionDenied);
    }
    final existing = await _forMutation(list, id, expectedRevision);
    if (existing.mutationBlockers.isNotEmpty) {
      throw const DavFailure(TaskProblemCode.unsupported);
    }
    final response = await _http.send(
      'DELETE',
      resource,
      headers: {'if-match': expectedRevision},
      mutation: true,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      davStatus(response, mutation: true);
    }
    return TaskUnit.value;
  }, mutation: true);

  Future<CalDavTodoDocument> _forMutation(
    CalDavTaskList list,
    TaskId id,
    String expected,
  ) async {
    if (!_strong(expected) || _etag(expected) != expected) {
      throw const DavFailure(TaskProblemCode.invalidInput);
    }
    final existing = await _read(list, id);
    if (existing == null || existing.etag != expected) {
      throw const DavFailure(TaskProblemCode.conflict);
    }
    return existing.document;
  }

  Future<({CalDavTodoDocument document, String etag})?> _read(
    CalDavTaskList list,
    TaskId id,
  ) async {
    final response = await _http.send(
      'GET',
      _resource(list, id),
      headers: {'accept': 'text/calendar'},
    );
    if (response.statusCode == 404 || response.statusCode == 410) return null;
    if (response.statusCode != 200) davStatus(response);
    final etag = _etag(response.headers['etag']);
    if (etag == null) {
      throw const FormatException('Missing CalDAV resource ETag.');
    }
    final document = _calendarDocument(utf8.decode(response.bodyBytes));
    if (document == null) throw const DavFailure(TaskProblemCode.conflict);
    return (document: document, etag: etag);
  }

  Future<RemoteTask> _put(
    CalDavTaskList list,
    TaskId id,
    CalDavTodoDocument document,
    Map<String, String> condition,
  ) async {
    final response = await _http.send(
      'PUT',
      _resource(list, id),
      body: document.encode(),
      headers: {...condition, 'content-type': 'text/calendar; charset=utf-8'},
      mutation: true,
    );
    if (!const {200, 201, 204}.contains(response.statusCode)) {
      davStatus(response, mutation: true);
    }
    // A server can normalize the calendar object and omit the response ETag.
    // Acknowledge the subsequent server representation, including its ETag.
    try {
      final stored = await _read(list, id);
      final writtenTag = _etag(response.headers['etag']);
      if (stored == null ||
          stored.document.uid != document.uid ||
          (writtenTag != null &&
              _strong(writtenTag) &&
              stored.etag != writtenTag)) {
        throw const DavFailure(TaskProblemCode.conflict);
      }
      return stored.document.toRemoteTask(id, etag: stored.etag);
    } on DavFailure catch (error) {
      throw DavFailure(
        error.code,
        retryAfter: error.retryAfter,
        mutationMayHaveOccurred: true,
      );
    } on UnsupportedError {
      throw const DavFailure(
        TaskProblemCode.unsupported,
        mutationMayHaveOccurred: true,
      );
    } on FormatException {
      throw const DavFailure(
        TaskProblemCode.invalidResponse,
        mutationMayHaveOccurred: true,
      );
    } on ArgumentError {
      throw const DavFailure(
        TaskProblemCode.invalidResponse,
        mutationMayHaveOccurred: true,
      );
    }
  }

  TaskId _creationId(CalDavTaskList list, String operationId) {
    final resource = _collection(list);
    if (operationId.isEmpty ||
        operationId.length > 128 ||
        operationId.contains(RegExp(r'[^a-zA-Z0-9_-]'))) {
      throw const DavFailure(TaskProblemCode.invalidInput);
    }
    return TaskId(
      collectionUri(
        resource,
      ).resolve('crispoffice-$operationId.ics').toString(),
      list: list.id,
    );
  }

  static String _creationUid(String id) => '$id@crispoffice';

  Uri _collection(CalDavTaskList list) {
    final uri = davHref(settings.discoveryUrl, list.id.value);
    final exact = settings.collectionUrl;
    if (list.id.account != account ||
        uri == null ||
        (exact != null && collectionUri(uri) != collectionUri(exact))) {
      throw const DavFailure(TaskProblemCode.invalidInput);
    }
    return uri;
  }

  Uri _resource(CalDavTaskList list, TaskId id) {
    final collection = _collection(list);
    final uri = davHref(collection, id.value);
    if (id.list != list.id ||
        uri == null ||
        id.value != uri.toString() ||
        !directMember(collection, uri)) {
      throw const DavFailure(TaskProblemCode.invalidInput);
    }
    return uri;
  }

  Uri _remoteUri(Uri base, String href) =>
      davHref(base, href) ??
      (throw const FormatException('Untrusted DAV href.'));

  Future<({DavRow row, Uri uri})> _properties(
    Uri uri,
    String properties, {
    bool discovery = false,
  }) async {
    final response = await _xml(
      'PROPFIND',
      uri,
      _propfind(properties),
      discovery: discovery,
    );
    if (response.statusCode != 207) davStatus(response);
    final requestUri = response.request!.url;
    final data = DavMultistatus(response.bodyBytes);
    if (data.rows.length != 1) {
      throw const FormatException('Expected one DAV property response.');
    }
    final row = data.rows.single;
    if (row.status case final status?) davStatusCode(status);
    final href = _remoteUri(requestUri, row.href);
    if (collectionUri(href) != collectionUri(requestUri)) {
      throw const FormatException(
        'DAV properties describe an unexpected resource.',
      );
    }
    return (row: row, uri: href);
  }

  Future<DavMultistatus> _multi(
    String method,
    Uri uri,
    String body, {
    String depth = '0',
  }) async {
    final response = await _xml(method, uri, body, depth: depth);
    if (response.statusCode != 207) davStatus(response);
    return DavMultistatus(response.bodyBytes);
  }

  Future<http.Response> _xml(
    String method,
    Uri uri,
    String body, {
    String depth = '0',
    bool discovery = false,
  }) => _http.send(
    method,
    uri,
    body: body,
    headers: {
      'depth': depth,
      'content-type': 'application/xml; charset=utf-8',
      'accept': 'application/xml, text/xml',
    },
    allowDiscoveryRedirect: discovery,
  );

  String _encodeCursor(CalDavTaskList list, String? token) =>
      jsonEncode([1, account.provider, account.value, list.id.value, token]);

  String? _decodeCursor(CalDavTaskList list, String cursor) {
    try {
      if (cursor.length > 131072) throw const FormatException();
      if (jsonDecode(cursor)
          case [
            1,
            final String provider,
            final String owner,
            final String collection,
            final String? token,
          ]
          when provider == account.provider &&
              owner == account.value &&
              collection == list.id.value) {
        return token == null
            ? null
            : _serverToken(token) ?? (throw const FormatException());
      }
    } on FormatException {
      // The host supplied foreign or malformed state.
    }
    throw const DavFailure(TaskProblemCode.invalidInput);
  }
}

CalDavTodoDocument _validateMutation(CalDavTodoDocument Function() work) {
  try {
    return work();
  } on FormatException {
    throw const DavFailure(TaskProblemCode.invalidInput);
  }
}

CalDavTodoDocument? _calendarDocument(String source) {
  try {
    return CalDavTodoDocument.parseCalendarResource(source);
  } on ArgumentError {
    throw const FormatException('Invalid CalDAV calendar data.');
  }
}

String _requiredText(DavRow row, String namespace, String name) {
  final data = xmlValue(row.property(namespace, name));
  if (data != null) return data;
  if (row.propertyStatus(namespace, name) case final status?
      when status >= 400) {
    davStatusCode(status);
  }
  throw const FormatException('Missing required CalDAV property.');
}

String _propfind(String properties) =>
    '<D:propfind $namespaces><D:prop>$properties</D:prop></D:propfind>';

bool _hasDavError(http.Response response, String name) {
  if (response.bodyBytes.isEmpty) return false;
  try {
    final root = davRoot(response.bodyBytes);
    return named(root, dav, 'error') && child(root, dav, name) != null;
  } on FormatException {
    return false;
  } on XmlException {
    return false;
  }
}

String? _serverToken(String? token) {
  if (token == null || token.isEmpty) return null;
  if (token.length > 16384 || token.contains(RegExp(r'[\x00-\x20\x7f]'))) {
    throw const FormatException('Invalid DAV sync token.');
  }
  return token;
}

String? _etag(String? raw) {
  final value = raw?.trim();
  return value != null &&
          value.length <= 1024 &&
          RegExp(r'^(?:W/)?"[\x21\x23-\x7e\x80-\xff]*"$').hasMatch(value)
      ? value
      : null;
}

bool _strong(String tag) => !tag.startsWith('W/');

Future<TaskResult<T>> _run<T>(
  Future<T> Function() work, {
  bool mutation = false,
}) async {
  try {
    return TaskSuccess(await work());
  } on DavFailure catch (error) {
    return TaskFailure(
      mutation && error.mutationMayHaveOccurred == null
          ? TaskProblem(
              error.code,
              retryAfter: error.retryAfter,
              mutationMayHaveOccurred: false,
            )
          : error.problem,
    );
  } on FormatException {
    return TaskFailure(
      TaskProblem(
        TaskProblemCode.invalidResponse,
        mutationMayHaveOccurred: mutation ? false : null,
      ),
    );
  } on XmlException {
    return TaskFailure(
      TaskProblem(
        TaskProblemCode.invalidResponse,
        mutationMayHaveOccurred: mutation ? false : null,
      ),
    );
  } on UnsupportedError {
    return const TaskFailure(
      TaskProblem(TaskProblemCode.unsupported, mutationMayHaveOccurred: false),
    );
  } on ArgumentError {
    return const TaskFailure(
      TaskProblem(TaskProblemCode.invalidInput, mutationMayHaveOccurred: false),
    );
  }
}
