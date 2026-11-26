part of 'soap.dart';

extension EwsCalendarSoap on EwsSoap {
  String findCalendarEvents(
    String folder, {
    required DateTime start,
    required DateTime end,
  }) => _request('FindItem', (builder) {
    builder.element(
      'm:ItemShape',
      nest: () {
        builder.element('t:BaseShape', nest: 'IdOnly');
        builder.element(
          't:AdditionalProperties',
          nest: () {
            for (final field in const [
              'item:Subject',
              'item:Categories',
              'calendar:Start',
              'calendar:End',
              'calendar:IsAllDayEvent',
              'calendar:Location',
              'calendar:CalendarItemType',
              'calendar:IsCancelled',
              'calendar:IsMeeting',
            ]) {
              builder.element('t:FieldURI', attributes: {'FieldURI': field});
            }
          },
        );
      },
    );
    builder.element(
      'm:CalendarView',
      attributes: {
        'MaxEntriesReturned': '${limits.maxPageSize}',
        'StartDate': start.toIso8601String(),
        'EndDate': end.toIso8601String(),
      },
    );
    builder.element(
      'm:ParentFolderIds',
      nest: () {
        _folderId(builder, folder);
      },
    );
  }, attributes: const {'Traversal': 'Shallow'});

  ({bool complete, List<EwsCalendarEvent> events}) calendarEvents(String xml) =>
      EwsSoap._guard(() {
        final responses = _responses(xml, 'FindItem');
        if (responses.length != 1) EwsSoap._invalid();
        final root = EwsSoap._one(responses.single!, 'RootFolder', _messages);
        final complete = EwsSoap._parseBoolean(
          root.getAttribute('IncludesLastItemInRange'),
        );
        final items = EwsSoap._one(root, 'Items', _types);
        final events = <EwsCalendarEvent>[];
        final ids = <String>{};
        for (final item in items.childElements) {
          final id = _calendarItemId(item);
          if (!ids.add(id.id)) EwsSoap._invalid();
          if (ids.length > limits.maxPageSize) EwsSoap._quota();
          final event = _calendarEvent(item, id);
          if (event != null) events.add(event);
        }
        return (complete: complete, events: events);
      });

  String getCalendarAppointment(String id) => _request('GetItem', (builder) {
    builder.element(
      'm:ItemShape',
      nest: () {
        builder.element('t:BaseShape', nest: 'IdOnly');
        builder.element('t:BodyType', nest: 'Text');
        builder.element(
          't:AdditionalProperties',
          nest: () {
            for (final field in const [
              'item:Subject',
              'item:Body',
              'item:Categories',
              'item:ParentFolderId',
              'calendar:Start',
              'calendar:End',
              'calendar:IsAllDayEvent',
              'calendar:Location',
              'calendar:CalendarItemType',
              'calendar:IsCancelled',
              'calendar:IsMeeting',
            ]) {
              builder.element('t:FieldURI', attributes: {'FieldURI': field});
            }
          },
        );
      },
    );
    builder.element('m:ItemIds', nest: () => _itemId(builder, id));
  });

  EwsCalendarEvent calendarAppointment(
    String xml, {
    required String folder,
    required String id,
    required String revision,
  }) => EwsSoap._guard(() {
    final responses = _responses(xml, 'GetItem', allowMissing: true);
    if (responses.length != 1) EwsSoap._invalid();
    final response = responses.single;
    if (response == null) throw const EwsException(MailProblemCode.conflict);
    final items = EwsSoap._one(response, 'Items', _messages).childElements;
    if (items.length != 1) EwsSoap._invalid();
    final item = items.single;
    final identity = _calendarItemId(item);
    final parent = EwsSoap._one(item, 'ParentFolderId', _types);
    if (identity.id != id ||
        identity.changeKey != revision ||
        parent.getAttribute('Id') != folder) {
      throw const EwsException(MailProblemCode.conflict);
    }
    final event = _calendarEvent(item, identity);
    if (event == null || event.appointmentRevision == null) {
      throw const EwsException(MailProblemCode.unsupported);
    }
    return event;
  });

  String createCalendarAppointment(
    String folder,
    EwsAppointmentFields fields,
  ) => _request(
    'CreateItem',
    (builder) {
      builder.element(
        'm:SavedItemFolderId',
        nest: () => _folderId(builder, folder),
      );
      builder.element(
        'm:Items',
        nest: () {
          builder.element(
            't:CalendarItem',
            nest: () {
              for (final entry in _appointmentProperties(fields).entries) {
                if (entry.value != null) {
                  _writeProperty(builder, entry.key, entry.value!);
                }
              }
            },
          );
        },
      );
    },
    attributes: const {
      'MessageDisposition': 'SaveOnly',
      'SendMeetingInvitations': 'SendToNone',
    },
  );

  String updateCalendarAppointment(
    String id,
    String revision,
    Map<String, String?> changes,
  ) => _request(
    'UpdateItem',
    (builder) {
      builder.element(
        'm:ItemChanges',
        nest: () {
          builder.element(
            't:ItemChange',
            nest: () {
              _itemId(builder, id, revision);
              builder.element(
                't:Updates',
                nest: () {
                  for (final entry in changes.entries) {
                    final value = entry.value;
                    builder.element(
                      value == null ? 't:DeleteItemField' : 't:SetItemField',
                      nest: () {
                        builder.element(
                          't:FieldURI',
                          attributes: {'FieldURI': entry.key},
                        );
                        if (value != null) {
                          builder.element(
                            't:CalendarItem',
                            nest: () =>
                                _writeProperty(builder, entry.key, value),
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
      'SendMeetingInvitationsOrCancellations': 'SendToNone',
    },
  );

  String deleteCalendarAppointment(String id, String revision) => _request(
    'DeleteItem',
    (builder) {
      builder.element('m:ItemIds', nest: () => _itemId(builder, id, revision));
    },
    attributes: const {
      'DeleteType': 'MoveToDeletedItems',
      'SendMeetingCancellations': 'SendToNone',
    },
  );

  EwsItemId? calendarMutation(String xml, String action) => EwsSoap._guard(() {
    final responses = _responses(xml, action, taskMutation: true);
    if (responses.length != 1) EwsSoap._invalid();
    final response = responses.single!;
    final conflicts = EwsSoap._optional(response, 'ConflictResults', _messages);
    if (conflicts != null &&
        EwsSoap._one(conflicts, 'Count', _types).innerText != '0') {
      throw const EwsException(MailProblemCode.conflict);
    }
    final items =
        EwsSoap._optional(
          response,
          'Items',
          _messages,
        )?.childElements.toList() ??
        const <XmlElement>[];
    if (action == 'DeleteItem' && items.isEmpty) return null;
    if (action == 'DeleteItem' || items.length != 1) EwsSoap._invalid();
    return _calendarItemId(items.single);
  });

  EwsItemId _calendarItemId(XmlElement item) {
    if (item.name.local != 'CalendarItem' || item.namespaceUri != _types) {
      EwsSoap._invalid();
    }
    return EwsSoap._id(EwsSoap._one(item, 'ItemId', _types));
  }

  EwsCalendarEvent? _calendarEvent(XmlElement item, EwsItemId id) {
    final budget = _HeaderBudget(limits.maxHeaderBytes);
    String? field(String name) => EwsSoap._optionalText(item, name, budget);
    final cancelled = field('IsCancelled');
    if (cancelled != null && EwsSoap._parseBoolean(cancelled)) return null;
    final meeting = field('IsMeeting');
    final isAppointment = meeting != null && !EwsSoap._parseBoolean(meeting);
    final type = field('CalendarItemType');
    if (!const {'Single', 'Occurrence', 'Exception'}.contains(type)) {
      EwsSoap._invalid();
    }
    final allDay = EwsSoap._parseBoolean(field('IsAllDayEvent'));
    final start = _calendarTime(field('Start'));
    final end = _calendarTime(field('End'));
    if (end.instant.isBefore(start.instant)) EwsSoap._invalid();
    final dayStart = allDay ? start.date : null;
    final dayEnd = allDay ? end.date : null;
    if (dayEnd != null && !dayEnd.isAfter(dayStart!)) EwsSoap._invalid();
    final categories = EwsSoap._optional(item, 'Categories', _types);
    return EwsCalendarEvent(
      id: id.id,
      title: field('Subject') ?? '',
      start: start.instant,
      end: end.instant,
      location: field('Location'),
      description: field('Body'),
      categories: categories == null
          ? const []
          : List.unmodifiable(
              categories
                  .findElements('String', namespaceUri: _types)
                  .map((entry) => EwsSoap._text(entry, budget)),
            ),
      allDayStart: dayStart,
      allDayEnd: dayEnd,
      appointmentRevision:
          type == 'Single' &&
              isAppointment &&
              !allDay &&
              end.instant.isAfter(start.instant)
          ? id.changeKey
          : null,
    );
  }
}

final _calendarTimestamp = RegExp(
  r'^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d{1,7})?(Z|[+-]\d\d:\d\d)$',
);

({DateTime instant, DateTime date}) _calendarTime(String? value) {
  final match = value == null ? null : _calendarTimestamp.firstMatch(value);
  if (match == null) EwsSoap._invalid();
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final wall = DateTime.utc(year, month, day);
  final offset = match[7]!;
  if (year < 1 ||
      wall.month != month ||
      wall.day != day ||
      int.parse(match[4]!) > 23 ||
      int.parse(match[5]!) > 59 ||
      int.parse(match[6]!) > 59 ||
      (offset != 'Z' &&
          (int.parse(offset.substring(1, 3)) > 14 ||
              int.parse(offset.substring(4)) > 59))) {
    EwsSoap._invalid();
  }
  final instant = DateTime.parse(value!).toUtc();
  // An explicit offset carries the original wall date. Exchange can also
  // normalize timestamps to UTC, which the agenda displays in the local zone.
  final display = offset == 'Z' && (instant.hour != 0 || instant.minute != 0)
      ? instant.toLocal()
      : wall;
  return (
    instant: instant,
    date: DateTime.utc(display.year, display.month, display.day),
  );
}

Map<String, String?> _appointmentProperties(EwsAppointmentFields fields) => {
  'item:Subject': fields.title,
  'item:Body': fields.description,
  'calendar:Start': fields.start.toIso8601String(),
  'calendar:End': fields.end.toIso8601String(),
  'calendar:Location': fields.location,
};

Map<String, String?> ewsAppointmentChanges(
  EwsAppointmentFields before,
  EwsAppointmentFields after,
) {
  final previous = _appointmentProperties(before);
  return _appointmentProperties(after)
    ..removeWhere((key, value) => previous[key] == value);
}
