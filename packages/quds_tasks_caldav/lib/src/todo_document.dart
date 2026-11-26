import 'dart:convert';

import 'package:quds_tasks_core/quds_tasks_core.dart';

import 'codec_limits.dart';
import 'date_value.dart';

part 'calendar_event.dart';
part 'calendar_event_document.dart';
part 'calendar_recurrence.dart';

/// Features that this first codec can preserve and read, but cannot safely edit.
enum CalDavTodoMutationBlocker {
  recurrence,
  duration,
  participants,
  relatedTasks,
  unknownStatus,
}

/// A single VTODO resource, including its original VCALENDAR and VTIMEZONE data.
///
/// Unchanged documents serialize byte-for-byte to their input Dart string.
/// Patches replace only the requested properties: unrelated properties,
/// parameters, folding, alarms, and time-zone components remain intact.
/// Multiple tasks/recurrence exceptions in one resource are rejected; they need
/// a series-aware codec before editing can be safe.
final class CalDavTodoDocument {
  CalDavTodoDocument._(
    this._lines,
    this._end,
    this._properties,
    this._indexes,
    this._definedTimeZones,
  );

  factory CalDavTodoDocument.parse(String source) =>
      _parse(source, allowOtherComponents: false)!;

  /// Reads a calendar resource from a mixed calendar. Well-formed resources
  /// containing only other component types do not project to a task.
  static CalDavTodoDocument? parseCalendarResource(String source) =>
      _parse(source, allowOtherComponents: true);

  static CalDavTodoDocument? _parse(
    String source, {
    required bool allowOtherComponents,
  }) {
    _validateSource(source);
    final lines = _readLines(source);
    final stack = <String>[];
    final properties = <String, List<_Property>>{};
    final indexes = <String, List<int>>{};
    final definedTimeZones = <String>{};
    var todoCount = 0;
    var hasOtherComponents = false;
    var rootCount = 0;
    var versionCount = 0;
    var end = -1;
    for (var i = 0; i < lines.length; i++) {
      final property = _Property.parse(lines[i].content);
      if (property.name == 'BEGIN') {
        if (property.rawParameters.isNotEmpty) {
          throw const FormatException(
            'Component markers cannot have parameters.',
          );
        }
        final component = property.value.toUpperCase();
        if (stack.isEmpty) {
          if (component != 'VCALENDAR' || ++rootCount != 1) {
            throw const FormatException('Expected one VCALENDAR resource.');
          }
        } else if (stack.length == 1) {
          if (component == 'VTODO') {
            todoCount++;
          } else if (component != 'VTIMEZONE') {
            hasOtherComponents = true;
          }
        } else if (component == 'VTODO' || component == 'VCALENDAR') {
          throw const FormatException(
            'Invalid nested task/calendar component.',
          );
        }
        if (stack.length >= CalDavCodecLimits.maxComponentDepth) {
          throw const FormatException(
            'iCalendar component nesting limit exceeded.',
          );
        }
        stack.add(component);
      } else if (property.name == 'END') {
        if (property.rawParameters.isNotEmpty) {
          throw const FormatException(
            'Component markers cannot have parameters.',
          );
        }
        if (stack.isEmpty || stack.last != property.value.toUpperCase()) {
          throw const FormatException('Unbalanced iCalendar component.');
        }
        if (stack.length == 2 && stack.last == 'VTODO') end = i;
        stack.removeLast();
      } else {
        if (stack.isEmpty) {
          throw const FormatException('Property outside VCALENDAR.');
        }
        if (stack.length == 1 && property.name == 'VERSION') {
          if (property.value != '2.0' || ++versionCount != 1) {
            throw const FormatException('Expected one iCalendar VERSION:2.0.');
          }
        }
        if (stack.length == 2 &&
            stack.last == 'VTIMEZONE' &&
            property.name == 'TZID') {
          final id = _decodeText(property.value);
          if (id.isEmpty || !definedTimeZones.add(id)) {
            throw const FormatException(
              'Ambiguous or empty VTIMEZONE identifier.',
            );
          }
        }
        if (stack.length == 2 && stack.last == 'VTODO') {
          properties.putIfAbsent(property.name, () => []).add(property);
          indexes.putIfAbsent(property.name, () => []).add(i);
        }
      }
    }
    if (stack.isNotEmpty || rootCount != 1 || versionCount != 1) {
      throw const FormatException('Expected a complete iCalendar resource.');
    }
    if (allowOtherComponents &&
        todoCount == 0 &&
        (hasOtherComponents || definedTimeZones.isNotEmpty)) {
      return null;
    }
    if (todoCount != 1 || hasOtherComponents || end < 0) {
      throw const FormatException(
        'Expected one complete VTODO; series resources are not editable.',
      );
    }
    for (final name in _singleValueProperties) {
      if ((properties[name]?.length ?? 0) > 1) {
        throw FormatException('Duplicate singleton VTODO property: $name.');
      }
    }
    final document = CalDavTodoDocument._(
      lines,
      end,
      properties,
      indexes,
      definedTimeZones,
    );
    if (document.uid.isEmpty) {
      throw const FormatException('A task needs a non-empty UID.');
    }
    // Parse the fields we expose now, so malformed date/number/text values
    // cannot fail later, halfway through a synchronization transaction.
    document.summary;
    document.description;
    document.start;
    document.due;
    document.completed;
    document.priority;
    document.percentComplete;
    return document;
  }

  factory CalDavTodoDocument.create({
    required String uid,
    required TaskFields fields,
    required DateTime timestamp,
  }) {
    if (uid.isEmpty) throw ArgumentError('A task needs a non-empty UID.');
    if (!timestamp.isUtc ||
        timestamp.year < 1 ||
        timestamp.year > 9999 ||
        timestamp.millisecond != 0 ||
        timestamp.microsecond != 0) {
      throw ArgumentError('DTSTAMP must be UTC with whole-second precision.');
    }
    final stamp = timestamp
        .toIso8601String()
        .substring(0, 19)
        .replaceAll('-', '')
        .replaceAll(':', '');
    final source = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//CrispOffice//Tasks CalDAV//EN',
      'BEGIN:VTODO',
      'UID:${_encodeText(uid)}',
      'DTSTAMP:${stamp}Z',
      'END:VTODO',
      'END:VCALENDAR',
    ].map(_foldLine).join();
    return CalDavTodoDocument.parse(source).apply(
      TaskPatch(
        title: TaskFieldPatch.set(fields.title),
        notes: fields.notes == null
            ? const TaskFieldPatch.unchanged()
            : TaskFieldPatch.set(fields.notes!),
        status: TaskFieldPatch.set(fields.status),
        priority: TaskFieldPatch.set(fields.priority),
        start: fields.start == null
            ? const TaskFieldPatch.unchanged()
            : TaskFieldPatch.set(fields.start!),
        due: fields.due == null
            ? const TaskFieldPatch.unchanged()
            : TaskFieldPatch.set(fields.due!),
        reminder: fields.reminder == null
            ? const TaskFieldPatch.unchanged()
            : TaskFieldPatch.set(fields.reminder!),
        completedAt: fields.completedAt == null
            ? const TaskFieldPatch.unchanged()
            : TaskFieldPatch.set(fields.completedAt!),
      ),
    );
  }

  final List<_Line> _lines;
  final int _end;
  final Map<String, List<_Property>> _properties;
  final Map<String, List<int>> _indexes;
  final Set<String> _definedTimeZones;

  static const _singleValueProperties = {
    'UID',
    'SUMMARY',
    'DESCRIPTION',
    'DTSTART',
    'DUE',
    'STATUS',
    'COMPLETED',
    'PRIORITY',
    'PERCENT-COMPLETE',
    'DTSTAMP',
  };

  String get uid => _decodeText(_single('UID')?.value ?? '');
  String? get summary => _text('SUMMARY');
  String? get description => _text('DESCRIPTION');
  String? get status => _single('STATUS')?.value.toUpperCase();
  CalDavDateValue? get start => _date('DTSTART');
  CalDavDateValue? get due => _date('DUE');
  CalDavDateValue? get completed {
    final date = _date('COMPLETED');
    if (date != null && date.kind != CalDavDateKind.utc) {
      throw const FormatException('COMPLETED must be a UTC date-time.');
    }
    return date;
  }

  int? get priority => _integer('PRIORITY', 0, 9);
  int? get percentComplete => _integer('PERCENT-COMPLETE', 0, 100);

  Set<CalDavTodoMutationBlocker> get mutationBlockers => Set.unmodifiable({
    if (const [
      'RRULE',
      'RDATE',
      'EXDATE',
      'RECURRENCE-ID',
    ].any(_properties.containsKey))
      CalDavTodoMutationBlocker.recurrence,
    if (_properties.containsKey('DURATION')) CalDavTodoMutationBlocker.duration,
    if (_properties.containsKey('ATTENDEE') ||
        _properties.containsKey('ORGANIZER'))
      CalDavTodoMutationBlocker.participants,
    if (_properties.containsKey('RELATED-TO'))
      CalDavTodoMutationBlocker.relatedTasks,
    if (status != null && !_knownStatuses.contains(status))
      CalDavTodoMutationBlocker.unknownStatus,
  });

  static const _knownStatuses = {
    'NEEDS-ACTION',
    'IN-PROCESS',
    'COMPLETED',
    'CANCELLED',
  };

  String encode() => _lines.map((line) => line.raw).join();

  /// The projection is deliberately smaller than the original resource.
  /// Alarms, categories, exact numeric priority, and extensions stay in raw data.
  TaskFields toTaskFields() => TaskFields(
    title: summary ?? '',
    notes: description == null ? null : TaskText(description!),
    status: switch (status) {
      null || 'NEEDS-ACTION' => TaskStatus.notStarted,
      'IN-PROCESS' => TaskStatus.inProgress,
      'COMPLETED' => TaskStatus.completed,
      'CANCELLED' => TaskStatus.cancelled,
      _ => throw UnsupportedError('Unknown VTODO status cannot be projected.'),
    },
    priority: switch (priority) {
      int() && >= 1 && <= 4 => TaskPriority.high,
      int() && >= 6 && <= 9 => TaskPriority.low,
      _ => TaskPriority.normal,
    },
    start: start?.toTaskDate(),
    due: due?.toTaskDate(),
    completedAt: completed?.toTaskDate(),
  );

  /// [id] is scoped to account/list and should identify the remote resource.
  /// It need not equal its iCalendar UID.
  RemoteTask toRemoteTask(TaskId id, {String? etag}) => RemoteTask(
    id: id,
    fields: toTaskFields(),
    revision: etag,
    providerData: TaskProviderData(format: 'text/calendar', raw: encode()),
  );

  /// Applies a core patch without reconstructing the task from a lossy model.
  ///
  /// This is not a recurrence/delegation engine. Such resources remain readable
  /// and serializable, but every nonempty mutation is refused. Reminder edits
  /// and HTML descriptions are also refused rather than silently simplified.
  CalDavTodoDocument apply(TaskPatch patch) {
    if (patch.isEmpty) return this;
    if (mutationBlockers.isNotEmpty) {
      throw UnsupportedError(
        'Task needs unsupported semantics: '
        '${mutationBlockers.map((blocker) => blocker.name).join(', ')}.',
      );
    }
    if (patch.reminder.isChanged) {
      throw UnsupportedError('VALARM changes are not implemented.');
    }
    final replacements = <String, String?>{};
    void scalar<T extends Object>(
      String name,
      TaskFieldPatch<T> field,
      String Function(T) encode, {
      bool canClear = true,
    }) {
      if (!field.isChanged) return;
      if (field.isClear) {
        if (!canClear) throw ArgumentError('$name cannot be cleared.');
        replacements[name] = null;
      } else {
        final value = encode(field.value!);
        replacements[name] = _single(name)?.withValue(value) ?? '$name:$value';
      }
    }

    scalar('SUMMARY', patch.title, _encodeText, canClear: false);
    scalar('DESCRIPTION', patch.notes, (notes) {
      if (notes.format != TaskTextFormat.text) {
        throw UnsupportedError('VTODO DESCRIPTION requires plain text.');
      }
      return _encodeText(notes.value);
    });
    scalar(
      'STATUS',
      patch.status,
      (status) => switch (status) {
        TaskStatus.notStarted => 'NEEDS-ACTION',
        TaskStatus.inProgress => 'IN-PROCESS',
        TaskStatus.completed => 'COMPLETED',
        TaskStatus.cancelled => 'CANCELLED',
        TaskStatus.waitingOnOthers ||
        TaskStatus.deferred => throw UnsupportedError(
          'This status has no faithful VTODO equivalent.',
        ),
      },
      canClear: false,
    );
    scalar(
      'PRIORITY',
      patch.priority,
      (priority) => switch (priority) {
        TaskPriority.high => '1',
        TaskPriority.normal => '5',
        TaskPriority.low => '9',
      },
      canClear: false,
    );

    void date(String name, TaskFieldPatch<TaskDateValue> field) {
      if (!field.isChanged) return;
      if (field.isClear) {
        replacements[name] = null;
      } else {
        final value = CalDavDateValue.fromTaskDate(field.value!);
        if (name == 'COMPLETED' && value.kind != CalDavDateKind.utc) {
          throw ArgumentError('Completion time must be a UTC date-time.');
        }
        if (value.kind == CalDavDateKind.zoned &&
            !_definedTimeZones.contains(value.timeZone)) {
          throw UnsupportedError(
            'Writing a zoned date requires a matching retained VTIMEZONE.',
          );
        }
        final dateLine = value.contentLine(name);
        final original = _single(name);
        // Preserve unknown parameters on a changed date while replacing only
        // the two parameters whose meaning changes with the date value.
        final extras = original?.rawParameters.where((part) {
          final key = part.split('=').first.toUpperCase();
          return key != 'VALUE' && key != 'TZID';
        }).toList();
        final colon = _colonIndex(dateLine);
        replacements[name] = extras == null || extras.isEmpty
            ? dateLine
            : '${dateLine.substring(0, colon)};${extras.join(';')}'
                  '${dateLine.substring(colon)}';
      }
    }

    date('DTSTART', patch.start);
    date('DUE', patch.due);
    date('COMPLETED', patch.completedAt);

    if (patch.status.isChanged && !patch.status.isClear) {
      if (patch.status.value == TaskStatus.completed) {
        replacements['PERCENT-COMPLETE'] =
            _single('PERCENT-COMPLETE')?.withValue('100') ??
            'PERCENT-COMPLETE:100';
      } else {
        if (!patch.completedAt.isChanged) replacements['COMPLETED'] = null;
        if (patch.status.value == TaskStatus.notStarted) {
          replacements['PERCENT-COMPLETE'] =
              _single('PERCENT-COMPLETE')?.withValue('0') ??
              'PERCENT-COMPLETE:0';
        } else if (percentComplete == 100) {
          replacements['PERCENT-COMPLETE'] = null;
        }
      }
    }

    final updated = <String>[];
    final byIndex = <int, String>{};
    for (final name in replacements.keys) {
      for (final index in _indexes[name] ?? const <int>[]) {
        byIndex[index] = name;
      }
    }
    for (var i = 0; i < _lines.length; i++) {
      if (i == _end) {
        for (final entry in replacements.entries) {
          if (!_indexes.containsKey(entry.key) && entry.value != null) {
            updated.add(_foldLine(entry.value!));
          }
        }
      }
      final key = byIndex[i];
      if (key == null) {
        updated.add(_lines[i].raw);
      } else if (replacements[key] != null) {
        updated.add(_foldLine(replacements[key]!));
      }
    }
    final outputLength = updated.fold<int>(
      0,
      (total, line) => total + line.length,
    );
    if (outputLength > CalDavCodecLimits.maxResourceCodeUnits) {
      throw const FormatException(
        'Updated iCalendar resource exceeds its limit.',
      );
    }
    final result = CalDavTodoDocument.parse(updated.join());
    if (patch.completedAt.isChanged &&
        !patch.completedAt.isClear &&
        result.status != 'COMPLETED') {
      throw ArgumentError('A completion time requires completed task status.');
    }
    if (patch.start.isChanged || patch.due.isChanged) {
      final start = result.start;
      final due = result.due;
      if (start != null && due != null) {
        if ((start.kind == CalDavDateKind.date) !=
            (due.kind == CalDavDateKind.date)) {
          throw ArgumentError('DTSTART and DUE must use the same value type.');
        }
        if (start.kind == due.kind &&
            start.timeZone == due.timeZone &&
            start.value.compareTo(due.value) >= 0) {
          throw ArgumentError('A task must be due strictly after its start.');
        }
      }
    }
    return result;
  }

  _Property? _single(String name) => _properties[name]?.first;
  String? _text(String name) {
    final value = _single(name)?.value;
    return value == null ? null : _decodeText(value);
  }

  CalDavDateValue? _date(String name) {
    final property = _single(name);
    return property == null
        ? null
        : CalDavDateValue.parse(
            property.value,
            valueType: property.parameter('VALUE'),
            timeZone: property.parameter('TZID'),
          );
  }

  int? _integer(String name, int min, int max) {
    final raw = _single(name)?.value;
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null || value < min || value > max) {
      throw FormatException('Invalid $name value.');
    }
    return value;
  }
}

final class _Line {
  const _Line(this.content, this.raw);
  final String content;
  final String raw;
}

List<_Line> _readLines(String source) {
  final result = <_Line>[];
  final rows = source.split('\n');
  StringBuffer? unfolded;
  StringBuffer? original;
  var unfoldedLength = 0;
  void flush() {
    if (unfolded != null) {
      result.add(_Line(unfolded.toString(), original.toString()));
    }
  }

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (i == rows.length - 1 && row.isEmpty) continue;
    final content = row.endsWith('\r') ? row.substring(0, row.length - 1) : row;
    final raw = '$row${i < rows.length - 1 ? '\n' : ''}';
    if (content.startsWith(' ') || content.startsWith('\t')) {
      if (unfolded == null) {
        throw const FormatException('Content line starts with an orphan fold.');
      }
      unfoldedLength += content.length - 1;
      if (unfoldedLength > CalDavCodecLimits.maxUnfoldedLineCodeUnits) {
        throw const FormatException('Unfolded iCalendar line limit exceeded.');
      }
      unfolded.write(content.substring(1));
      original!.write(raw);
    } else {
      if (content.isEmpty) throw const FormatException('Empty content line.');
      if (content.length > CalDavCodecLimits.maxUnfoldedLineCodeUnits) {
        throw const FormatException('iCalendar content line limit exceeded.');
      }
      flush();
      unfolded = StringBuffer(content);
      original = StringBuffer(raw);
      unfoldedLength = content.length;
    }
  }
  flush();
  return result;
}

void _validateSource(String source) {
  if (source.length > CalDavCodecLimits.maxResourceCodeUnits) {
    throw const FormatException('iCalendar resource size limit exceeded.');
  }
  var physicalLines = source.isEmpty ? 0 : 1;
  for (var i = 0; i < source.length; i++) {
    final code = source.codeUnitAt(i);
    if ((code < 32 && code != 9 && code != 10 && code != 13) || code == 127) {
      throw const FormatException('Forbidden control character in iCalendar.');
    }
    if (code == 13 &&
        (i + 1 == source.length || source.codeUnitAt(i + 1) != 10)) {
      throw const FormatException('Bare carriage return in iCalendar.');
    }
    if (code == 10 && i < source.length - 1) {
      if (++physicalLines > CalDavCodecLimits.maxPhysicalLines) {
        throw const FormatException('iCalendar physical line limit exceeded.');
      }
    }
  }
}

final class _Property {
  const _Property(this.name, this.head, this.value, this.rawParameters);

  factory _Property.parse(String content) {
    final colon = _colonIndex(content);
    if (colon < 1) {
      throw const FormatException('Invalid iCalendar content line.');
    }
    final head = content.substring(0, colon);
    final parts = _splitHead(head);
    final name = parts.first.toUpperCase();
    if (!RegExp(r'^[A-Z0-9-]+$').hasMatch(name)) {
      throw const FormatException('Invalid iCalendar property name.');
    }
    for (final parameter in parts.skip(1)) {
      final equals = parameter.indexOf('=');
      if (equals < 1 ||
          !RegExp(
            r'^[A-Za-z0-9-]+$',
          ).hasMatch(parameter.substring(0, equals))) {
        throw const FormatException('Invalid iCalendar parameter.');
      }
    }
    return _Property(
      name,
      head,
      content.substring(colon + 1),
      parts.skip(1).toList(),
    );
  }

  final String name;
  final String head;
  final String value;
  final List<String> rawParameters;

  String withValue(String value) => '$head:$value';

  String? parameter(String name) {
    String? value;
    for (final raw in rawParameters) {
      final equals = raw.indexOf('=');
      if (raw.substring(0, equals).toUpperCase() != name) continue;
      if (value != null) throw FormatException('Duplicate $name parameter.');
      value = raw.substring(equals + 1);
      if (value.startsWith('"')) {
        if (value.length < 2 || !value.endsWith('"')) {
          throw const FormatException('Unbalanced quoted parameter.');
        }
        value = value.substring(1, value.length - 1);
      }
      value = value.replaceAllMapped(RegExp(r'\^(\^|n|N|\x27)'), (match) {
        return switch (match.group(1)) {
          '^' => '^',
          'n' || 'N' => '\n',
          _ => '"',
        };
      });
    }
    return value;
  }
}

int _colonIndex(String line) {
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    if (line[i] == '"') quoted = !quoted;
    if (line[i] == ':' && !quoted) return i;
  }
  return -1;
}

List<String> _splitHead(String value) {
  final result = <String>[];
  var quoted = false;
  var start = 0;
  for (var i = 0; i < value.length; i++) {
    if (value[i] == '"') quoted = !quoted;
    if (value[i] == ';' && !quoted) {
      result.add(value.substring(start, i));
      start = i + 1;
    }
  }
  if (quoted) throw const FormatException('Unbalanced quoted parameter.');
  result.add(value.substring(start));
  return result;
}

String _decodeText(String value) {
  final result = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    if (value[i] != '\\') {
      result.write(value[i]);
      continue;
    }
    if (++i >= value.length) {
      throw const FormatException('Incomplete text escape.');
    }
    result.write(switch (value[i]) {
      'n' || 'N' => '\n',
      '\\' => '\\',
      ',' => ',',
      ';' => ';',
      _ => throw const FormatException('Invalid iCalendar text escape.'),
    });
  }
  return result.toString();
}

String _encodeText(String value) {
  if (value.length > CalDavCodecLimits.maxUnfoldedLineCodeUnits) {
    throw ArgumentError('Task text exceeds the codec content-line limit.');
  }
  if (value.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'))) {
    throw ArgumentError('Task text contains an invalid control character.');
  }
  return value
      .replaceAll('\\', '\\\\')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', r'\n')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,');
}

String _foldLine(String content) {
  if (content.length > CalDavCodecLimits.maxUnfoldedLineCodeUnits) {
    throw const FormatException(
      'Encoded iCalendar content line limit exceeded.',
    );
  }
  final result = StringBuffer();
  var octets = 0;
  for (final rune in content.runes) {
    final character = String.fromCharCode(rune);
    final size = utf8.encode(character).length;
    if (octets + size > 75) {
      result.write('\r\n ');
      octets = 1;
    }
    result.write(character);
    octets += size;
  }
  result.write('\r\n');
  return result.toString();
}
