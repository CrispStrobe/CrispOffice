import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_tasks_caldav/quds_tasks_caldav_native.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_tasks_graph/quds_tasks_graph_native.dart';
import 'package:quds_tasks_store/quds_tasks_store.dart';
import 'package:sqlite3/sqlite3.dart' show Database;
import 'package:url_launcher/url_launcher.dart';

import 'credentials/secure_storage_service.dart';
import 'studio_productivity_export.dart';
import 'studio_credential_storage.dart';
import 'studio_chrome.dart';
import 'studio_task_editor.dart';
import 'studio_device_tasks.dart';
import 'studio_ews_credentials.dart';
import 'studio_tasks_ews_sync.dart';
import 'studio_tasks_google_sync.dart';
import 'studio_productivity_accounts.dart';

Widget buildStudioTasks(
  String title,
  VoidCallback close, {
  WidgetBuilder? chromeBuilder,
  bool compactRibbon = true,
  bool showCommandLabels = true,
  bool showGroupLabels = false,
}) => StudioTasksPage(
  title: title,
  onClose: close,
  chromeBuilder: chromeBuilder,
  compactRibbon: compactRibbon,
  showCommandLabels: showCommandLabels,
  showGroupLabels: showGroupLabels,
);

bool _isTaskCloud(String provider) =>
    provider == 'graph' || provider == 'google';

enum _TaskView {
  all('All tasks'),
  open('Open'),
  today('Due today'),
  overdue('Overdue'),
  completed('Completed');

  const _TaskView(this.label);
  final String label;

  bool includes(TaskFields fields, String currentDay) {
    final active =
        fields.status != TaskStatus.completed &&
        fields.status != TaskStatus.cancelled;
    final due = fields.due;
    return switch (this) {
      all => true,
      open => active,
      today => active && due != null && studioTaskDueDate(due) == currentDay,
      overdue =>
        active &&
            due != null &&
            studioTaskDueDate(due).compareTo(currentDay) < 0,
      completed => fields.status == TaskStatus.completed,
    };
  }
}

typedef _Selection = ({
  TaskList list,
  Future<TaskResult<bool>> Function()? sync,
});

final class StudioTasksPage extends StatefulWidget {
  const StudioTasksPage({
    super.key,
    required this.title,
    this.openDatabase,
    this.credentialStorage,
    this.openDavClient,
    this.openEwsProvider,
    this.onClose,
    this.chromeBuilder,
    this.compactRibbon = true,
    this.showCommandLabels = true,
    this.showGroupLabels = false,
  });
  final String title;
  final VoidCallback? onClose;
  final WidgetBuilder? chromeBuilder;
  final bool compactRibbon;
  final bool showCommandLabels;
  final bool showGroupLabels;
  final Future<Database> Function()? openDatabase;
  final StudioCredentialStorage? credentialStorage;
  final http.Client Function()? openDavClient;
  final EwsTaskProvider Function(
    TaskAccountId account,
    MailEwsConfiguration configuration,
    MailCredentialStore credentials,
  )?
  openEwsProvider;

  @override
  State<StudioTasksPage> createState() => _StudioTasksPageState();
}

final class _StudioTasksPageState extends State<StudioTasksPage>
    with WidgetsBindingObserver {
  final _records = <TaskAccountId, Map<String, Object?>>{};
  late final _credentialStorage =
      widget.credentialStorage ?? StudioCredentialStorage.instance;
  Database? _database;
  TaskPullStore? _store;
  TaskAccountLease? _deviceLease;
  TaskAccountLease? _syncLease;
  SecureStorage? _vault;
  Map<String, Object?>? _record;
  List<_Selection> _lists = [];
  TaskListId _selected = studioDeviceTaskList.id;
  List<RemoteTask> _cached = [];
  List<LocalTaskEdit> _edits = [];
  Timer? _timer;
  Future<void>? _running;
  VoidCallback? _closeConnection;
  String? _notice;
  int? _vaultRevision;
  String _query = '';
  _TaskView _view = _TaskView.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _credentialStorage.addListener(_credentialsChanged);
    studioDeviceTaskChanges.addListener(_deviceTasksChanged);
    _run(_initialize);
    _timer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _refresh(background: true),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(background: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _credentialStorage.removeListener(_credentialsChanged);
    studioDeviceTaskChanges.removeListener(_deviceTasksChanged);
    _timer?.cancel();
    _closeConnection?.call();
    final running = _running;
    final database = _database;
    if (database != null) {
      if (running == null) {
        database.close();
      } else {
        unawaited(running.whenComplete(database.close));
      }
    }
    super.dispose();
  }

  void _run(Future<void> Function() work) {
    if (!mounted || _running != null) return;
    final operation = Future<void>(() async {
      try {
        await work();
      } on _TasksDisplayException catch (error) {
        if (mounted) _notice = error.message;
      } on Object {
        if (mounted) _notice = 'Tasks could not complete the operation.';
      } finally {
        _running = null;
        if (mounted) _reload();
      }
    });
    setState(() {
      _running = operation;
    });
  }

  Future<void> _initialize() async {
    final database = await (widget.openDatabase ?? openStudioTasksDatabase)();
    if (!mounted) {
      database.close();
      return;
    }
    _database = database;
    final store = _store = TaskPullStore(database);
    _deviceLease = _require(store.connect(studioDeviceTaskList.id.account));
    if (widget.openDatabase != null && widget.credentialStorage == null) return;
    await _restore();
  }

  Future<void> _restore() async {
    final vault = _vault = await _credentialStorage.storage;
    _vaultRevision = _credentialStorage.revision;
    final catalog = await StudioTaskAccountCatalog.load(vault);
    if (!mounted || _vaultRevision != _credentialStorage.revision) return;
    _records.addAll(catalog.records);
    if (catalog.fromLegacy) {
      await _saveCatalog(vault, _records, catalog.active);
      await vault.delete(studioTasksLegacyKey);
    }
    if (catalog.active case final account?) await _openSaved(account, vault);
  }

  Future<void> _saveCatalog(
    SecureStorage vault,
    Map<TaskAccountId, Map<String, Object?>> accounts,
    TaskAccountId? active,
  ) => vault.write(
    studioTasksAccountsKey,
    jsonEncode({
      'active': active == null ? null : [active.provider, active.value],
      'accounts': accounts.values.toList(),
    }),
  );

  Future<void> _openSaved(TaskAccountId account, SecureStorage vault) async {
    if (!mounted || _vaultRevision != _credentialStorage.revision) return;
    final record = _records[account]!;
    final previous = _syncLease;
    _closeConnection?.call();
    _closeConnection = null;
    if (previous != null && previous.account != account) {
      _require(_store!.disconnect(previous));
    }
    _record = record;
    _syncLease = _require(_store!.connect(account));
    _lists = [
      for (final row in (record['lists'] as List<Object?>? ?? []))
        (list: _decodeList(account, row), sync: null),
    ];
    _selected = _preferredList(record, _lists);
    _reload();
    await _resumeConnection(record, vault, account);
    await _syncSelected();
  }

  TaskListId _preferredList(
    Map<String, Object?> record,
    List<_Selection> lists,
  ) =>
      (lists
                  .where((entry) => entry.list.id.value == record['selected'])
                  .firstOrNull ??
              lists.firstOrNull)
          ?.list
          .id ??
      studioDeviceTaskList.id;

  void _switchSaved(TaskAccountId? account) => _run(() async {
    final vault = _vault;
    if (account == null || account == _syncLease?.account || vault == null) {
      return;
    }
    await _saveCatalog(vault, _records, account);
    await _openSaved(account, vault);
  });

  Future<void> _resumeConnection(
    Map<String, Object?> record,
    SecureStorage vault,
    TaskAccountId account,
  ) async {
    _closeConnection?.call();
    if (_isTaskCloud(account.provider)) {
      final token = await vault.read(_refreshKey(account));
      if (!mounted) return;
      if (token == null) {
        throw const _TasksDisplayException('Reconnect the task account.');
      }
      await _connectTaskCloud(record, vault, account, refreshToken: token);
    } else if (account.provider == 'ews') {
      await _connectEws(record, vault, account);
    } else {
      await _connectDav(record, vault, account);
    }
  }

  TaskList _decodeList(TaskAccountId account, Object? row) {
    final values = row as List<Object?>;
    return TaskList(
      id: TaskListId(values[0] as String, account: account),
      name: values[1] as String,
      readOnly: values[2] as bool,
    );
  }

  Future<void> _attach(
    Map<String, Object?> record,
    SecureStorage vault,
    TaskAccountLease lease,
    List<_Selection> lists,
  ) async {
    final persisted = <String, Object?>{
      ...record,
      'lists': [
        for (final entry in lists)
          [entry.list.id.value, entry.list.name, entry.list.readOnly],
      ],
    };
    if (!mounted || _vaultRevision != _credentialStorage.revision) return;
    final updated = {..._records, lease.account: persisted};
    await _saveCatalog(vault, updated, lease.account);
    if (!mounted || _vaultRevision != _credentialStorage.revision) return;
    _records[lease.account] = persisted;
    _record = persisted;
    _syncLease = lease;
    _lists = lists;
    if (!_lists.any((entry) => entry.list.id == _selected)) {
      _selected = _preferredList(persisted, lists);
    }
  }

  Future<void> _connectDav(
    Map<String, Object?> record,
    SecureStorage vault,
    TaskAccountId account,
  ) async {
    final client = widget.openDavClient?.call() ?? createNativeCalDavClient();
    _closeConnection = client.close;
    final provider = CalDavTaskProvider(
      account: account,
      settings: studioDavSettings(record),
      client: client,
      appPassword: () async => _vaultRevision == _credentialStorage.revision
          ? record['secret'] as String
          : null,
    );
    final discovered = _require(await provider.discoverLists());
    if (!mounted) return;
    final lease = _require(_store!.connect(account));
    await _attach(record, vault, lease, [
      for (final entry in discovered)
        (
          list: entry.list,
          sync: () =>
              syncCalDavTasks(TaskSyncWorker(_store!), lease, provider, entry),
        ),
    ]);
  }

  Future<void> _connectEws(
    Map<String, Object?> record,
    SecureStorage vault,
    TaskAccountId account,
  ) async {
    final mail = MailAccountId(
      account.value,
      profile: MailProfileId('tasks', hostId: 'crispoffice'),
    );
    final session = MailAccountSession(mail);
    _closeConnection = session.dispose;
    final reference = MailCredentialReference(account: mail, key: 'ews-tasks');
    final configuration = MailEwsConfiguration(
      account: mail,
      endpoint: Uri.parse(record['url'] as String),
      username: record['login'] as String,
      domain: record['domain'] as String,
      credential: reference,
      mailboxAddress: record['mailbox'] as String?,
    );
    final credentials = StudioEwsCredentials(reference, () {
      if (session.isDisposed || _vaultRevision != _credentialStorage.revision) {
        return null;
      }
      return record['secret'] as String;
    });
    final reader =
        widget.openEwsProvider?.call(account, configuration, credentials) ??
        createEwsTaskReader(
          account: account,
          enableWrites: true,
          enableDeletes: record['ewsDeletes'] == true,
          configuration: configuration,
          credentialStore: credentials,
        );
    final lists = _require(await reader.taskLists(session.begin()));
    if (!mounted || session.isDisposed) return;
    final lease = _require(_store!.connect(account));
    await _attach(record, vault, lease, [
      for (final list in lists)
        (
          list: list,
          sync: () => syncStudioEwsTasks(
            TaskSyncWorker(_store!),
            lease,
            reader,
            list,
            session,
          ),
        ),
    ]);
  }

  static String _refreshKey(TaskAccountId account) =>
      'crispoffice.tasks.refresh.${account.value}';

  Future<void> _connectTaskCloud(
    Map<String, Object?> record,
    SecureStorage vault,
    TaskAccountId account, {
    String? refreshToken,
  }) async {
    final mail = MailAccountId(
      account.value,
      profile: MailProfileId('tasks', hostId: 'crispoffice'),
    );
    final session = MailAccountSession(mail);
    final microsoft = account.provider == 'graph';
    MailCloudTokenSource? tokens;
    VoidCallback? closeProvider;
    _closeConnection = () {
      session.dispose();
      tokens?.dispose();
      closeProvider?.call();
    };
    final enableWrites = record['writes'] == true;
    final configuration = MailOAuthConfiguration(
      service: microsoft
          ? MailCloudService.microsoft365
          : MailCloudService.gmail,
      clientId: record['client'] as String,
      clientSecret: record['googleDesktopSecret'] as String?,
      tasksOnly: true,
      googleTaskWrites: !microsoft && enableWrites,
    );
    final vaultRevision = _credentialStorage.revision;
    String? issuedToken = refreshToken;
    var activeGrant = refreshToken != null;
    Future<void> saveRefreshToken(String token) async {
      if (!mounted ||
          session.isDisposed ||
          _credentialStorage.revision != vaultRevision) {
        throw StateError('The credential selection changed.');
      }
      issuedToken = token;
      if (activeGrant) await vault.write(_refreshKey(account), token);
    }

    final source = refreshToken == null
        ? _requireMail(
            await authorizeTasksCloud(
              configuration: configuration,
              account: mail,
              openBrowser: (uri) =>
                  launchUrl(uri, mode: LaunchMode.externalApplication),
              lease: session.begin(),
              saveRefreshToken: saveRefreshToken,
            ),
          )
        : restoreTasksCloud(
            configuration: configuration,
            account: mail,
            refreshToken: refreshToken,
            saveRefreshToken: saveRefreshToken,
          );
    tokens = source;
    if (!mounted) {
      source.dispose();
      return;
    }
    final Future<TaskResult<TaskListPage>> Function(String?) fetchLists;
    final Future<TaskResult<bool>> Function(TaskAccountLease, TaskList) sync;
    if (microsoft) {
      final transport = NativeGraphTaskHttpTransport();
      closeProvider = transport.close;
      final provider = GraphTaskProvider(
        account: account,
        transport: transport,
        tokens: _StudioGraphTokens(session, source),
      );
      fetchLists = (cursor) => provider.listTaskLists(cursor: cursor);
      sync = (lease, list) => syncGraphTasks(
        TaskSyncWorker(_store!),
        lease,
        provider,
        list,
        enableWrites: enableWrites,
      );
    } else {
      final provider = createGoogleTaskReader(
        account: account,
        mailAccount: mail,
        tokens: source,
        enableWrites: enableWrites,
      );
      closeProvider = provider.close;
      fetchLists = (cursor) => provider.lists(session.begin(), cursor: cursor);
      sync = (lease, list) => enableWrites
          ? syncStudioGoogleTasks(
              TaskSyncWorker(_store!),
              lease,
              provider,
              list,
              session,
            )
          : TaskPullWorker(_store!).refresh(
              lease,
              list.id,
              (position) => provider.pull(
                list.id,
                cursor: position.cursor,
                lease: session.begin(),
              ),
            );
    }
    final lists = <TaskListId, TaskList>{};
    String? cursor;
    for (var page = 0; page < 32; page++) {
      final found = _require(await fetchLists(cursor));
      for (final list in found.lists) {
        lists[list.id] = list;
      }
      if (found.nextCursor == null) break;
      if (found.nextCursor == cursor || page == 31) {
        throw StateError('Incomplete task list discovery.');
      }
      cursor = found.nextCursor;
    }
    if (!mounted) return;
    if (issuedToken == null) {
      throw const _TasksDisplayException(
        'The service did not grant offline Tasks access.',
      );
    }
    if (!activeGrant) {
      await vault.write(_refreshKey(account), issuedToken!);
      activeGrant = true;
    }
    final lease = _require(_store!.connect(account));
    await _attach(record, vault, lease, [
      for (final list in lists.values)
        (
          list: TaskList(
            id: list.id,
            name: list.name,
            readOnly: list.readOnly || !enableWrites,
          ),
          sync: () => sync(lease, list),
        ),
    ]);
  }

  _Selection get _selection =>
      _lists.where((entry) => entry.list.id == _selected).firstOrNull ??
      (list: studioDeviceTaskList, sync: null);

  Future<void> _syncSelected() => _syncLists([_selection]);

  Future<void> _syncLists(List<_Selection> lists) async {
    String? error;
    var hasMore = false;
    for (final entry in lists) {
      final sync = entry.sync;
      if (sync == null) continue;
      final result = await sync();
      if (!mounted || _syncLease?.account != entry.list.id.account) return;
      switch (result) {
        case TaskFailure(:final problem):
          error ??= '${entry.list.name}: ${_problemText(problem.code)}';
        case TaskSuccess(value: false):
          hasMore = true;
        case TaskSuccess():
          break;
      }
    }
    _notice = error ?? (hasMore ? 'More changes are waiting to sync.' : null);
  }

  void _refresh({bool background = false}) => _run(() async {
    if (_record case final record?) {
      if (!_lists.any((entry) => entry.sync != null) &&
          _syncLease != null &&
          _vault != null) {
        await _resumeConnection(record, _vault!, _syncLease!.account);
      }
    }
    if (!mounted) return;
    if (background || _selected == studioDeviceTaskList.id) {
      await _syncLists(_lists);
    } else {
      await _syncSelected();
    }
  });

  void _credentialsChanged() {
    if (_vaultRevision == null ||
        _vaultRevision == _credentialStorage.revision) {
      return;
    }
    _closeConnection?.call();
    final lease = _syncLease;
    if (lease != null) _store?.disconnect(lease);
    _record = null;
    _records.clear();
    _vault = null;
    _vaultRevision = null;
    _syncLease = null;
    _lists = [];
    _selected = studioDeviceTaskList.id;
    _notice = 'Credential storage changed. Connect the task account again.';
    _reload();
  }

  void _deviceTasksChanged() {
    if (_selected == studioDeviceTaskList.id) _reload();
  }

  void _reload() {
    final store = _store;
    if (!mounted || store == null) return;
    setState(() {
      final remote = store.tasks(_selected);
      final edits = store.edits(_selected);
      if (remote case TaskSuccess(:final value)) _cached = value;
      if (edits case TaskSuccess(:final value)) _edits = value;
    });
  }

  Future<void> _connect() async {
    final proposed = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => const _TaskConnectionDialog(),
    );
    if (!mounted || proposed == null) return;
    _run(() async {
      final vault = _vault = await _credentialStorage.storage;
      _vaultRevision = _credentialStorage.revision;
      if (!mounted) return;
      final provider = proposed['provider'] as String;
      final id = _isTaskCloud(provider)
          ? _randomId()
          : sha256
                .convert(
                  utf8.encode(
                    jsonEncode([
                      proposed['url'],
                      proposed['login'],
                      if (provider == 'ews') ...[
                        proposed['domain'],
                        proposed['mailbox'],
                      ],
                    ]),
                  ),
                )
                .toString();
      final account = TaskAccountId(id, provider: provider);
      final record = {...?_records[account], ...proposed, 'id': id};
      final previous = _syncLease;
      final priorClose = _closeConnection;
      _closeConnection = null;
      try {
        if (_isTaskCloud(provider)) {
          await _connectTaskCloud(record, vault, account);
        } else if (provider == 'ews') {
          await _connectEws(record, vault, account);
        } else {
          await _connectDav(record, vault, account);
        }
      } on Object {
        _closeConnection?.call();
        if (mounted && _vaultRevision == _credentialStorage.revision) {
          _closeConnection = priorClose;
        } else {
          priorClose?.call();
        }
        if (_isTaskCloud(provider) && !_records.containsKey(account)) {
          await vault.delete(_refreshKey(account));
        }
        rethrow;
      }
      priorClose?.call();
      if (!mounted || _vaultRevision != _credentialStorage.revision) return;
      if (previous != null && previous.account != account) {
        _require(_store!.disconnect(previous));
      }
      await _syncSelected();
    });
  }

  void _disconnect() => _run(() async {
    final lease = _syncLease;
    final vault = _vault;
    if (lease == null || vault == null) return;
    final updated = {..._records}..remove(lease.account);
    final next = updated.keys.firstOrNull;
    await _saveCatalog(vault, updated, next);
    if (!mounted || _vaultRevision != _credentialStorage.revision) return;
    _records.remove(lease.account);
    _require(_store!.disconnect(lease));
    _closeConnection?.call();
    _closeConnection = null;
    _record = null;
    _syncLease = null;
    _lists = [];
    _selected = studioDeviceTaskList.id;
    _notice = null;
    if (_isTaskCloud(lease.account.provider)) {
      await vault.delete(_refreshKey(lease.account));
    }
    if (next != null) await _openSaved(next, vault);
  });

  static String _randomId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _select(TaskListId? id) {
    if (id == null) return;
    _selected = id;
    _notice = null;
    _reload();
    _run(() async {
      final record = _record;
      if (record != null && id != studioDeviceTaskList.id) {
        record['selected'] = id.value;
        await _saveCatalog(_vault!, _records, _syncLease?.account);
      }
      await _syncSelected();
    });
  }

  void _save(TaskFields? value, LocalTaskEdit? edit, RemoteTask? remote) {
    final lease = _selected == studioDeviceTaskList.id
        ? _deviceLease
        : _syncLease;
    if (lease == null || _selection.list.readOnly) return;
    final outcome = _store!.saveEdit(
      lease,
      _selected,
      fields: value,
      edit: edit,
      remote: remote,
    );
    if (outcome case TaskFailure(:final problem)) {
      _notice = _problemText(problem.code);
    }
    _reload();
    if (_selection.sync != null) _refresh();
  }

  Future<void> _edit(
    TaskFields? existing, {
    LocalTaskEdit? edit,
    RemoteTask? remote,
  }) async {
    final list = _selected;
    final value = await showDialog<TaskFields>(
      context: context,
      builder: (_) => StudioTaskFieldsDialog(fields: existing),
    );
    if (mounted && value != null && list == _selected) {
      _save(value, edit, remote);
    }
  }

  Future<void> _viewTask(TaskFields fields) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(fields.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(switch (fields.status) {
                TaskStatus.notStarted => 'Not started',
                TaskStatus.inProgress => 'In progress',
                TaskStatus.completed => 'Completed',
                TaskStatus.waitingOnOthers => 'Waiting on others',
                TaskStatus.deferred => 'Deferred',
                TaskStatus.cancelled => 'Cancelled',
              }),
              if (fields.due case final due?)
                Text('Due ${studioTaskDueDate(due)}'),
              if (fields.notes case TaskText(
                :final value,
              ) when value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(value),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  void _resolve(LocalTaskEdit edit, bool keepLocal) {
    final lease = _syncLease;
    if (lease == null) return;
    if (_store!.resolveEdit(lease, _selected, edit, keepLocal: keepLocal)
        case TaskFailure(:final problem)) {
      _notice = _problemText(problem.code);
    }
    _reload();
  }

  Future<void> _exportTasks(Iterable<TaskFields> tasks) {
    final list = _selected;
    final revision = _credentialStorage.revision;
    return exportStudioProductivityView(
      context,
      kind: ProductivityKind.tasks,
      scope: 'the currently displayed task list and filter',
      isCurrent: () =>
          mounted &&
          _selected == list &&
          _credentialStorage.revision == revision,
      rows: tasks.map(
        (fields) => {
          'title': fields.title,
          'status': fields.status.name,
          if (fields.due case final due?) 'due': studioTaskDueDate(due),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = _running != null;
    final ready = _store != null;
    final connected = _record != null;
    final overlays = {
      for (final edit in _edits)
        if (edit.remoteId != null) edit.remoteId!: edit,
    };
    final now = DateTime.now();
    final today = studioTaskDueDate(TaskDate(now.year, now.month, now.day));
    final rows = [
      for (final task in _cached)
        if (!overlays.containsKey(task.id) && _matches(task.fields, today))
          (fields: task.fields, remote: task, edit: null),
      for (final edit in _edits)
        if (_matches(edit.fields, today) &&
            (edit.fields != null ||
                edit.state != TaskEditState.pending ||
                _selected != studioDeviceTaskList.id))
          (fields: edit.fields, remote: null, edit: edit),
    ];
    final exportable = rows.map((row) => row.fields).nonNulls;
    final export = busy || exportable.isEmpty
        ? null
        : () => _exportTasks(exportable);
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: widget.chromeBuilder != null
          ? null
          : AppBar(
              backgroundColor: colors.surface,
              foregroundColor: colors.onSurface,
              title: Text(widget.title),
              leading: widget.onClose == null
                  ? null
                  : BackButton(onPressed: widget.onClose),
              actions: [
                IconButton(
                  tooltip: studioProductivityExportLabel,
                  onPressed: export,
                  icon: const Icon(Icons.file_download_outlined),
                ),
                if (connected)
                  TextButton(
                    onPressed: busy ? null : _disconnect,
                    child: const Text('Disconnect'),
                  ),
                TextButton(
                  onPressed: !ready || busy ? null : _connect,
                  child: Text(connected ? 'Add account' : 'Connect account'),
                ),
                IconButton(
                  tooltip: 'Sync now',
                  onPressed: busy || !connected ? null : () => _refresh(),
                  icon: const Icon(Icons.sync),
                ),
              ],
            ),
      floatingActionButton:
          widget.chromeBuilder != null || !ready || _selection.list.readOnly
          ? null
          : FloatingActionButton(
              tooltip: 'Add task',
              onPressed: () => _edit(null),
              child: const Icon(Icons.add),
            ),
      body: Column(
        children: [
          if (widget.chromeBuilder case final chrome?) ...[
            chrome(context),
            _ribbon(
              ready: ready,
              connected: connected,
              busy: busy,
              export: export,
            ),
          ],
          if (busy) const LinearProgressIndicator(),
          if (_notice case final notice?)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(notice, key: const ValueKey('tasks-status')),
            ),
          if (widget.chromeBuilder == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                children: [
                  _listSelector(busy),
                  if (_records.length > 1) _accountSelector(busy),
                ],
              ),
            ),
          if (_selection.list.readOnly)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Read-only list'),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurface,
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search tasks',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<_TaskView>(
                  value: _view,
                  onChanged: (view) {
                    if (view != null) setState(() => _view = view);
                  },
                  items: [
                    for (final view in _TaskView.values)
                      DropdownMenuItem(value: view, child: Text(view.label)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty && !busy
                ? Center(
                    child: Text(
                      _query.isEmpty && _view == _TaskView.all
                          ? 'No tasks in this list.'
                          : 'No tasks match this view.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: rows.length,
                    itemBuilder: (_, index) {
                      final row = rows[index];
                      return _row(
                        row.fields,
                        remote: row.remote,
                        edit: row.edit,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _listSelector(bool busy) => SizedBox(
    width: 174,
    child: Tooltip(
      message: 'Task list',
      child: DropdownButton<TaskListId>(
        key: const ValueKey('studio-task-list-selector'),
        isExpanded: true,
        value: _selected,
        onChanged: busy ? null : _select,
        items: [
          DropdownMenuItem(
            value: studioDeviceTaskList.id,
            child: Text(
              studioDeviceTaskList.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (final entry in _lists)
            DropdownMenuItem(
              value: entry.list.id,
              child: Text(entry.list.name, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    ),
  );

  Widget _accountSelector(bool busy) => SizedBox(
    width: 174,
    child: Tooltip(
      message: 'Task account',
      child: DropdownButton<TaskAccountId>(
        isExpanded: true,
        value: _syncLease?.account,
        onChanged: busy ? null : _switchSaved,
        items: [
          for (final entry in _records.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(
                studioTaskAccountLabel(entry.key, entry.value),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    ),
  );

  Widget _ribbon({
    required bool ready,
    required bool connected,
    required bool busy,
    required VoidCallback? export,
  }) {
    final scheme = Theme.of(context).colorScheme;
    Widget command(IconData icon, String label, VoidCallback? action) =>
        StudioCmd(
          icon: icon,
          label: label,
          accent: scheme.primary,
          foreground: scheme.onSurface,
          onPressed: action,
        );
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                    id: 'task-actions',
                    title: 'Tasks',
                    children: [
                      _listSelector(busy),
                      command(
                        Icons.add_task,
                        'Add task',
                        !ready || _selection.list.readOnly
                            ? null
                            : () => _edit(null),
                      ),
                      command(
                        Icons.file_download_outlined,
                        studioProductivityExportLabel,
                        export,
                      ),
                    ],
                  ),
                  StudioRibbonGroup(
                    id: 'task-connection',
                    title: 'Accounts',
                    children: [
                      if (_records.length > 1) _accountSelector(busy),
                      if (connected)
                        command(
                          Icons.link_off,
                          'Disconnect',
                          busy ? null : _disconnect,
                        ),
                      command(
                        Icons.person_add_alt,
                        connected ? 'Add account' : 'Connect account',
                        !ready || busy ? null : _connect,
                      ),
                      command(
                        Icons.sync,
                        'Sync now',
                        busy || !connected ? null : () => _refresh(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 2,
            thickness: 2,
            color: scheme.primary.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }

  bool _matches(TaskFields? fields, String today) {
    if (fields == null) return _query.isEmpty;
    return _view.includes(fields, today) &&
        (_query.isEmpty ||
            fields.title.toLowerCase().contains(_query) ||
            (fields.notes?.value.toLowerCase().contains(_query) ?? false));
  }

  Widget _row(TaskFields? fields, {LocalTaskEdit? edit, RemoteTask? remote}) {
    final completed = fields?.status == TaskStatus.completed;
    final original =
        remote ??
        _cached.where((task) => task.id == edit?.remoteId).firstOrNull;
    final assigned = original != null && googleTaskIsAssigned(original);
    final editable = fields != null && !_selection.list.readOnly && !assigned;
    final remoteDeleteAvailable =
        _selected.account.provider != 'ews' || _record?['ewsDeletes'] == true;
    final canDelete =
        editable &&
        (remoteDeleteAvailable || (remote == null && edit?.remoteId == null));
    final local = _selected == studioDeviceTaskList.id;
    final String? status = local || edit == null
        ? null
        : switch (edit.state) {
            TaskEditState.pending =>
              fields == null ? 'Deletion pending' : 'Pending sync',
            TaskEditState.uncertain =>
              'Checking if the server accepted this change',
            TaskEditState.blocked => _problemText(
              edit.problem ?? TaskProblemCode.conflict,
            ),
          };
    final colors = Theme.of(context).colorScheme;
    final due = fields?.due;
    void toggle(bool checked) {
      final patch = TaskPatch(
        status: TaskFieldPatch.set(
          checked ? TaskStatus.completed : TaskStatus.notStarted,
        ),
        completedAt: checked
            ? const TaskFieldPatch.unchanged()
            : const TaskFieldPatch.clear(),
      );
      _save(patch.applyTo(fields!), edit, remote);
    }

    final tile = ListTile(
      textColor: colors.onSurface,
      iconColor: colors.onSurfaceVariant,
      leading: Checkbox(
        value: completed,
        onChanged: editable ? (checked) => toggle(checked == true) : null,
      ),
      title: Text(fields?.title ?? 'Deleted task'),
      subtitle: status == null && due == null && !assigned
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (due != null) Text('Due ${studioTaskDueDate(due)}'),
                if (assigned) const Text('Assigned in Google Docs or Chat'),
                if (status != null) Text(status),
              ],
            ),
      onTap: fields == null
          ? null
          : editable
          ? () => _edit(fields, edit: edit, remote: remote)
          : () => _viewTask(fields),
      trailing: edit?.state == TaskEditState.blocked
          ? PopupMenuButton<bool>(
              onSelected: (keep) => _resolve(edit!, keep),
              itemBuilder: (_) => const [
                PopupMenuItem(value: true, child: Text('Keep my changes')),
                PopupMenuItem(value: false, child: Text('Use server version')),
              ],
            )
          : IconButton(
              tooltip: 'Delete task',
              onPressed: canDelete ? () => _save(null, edit, remote) : null,
              icon: const Icon(Icons.delete_outline),
            ),
    );
    if (!editable) return tile;
    final list = _selected;
    return Dismissible(
      key: ValueKey((list, edit?.id ?? remote!.id.value, edit != null)),
      direction: canDelete
          ? DismissDirection.horizontal
          : DismissDirection.startToEnd,
      background: _swipeAction(
        leading: true,
        color: colors.secondaryContainer,
        foreground: colors.onSecondaryContainer,
        icon: completed ? Icons.undo : Icons.check,
        label: completed ? 'Reopen' : 'Complete',
      ),
      secondaryBackground: _swipeAction(
        leading: false,
        color: colors.errorContainer,
        foreground: colors.onErrorContainer,
        icon: Icons.delete_outline,
        label: 'Delete',
      ),
      confirmDismiss: (direction) async {
        if (!mounted || _selected != list) return false;
        if (direction == DismissDirection.startToEnd) {
          toggle(!completed);
        } else if (canDelete &&
            await _confirmSwipeDelete(fields.title) &&
            mounted &&
            _selected == list) {
          _save(null, edit, remote);
        }
        return false;
      },
      child: tile,
    );
  }

  Widget _swipeAction({
    required bool leading,
    required Color color,
    required Color foreground,
    required IconData icon,
    required String label,
  }) => Container(
    padding: const EdgeInsetsDirectional.symmetric(horizontal: 24),
    alignment: leading
        ? AlignmentDirectional.centerStart
        : AlignmentDirectional.centerEnd,
    color: color,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: foreground),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: foreground)),
      ],
    ),
  );

  Future<bool> _confirmSwipeDelete(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete task?'),
          content: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete task'),
            ),
          ],
        ),
      ) ??
      false;
}

final class _StudioGraphTokens implements GraphTaskTokenSource {
  const _StudioGraphTokens(this.session, this.tokens);
  final MailAccountSession session;
  final MailCloudTokenSource tokens;

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    final result = await tokens.accessToken(
      session.begin(),
      forceRefresh: forceRefresh,
    );
    if (result case MailSuccess(:final value)) return value.value;
    throw const GraphTaskTokenException(
      TaskProblem(TaskProblemCode.authenticationRequired),
    );
  }
}

final class _TasksDisplayException implements Exception {
  const _TasksDisplayException(this.message);
  final String message;
}

T _require<T>(TaskResult<T> result) => switch (result) {
  TaskSuccess(:final value) => value,
  TaskFailure(:final problem) => throw _TasksDisplayException(
    _problemText(problem.code),
  ),
};
T _requireMail<T>(MailResult<T> result) => switch (result) {
  MailSuccess(:final value) => value,
  MailFailure() => throw const _TasksDisplayException(
    'Task account authorization failed.',
  ),
};
String _problemText(TaskProblemCode code) => switch (code) {
  TaskProblemCode.unsupported => 'This provider cannot apply this task change.',
  TaskProblemCode.conflict => 'Local and server changes need review.',
  TaskProblemCode.authenticationRequired => 'Reconnect the task account.',
  TaskProblemCode.permissionDenied =>
    'This list or account does not allow the operation.',
  TaskProblemCode.throttled => 'The service asked to retry later.',
  TaskProblemCode.unavailable => 'The task service is unavailable.',
  TaskProblemCode.staleOperation =>
    'This task changed. Reopen it and try again.',
  _ => 'Tasks could not complete the operation.',
};

class _TaskConnectionDialog extends StatefulWidget {
  const _TaskConnectionDialog();
  @override
  State<_TaskConnectionDialog> createState() => _TaskConnectionDialogState();
}

class _TaskConnectionDialogState extends State<_TaskConnectionDialog> {
  final _label = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _url = TextEditingController(text: 'https://dav.mailbox.org/');
  final _collection = TextEditingController();
  final _ewsUrl = TextEditingController();
  final _domain = TextEditingController();
  final _mailbox = TextEditingController();
  final _client = TextEditingController(
    text: const String.fromEnvironment('CRISPOFFICE_MICROSOFT_CLIENT_ID'),
  );
  final _googleClient = TextEditingController(
    text: const String.fromEnvironment('CRISPOFFICE_GOOGLE_CLIENT_ID'),
  );
  final _googleSecret = TextEditingController();
  final _form = GlobalKey<FormState>();
  String _provider = 'caldav';
  CalDavServerProfile _davProfile = CalDavServerProfile.mailboxOrg;
  bool get _graph => _provider == 'graph';
  bool get _google => _provider == 'google';
  bool get _ews => _provider == 'ews';
  bool _graphWrites = false;
  bool _googleWrites = false;
  bool _ewsDeletes = false;

  @override
  void dispose() {
    for (final field in [
      _label,
      _login,
      _password,
      _url,
      _collection,
      _ewsUrl,
      _domain,
      _mailbox,
      _client,
      _googleClient,
      _googleSecret,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect a task account'),
    content: SizedBox(
      width: 460,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: _provider,
                onChanged: (value) => setState(() => _provider = value!),
                items: const [
                  DropdownMenuItem(value: 'caldav', child: Text('CalDAV')),
                  DropdownMenuItem(
                    value: 'graph',
                    child: Text('Microsoft To Do'),
                  ),
                  DropdownMenuItem(
                    value: 'google',
                    child: Text('Google Tasks'),
                  ),
                  DropdownMenuItem(value: 'ews', child: Text('Exchange EWS')),
                ],
              ),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Account name (optional)',
                ),
              ),
              if (_graph) ...[
                TextFormField(
                  controller: _client,
                  validator: _required,
                  decoration: const InputDecoration(
                    labelText: 'Microsoft application client ID',
                  ),
                ),
                CheckboxListTile(
                  value: _graphWrites,
                  onChanged: (v) => setState(() => _graphWrites = v!),
                  title: const Text('Allow Microsoft task edits'),
                  subtitle: const Text(
                    'Microsoft writes can race with edits made in another app.',
                  ),
                ),
              ] else if (_google) ...[
                TextFormField(
                  controller: _googleClient,
                  validator: _required,
                  decoration: const InputDecoration(
                    labelText: 'Google desktop client ID',
                  ),
                ),
                TextFormField(
                  controller: _googleSecret,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Google desktop client secret (if issued)',
                  ),
                ),
                CheckboxListTile(
                  value: _googleWrites,
                  onChanged: (value) => setState(() => _googleWrites = value!),
                  title: const Text('Allow Google task edits'),
                  subtitle: const Text('Assigned tasks stay read-only.'),
                ),
              ] else ...[
                if (_ews) ...[
                  TextFormField(
                    controller: _ewsUrl,
                    validator: _required,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'EWS endpoint',
                      hintText: 'https://mail.example.com/EWS/Exchange.asmx',
                    ),
                  ),
                  TextFormField(
                    controller: _domain,
                    decoration: const InputDecoration(
                      labelText: 'Windows domain (optional)',
                    ),
                  ),
                  TextFormField(
                    controller: _mailbox,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Mailbox address (optional)',
                    ),
                  ),
                  CheckboxListTile(
                    value: _ewsDeletes,
                    onChanged: (value) => setState(() => _ewsDeletes = value!),
                    title: const Text('Allow deleting Exchange tasks'),
                    subtitle: const Text(
                      'Moves tasks to Deleted Items. Concurrent edits can race with deletion.',
                    ),
                  ),
                ] else ...[
                  DropdownButton<CalDavServerProfile>(
                    value: _davProfile,
                    onChanged: (value) => setState(() {
                      if (_url.text.isEmpty ||
                          _url.text == _davProfile.defaultDiscoveryUrl) {
                        _url.text = value!.defaultDiscoveryUrl ?? '';
                      }
                      _davProfile = value!;
                    }),
                    items: [
                      for (final profile in studioDavProfiles)
                        DropdownMenuItem(
                          value: profile,
                          child: Text(profile.label),
                        ),
                    ],
                  ),
                  TextFormField(
                    controller: _url,
                    validator: _required,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'DAV URL'),
                  ),
                  TextFormField(
                    controller: _collection,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Exact task-list URL (optional)',
                    ),
                  ),
                ],
                TextFormField(
                  controller: _login,
                  validator: _required,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                TextFormField(
                  controller: _password,
                  validator: _required,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: _ews ? 'Password' : 'App password',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop<Map<String, Object?>>(
            context,
            _graph
                ? {
                    'provider': 'graph',
                    if (_label.text.trim().isNotEmpty)
                      'label': _label.text.trim(),
                    'client': _client.text.trim(),
                    'writes': _graphWrites,
                  }
                : _google
                ? {
                    'provider': 'google',
                    if (_label.text.trim().isNotEmpty)
                      'label': _label.text.trim(),
                    'client': _googleClient.text.trim(),
                    'writes': _googleWrites,
                    if (_googleSecret.text.trim().isNotEmpty)
                      'googleDesktopSecret': _googleSecret.text.trim(),
                  }
                : {
                    'provider': _provider,
                    if (_label.text.trim().isNotEmpty)
                      'label': _label.text.trim(),
                    'url': (_ews ? _ewsUrl : _url).text.trim(),
                    'login': _login.text.trim(),
                    'secret': _password.text,
                    if (_ews) ...{
                      'domain': _domain.text.trim(),
                      'ewsDeletes': _ewsDeletes,
                      if (_mailbox.text.trim().isNotEmpty)
                        'mailbox': _mailbox.text.trim(),
                    } else ...{
                      'davProfile': _davProfile.id,
                      if (_collection.text.trim().isNotEmpty)
                        'collection': _collection.text.trim(),
                    },
                  },
          );
        },
        child: Text(_graph ? 'Authorize Tasks' : 'Connect'),
      ),
    ],
  );
}
