import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

import 'configuration.dart';
import 'http.dart';

part 'task_writer.dart';

/// Google Tasks lists and paginated snapshots using a delegated Tasks grant.
abstract interface class GoogleTaskReader {
  Future<TaskResult<TaskListPage>> lists(
    MailOperationLease lease, {
    String? cursor,
  });

  Future<TaskResult<TaskSyncPage>> pull(
    TaskListId list, {
    required MailOperationLease lease,
    String? cursor,
  });

  void close();
}

final class ApiGoogleTaskReader extends _GoogleTaskConnection
    with _GoogleTaskWrites
    implements GoogleTaskProvider {
  ApiGoogleTaskReader({
    required super.account,
    required super.mailAccount,
    required super.tokens,
    required super.transport,
    super.enableWrites,
  });

  @override
  Future<TaskResult<TaskListPage>> lists(
    MailOperationLease lease, {
    String? cursor,
  }) => _request(
    lease,
    const ['users', '@me', 'lists'],
    cursor,
    (rows, next) => TaskListPage(
      lists: [
        for (final row in rows)
          TaskList(
            id: TaskListId(_id(row['id']), account: account),
            name: _string(row['title']),
            readOnly: !enableWrites,
            revision: _optional(row['etag']),
          ),
      ],
      nextCursor: next,
    ),
  );

  @override
  Future<TaskResult<TaskSyncPage>> pull(
    TaskListId list, {
    required MailOperationLease lease,
    String? cursor,
  }) {
    if (list.account != account || !_validId(list.value)) {
      return Future.value(
        const TaskFailure(TaskProblem(TaskProblemCode.invalidInput)),
      );
    }
    return _request(
      lease,
      ['lists', list.value, 'tasks'],
      cursor,
      (rows, next) => TaskSyncPage(
        list: list,
        upserts: [
          for (final row in rows)
            if (row['deleted'] != true) _task(list, row),
        ],
        tombstones: [
          for (final row in rows)
            if (row['deleted'] == true) TaskId(_id(row['id']), list: list),
        ],
        nextCursor: next,
      ),
      query: const {
        'showCompleted': 'true',
        'showHidden': 'true',
        'showAssigned': 'true',
      },
    );
  }

  Future<TaskResult<T>> _request<T>(
    MailOperationLease lease,
    List<String> path,
    String? cursor,
    T Function(List<Map<String, Object?>> rows, String? next) parse, {
    Map<String, String> query = const {},
  }) async {
    if (lease.account != mailAccount) {
      return const TaskFailure(TaskProblem(TaskProblemCode.invalidInput));
    }
    final scope = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              account.provider,
              account.value,
              mailAccount.profile.hostId,
              mailAccount.profile.value,
              mailAccount.value,
              ...path,
            ]),
          ),
        )
        .toString();
    final String? pageToken;
    try {
      pageToken = cursor == null ? null : _decodeCursor(cursor, scope);
    } on FormatException {
      return const TaskFailure(TaskProblem(TaskProblemCode.invalidInput));
    }
    try {
      final response = await _send(
        lease,
        'GET',
        path,
        query: {...query, 'maxResults': '100', 'pageToken': ?pageToken},
      );
      lease.checkCurrent();
      if (response.statusCode != 200) {
        return TaskFailure(
          TaskProblem(switch (response.statusCode) {
            400 when pageToken != null => TaskProblemCode.cursorExpired,
            400 => TaskProblemCode.invalidInput,
            401 => TaskProblemCode.authenticationRequired,
            403 => TaskProblemCode.permissionDenied,
            404 => TaskProblemCode.unavailable,
            429 => TaskProblemCode.throttled,
            >= 500 => TaskProblemCode.unavailable,
            _ => TaskProblemCode.providerFailure,
          }),
        );
      }
      final decoded = jsonDecode(utf8.decode(response.body));
      if (decoded is! Map<String, Object?>) throw const FormatException();
      final Object data = decoded['items'] ?? const [];
      if (data is! List<Object?> || data.length > 100) {
        throw const FormatException();
      }
      final rows = <Map<String, Object?>>[];
      final ids = <String>{};
      for (final row in data) {
        if (row is! Map<String, Object?> || !ids.add(_id(row['id']))) {
          throw const FormatException();
        }
        rows.add(row);
      }
      final raw = _optional(decoded['nextPageToken']);
      if (raw != null && (!_validToken(raw) || raw == pageToken)) {
        throw const FormatException();
      }
      return TaskSuccess(
        parse(rows, raw == null ? null : jsonEncode([scope, raw])),
      );
    } on MailCancelled catch (error) {
      return TaskFailure(
        TaskProblem(
          error.reason == MailCancellationReason.user ||
                  error.reason == MailCancellationReason.budgetExpired
              ? TaskProblemCode.cancelled
              : TaskProblemCode.staleOperation,
        ),
      );
    } on MailCloudException catch (error) {
      return _mailFailure(error.problem);
    } on FormatException {
      return const TaskFailure(TaskProblem(TaskProblemCode.invalidResponse));
    } on ArgumentError {
      return const TaskFailure(TaskProblem(TaskProblemCode.invalidResponse));
    }
  }

  TaskFailure<T> _mailFailure<T>(MailProblem problem) => TaskFailure(
    TaskProblem(
      TaskProblemCode.values.byName(problem.code.name),
      retryAfter: problem.retryAfter,
    ),
  );

  @override
  void close() => transport.close();
}

String _decodeCursor(String cursor, String scope) {
  if (cursor.length > 16384) throw const FormatException();
  final decoded = jsonDecode(cursor);
  if (decoded is! List<Object?> ||
      decoded.length != 2 ||
      decoded[0] != scope ||
      decoded[1] is! String ||
      !_validToken(decoded[1]! as String)) {
    throw const FormatException();
  }
  return decoded[1]! as String;
}

bool _validToken(String token) =>
    token.isNotEmpty &&
    token.length <= 4096 &&
    !token.contains(RegExp(r'[\x00-\x1f\x7f]'));

bool _validId(String id) =>
    id.isNotEmpty &&
    id.length <= 1024 &&
    id != '.' &&
    id != '..' &&
    !id.contains(RegExp(r'[/\\\x00-\x1f\x7f]'));

String _id(Object? id) {
  if (id is! String || !_validId(id)) throw const FormatException();
  return id;
}

String _string(Object? value) {
  if (value is! String) throw const FormatException();
  return value;
}

String? _optional(Object? value) => value == null ? null : _string(value);

RemoteTask _task(TaskListId list, Map<String, Object?> row) {
  final status = switch (row['status']) {
    'completed' => TaskStatus.completed,
    'needsAction' => TaskStatus.notStarted,
    _ => throw const FormatException(),
  };
  final notes = _optional(row['notes']);
  final due = _optional(row['due']);
  final completed = _optional(row['completed']);
  return RemoteTask(
    id: TaskId(_id(row['id']), list: list),
    fields: TaskFields(
      title: _string(row['title']),
      notes: notes == null ? null : TaskText(notes),
      status: status,
      due: due == null ? null : _civilDate(due),
      completedAt: status == TaskStatus.completed && completed != null
          ? _instant(completed)
          : null,
    ),
    revision: _optional(row['etag']),
    providerData: TaskProviderData(
      format: 'google-tasks-json',
      raw: jsonEncode(row),
    ),
  );
}

TaskDate _civilDate(String wire) {
  final match = RegExp(r'^(\d{4})-(\d\d)-(\d\d)T').firstMatch(wire);
  if (match == null || DateTime.tryParse(wire) == null) {
    throw const FormatException();
  }
  return TaskDate(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
  );
}

TaskDateTime _instant(String wire) {
  final date = DateTime.tryParse(wire);
  if (date == null || !date.isUtc) throw const FormatException();
  return TaskDateTime(
    date.toIso8601String().replaceFirst(RegExp(r'Z$'), ''),
    timeZone: 'UTC',
  );
}
