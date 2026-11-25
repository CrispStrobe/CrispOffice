import 'dart:async';
import 'dart:convert';

import 'package:quds_tasks_core/quds_tasks_core.dart';

import 'configuration.dart';
import 'http.dart';

/// A bounded page of possible matches for a previously attempted create.
/// Zero matches never proves that an earlier write was not accepted. More than
/// one match is a conflict; the host must not silently choose one.
final class GraphTaskCreateRecoveryPage {
  GraphTaskCreateRecoveryPage({
    required List<RemoteTask> matches,
    this.nextCursor,
  }) : matches = List.unmodifiable(matches);

  final List<RemoteTask> matches;
  final String? nextCursor;
}

/// Microsoft Graph v1.0, delegated /me/todo access, in the global cloud.
///
/// This adapter performs single, bounded operations. Hosts own durable outbox
/// state, cursor transactions, consent, cancellation and conflict resolution.
/// Writes are NEVER retried here, including after 401 or an ambiguous timeout.
/// Hosts also admit write targets against current [TaskList.readOnly] metadata;
/// an ID does not carry permissions and mutations do not re-fetch list metadata.
final class GraphTaskProvider {
  GraphTaskProvider({
    required this.account,
    required this.transport,
    required this.tokens,
    GraphTaskLimits? limits,
    this.dateOnlyTimeZone = 'UTC',
    DateTime Function()? clock,
  }) : limits = limits ?? GraphTaskLimits(),
       _clock = clock ?? DateTime.now {
    TaskDateTime('2000-01-01T00:00:00', timeZone: dateOnlyTimeZone);
  }

  final TaskAccountId account;
  final GraphTaskHttpTransport transport;
  final GraphTaskTokenSource tokens;
  final GraphTaskLimits limits;
  final DateTime Function() _clock;

  /// Explicit wall-time zone used only when writing a civil [TaskDate]. It is
  /// never inferred from the host's locale/timezone. Reads preserve the remote
  /// dateTime/timeZone pair as [TaskDateTime], including non-midnight values.
  final String dateOnlyTimeZone;

  static const createMarkerName = 'com.crispoffice.taskSync.v1';

  /// ETags are retained but atomic If-Match enforcement has not been verified.
  /// Recurrence, children, attachments, list sharing and smart views are not
  /// exposed as writable capabilities by this adapter.
  final TaskCapabilities capabilities = TaskCapabilities(const [
    TaskCapability.listTasks,
    TaskCapability.createTasks,
    TaskCapability.updateTasks,
    TaskCapability.deleteTasks,
    TaskCapability.delta,
    TaskCapability.notes,
    TaskCapability.htmlNotes,
    TaskCapability.startDates,
    TaskCapability.dueDates,
    TaskCapability.reminders,
  ]);

  Future<TaskResult<TaskListPage>> listTaskLists({
    String? cursor,
    int limit = 100,
  }) => _result(() async {
    final segments = _listsPath;
    final uri = _pageUri(segments, cursor, 'lists', limit: limit);
    final data = await _readObject(uri, pageSize: limit);
    final rows = _rows(data);
    final next = _optionalCursor(data, '@odata.nextLink', segments, 'lists');
    return TaskListPage(lists: rows.map(_parseList).toList(), nextCursor: next);
  });

  Future<TaskResult<TaskListSyncPage>> pullListChanges({
    String? cursor,
    int limit = 100,
  }) => _result(() async {
    final segments = [..._listsPath, 'delta'];
    final uri = _pageUri(segments, cursor, 'listsDelta', limit: limit);
    final data = await _readObject(uri, cursorRead: true, pageSize: limit);
    final upserts = <TaskList>[];
    final tombstones = <TaskListId>[];
    for (final row in _lastEvents(data)) {
      if (_isRemoved(row)) {
        tombstones.add(TaskListId(_string(row, 'id'), account: account));
      } else {
        upserts.add(_parseList(row));
      }
    }
    final cursors = _deltaCursors(data, segments, 'listsDelta');
    return TaskListSyncPage(
      account: account,
      upserts: upserts,
      tombstones: tombstones,
      nextCursor: cursors.next,
      checkpoint: cursors.checkpoint,
    );
  });

  Future<TaskResult<TaskSyncPage>> pullTaskChanges(
    TaskListId list, {
    String? cursor,
    int limit = 100,
  }) => _result(() async {
    _checkList(list);
    final segments = [..._tasksPath(list), 'delta'];
    final uri = _pageUri(segments, cursor, 'tasksDelta', limit: limit);
    final data = await _readObject(uri, cursorRead: true, pageSize: limit);
    final upserts = <RemoteTask>[];
    final tombstones = <TaskId>[];
    for (final row in _lastEvents(data)) {
      if (_isRemoved(row)) {
        tombstones.add(TaskId(_string(row, 'id'), list: list));
      } else {
        upserts.add(_parseTask(row, list));
      }
    }
    final cursors = _deltaCursors(data, segments, 'tasksDelta');
    return TaskSyncPage(
      list: list,
      upserts: upserts,
      tombstones: tombstones,
      nextCursor: cursors.next,
      checkpoint: cursors.checkpoint,
    );
  });

  /// Null means this exact endpoint returned 404. It is not proof of deletion,
  /// and must not authorize replay of an uncertain mutation.
  Future<TaskResult<RemoteTask?>> getTask(TaskId task) => _result(() async {
    _checkTask(task);
    final response = await _request('GET', _uri(_taskPath(task)));
    if (response.statusCode == 404) return null;
    _requireSuccess(response, const {200});
    final parsed = _parseTask(_object(response), task.list);
    if (parsed.id != task) _fail(TaskProblemCode.invalidResponse);
    return parsed;
  });

  /// Call only after the host durably records this unique [operationId] as an
  /// attempted operation. The marker is embedded in the SAME create POST.
  /// A failure with mutationMayHaveOccurred=true requires read-only recovery.
  Future<TaskResult<RemoteTask>> createTask(
    TaskListId list,
    TaskFields fields, {
    required String operationId,
    required String localTaskId,
  }) => _result(() async {
    _checkList(list);
    _checkMarker(operationId, localTaskId);
    final body = _createBody(fields)
      ..['extensions'] = [
        {
          '@odata.type': 'microsoft.graph.openTypeExtension',
          'extensionName': createMarkerName,
          'version': 1,
          'operationId': operationId,
          'localTaskId': localTaskId,
        },
      ];
    final response = await _request('POST', _uri(_tasksPath(list)), body: body);
    _requireSuccess(response, const {201}, write: true);
    return _parseWriteTask(response, list);
  });

  /// Sends only changed fields. An expected revision is rejected rather than
  /// silently ignored: the host must resolve conflicts and acknowledge the
  /// documented read/write race before using unconditional Graph writes.
  Future<TaskResult<RemoteTask>> updateTask(
    TaskId task,
    TaskPatch patch, {
    String? expectedRevision,
  }) => _result(() async {
    _checkTask(task);
    if (expectedRevision != null) _fail(TaskProblemCode.unsupported);
    final body = _patchBody(patch);
    if (body.isEmpty) _fail(TaskProblemCode.invalidInput);
    if (patch.status.isChanged || patch.completedAt.isChanged) {
      await _guardCompletion(task);
    }
    final response = await _request('PATCH', _uri(_taskPath(task)), body: body);
    _requireSuccess(response, const {200}, write: true);
    final parsed = _parseWriteTask(response, task.list);
    if (parsed.id != task) {
      _fail(TaskProblemCode.invalidResponse, mutationMayHaveOccurred: true);
    }
    return parsed;
  });

  Future<TaskResult<TaskUnit>> deleteTask(
    TaskId task, {
    String? expectedRevision,
  }) => _result(() async {
    _checkTask(task);
    if (expectedRevision != null) _fail(TaskProblemCode.unsupported);
    final response = await _request('DELETE', _uri(_taskPath(task)));
    // A 404 is not silently treated as success: a host may need to distinguish
    // an inaccessible list/account from an already deleted task.
    _requireSuccess(response, const {204}, write: true);
    return TaskUnit.value;
  });

  /// Scans one bounded page with the static extension expanded. It never sends
  /// a mutation. Continue every nextCursor, even when matches is empty.
  Future<TaskResult<GraphTaskCreateRecoveryPage>> findCreateOperation(
    TaskListId list, {
    required String operationId,
    required String localTaskId,
    String? cursor,
    int limit = 100,
  }) => _result(() async {
    _checkList(list);
    _checkMarker(operationId, localTaskId);
    final segments = _tasksPath(list);
    final kind = 'recovery:${jsonEncode([operationId, localTaskId])}';
    final uri = _pageUri(
      segments,
      cursor,
      kind,
      limit: limit,
      query: {r'$expand': "extensions(\$filter=id eq '$createMarkerName')"},
    );
    final data = await _readObject(uri, pageSize: limit);
    final matches = <RemoteTask>[];
    for (final row in _rows(data)) {
      if (_matchesMarker(row, operationId, localTaskId)) {
        matches.add(_parseTask(row, list));
      }
    }
    return GraphTaskCreateRecoveryPage(
      matches: matches,
      nextCursor: _optionalCursor(data, '@odata.nextLink', segments, kind),
    );
  });

  List<String> get _listsPath => const ['v1.0', 'me', 'todo', 'lists'];

  List<String> _tasksPath(TaskListId list) => [
    ..._listsPath,
    list.value,
    'tasks',
  ];

  List<String> _taskPath(TaskId task) => [..._tasksPath(task.list), task.value];

  void _checkList(TaskListId list) {
    if (list.account != account) _fail(TaskProblemCode.invalidInput);
    _checkId(list.value);
  }

  void _checkTask(TaskId task) {
    _checkList(task.list);
    _checkId(task.value);
  }

  void _checkId(String id) {
    if (id.isEmpty ||
        id == '.' ||
        id == '..' ||
        id.length > 16384 ||
        id.contains(RegExp(r'[\x00-\x1f\x7f\\]'))) {
      _fail(TaskProblemCode.invalidInput);
    }
  }

  Uri _uri(List<String> segments, [Map<String, String>? query]) {
    final uri = Uri(
      scheme: 'https',
      host: 'graph.microsoft.com',
      pathSegments: segments,
      queryParameters: query,
    );
    _validateUri(uri, segments, TaskProblemCode.invalidInput);
    return uri;
  }

  Uri _pageUri(
    List<String> segments,
    String? cursor,
    String kind, {
    required int limit,
    Map<String, String> query = const {},
  }) {
    if (limit < 1 || limit > limits.maxPageSize) {
      _fail(TaskProblemCode.invalidInput);
    }
    if (cursor == null) {
      // $top is documented for task delta; list delta uses the Prefer header.
      final isListDelta = kind == 'listsDelta';
      return _uri(segments, {...query, if (!isListDelta) r'$top': '$limit'});
    }
    if (cursor.length > limits.maxCursorBytes) {
      _fail(TaskProblemCode.invalidInput);
    }
    try {
      final Object? decoded = jsonDecode(utf8.decode(base64Url.decode(cursor)));
      if (decoded is! Map<String, Object?> ||
          decoded['v'] != 1 ||
          decoded['account'] != account.value ||
          decoded['provider'] != account.provider ||
          decoded['kind'] != kind ||
          decoded['url'] is! String) {
        _fail(TaskProblemCode.invalidInput);
      }
      final uri = Uri.parse(decoded['url']! as String);
      _validateUri(uri, segments, TaskProblemCode.invalidInput);
      return uri;
    } on FormatException {
      _fail(TaskProblemCode.invalidInput);
    }
  }

  void _validateUri(Uri uri, List<String> segments, TaskProblemCode code) {
    final path = uri.pathSegments;
    final samePath =
        path.length == segments.length &&
        List.generate(path.length, (i) {
          if (path[i] == segments[i]) return true;
          return i == path.length - 1 &&
              segments[i] == 'delta' &&
              path[i] == 'microsoft.graph.delta';
        }).every((value) => value);
    if (uri.scheme != 'https' ||
        uri.host != 'graph.microsoft.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.toString().length > limits.maxUrlBytes ||
        !samePath) {
      _fail(code);
    }
  }

  String? _optionalCursor(
    Map<String, Object?> data,
    String key,
    List<String> segments,
    String kind,
  ) {
    if (!data.containsKey(key)) return null;
    final url = data[key];
    if (url is! String || url.isEmpty) _fail(TaskProblemCode.invalidResponse);
    Uri uri;
    try {
      uri = Uri.parse(url);
      _validateUri(uri, segments, TaskProblemCode.invalidResponse);
    } on FormatException {
      _fail(TaskProblemCode.invalidResponse);
    }
    final cursor = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'account': account.value,
          'provider': account.provider,
          'kind': kind,
          'url': url,
        }),
      ),
    );
    if (cursor.length > limits.maxCursorBytes) {
      _fail(TaskProblemCode.invalidResponse);
    }
    return cursor;
  }

  ({String? next, String? checkpoint}) _deltaCursors(
    Map<String, Object?> data,
    List<String> segments,
    String kind,
  ) {
    final next = _optionalCursor(data, '@odata.nextLink', segments, kind);
    final checkpoint = _optionalCursor(
      data,
      '@odata.deltaLink',
      segments,
      kind,
    );
    if ((next == null) == (checkpoint == null)) {
      _fail(TaskProblemCode.invalidResponse);
    }
    return (next: next, checkpoint: checkpoint);
  }

  Future<Map<String, Object?>> _readObject(
    Uri uri, {
    bool cursorRead = false,
    int? pageSize,
  }) async {
    final response = await _request('GET', uri, pageSize: pageSize);
    _requireSuccess(response, const {200}, cursorRead: cursorRead);
    return _object(response);
  }

  Future<GraphTaskHttpResponse> _request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
    int? pageSize,
  }) async {
    final write = method != 'GET';
    final bytes = body == null ? const <int>[] : utf8.encode(jsonEncode(body));
    if (bytes.length > limits.maxRequestBytes) {
      _fail(TaskProblemCode.invalidInput);
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      String token;
      try {
        token = await tokens
            .accessToken(forceRefresh: attempt == 1)
            .timeout(limits.timeout);
      } on GraphTaskTokenException catch (error) {
        throw _Failure(error.problem);
      } on Object {
        _fail(
          TaskProblemCode.authenticationRequired,
          mutationMayHaveOccurred: false,
        );
      }
      if (token.isEmpty ||
          token.length > 64 * 1024 ||
          token.contains(RegExp(r'[\x00-\x20\x7f]'))) {
        _fail(
          TaskProblemCode.authenticationRequired,
          mutationMayHaveOccurred: false,
        );
      }
      GraphTaskHttpResponse response;
      try {
        response = await transport
            .send(
              GraphTaskHttpRequest(
                method: method,
                uri: uri,
                headers: {
                  'Authorization': 'Bearer $token',
                  'Accept': 'application/json',
                  'Prefer':
                      'odata.maxpagesize=${pageSize ?? limits.maxPageSize}',
                  if (body != null) 'Content-Type': 'application/json',
                },
                body: bytes,
              ),
              timeout: limits.timeout,
              maxResponseBytes: limits.maxResponseBytes,
            )
            .timeout(limits.timeout);
      } on GraphTaskTransportException catch (error) {
        final code = switch (error.problem) {
          GraphTaskTransportProblem.cancelled => TaskProblemCode.cancelled,
          GraphTaskTransportProblem.invalidRequest =>
            TaskProblemCode.invalidInput,
          GraphTaskTransportProblem.responseTooLarge =>
            TaskProblemCode.invalidResponse,
          GraphTaskTransportProblem.unavailable => TaskProblemCode.unavailable,
        };
        _fail(
          code,
          mutationMayHaveOccurred: write && error.requestMayHaveReachedServer,
        );
      } on Object {
        _fail(TaskProblemCode.unavailable, mutationMayHaveOccurred: write);
      }
      if (response.body.length > limits.maxResponseBytes ||
          response.statusCode < 100 ||
          response.statusCode > 599) {
        _fail(TaskProblemCode.invalidResponse, mutationMayHaveOccurred: write);
      }
      // Only a safe read gets one forced token refresh. In particular there is
      // no retry after any transport exception, 429, 5xx or mutation response.
      if (!write && attempt == 0 && response.statusCode == 401) continue;
      return response;
    }
    _fail(
      TaskProblemCode.authenticationRequired,
      mutationMayHaveOccurred: false,
    );
  }

  void _requireSuccess(
    GraphTaskHttpResponse response,
    Set<int> success, {
    bool write = false,
    bool cursorRead = false,
  }) {
    if (success.contains(response.statusCode)) return;
    final status = response.statusCode;
    final errorCode = _serverErrorCode(response);
    if (cursorRead &&
        (status == 410 ||
            const {
              'syncstatenotfound',
              'invaliddeltatoken',
              'resyncrequired',
              'errorinvalidsyncstatedata',
              'errorsyncstatenotfound',
              'invalidsyncstate',
            }.contains(errorCode))) {
      _fail(TaskProblemCode.cursorExpired);
    }
    final code = switch (status) {
      400 || 422 => TaskProblemCode.invalidInput,
      401 => TaskProblemCode.authenticationRequired,
      403 => TaskProblemCode.permissionDenied,
      408 => TaskProblemCode.unavailable,
      409 || 412 => TaskProblemCode.conflict,
      413 || 507 => TaskProblemCode.quotaExceeded,
      429 => TaskProblemCode.throttled,
      >= 500 => TaskProblemCode.unavailable,
      _ => TaskProblemCode.providerFailure,
    };
    throw _Failure(
      TaskProblem(
        code,
        retryAfter: status == 429 || status == 503
            ? _retryAfter(response)
            : null,
        mutationMayHaveOccurred:
            write &&
            (status >= 500 || status == 408 || status >= 200 && status < 300),
      ),
    );
  }

  String? _serverErrorCode(GraphTaskHttpResponse response) {
    try {
      final data = _object(response);
      final error = data['error'];
      if (error is Map<String, Object?> && error['code'] is String) {
        return (error['code']! as String).toLowerCase();
      }
    } on Object {
      // HTTP status is sufficient; never surface raw provider error content.
    }
    return null;
  }

  Duration? _retryAfter(GraphTaskHttpResponse response) {
    String? header;
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == 'retry-after') header = entry.value;
    }
    if (header == null || header.length > 128) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds != null) {
      if (seconds < 0 || seconds > 31536000) return null;
      return Duration(seconds: seconds);
    }
    final match = RegExp(
      r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(header.trim());
    if (match == null) return null;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months.indexOf(match.group(2)!);
    if (month < 0) return null;
    final at = DateTime.utc(
      int.parse(match.group(3)!),
      month + 1,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
    final duration = at.difference(_clock().toUtc());
    return duration < Duration.zero ? Duration.zero : duration;
  }

  Map<String, Object?> _object(GraphTaskHttpResponse response) {
    try {
      final Object? value = jsonDecode(utf8.decode(response.body));
      if (value is Map<String, Object?>) return value;
    } on FormatException {
      _fail(TaskProblemCode.invalidResponse);
    }
    _fail(TaskProblemCode.invalidResponse);
  }

  List<Map<String, Object?>> _rows(Map<String, Object?> data) {
    final value = data['value'];
    if (value is! List<Object?> || value.length > limits.maxResponseItems) {
      _fail(TaskProblemCode.invalidResponse);
    }
    return value.map((row) {
      if (row is! Map<String, Object?>) _fail(TaskProblemCode.invalidResponse);
      return row;
    }).toList();
  }

  /// A delta page can repeat one identity. Resolve its final observed event
  /// before splitting records/tombstones, otherwise their order would be lost.
  Iterable<Map<String, Object?>> _lastEvents(Map<String, Object?> data) {
    final events = <String, Map<String, Object?>>{};
    for (final row in _rows(data)) {
      events[_string(row, 'id')] = row;
    }
    return events.values;
  }

  Future<void> _guardCompletion(TaskId task) async {
    final data = await _readObject(_uri(_taskPath(task)));
    if (_string(data, 'id') != task.value) {
      _fail(TaskProblemCode.invalidResponse);
    }
    // Completing/reopening recurring tasks has occurrence-generation semantics
    // beyond this adapter's capability. A fresh read blocks known recurring
    // tasks. The documented unconditional read/write race still applies.
    if (data['recurrence'] != null) _fail(TaskProblemCode.unsupported);
  }

  bool _isRemoved(Map<String, Object?> row) {
    if (!row.containsKey('@removed')) return false;
    if (row['@removed'] is! Map<String, Object?>) {
      _fail(TaskProblemCode.invalidResponse);
    }
    return true;
  }

  String _string(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value is! String) _fail(TaskProblemCode.invalidResponse);
    return value;
  }

  String? _optionalString(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is! String) _fail(TaskProblemCode.invalidResponse);
    return value;
  }

  TaskList _parseList(Map<String, Object?> data) {
    return TaskList(
      id: TaskListId(_string(data, 'id'), account: account),
      name: _string(data, 'displayName'),
      // Flagged email has special semantics: expose a host admission rule.
      readOnly: data['wellknownListName'] == 'flaggedEmails',
      revision: _optionalString(data, '@odata.etag'),
      providerData: TaskProviderData(
        format: 'microsoft.graph.todoTaskList.v1',
        raw: jsonEncode(data),
      ),
    );
  }

  RemoteTask _parseTask(Map<String, Object?> data, TaskListId list) {
    final status = switch (_string(data, 'status')) {
      'notStarted' => TaskStatus.notStarted,
      'inProgress' => TaskStatus.inProgress,
      'completed' => TaskStatus.completed,
      'waitingOnOthers' => TaskStatus.waitingOnOthers,
      'deferred' => TaskStatus.deferred,
      _ => throw const _Failure(TaskProblem(TaskProblemCode.unsupported)),
    };
    final priority = switch (_string(data, 'importance')) {
      'low' => TaskPriority.low,
      'normal' => TaskPriority.normal,
      'high' => TaskPriority.high,
      _ => throw const _Failure(TaskProblem(TaskProblemCode.unsupported)),
    };
    TaskText? notes;
    final body = data['body'];
    if (body != null) {
      if (body is! Map<String, Object?>) _fail(TaskProblemCode.invalidResponse);
      final format = switch (_string(body, 'contentType').toLowerCase()) {
        'text' => TaskTextFormat.text,
        'html' => TaskTextFormat.html,
        _ => throw const _Failure(TaskProblem(TaskProblemCode.unsupported)),
      };
      notes = TaskText(_string(body, 'content'), format: format);
    }
    final reminderOn = data['isReminderOn'];
    if (reminderOn != null && reminderOn is! bool) {
      _fail(TaskProblemCode.invalidResponse);
    }
    return RemoteTask(
      id: TaskId(_string(data, 'id'), list: list),
      fields: TaskFields(
        title: _string(data, 'title'),
        notes: notes,
        status: status,
        priority: priority,
        start: _parseDate(data['startDateTime']),
        due: _parseDate(data['dueDateTime']),
        reminder: reminderOn == true
            ? _parseDate(data['reminderDateTime'])
            : null,
        completedAt: _parseDate(data['completedDateTime']),
      ),
      revision: _optionalString(data, '@odata.etag'),
      providerData: TaskProviderData(
        format: 'microsoft.graph.todoTask.v1',
        raw: jsonEncode(data),
      ),
    );
  }

  RemoteTask _parseWriteTask(GraphTaskHttpResponse response, TaskListId list) {
    try {
      return _parseTask(_object(response), list);
    } on Object {
      // The write succeeded at HTTP level; malformed/unexpected response data
      // must not be downgraded to a failure that invites a duplicate retry.
      _fail(TaskProblemCode.invalidResponse, mutationMayHaveOccurred: true);
    }
  }

  TaskDateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, Object?>) _fail(TaskProblemCode.invalidResponse);
    try {
      return TaskDateTime(
        _string(value, 'dateTime'),
        timeZone: _string(value, 'timeZone'),
      );
    } on ArgumentError {
      _fail(TaskProblemCode.invalidResponse);
    }
  }

  Map<String, Object?> _createBody(TaskFields fields) {
    _checkTitle(fields.title);
    return {
      'title': fields.title,
      'status': _status(fields.status),
      'importance': fields.priority.name,
      if (fields.notes != null) 'body': _notes(fields.notes!),
      if (fields.start != null) 'startDateTime': _date(fields.start!),
      if (fields.due != null) 'dueDateTime': _date(fields.due!),
      if (fields.reminder != null) ...{
        'isReminderOn': true,
        'reminderDateTime': _date(fields.reminder!),
      },
      if (fields.completedAt != null)
        'completedDateTime': _date(fields.completedAt!),
    };
  }

  Map<String, Object?> _patchBody(TaskPatch patch) {
    final body = <String, Object?>{};
    if (patch.title.isChanged) {
      if (patch.title.isClear) _fail(TaskProblemCode.invalidInput);
      _checkTitle(patch.title.value!);
      body['title'] = patch.title.value!;
    }
    if (patch.notes.isChanged) {
      body['body'] = patch.notes.isClear
          ? const {'contentType': 'html', 'content': ''}
          : _notes(patch.notes.value!);
    }
    if (patch.status.isChanged) {
      if (patch.status.isClear) _fail(TaskProblemCode.invalidInput);
      body['status'] = _status(patch.status.value!);
    }
    if (patch.priority.isChanged) {
      if (patch.priority.isClear) _fail(TaskProblemCode.invalidInput);
      body['importance'] = patch.priority.value!.name;
    }
    void addDate(String name, TaskFieldPatch<TaskDateValue> field) {
      if (field.isChanged) {
        body[name] = field.isClear ? null : _date(field.value!);
      }
    }

    addDate('startDateTime', patch.start);
    addDate('dueDateTime', patch.due);
    addDate('completedDateTime', patch.completedAt);
    if (patch.reminder.isChanged) {
      body['isReminderOn'] = !patch.reminder.isClear;
      addDate('reminderDateTime', patch.reminder);
    }
    return body;
  }

  void _checkTitle(String title) {
    if (title.trim().isEmpty ||
        title.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'))) {
      _fail(TaskProblemCode.invalidInput);
    }
  }

  String _status(TaskStatus status) {
    if (status == TaskStatus.cancelled) _fail(TaskProblemCode.unsupported);
    return status.name;
  }

  Map<String, Object?> _notes(TaskText text) => {
    'contentType': 'html',
    'content': text.format == TaskTextFormat.html
        ? text.value
        : '<div>${const HtmlEscape().convert(text.value).replaceAll('\r\n', '\n').replaceAll('\n', '<br>')}</div>',
  };

  Map<String, Object?> _date(TaskDateValue value) => switch (value) {
    TaskDate(:final year, :final month, :final day) => {
      'dateTime':
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}T00:00:00',
      'timeZone': dateOnlyTimeZone,
    },
    TaskDateTime(:final localDateTime, :final timeZone) =>
      timeZone == null
          ? throw const _Failure(
              TaskProblem(
                TaskProblemCode.unsupported,
                mutationMayHaveOccurred: false,
              ),
            )
          : {'dateTime': localDateTime, 'timeZone': timeZone},
  };

  void _checkMarker(String operationId, String localTaskId) {
    if (!RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(operationId) ||
        localTaskId.isEmpty ||
        localTaskId.length > 256 ||
        localTaskId.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      _fail(TaskProblemCode.invalidInput);
    }
  }

  bool _matchesMarker(
    Map<String, Object?> row,
    String operationId,
    String localTaskId,
  ) {
    final extensions = row['extensions'];
    if (extensions == null) return false;
    if (extensions is! List<Object?>) _fail(TaskProblemCode.invalidResponse);
    return extensions.any((extension) {
      if (extension is! Map<String, Object?>) {
        _fail(TaskProblemCode.invalidResponse);
      }
      return (extension['extensionName'] == createMarkerName ||
              extension['id'] == createMarkerName ||
              extension['id'] ==
                  'Microsoft.OutlookServices.OpenTypeExtension.$createMarkerName') &&
          extension['version'] == 1 &&
          extension['operationId'] == operationId &&
          extension['localTaskId'] == localTaskId;
    });
  }

  Future<TaskResult<T>> _result<T>(Future<T> Function() work) async {
    try {
      return TaskSuccess(await work());
    } on _Failure catch (error) {
      return TaskFailure(error.problem);
    } on ArgumentError {
      return const TaskFailure(TaskProblem(TaskProblemCode.invalidResponse));
    } on FormatException {
      return const TaskFailure(TaskProblem(TaskProblemCode.invalidResponse));
    }
  }

  Never _fail(TaskProblemCode code, {bool? mutationMayHaveOccurred = false}) =>
      throw _Failure(
        TaskProblem(code, mutationMayHaveOccurred: mutationMayHaveOccurred),
      );
}

final class _Failure implements Exception {
  const _Failure(this.problem);
  final TaskProblem problem;
}
