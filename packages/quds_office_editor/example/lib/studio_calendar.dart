import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quds_tasks_caldav/quds_tasks_caldav_native.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

import 'studio_chrome.dart';
import 'studio_credential_storage.dart';
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
  });

  final String title;
  final WidgetBuilder chromeBuilder;
  final VoidCallback openConnections;
  final bool compactRibbon;
  final bool showCommandLabels;
  final bool showGroupLabels;
  final StudioCredentialStorage? credentialStorage;
  final http.Client Function()? openDavClient;

  @override
  State<StudioCalendarPage> createState() => _StudioCalendarPageState();
}

final class _StudioCalendarPageState extends State<StudioCalendarPage> {
  late final _storage =
      widget.credentialStorage ?? StudioCredentialStorage.instance;
  http.Client? _client;
  int _generation = 0;
  bool _busy = true;
  String? _error;
  Map<TaskAccountId, String> _accounts = {};
  TaskAccountId? _account;
  List<CalDavCalendar> _calendars = [];
  Uri? _calendar;
  CalDavAgenda? _agenda;
  DateTime _start = _day(DateTime.now());

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

  Future<void> _reload() async {
    final generation = ++_generation;
    _client?.close();
    _client = null;
    final revision = _storage.revision;
    bool current() =>
        mounted && generation == _generation && revision == _storage.revision;
    setState(() {
      _busy = true;
      _error = null;
      _agenda = null;
    });
    try {
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
        _account = account;
        _calendars = [];
      });
      if (account == null) return;
      final client = _client =
          widget.openDavClient?.call() ?? createNativeCalDavClient();
      final provider = CalDavCalendarProvider(
        account: account,
        settings: studioDavSettings(
          accounts[account]!,
          useTaskCollection: false,
        ),
        client: client,
        appPassword: () async {
          if (!current()) return null;
          final fresh = await StudioTaskAccountCatalog.load(vault);
          if (!current()) return null;
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
        _calendars = calendars;
        _calendar = selected?.url;
      });
      if (selected == null) return;
      final result = await provider.agenda(
        selected,
        start: _start.toUtc(),
        end: _day(_start, 7).toUtc(),
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

  void _navigate([int? days]) {
    _start = days == null ? _day(DateTime.now()) : _day(_start, days);
    unawaited(_reload());
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
    Widget command(IconData icon, String label, VoidCallback? action) =>
        StudioCmd(
          icon: icon,
          label: label,
          accent: colors.primary,
          foreground: colors.onSurface,
          onPressed: action,
        );
    return Scaffold(
      backgroundColor: colors.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.chromeBuilder(context),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StudioTabChip(
              label: widget.title,
              selected: true,
              accent: colors.primary,
              onTap: () {},
            ),
          ),
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
                    id: 'calendar-week',
                    title: 'Agenda',
                    children: [
                      command(
                        Icons.chevron_left,
                        'Previous week',
                        _busy ? null : () => _navigate(-7),
                      ),
                      command(
                        Icons.today_outlined,
                        'Today',
                        _busy ? null : _navigate,
                      ),
                      command(
                        Icons.chevron_right,
                        'Next week',
                        _busy ? null : () => _navigate(7),
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
                  '${date.formatMediumDate(_start)} – ${date.formatMediumDate(_day(_start, 6))}',
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
                            unawaited(_reload());
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
              child: Text(
                '$count recurring series could not be expanded by the server.',
              ),
            ),
          Expanded(
            child: !_busy && _error == null && events.isEmpty
                ? Center(
                    child: Text(
                      _accounts.isEmpty
                          ? 'Connect a CalDAV account in Tasks to see its calendars here.'
                          : _calendars.isEmpty
                          ? 'This account has no event calendars.'
                          : 'No events this week.',
                    ),
                  )
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      final when = _format(event.start, date);
                      return ListTile(
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

  String _format(CalDavDateValue value, MaterialLocalizations locale) {
    final wall = value.toTaskDate();
    if (wall case TaskDate(:final year, :final month, :final day)) {
      return '${locale.formatMediumDate(DateTime(year, month, day))} · All day';
    }
    final time = wall as TaskDateTime;
    final utc = value.kind == CalDavDateKind.utc;
    final parsed = DateTime.parse('${time.localDateTime}${utc ? 'Z' : ''}');
    final shown = utc ? parsed.toLocal() : parsed;
    final date = locale.formatMediumDate(shown);
    final clock = locale.formatTimeOfDay(TimeOfDay.fromDateTime(shown));
    return '$date · $clock${value.kind == CalDavDateKind.zoned ? ' ${value.timeZone}' : ''}';
  }
}
