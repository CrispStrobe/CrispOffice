part of 'todo_document.dart';

/// The fields edited by the single-appointment editor. An all-day end is
/// exclusive. A timed event uses UTC so daylight-saving transitions are exact.
final class CalDavEventFields {
  const CalDavEventFields({
    required this.title,
    required this.start,
    required this.end,
    this.location,
    this.description,
  });

  factory CalDavEventFields.fromEvent(CalDavEvent event) => CalDavEventFields(
    title: event.title,
    start: event.start,
    end: event.end,
    location: event.location,
    description: event.description,
  );

  final String title;
  final CalDavDateValue start;
  final CalDavDateValue? end;
  final String? location;
  final String? description;

  void _validate() {
    if (title.trim().isEmpty ||
        (start.kind != CalDavDateKind.date &&
            start.kind != CalDavDateKind.utc) ||
        (end != null &&
            (end!.kind != start.kind ||
                end!.value.compareTo(start.value) <= 0))) {
      throw ArgumentError('Invalid calendar appointment bounds or title.');
    }
  }

  Map<String, String?> _contentLines() => {
    'SUMMARY': 'SUMMARY:${_encodeText(title)}',
    'DTSTART': start.contentLine('DTSTART'),
    'DTEND': end?.contentLine('DTEND'),
    'LOCATION': location == null ? null : 'LOCATION:${_encodeText(location!)}',
    'DESCRIPTION': description == null
        ? null
        : 'DESCRIPTION:${_encodeText(description!)}',
  };
}

/// An authoritative, unexpanded iCalendar resource safe for single-event edits.
final class CalDavEventDocument {
  const CalDavEventDocument._(
    this.event,
    this._lines,
    this._end,
    this._indexes,
  );

  factory CalDavEventDocument.parse(String source) {
    final agenda = readCalDavAgenda(source);
    if (agenda.unexpandedSeries != 0 || agenda.events.length != 1) {
      throw UnsupportedError('Resource is outside single-appointment editing.');
    }
    final event = agenda.events.single;
    if (event.recurrenceId != null ||
        (event.start.kind != CalDavDateKind.utc &&
            event.start.kind != CalDavDateKind.date) ||
        (event.end != null &&
            (event.end!.kind != event.start.kind ||
                event.end!.value.compareTo(event.start.value) <= 0))) {
      throw UnsupportedError('Resource is outside single-appointment editing.');
    }
    final lines = _readLines(source);
    final indexes = <String, int>{};
    var depth = 0;
    var end = -1;
    var inEvent = false;
    for (var index = 0; index < lines.length; index++) {
      final property = _Property.parse(lines[index].content);
      switch (property.name) {
        case 'BEGIN':
          if (depth == 1) {
            switch (property.value.toUpperCase()) {
              case 'VEVENT' when end == -1:
                inEvent = true;
              case 'VTIMEZONE':
                break;
              default:
                throw UnsupportedError('Resource contains other components.');
            }
          }
          depth++;
        case 'END':
          if (depth == 2 && inEvent) {
            end = index;
            inEvent = false;
          }
          depth--;
        default:
          if ((depth == 1 && property.name == 'METHOD') ||
              (inEvent &&
                  depth == 2 &&
                  const {
                    'ATTENDEE',
                    'ORGANIZER',
                    'DURATION',
                  }.contains(property.name))) {
            throw UnsupportedError(
              'Resource contains scheduling or duration data.',
            );
          }
          if (inEvent &&
              depth == 2 &&
              const {
                'DTSTAMP',
                'DTSTART',
                'DTEND',
                'SUMMARY',
                'LOCATION',
                'DESCRIPTION',
                'LAST-MODIFIED',
              }.contains(property.name)) {
            if (indexes.containsKey(property.name)) {
              throw const FormatException('Duplicate event property.');
            }
            indexes[property.name] = index;
          }
      }
    }
    return CalDavEventDocument._(event, lines, end, indexes);
  }

  final CalDavEvent event;
  final List<_Line> _lines;
  final int _end;
  final Map<String, int> _indexes;

  static String create({
    required String uid,
    required CalDavEventFields fields,
    required DateTime timestamp,
  }) {
    if (uid.trim().isEmpty) throw ArgumentError('Calendar event UID is empty.');
    fields._validate();
    final source = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//CrispOffice//Calendar//EN',
      'BEGIN:VEVENT',
      'UID:${_encodeText(uid)}',
      'DTSTAMP:${_eventStamp(timestamp)}',
      ...fields._contentLines().values.nonNulls,
      'END:VEVENT',
      'END:VCALENDAR',
    ].map(_foldLine).join();
    _validateSource(source);
    return source;
  }

  String update(CalDavEventFields fields, {required DateTime timestamp}) {
    fields._validate();
    final changes = fields._contentLines();
    final previous = CalDavEventFields.fromEvent(event)._contentLines();
    changes.removeWhere((key, value) => previous[key] == value);
    if (changes.isEmpty) return _lines.map((line) => line.raw).join();
    final stamp = _eventStamp(timestamp);
    changes['DTSTAMP'] = 'DTSTAMP:$stamp';
    if (_indexes.containsKey('LAST-MODIFIED')) {
      changes['LAST-MODIFIED'] = 'LAST-MODIFIED:$stamp';
    }
    final replacements = {
      for (final field in changes.entries) ?_indexes[field.key]: field.value,
    };
    final output = StringBuffer();
    for (var index = 0; index < _lines.length; index++) {
      if (index == _end) {
        for (final field in changes.entries) {
          if (!_indexes.containsKey(field.key) && field.value != null) {
            output.write(_foldLine(field.value!));
          }
        }
      }
      if (replacements.containsKey(index)) {
        final line = replacements[index];
        if (line != null) output.write(_foldLine(line));
      } else {
        output.write(_lines[index].raw);
      }
    }
    final result = output.toString();
    _validateSource(result);
    return result;
  }
}

String _eventStamp(DateTime timestamp) {
  final utc = timestamp.toUtc();
  if (utc.year < 1 || utc.year > 9999) {
    throw ArgumentError('Calendar event timestamp out of range.');
  }
  return '${utc.toIso8601String().split('.').first.replaceAll('-', '').replaceAll(':', '')}Z';
}
