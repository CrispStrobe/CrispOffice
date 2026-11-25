part of 'soap.dart';

const _taskFields = [
  'item:ParentFolderId',
  'item:Subject',
  'item:Body',
  'item:Importance',
  'task:StartDate',
  'task:DueDate',
  'task:CompleteDate',
  'task:Status',
  'item:ReminderIsSet',
  'item:ReminderDueBy',
];

void _taskItem(XmlElement item) {
  if (item.namespaceUri != _types || item.name.local != 'Task') {
    EwsSoap._invalid();
  }
}

extension EwsTaskSoap on EwsSoap {
  String getTasks(List<String> ids) => _request('GetItem', (builder) {
    builder.element(
      'm:ItemShape',
      nest: () {
        builder.element('t:BaseShape', nest: 'IdOnly');
        builder.element('t:BodyType', nest: 'Text');
        builder.element(
          't:AdditionalProperties',
          nest: () {
            for (final field in _taskFields) {
              builder.element('t:FieldURI', attributes: {'FieldURI': field});
            }
          },
        );
      },
    );
    builder.element(
      'm:ItemIds',
      nest: () {
        for (final id in ids) {
          _itemId(builder, id);
        }
      },
    );
  });

  List<RemoteTask?> tasks(String xml, TaskListId list, List<String> ids) =>
      EwsSoap._guard(() {
        final responses = _responses(xml, 'GetItem', allowMissing: true);
        if (responses.length != ids.length) EwsSoap._invalid();
        return [
          for (var i = 0; i < ids.length; i++)
            if (responses[i] case final response?)
              _readTask(response, list, ids[i])
            else
              null,
        ];
      });

  RemoteTask _readTask(
    XmlElement response,
    TaskListId list,
    String expectedId,
  ) {
    final items = EwsSoap._one(
      response,
      'Items',
      _messages,
    ).childElements.toList();
    if (items.length != 1) EwsSoap._invalid();
    final item = items.single;
    _taskItem(item);
    final id = EwsSoap._id(EwsSoap._one(item, 'ItemId', _types));
    final parent = EwsSoap._identifier(
      EwsSoap._one(item, 'ParentFolderId', _types).getAttribute('Id'),
    );
    if (id.id != expectedId || parent != list.value) EwsSoap._invalid();
    final budget = _HeaderBudget(limits.maxHeaderBytes);
    String? read(String name) => EwsSoap._optionalText(item, name, budget);
    final status = switch (read('Status')) {
      null || 'NotStarted' => TaskStatus.notStarted,
      'InProgress' => TaskStatus.inProgress,
      'Completed' => TaskStatus.completed,
      'WaitingOnOthers' => TaskStatus.waitingOnOthers,
      'Deferred' => TaskStatus.deferred,
      _ => EwsSoap._invalid(),
    };
    final priority = switch (read('Importance')) {
      null || 'Normal' => TaskPriority.normal,
      'Low' => TaskPriority.low,
      'High' => TaskPriority.high,
      _ => EwsSoap._invalid(),
    };
    final reminder = EwsSoap._optional(item, 'ReminderIsSet', _types);
    final notes = read('Body');
    return RemoteTask(
      id: TaskId(id.id, list: list),
      revision: id.changeKey,
      fields: TaskFields(
        title: read('Subject') ?? '',
        notes: notes == null ? null : TaskText(notes),
        priority: priority,
        status: status,
        start: _taskTime(read('StartDate')),
        due: _taskTime(read('DueDate')),
        completedAt: status == TaskStatus.completed
            ? _taskTime(read('CompleteDate'))
            : null,
        reminder: reminder != null && EwsSoap._boolean(reminder)
            ? _taskTime(read('ReminderDueBy'))
            : null,
      ),
    );
  }
}

TaskDateTime? _taskTime(String? value) {
  if (value == null) return null;
  if (!RegExp(
    r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?(?:Z|[+-]\d\d:\d\d)$',
  ).hasMatch(value)) {
    EwsSoap._invalid();
  }
  final date = DateTime.tryParse(value);
  if (date == null) EwsSoap._invalid();
  return TaskDateTime(
    date.toUtc().toIso8601String().replaceFirst(RegExp(r'Z$'), ''),
    timeZone: 'UTC',
  );
}
