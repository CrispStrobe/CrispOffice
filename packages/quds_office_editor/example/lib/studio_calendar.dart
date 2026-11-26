import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quds_tasks_caldav/quds_tasks_caldav_native.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

import 'studio_calendar_editor.dart';
import 'studio_calendar_grid.dart';
import 'studio_chrome.dart';
import 'studio_credential_storage.dart';
import 'studio_device_tasks.dart';
import 'studio_productivity_accounts.dart';

Widget buildStudioCalendar(
  String title,
  WidgetBuilder chromeBuilder,
  VoidCallback openConnections, {
  required bool compactRibbon,
  required bool showCommandLabels,
  required bool showGroupLabels,
}) => StudioCalendarPage(
  title: title,
  chromeBuilder: chromeBuilder,
  openConnections: openConnections,
  compactRibbon: compactRibbon,
  showCommandLabels: showCommandLabels,
  showGroupLabels: showGroupLabels,
);

final class StudioCalendarPage extends StatefulWidget {
  const StudioCalendarPage({
    super.key,
    required this.title,
    required this.chromeBuilder,
    required this.openConnections,
    this.compactRibbon = false,
    this.showCommandLabels = true,
    this.showGroupLabels = true,
    this.credentialStorage,
    this.openDavClient,
    this.initialDate,
  });

  final String title;
  final WidgetBuilder chromeBuilder;
  final VoidCallback openConnections;
  final bool compactRibbon;
  final bool showCommandLabels;
  final bool showGroupLabels;
  final StudioCredentialStorage? credentialStorage;
  final http.Client Function()? openDavClient;
  final DateTime? initialDate;

  @override
  State<StudioCalendarPage> createState() => _StudioCalendarPageState();
}

enum _EventAction { followUp, edit, delete }

typedef _CalendarKey = ({TaskAccountId account, Uri url});
typedef _CalendarSource = ({
  CalDavCalendarProvider provider,
  CalDavCalendar calendar,
  String accountLabel,
  int colorSlot,
});

_CalendarKey _calendarKey(CalDavCalendar calendar) =>
    (account: calendar.account, url: calendar.url);

typedef _CalendarTarget = ({
  CalDavCalendarProvider provider,
  CalDavCalendar calendar,
  int generation,
});

final class _StudioCalendarPageState extends State<StudioCalendarPage> {
  late final _storage =
      widget.credentialStorage ?? StudioCredentialStorage.instance;
  http.Client? _client;
  int _generation = 0;
  bool _busy = true;
  String? _error;
  String? _notice;
  var _hasAccounts = false;
  var _discovered = false;
  Map<_CalendarKey, _CalendarSource> _sources = {};
  Set<_CalendarKey>? _selection;
  List<String> _discoveryIssues = [];
  List<String> _issues = [];
  Map<CalDavEvent, _CalendarSource> _eventSources = {};
  final _colorSlots = <_CalendarKey, int>{};
  CalDavAgenda? _agenda;
  final _search = TextEditingController();
  late DateTime _anchor = _day(widget.initialDate ?? DateTime.now());
  StudioCalendarPeriod _period = StudioCalendarPeriod.week;
  bool _grid = false;

  DateTime get _start => _period.start(_anchor);
  DateTime get _end => _period.advance(_start, 1);

  Iterable<_CalendarSource> get _visibleSources => _sources.entries
      .where((entry) => _selection?.contains(entry.key) == true)
      .map((entry) => entry.value);

  _CalendarTarget _targetFor(_CalendarSource source) => (
    provider: source.provider,
    calendar: source.calendar,
    generation: _generation,
  );

  bool _currentTarget(_CalendarTarget target) {
    final key = _calendarKey(target.calendar);
    return mounted &&
        target.generation == _generation &&
        _selection?.contains(key) == true &&
        identical(_sources[key]?.provider, target.provider);
  }

  Color _sourceColor(_CalendarSource source, ColorScheme colors) {
    const accents = [
      Color(0xff15896c),
      Color(0xffa83e82),
      Color(0xffbd591c),
      Color(0xff6554c6),
      Color(0xff138595),
      Color(0xffa33f3f),
      Color(0xff7e8217),
    ];
    final slot = source.colorSlot % (accents.length + 1);
    return slot == 0 ? colors.primary : accents[slot - 1];
  }

  @override
  void initState() {
    super.initState();
    _storage.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _storage.removeListener(_reload);
    _search.dispose();
    _client?.close();
    super.dispose();
  }

  static DateTime _day(DateTime date, [int offset = 0]) =>
      DateTime(date.year, date.month, date.day + offset);

  Future<void> _reload({bool rediscover = true}) async {
    final generation = ++_generation;
    final revision = _storage.revision;
    bool current() =>
        mounted && generation == _generation && revision == _storage.revision;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _issues = rediscover ? [] : _discoveryIssues;
      _agenda = null;
      _eventSources = {};
    });
    try {
      if (rediscover || !_discovered) {
        _client?.close();
        _client = null;
        _discovered = false;
        setState(() => _sources = {});
        final vault = await _storage.storage;
        final catalog = await StudioTaskAccountCatalog.load(vault);
        if (!current()) return;
        final accounts = catalog.records.entries
            .where((entry) => entry.key.provider == 'caldav')
            .toList(growable: false);
        _hasAccounts = accounts.isNotEmpty;
        final sources = <_CalendarKey, _CalendarSource>{};
        final issues = <String>[];
        if (accounts.isNotEmpty) {
          final client = _client =
              widget.openDavClient?.call() ?? createNativeCalDavClient();
          bool authorized() =>
              mounted &&
              identical(_client, client) &&
              revision == _storage.revision;

          final discoveries = await _loadBatches(accounts, (entry) async {
            final account = entry.key;
            var label = 'CalDAV account';
            try {
              label = studioTaskAccountLabel(account, entry.value);
              final provider = CalDavCalendarProvider(
                account: account,
                settings: studioDavSettings(
                  entry.value,
                  useTaskCollection: false,
                ),
                client: client,
                appPassword: () async {
                  if (!authorized()) return null;
                  final fresh = await StudioTaskAccountCatalog.load(vault);
                  if (!authorized()) return null;
                  return fresh.records[account]?['secret'] as String?;
                },
              );
              final result = await provider.discoverCalendars();
              return (label: label, provider: provider, result: result);
            } on Object {
              return (
                label: label,
                provider: null,
                result: const TaskFailure<List<CalDavCalendar>>(
                  TaskProblem(TaskProblemCode.invalidInput),
                ),
              );
            }
          }, current);
          if (!current()) return;
          for (final discovery in discoveries) {
            switch (discovery.result) {
              case TaskSuccess(:final value):
                for (final calendar in value) {
                  final key = _calendarKey(calendar);
                  sources[key] = (
                    provider: discovery.provider!,
                    calendar: calendar,
                    accountLabel: discovery.label,
                    colorSlot: _colorSlots.putIfAbsent(
                      key,
                      () => _colorSlots.length,
                    ),
                  );
                }
              case TaskFailure(:final problem):
                issues.add('${discovery.label} · ${_problem(problem.code)}');
            }
          }
        }
        if (!current()) return;
        final initial =
            sources.keys
                .where((key) => key.account == catalog.active)
                .firstOrNull ??
            sources.keys.firstOrNull;
        setState(() {
          _discovered = true;
          _sources = sources;
          _discoveryIssues = issues;
          _issues = issues;
          if (initial != null) _selection ??= {initial};
        });
      }

      final visible = _visibleSources.toList(growable: false);
      if (visible.isEmpty) return;
      final start = _start.toUtc();
      final end = _end.toUtc();
      final results = await _loadBatches(
        visible,
        (source) async => (
          source: source,
          result: await source.provider.agenda(
            source.calendar,
            start: start,
            end: end,
          ),
        ),
        current,
      );
      if (!current()) return;
      final eventSources = <CalDavEvent, _CalendarSource>{};
      final issues = [..._discoveryIssues];
      var unexpanded = 0;
      var hasAgenda = false;
      for (final item in results) {
        switch (item.result) {
          case TaskSuccess(:final value):
            hasAgenda = true;
            unexpanded += value.unexpandedSeries;
            for (final event in value.events) {
              eventSources[event] = item.source;
            }
          case TaskFailure(:final problem):
            issues.add(
              '${_sourceName(item.source)} · ${_problem(problem.code)}',
            );
        }
      }
      final events = eventSources.keys.toList()
        ..sort((a, b) => _wallOrder(a.start).compareTo(_wallOrder(b.start)));
      setState(() {
        _eventSources = eventSources;
        _issues = issues;
        if (hasAgenda) {
          _agenda = CalDavAgenda(events, unexpandedSeries: unexpanded);
        }
      });
    } on Object {
      if (current()) setState(() => _error = 'Calendar could not load.');
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  static Future<List<R>> _loadBatches<T, R>(
    List<T> items,
    Future<R> Function(T) fetch,
    bool Function() current,
  ) async {
    const batchSize = 4;
    final results = <R>[];
    for (var index = 0; index < items.length && current(); index += batchSize) {
      results.addAll(
        await Future.wait(items.skip(index).take(batchSize).map(fetch)),
      );
    }
    return results;
  }

  static DateTime _wallOrder(CalDavDateValue value) {
    final date = studioCalendarDisplayTime(value);
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      date.hour,
      date.minute,
      date.second,
    );
  }

  String _sourceName(_CalendarSource source) =>
      '${source.calendar.name} (${source.accountLabel})';

  void _navigate([int? direction]) {
    _anchor = direction == null
        ? _day(DateTime.now())
        : _period.advance(_anchor, direction);
    unawaited(_reload(rediscover: false));
  }

  void _showDay(DateTime day) {
    if (_busy) return;
    _period = StudioCalendarPeriod.day;
    _anchor = _day(day);
    unawaited(_reload(rediscover: false));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
      initialDate: _anchor,
    );
    if (!mounted || picked == null || _busy) return;
    _anchor = _day(picked);
    await _reload(rediscover: false);
  }

  Future<void> _showEvent(CalDavEvent event) async {
    final locale = MaterialLocalizations.of(context);
    final title = event.title.isEmpty ? 'Untitled event' : event.title;
    final source = _eventSources[event];
    final target = source == null ? null : _targetFor(source);
    final hasRevision =
        target != null &&
        target.provider.hasEventRevision(target.calendar, event);
    final action = await showDialog<_EventAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: ListBody(
            children: [
              if (source != null && _visibleSources.length > 1)
                Text(_sourceName(source)),
              Text(_format(event.start, locale, showLocalZone: true)),
              if (event.end case final end?
                  when end.kind != CalDavDateKind.date)
                Text('Ends ${_format(end, locale, showLocalZone: true)}'),
              if (event.end?.toTaskDate() case TaskDate(
                :final year,
                :final month,
                :final day,
              ))
                if (DateTime.utc(year, month, day - 1) case final last
                    when studioCalendarDisplayTime(event.start).isBefore(last))
                  Text('Through ${locale.formatMediumDate(last)}'),
              if (event.location case final location? when location.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(location),
                ),
              if (event.description case final description?
                  when description.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(description),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (hasRevision && target.calendar.canDelete)
            TextButton(
              onPressed: () => Navigator.pop(context, _EventAction.delete),
              child: const Text('Delete'),
            ),
          if (hasRevision && target.calendar.canUpdate)
            TextButton(
              onPressed: () => Navigator.pop(context, _EventAction.edit),
              child: const Text('Edit'),
            ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _EventAction.followUp),
            icon: const Icon(Icons.add_task_outlined),
            label: const Text('Create follow-up task'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action != _EventAction.followUp) {
      if (target != null && _currentTarget(target)) {
        if (action == _EventAction.edit) {
          await _editEvent(event: event);
        } else {
          await _deleteEvent(target, event);
        }
      }
      return;
    }
    final day = studioCalendarDisplayTime(event.start);
    await createStudioFollowUpTask(
      context,
      title: title,
      due: TaskDate(day.year, day.month, day.day),
      notes: event.location,
    );
  }

  Future<CalDavEditableEvent?> _openEditable(
    _CalendarTarget target,
    CalDavEvent event,
  ) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await target.provider.openEvent(target.calendar, event);
      if (!_currentTarget(target)) return null;
      return switch (result) {
        TaskSuccess(:final value) => value,
        TaskFailure(:final problem) => _reportUneditable(problem),
      };
    } finally {
      if (_currentTarget(target)) setState(() => _busy = false);
    }
  }

  CalDavEditableEvent? _reportUneditable(TaskProblem problem) {
    _notice = _writeProblem(problem);
    return null;
  }

  Future<void> _editEvent({CalDavEvent? event, DateTime? startsAt}) async {
    if (_busy) return;
    final target = event == null
        ? await _chooseCreationTarget()
        : _eventSources[event] == null
        ? null
        : _targetFor(_eventSources[event]!);
    if (target == null ||
        !_currentTarget(target) ||
        _busy ||
        (event == null
            ? !target.calendar.canCreate
            : !target.calendar.canUpdate)) {
      return;
    }
    final editable = event == null ? null : await _openEditable(target, event);
    if (!mounted ||
        !_currentTarget(target) ||
        (event != null && editable == null)) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StudioCalendarEditor(
        initial:
            startsAt ?? DateTime(_anchor.year, _anchor.month, _anchor.day, 9),
        calendarName:
            _visibleSources.length > 1 &&
                _sources[_calendarKey(target.calendar)] != null
            ? _sourceName(_sources[_calendarKey(target.calendar)]!)
            : target.calendar.name,
        event: editable?.event,
        save: (fields) => _submitEvent(target, editable, fields),
      ),
    );
  }

  Future<_CalendarTarget?> _chooseCreationTarget() async {
    final writable = _visibleSources
        .where((source) => source.calendar.canCreate)
        .toList();
    if (writable.isEmpty) return null;
    if (writable.length == 1) return _targetFor(writable.single);
    final generation = _generation;
    final source = await showDialog<_CalendarSource>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Create in calendar'),
        children: [
          for (final calendar in writable)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, calendar),
              child: Text(_sourceName(calendar)),
            ),
        ],
      ),
    );
    return mounted && generation == _generation && source != null
        ? _targetFor(source)
        : null;
  }

  Future<StudioCalendarSaveFailure?> _submitEvent(
    _CalendarTarget target,
    CalDavEditableEvent? editable,
    CalDavEventFields fields,
  ) async {
    final problem = await _saveEvent(
      target,
      () {
        final timestamp = DateTime.now();
        if (editable != null) {
          return target.provider.updateEvent(
            editable,
            fields: fields,
            timestamp: timestamp,
          );
        }
        final random = Random.secure();
        final id = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        return target.provider.createEvent(
          target.calendar,
          operationId: id,
          fields: fields,
          timestamp: timestamp,
        );
      },
      success: editable == null ? 'Event created.' : 'Event saved.',
      date: studioCalendarDisplayTime(fields.start),
    );
    if (problem == null) return null;
    return (
      message: _writeProblem(problem),
      retryable:
          problem.mutationMayHaveOccurred != true &&
          (problem.code == TaskProblemCode.invalidInput ||
              problem.code == TaskProblemCode.throttled),
    );
  }

  Future<void> _deleteEvent(_CalendarTarget target, CalDavEvent event) async {
    if (_busy || !target.calendar.canDelete) return;
    final editable = await _openEditable(target, event);
    if (!mounted || !_currentTarget(target) || editable == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text(
          editable.event.title.isEmpty
              ? 'Untitled event'
              : editable.event.title,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete event'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_currentTarget(target) || _busy) return;
    final problem = await _saveEvent(
      target,
      () => target.provider.deleteEvent(editable),
      success: 'Event deleted.',
    );
    if (_currentTarget(target) && problem != null) {
      setState(() => _notice = _writeProblem(problem));
    }
  }

  Future<TaskProblem?> _saveEvent(
    _CalendarTarget target,
    Future<TaskResult<TaskUnit>> Function() operation, {
    required String success,
    DateTime? date,
  }) async {
    const retired = TaskProblem(TaskProblemCode.staleOperation);
    if (!_currentTarget(target) || _busy) return retired;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await operation();
      if (!_currentTarget(target)) return retired;
      if (result case TaskFailure(:final problem)) return problem;
      if (date != null) _anchor = _day(date);
      await _reload(rediscover: false);
      if (mounted && _generation == target.generation + 1) {
        setState(() => _notice = success);
      }
      return null;
    } finally {
      if (_currentTarget(target)) setState(() => _busy = false);
    }
  }

  String _writeProblem(TaskProblem problem) {
    if (problem.mutationMayHaveOccurred == true) {
      return 'The server may have applied the change. Refresh the calendar and check before trying again.';
    }
    return switch (problem.code) {
      TaskProblemCode.conflict =>
        'The event changed on the server. Refresh the calendar.',
      TaskProblemCode.unsupported =>
        'This event contains recurrence, invitations or date settings that require a different editor.',
      TaskProblemCode.permissionDenied =>
        'This calendar does not allow that change.',
      TaskProblemCode.invalidInput => 'Check the event title and dates.',
      TaskProblemCode.throttled => 'The calendar server asked to retry later.',
      TaskProblemCode.staleOperation =>
        'The calendar changed while you were editing. Refresh to continue.',
      TaskProblemCode.authenticationRequired => _problem(problem.code),
      _ => 'The calendar change could not be completed.',
    };
  }

  String _problem(TaskProblemCode code) => switch (code) {
    TaskProblemCode.authenticationRequired => 'Reconnect the CalDAV account.',
    TaskProblemCode.permissionDenied =>
      'This account cannot read the calendar.',
    TaskProblemCode.throttled => 'The calendar server asked to retry later.',
    _ => 'Calendar could not load.',
  };

  Future<void> _chooseCalendars() async {
    final original = _selection ?? const <_CalendarKey>{};
    final selected = {...original};
    final generation = _generation;
    final colors = Theme.of(context).colorScheme;
    final byAccount = <TaskAccountId, List<_CalendarSource>>{};
    for (final source in _sources.values) {
      byAccount.putIfAbsent(source.calendar.account, () => []).add(source);
    }
    final result = await showDialog<Set<_CalendarKey>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          scrollable: true,
          title: const Text('Calendars'),
          content: SizedBox(
            width: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final calendars in byAccount.values) ...[
                  Text(
                    calendars.first.accountLabel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final source in calendars)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.circle,
                        size: 11,
                        color: _sourceColor(source, colors),
                      ),
                      title: Text(source.calendar.name),
                      value: selected.contains(_calendarKey(source.calendar)),
                      onChanged: (checked) => refresh(() {
                        final key = _calendarKey(source.calendar);
                        if (checked == true) {
                          selected.add(key);
                        } else {
                          selected.remove(key);
                        }
                      }),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, {...selected, ..._sources.keys}),
              child: const Text('Show all'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (!mounted ||
        _busy ||
        generation != _generation ||
        result == null ||
        (result.length == original.length && result.containsAll(original))) {
      return;
    }
    _selection = result;
    await _reload(rediscover: false);
  }

  Future<void> _showIssues() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Calendar loading issues'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final issue in _issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(issue),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  String _emptyMessage(bool filtering, int shownCalendars, String period) {
    if (!_hasAccounts) {
      return 'Connect a CalDAV account in Tasks to see its calendars here.';
    }
    if (_sources.isEmpty) {
      return _issues.isEmpty
          ? 'No event calendars found.'
          : 'Calendar data is unavailable.';
    }
    if (shownCalendars == 0) return 'Choose calendars to display.';
    if (_agenda == null) return 'Calendar data is unavailable.';
    if (filtering) return 'No events match your search in this range.';
    return 'No events this $period.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = MaterialLocalizations.of(context);
    final allEvents = _agenda?.events ?? const <CalDavEvent>[];
    final query = _search.text.trim().toLowerCase();
    final events = query.isEmpty
        ? allEvents
        : allEvents
              .where(
                (event) =>
                    event.title.toLowerCase().contains(query) ||
                    event.location?.toLowerCase().contains(query) == true ||
                    event.description?.toLowerCase().contains(query) == true,
              )
              .toList(growable: false);
    final visible = _visibleSources.toList(growable: false);
    final multiple = visible.length > 1;
    final canCreate =
        !_busy && visible.any((source) => source.calendar.canCreate);
    final period = _period.label.toLowerCase();
    StudioCmd command(
      IconData icon,
      String label,
      VoidCallback? action, {
      bool selected = false,
    }) => StudioCmd(
      icon: icon,
      label: label,
      accent: colors.primary,
      foreground: colors.onSurface,
      onPressed: action,
      selected: selected,
    );
    return Scaffold(
      backgroundColor: colors.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.chromeBuilder(context),
          StudioRibbonStyle(
            compact: widget.compactRibbon,
            showCommandLabels: widget.showCommandLabels,
            showGroupLabels: widget.showGroupLabels,
            child: SizedBox(
              height: StudioRibbonStrip.preferredHeight(
                context,
                compact: widget.compactRibbon,
                showCommandLabels: widget.showCommandLabels,
                showGroupLabels: widget.showGroupLabels,
              ),
              child: StudioRibbonStrip(
                groups: [
                  StudioRibbonGroup(
                    id: 'calendar-events',
                    title: 'Events',
                    children: [
                      command(
                        Icons.add_circle_outline,
                        'New event',
                        canCreate ? _editEvent : null,
                      ),
                    ],
                  ),
                  StudioRibbonGroup(
                    id: 'calendar-navigation',
                    title: 'Calendar',
                    children: [
                      command(
                        Icons.chevron_left,
                        'Previous $period',
                        _busy ? null : () => _navigate(-1),
                      ),
                      command(
                        Icons.today_outlined,
                        'Today',
                        _busy ? null : _navigate,
                      ),
                      command(
                        Icons.chevron_right,
                        'Next $period',
                        _busy ? null : () => _navigate(1),
                      ),
                      command(
                        Icons.event_outlined,
                        'Go to date',
                        _busy ? null : _pickDate,
                      ),
                      StudioCommandMenu(
                        icon: _period.icon,
                        label: 'Range',
                        currentValue: _period.label,
                        accent: colors.primary,
                        foreground: colors.onSurface,
                        commands: [
                          for (final option in StudioCalendarPeriod.values)
                            command(
                              option.icon,
                              option.label,
                              _busy
                                  ? null
                                  : () {
                                      if (_period == option) return;
                                      _period = option;
                                      unawaited(_reload(rediscover: false));
                                    },
                              selected: option == _period,
                            ),
                        ],
                      ),
                      command(
                        _grid ? Icons.view_agenda_outlined : _period.icon,
                        _grid ? 'Show agenda' : 'Show grid',
                        _busy ? null : () => setState(() => _grid = !_grid),
                      ),
                    ],
                  ),
                  StudioRibbonGroup(
                    id: 'calendar-connection',
                    title: 'Accounts',
                    children: [
                      command(
                        Icons.manage_accounts_outlined,
                        'Connections',
                        widget.openConnections,
                      ),
                      command(Icons.sync, 'Refresh', _busy ? null : _reload),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 2,
            thickness: 2,
            color: colors.primary.withValues(alpha: 0.35),
          ),
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _period == StudioCalendarPeriod.day
                      ? date.formatFullDate(_start)
                      : '${date.formatMediumDate(_start)} – ${date.formatMediumDate(_day(_end, -1))}',
                ),
                if (_sources.isNotEmpty)
                  OutlinedButton.icon(
                    key: const ValueKey('studio-calendar-picker'),
                    onPressed: _busy ? null : _chooseCalendars,
                    icon: const Icon(Icons.calendar_view_month_outlined),
                    label: Text(
                      visible.isEmpty
                          ? 'Choose calendars'
                          : multiple
                          ? '${visible.length} calendars'
                          : visible.single.calendar.name,
                    ),
                  ),
                if (visible.isNotEmpty)
                  SizedBox(
                    width: 232,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Search this range',
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(_search.clear),
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_error case final error?)
            Padding(padding: const EdgeInsets.all(12), child: Text(error)),
          if (_issues.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.info_outline),
                onPressed: _showIssues,
                label: Text(
                  _issues.length == 1
                      ? 'One calendar source could not load'
                      : '${_issues.length} calendar sources could not load',
                ),
              ),
            ),
          if (_notice case final notice?)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Semantics(liveRegion: true, child: Text(notice)),
            ),
          if (_agenda?.unexpandedSeries case final count? when count > 0)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('$count recurring series could not be expanded.'),
            ),
          Expanded(
            child:
                _grid && _agenda != null && (query.isEmpty || events.isNotEmpty)
                ? StudioCalendarGrid(
                    key: ValueKey((_period, _start)),
                    period: _period,
                    start: _start,
                    end: _end,
                    events: events,
                    openEvent: _showEvent,
                    openDay: _showDay,
                    createEvent: canCreate
                        ? (startsAt) => _editEvent(startsAt: startsAt)
                        : null,
                    appearanceOf: multiple
                        ? (event) {
                            final source = _eventSources[event];
                            return source == null
                                ? null
                                : (
                                    label: _sourceName(source),
                                    color: _sourceColor(source, colors),
                                  );
                          }
                        : null,
                  )
                : !_busy && _error == null && events.isEmpty
                ? Center(
                    child: Text(
                      _emptyMessage(query.isNotEmpty, visible.length, period),
                    ),
                  )
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      final when = _format(event.start, date);
                      final source = _eventSources[event];
                      return ListTile(
                        onTap: () => _showEvent(event),
                        textColor: colors.onSurface,
                        leading: Icon(
                          Icons.event_outlined,
                          color: !multiple || source == null
                              ? colors.onSurfaceVariant
                              : _sourceColor(source, colors),
                        ),
                        title: Text(
                          event.title.isEmpty ? 'Untitled event' : event.title,
                        ),
                        subtitle: Text(
                          [
                            when,
                            if (multiple && source != null) _sourceName(source),
                            if (event.location case final location?
                                when location.isNotEmpty)
                              location,
                          ].join(' · '),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _format(
    CalDavDateValue value,
    MaterialLocalizations locale, {
    bool showLocalZone = false,
  }) {
    final wall = value.toTaskDate();
    if (wall case TaskDate(:final year, :final month, :final day)) {
      return '${locale.formatMediumDate(DateTime(year, month, day))} · All day';
    }
    final shown = studioCalendarDisplayTime(value);
    final date = locale.formatMediumDate(shown);
    final clock = locale.formatTimeOfDay(TimeOfDay.fromDateTime(shown));
    final zone = switch (value.kind) {
      CalDavDateKind.zoned => value.timeZone,
      CalDavDateKind.utc when showLocalZone => shown.timeZoneName,
      _ => null,
    };
    return '$date · $clock${zone == null || zone.isEmpty ? '' : ' $zone'}';
  }
}
