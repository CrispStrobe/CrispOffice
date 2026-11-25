import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quds_tasks_caldav/quds_tasks_caldav_native.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

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

final class _StudioCalendarPageState extends State<StudioCalendarPage> {
  late final _storage =
      widget.credentialStorage ?? StudioCredentialStorage.instance;
  http.Client? _client;
  CalDavCalendarProvider? _provider;
  int _generation = 0;
  bool _busy = true;
  String? _error;
  Map<TaskAccountId, String> _accounts = {};
  TaskAccountId? _account;
  List<CalDavCalendar> _calendars = [];
  Uri? _calendar;
  CalDavAgenda? _agenda;
  late DateTime _anchor = _day(widget.initialDate ?? DateTime.now());
  StudioCalendarPeriod _period = StudioCalendarPeriod.week;
  bool _grid = false;

  DateTime get _start => _period.start(_anchor);
  DateTime get _end => _period.advance(_start, 1);

  @override
  void initState() {
    super.initState();
    _storage.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _storage.removeListener(_reload);
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
      _agenda = null;
    });
    try {
      if (rediscover || _provider == null) {
        _provider = null;
        _client?.close();
        _client = null;
        setState(() => _calendars = []);
        final vault = await _storage.storage;
        final catalog = await StudioTaskAccountCatalog.load(vault);
        if (!current()) return;
        final accounts = {
          for (final entry in catalog.records.entries)
            if (entry.key.provider == 'caldav') entry.key: entry.value,
        };
        final account = accounts.containsKey(_account)
            ? _account
            : accounts.containsKey(catalog.active)
            ? catalog.active
            : accounts.keys.firstOrNull;
        setState(() {
          _accounts = {
            for (final entry in accounts.entries)
              entry.key: studioTaskAccountLabel(entry.key, entry.value),
          };
          if (_account != account) _calendar = null;
          _account = account;
        });
        if (account == null) return;
        final client = _client =
            widget.openDavClient?.call() ?? createNativeCalDavClient();
        bool authorized() =>
            mounted &&
            identical(_client, client) &&
            revision == _storage.revision;
        final provider = CalDavCalendarProvider(
          account: account,
          settings: studioDavSettings(
            accounts[account]!,
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
        final lists = await provider.discoverCalendars();
        if (!current()) return;
        if (lists case TaskFailure(:final problem)) {
          setState(() => _error = _problem(problem.code));
          return;
        }
        final calendars = (lists as TaskSuccess<List<CalDavCalendar>>).value;
        final selected =
            calendars.where((item) => item.url == _calendar).firstOrNull ??
            calendars.firstOrNull;
        setState(() {
          _provider = provider;
          _calendars = calendars;
          _calendar = selected?.url;
        });
      }
      final selected = _calendars
          .where((item) => item.url == _calendar)
          .firstOrNull;
      if (selected == null) return;
      final result = await _provider!.agenda(
        selected,
        start: _start.toUtc(),
        end: _end.toUtc(),
      );
      if (!current()) return;
      setState(() {
        switch (result) {
          case TaskSuccess(:final value):
            _agenda = value;
          case TaskFailure(:final problem):
            _error = _problem(problem.code);
        }
      });
    } on Object {
      if (current()) setState(() => _error = 'Calendar could not load.');
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

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
    final followUp = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: ListBody(
            children: [
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
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.add_task_outlined),
            label: const Text('Create follow-up task'),
          ),
        ],
      ),
    );
    if (!mounted || followUp != true) return;
    final day = studioCalendarDisplayTime(event.start);
    await createStudioFollowUpTask(
      context,
      title: title,
      due: TaskDate(day.year, day.month, day.day),
      notes: event.location,
    );
  }

  String _problem(TaskProblemCode code) => switch (code) {
    TaskProblemCode.authenticationRequired => 'Reconnect the CalDAV account.',
    TaskProblemCode.permissionDenied =>
      'This account cannot read the calendar.',
    TaskProblemCode.throttled => 'The calendar server asked to retry later.',
    _ => 'Calendar could not load.',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = MaterialLocalizations.of(context);
    final events = _agenda?.events ?? const <CalDavEvent>[];
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
                if (_accounts.isNotEmpty)
                  DropdownButton<TaskAccountId>(
                    value: _account,
                    hint: const Text('Calendar account'),
                    onChanged: _busy
                        ? null
                        : (value) {
                            _account = value;
                            _calendar = null;
                            unawaited(_reload());
                          },
                    items: [
                      for (final entry in _accounts.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                  ),
                if (_calendars.isNotEmpty)
                  DropdownButton<Uri>(
                    value: _calendar,
                    hint: const Text('Calendar'),
                    onChanged: _busy
                        ? null
                        : (value) {
                            _calendar = value;
                            unawaited(_reload(rediscover: false));
                          },
                    items: [
                      for (final calendar in _calendars)
                        DropdownMenuItem(
                          value: calendar.url,
                          child: Text(calendar.name),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (_error case final error?)
            Padding(padding: const EdgeInsets.all(12), child: Text(error)),
          if (_agenda?.unexpandedSeries case final count? when count > 0)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('$count recurring series could not be expanded.'),
            ),
          Expanded(
            child: _grid && _agenda != null
                ? StudioCalendarGrid(
                    key: ValueKey((_period, _start)),
                    period: _period,
                    start: _start,
                    end: _end,
                    events: events,
                    openEvent: _showEvent,
                    openDay: _showDay,
                  )
                : !_busy && _error == null && events.isEmpty
                ? Center(
                    child: Text(
                      _accounts.isEmpty
                          ? 'Connect a CalDAV account in Tasks to see its calendars here.'
                          : _calendars.isEmpty
                          ? 'This account has no event calendars.'
                          : 'No events this $period.',
                    ),
                  )
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      final when = _format(event.start, date);
                      return ListTile(
                        onTap: () => _showEvent(event),
                        textColor: colors.onSurface,
                        leading: Icon(
                          Icons.event_outlined,
                          color: colors.onSurfaceVariant,
                        ),
                        title: Text(
                          event.title.isEmpty ? 'Untitled event' : event.title,
                        ),
                        subtitle: Text(
                          [
                            when,
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
