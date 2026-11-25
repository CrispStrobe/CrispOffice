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
  'task:IsRecurring',
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
            _operationField(builder);
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
              _readTask(response, list, ids[i]).$1
            else
              null,
        ];
      });

  (RemoteTask, bool?)? taskForWrite(String xml, TaskId id) =>
      EwsSoap._guard(() {
        final responses = _responses(xml, 'GetItem', allowMissing: true);
        if (responses.length != 1) EwsSoap._invalid();
        final response = responses.single;
        return response == null ? null : _readTask(response, id.list, id.value);
      });

  (RemoteTask, bool?) _readTask(
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
    final recurring = EwsSoap._optional(item, 'IsRecurring', _types);
    final marker = _readOperationMarker(item, budget);
    return (
      RemoteTask(
        id: TaskId(id.id, list: list),
        revision: id.changeKey,
        providerData: marker == null
            ? null
            : TaskProviderData(format: 'ews-task-operation', raw: marker),
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
      ),
      recurring == null ? null : EwsSoap._boolean(recurring),
    );
  }

  String createTask(String folder, TaskFields fields, String operationId) {
    final patch = TaskPatch.between(const TaskFields(title: ''), fields);
    final properties = _taskProperties(patch);
    return _request('CreateItem', (builder) {
      builder.element(
        'm:SavedItemFolderId',
        nest: () => _folderId(builder, folder),
      );
      builder.element(
        'm:Items',
        nest: () {
          builder.element(
            't:Task',
            nest: () {
              void write(bool taskField) {
                for (final property in properties.entries) {
                  if (property.key.startsWith('task:') == taskField) {
                    _writeProperty(builder, property.key, property.value!);
                  }
                }
              }

              write(false);
              builder.element(
                't:ExtendedProperty',
                nest: () {
                  _operationField(builder);
                  builder.element('t:Value', nest: operationId);
                },
              );
              write(true);
            },
          );
        },
      );
    }, attributes: const {'MessageDisposition': 'SaveOnly'});
  }

  String updateTask(TaskId id, String revision, TaskPatch patch) {
    final properties = _taskProperties(patch);
    return _request(
      'UpdateItem',
      (builder) {
        builder.element(
          'm:ItemChanges',
          nest: () {
            builder.element(
              't:ItemChange',
              nest: () {
                _itemId(builder, id.value, revision);
                builder.element(
                  't:Updates',
                  nest: () {
                    for (final property in properties.entries) {
                      final value = property.value;
                      builder.element(
                        value == null ? 't:DeleteItemField' : 't:SetItemField',
                        nest: () {
                          builder.element(
                            't:FieldURI',
                            attributes: {'FieldURI': property.key},
                          );
                          if (value != null) {
                            builder.element(
                              't:Task',
                              nest: () =>
                                  _writeProperty(builder, property.key, value),
                            );
                          }
                        },
                      );
                    }
                  },
                );
              },
            );
          },
        );
      },
      attributes: const {
        'MessageDisposition': 'SaveOnly',
        'ConflictResolution': 'NeverOverwrite',
      },
    );
  }

  String deleteTask(TaskId id, String revision) => _request(
    'DeleteItem',
    (builder) {
      builder.element(
        'm:ItemIds',
        nest: () => _itemId(builder, id.value, revision),
      );
    },
    attributes: const {
      'DeleteType': 'MoveToDeletedItems',
      'AffectedTaskOccurrences': 'AllOccurrences',
      'SuppressReadReceipts': 'true',
    },
  );

  EwsItemId? taskMutation(String xml, String action) => EwsSoap._guard(() {
    final responses = _responses(xml, action, taskMutation: true);
    if (responses.length != 1) EwsSoap._invalid();
    final items =
        EwsSoap._optional(
          responses.single!,
          'Items',
          _messages,
        )?.childElements.toList() ??
        const <XmlElement>[];
    if (action == 'DeleteItem' && items.isEmpty) return null;
    if (action == 'DeleteItem' || items.length != 1) EwsSoap._invalid();
    final item = items.single;
    _taskItem(item);
    return EwsSoap._id(EwsSoap._one(item, 'ItemId', _types));
  });
}

const _operationProperty = {
  'PropertySetId': '36162429-0c2c-4312-9ef6-975e936fcfb2',
  'PropertyName': 'CrispOfficeTaskOperation',
  'PropertyType': 'String',
};

void _operationField(XmlBuilder builder) =>
    builder.element('t:ExtendedFieldURI', attributes: _operationProperty);

String? _readOperationMarker(XmlElement item, _HeaderBudget budget) {
  String? marker;
  for (final extension in item.findElements(
    'ExtendedProperty',
    namespaceUri: _types,
  )) {
    final field = EwsSoap._one(extension, 'ExtendedFieldURI', _types);
    if (_operationProperty.entries.every(
      (entry) =>
          field.getAttribute(entry.key)?.toLowerCase() ==
          entry.value.toLowerCase(),
    )) {
      if (marker != null) EwsSoap._invalid();
      marker = EwsSoap._text(EwsSoap._one(extension, 'Value', _types), budget);
    }
  }
  return marker;
}

Map<String, String?> _taskProperties(TaskPatch patch) {
  if (patch.title.isClear ||
      patch.status.isClear ||
      patch.priority.isClear ||
      patch.reminder.isChanged ||
      patch.completedAt.value != null) {
    throw const EwsException(MailProblemCode.unsupported);
  }
  final title = patch.title.value;
  final notes = patch.notes.value;
  if (title != null && (title.trim().isEmpty || title.length > 1024) ||
      notes != null &&
          (notes.format != TaskTextFormat.text ||
              notes.value.length > 262144) ||
      [?title, ?notes?.value].any(
        (value) => value.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]')),
      )) {
    throw const EwsException(MailProblemCode.invalidInput);
  }
  if (patch.completedAt.isClear &&
      (patch.status.value == null ||
          patch.status.value == TaskStatus.completed)) {
    throw const EwsException(MailProblemCode.unsupported);
  }
  return {
    'item:Subject': ?title,
    if (notes != null) 'item:Body': notes.value,
    if (notes == null && patch.notes.isClear) 'item:Body': null,
    if (patch.priority.value case final priority?)
      'item:Importance': _capitalized(priority.name),
    if (patch.start.isChanged)
      'task:StartDate': _writeTaskTime(patch.start.value),
    if (patch.due.isChanged) 'task:DueDate': _writeTaskTime(patch.due.value),
    if (patch.status.value case final status?)
      'task:Status': switch (status) {
        TaskStatus.cancelled => throw const EwsException(
          MailProblemCode.unsupported,
        ),
        _ => _capitalized(status.name),
      },
  };
}

String _capitalized(String name) =>
    '${name[0].toUpperCase()}${name.substring(1)}';

String? _writeTaskTime(TaskDateValue? value) => switch (value) {
  null => null,
  TaskDate(:final year, :final month, :final day) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}T00:00:00Z',
  TaskDateTime(:final localDateTime, timeZone: 'UTC') => '${localDateTime}Z',
  _ => throw const EwsException(MailProblemCode.unsupported),
};

void _writeProperty(XmlBuilder builder, String field, String value) =>
    builder.element(
      't:${field.split(':').last}',
      nest: value,
      attributes: field == 'item:Body' ? const {'BodyType': 'Text'} : const {},
    );

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
