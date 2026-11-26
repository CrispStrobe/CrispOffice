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
              'calendar:Start',
              'calendar:End',
              'calendar:IsAllDayEvent',
              'calendar:Location',
              'calendar:CalendarItemType',
              'calendar:IsCancelled',
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
          if (item.name.local != 'CalendarItem' ||
              item.namespaceUri != _types) {
            EwsSoap._invalid();
          }
          final id = EwsSoap._id(EwsSoap._one(item, 'ItemId', _types)).id;
          if (!ids.add(id)) EwsSoap._invalid();
          if (ids.length > limits.maxPageSize) EwsSoap._quota();
          final budget = _HeaderBudget(limits.maxHeaderBytes);
          String? field(String name) =>
              EwsSoap._optionalText(item, name, budget);
          final cancelled = field('IsCancelled');
          if (cancelled != null && EwsSoap._parseBoolean(cancelled)) continue;
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
          if (dayEnd != null && !dayEnd.isAfter(dayStart!)) {
            EwsSoap._invalid();
          }
          events.add(
            EwsCalendarEvent(
              id: id,
              title: field('Subject') ?? '',
              start: start.instant,
              end: end.instant,
              location: field('Location'),
              allDayStart: dayStart,
              allDayEnd: dayEnd,
            ),
          );
        }
        return (complete: complete, events: events);
      });
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
