part of 'task_reader.dart';

abstract interface class GoogleTaskProvider implements GoogleTaskReader {
  Future<TaskResult<RemoteTask>> create(
    TaskListId list,
    TaskFields fields,
    MailOperationLease lease,
  );

  Future<TaskResult<RemoteTask>> update(
    TaskId id,
    TaskPatch patch, {
    required String revision,
    required MailOperationLease lease,
  });

  Future<TaskResult<TaskUnit>> delete(
    TaskId id, {
    required String revision,
    required MailOperationLease lease,
  });
}

abstract class _GoogleTaskConnection {
  _GoogleTaskConnection({
    required this.account,
    required this.mailAccount,
    required this.tokens,
    required this.transport,
    this.enableWrites = false,
  });

  final TaskAccountId account;
  final MailAccountId mailAccount;
  final MailCloudTokenSource tokens;
  final MailCloudHttpTransport transport;
  final bool enableWrites;

  Future<MailCloudHttpResponse> _send(
    MailOperationLease lease,
    String method,
    List<String> path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    String? revision,
  }) async {
    lease.checkCurrent();
    final token = await tokens.accessToken(lease);
    if (token case MailFailure(:final problem)) {
      throw MailCloudException(problem);
    }
    lease.checkCurrent();
    return transport.send(
      MailCloudHttpRequest(
        method: method,
        uri: Uri(
          scheme: 'https',
          host: 'tasks.googleapis.com',
          pathSegments: ['tasks', 'v1', ...path],
          queryParameters: query,
        ),
        headers: {
          'authorization':
              'Bearer ${(token as MailSuccess<MailCloudAccessToken>).value.value}',
          'accept': 'application/json',
          if (body != null) 'content-type': 'application/json; charset=utf-8',
          'if-match': ?revision,
        },
        body: body == null ? const [] : utf8.encode(jsonEncode(body)),
      ),
      lease: lease,
      timeout: const Duration(seconds: 30),
      maxResponseBytes: 4 * 1024 * 1024,
    );
  }
}

mixin _GoogleTaskWrites on _GoogleTaskConnection implements GoogleTaskProvider {
  @override
  Future<TaskResult<RemoteTask>> create(
    TaskListId list,
    TaskFields fields,
    MailOperationLease lease,
  ) async {
    if (!enableWrites) return _failure(TaskProblemCode.permissionDenied);
    if (!_listValid(list, lease) || fields.title.trim().isEmpty) {
      return _failure(TaskProblemCode.invalidInput);
    }
    final patch = TaskPatch.between(const TaskFields(title: ''), fields);
    return _writeTask(list, lease, patch);
  }

  @override
  Future<TaskResult<RemoteTask>> update(
    TaskId id,
    TaskPatch patch, {
    required String revision,
    required MailOperationLease lease,
  }) async {
    if (!enableWrites) return _failure(TaskProblemCode.permissionDenied);
    if (patch.isEmpty ||
        !_listValid(id.list, lease) ||
        !_validId(id.value) ||
        _ifMatch(revision) == null) {
      return _failure(TaskProblemCode.invalidInput);
    }
    return _writeTask(id.list, lease, patch, id: id, revision: revision);
  }

  Future<TaskResult<RemoteTask>> _writeTask(
    TaskListId list,
    MailOperationLease lease,
    TaskPatch patch, {
    TaskId? id,
    String? revision,
  }) async {
    final body = _writeFields(patch);
    if (body == null) return _failure(TaskProblemCode.unsupported);
    if (id != null) {
      final problem = await _checkCurrent(id, revision!, lease);
      if (problem != null) return TaskFailure(problem);
    }
    return _itemRequest(
      lease,
      id == null ? 'POST' : 'PATCH',
      list,
      id: id,
      revision: revision,
      body: body,
      decode: (response) {
        final task = _decodeTask(list, id, response);
        if (googleTaskIsAssigned(task) ||
            !googleTaskMatchesUpdate(task, patch)) {
          throw const FormatException();
        }
        return task;
      },
    );
  }

  @override
  Future<TaskResult<TaskUnit>> delete(
    TaskId id, {
    required String revision,
    required MailOperationLease lease,
  }) async {
    if (!enableWrites) return _failure(TaskProblemCode.permissionDenied);
    if (!_listValid(id.list, lease) ||
        !_validId(id.value) ||
        _ifMatch(revision) == null) {
      return _failure(TaskProblemCode.invalidInput);
    }
    final problem = await _checkCurrent(id, revision, lease);
    if (problem != null) return TaskFailure(problem);
    return _itemRequest(
      lease,
      'DELETE',
      id.list,
      id: id,
      revision: revision,
      decode: (response) {
        if (response.body.isNotEmpty) throw const FormatException();
        return TaskUnit.value;
      },
    );
  }

  bool _listValid(TaskListId list, MailOperationLease lease) =>
      lease.account == mailAccount &&
      list.account == account &&
      _validId(list.value);

  Future<TaskProblem?> _checkCurrent(
    TaskId id,
    String revision,
    MailOperationLease lease,
  ) async {
    final observed = await _itemRequest(
      lease,
      'GET',
      id.list,
      id: id,
      decode: (response) => _decodeTask(id.list, id, response),
    );
    return switch (observed) {
      TaskFailure(:final problem) => problem,
      TaskSuccess(:final value) when googleTaskIsAssigned(value) =>
        const TaskProblem(
          TaskProblemCode.permissionDenied,
          mutationMayHaveOccurred: false,
        ),
      TaskSuccess(:final value)
          when _ifMatch(value.revision) == _ifMatch(revision) =>
        null,
      _ => const TaskProblem(
        TaskProblemCode.conflict,
        mutationMayHaveOccurred: false,
      ),
    };
  }

  Future<TaskResult<T>> _itemRequest<T>(
    MailOperationLease lease,
    String method,
    TaskListId list, {
    TaskId? id,
    String? revision,
    Map<String, Object?>? body,
    required T Function(MailCloudHttpResponse) decode,
  }) async {
    final mutation = method != 'GET';
    var received = false;
    try {
      final response = await _send(
        lease,
        method,
        ['lists', list.value, 'tasks', if (id != null) id.value],
        body: body,
        revision: _ifMatch(revision),
      );
      received = true;
      lease.checkCurrent();
      final status = response.statusCode;
      if ((method == 'DELETE' && (status == 200 || status == 204)) ||
          (method != 'DELETE' &&
              (status == 200 || (method == 'POST' && status == 201)))) {
        return TaskSuccess(decode(response));
      }
      final code = switch (status) {
        400 => TaskProblemCode.invalidInput,
        401 => TaskProblemCode.authenticationRequired,
        403 => TaskProblemCode.permissionDenied,
        404 || 409 || 410 || 412 => TaskProblemCode.conflict,
        429 => TaskProblemCode.throttled,
        >= 500 => TaskProblemCode.unavailable,
        _ => TaskProblemCode.invalidResponse,
      };
      final rejected = const {
        400,
        401,
        403,
        404,
        409,
        410,
        412,
        429,
      }.contains(status);
      return _failure(code, uncertain: mutation && !rejected);
    } on MailCloudException catch (error) {
      return TaskFailure(
        TaskProblem(
          TaskProblemCode.values.byName(error.problem.code.name),
          retryAfter: error.problem.retryAfter,
          mutationMayHaveOccurred:
              mutation && error.requestMayHaveReachedServer,
        ),
      );
    } on MailCancelled catch (error) {
      return _failure(
        error.reason == MailCancellationReason.user ||
                error.reason == MailCancellationReason.budgetExpired
            ? TaskProblemCode.cancelled
            : TaskProblemCode.staleOperation,
        uncertain: mutation && received,
      );
    } on FormatException {
      return _failure(
        TaskProblemCode.invalidResponse,
        uncertain: mutation && received,
      );
    } on ArgumentError {
      return _failure(
        TaskProblemCode.invalidResponse,
        uncertain: mutation && received,
      );
    }
  }
}

TaskFailure<T> _failure<T>(TaskProblemCode code, {bool uncertain = false}) =>
    TaskFailure(TaskProblem(code, mutationMayHaveOccurred: uncertain));

RemoteTask _decodeTask(
  TaskListId list,
  TaskId? expected,
  MailCloudHttpResponse response,
) {
  final decoded = jsonDecode(utf8.decode(response.body));
  if (decoded is! Map<String, Object?> || decoded['deleted'] == true) {
    throw const FormatException();
  }
  final task = _task(list, decoded);
  if (expected != null && task.id != expected) throw const FormatException();
  if (_ifMatch(task.revision) == null) throw const FormatException();
  return task;
}

String? _ifMatch(String? tag) {
  if (tag == null || tag.length > 1024) return null;
  if (RegExp(r'^"[^"\x00-\x20\x7f]+"$').hasMatch(tag)) return tag;
  if (RegExp(r'^[A-Za-z0-9_+=./-]+$').hasMatch(tag)) return '"$tag"';
  return null;
}

Map<String, Object?>? _writeFields(TaskPatch patch) {
  if (patch.title.isClear ||
      patch.status.isClear ||
      patch.priority.isChanged ||
      patch.start.isChanged ||
      patch.reminder.isChanged ||
      patch.completedAt.value != null ||
      (patch.completedAt.isClear &&
          patch.status.value != TaskStatus.notStarted)) {
    return null;
  }
  final title = patch.title.value;
  final notes = patch.notes.value;
  final status = patch.status.value;
  final due = patch.due.value;
  if (title != null && (title.trim().isEmpty || title.length > 1024) ||
      notes != null &&
          (notes.format != TaskTextFormat.text || notes.value.length > 8192) ||
      status != null &&
          status != TaskStatus.notStarted &&
          status != TaskStatus.completed ||
      due != null && due is! TaskDate) {
    return null;
  }
  return {
    'title': ?title,
    if (patch.notes.isChanged) 'notes': notes?.value,
    if (patch.due.isChanged)
      'due': due == null ? null : _wireDate(due as TaskDate),
    if (status != null)
      'status': status == TaskStatus.completed ? 'completed' : 'needsAction',
    if (status == TaskStatus.notStarted) 'completed': null,
  };
}

String _wireDate(TaskDate date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}T00:00:00.000Z';

/// Google can propagate changes on assigned tasks to Docs and Chat.
bool googleTaskIsAssigned(RemoteTask task) {
  final data = task.providerData;
  if (data == null || data.format != 'google-tasks-json') return false;
  try {
    final value = jsonDecode(data.raw);
    return value is! Map<String, Object?> || value['assignmentInfo'] != null;
  } on FormatException {
    return true;
  }
}

/// Matches only fields the patch explicitly changed, with Google normalization.
bool googleTaskMatchesUpdate(RemoteTask task, TaskPatch patch) {
  bool matches<T extends Object>(TaskFieldPatch<T> field, T? value) =>
      !field.isChanged || field.value == value;
  final fields = task.fields;
  return matches(patch.title, fields.title) &&
      matches(
        patch.notes,
        fields.notes?.value.isEmpty == true ? null : fields.notes,
      ) &&
      matches(patch.status, fields.status) &&
      matches(patch.due, fields.due) &&
      matches(patch.completedAt, fields.completedAt);
}
