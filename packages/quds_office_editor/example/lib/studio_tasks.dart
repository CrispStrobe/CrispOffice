import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_tasks_caldav/quds_tasks_caldav_native.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_tasks_graph/quds_tasks_graph_native.dart';
import 'package:quds_tasks_store/quds_tasks_store.dart';
import 'package:sqlite3/sqlite3.dart' show Database, sqlite3;
import 'package:url_launcher/url_launcher.dart';

import 'credentials/secure_storage_service.dart';
import 'studio_credential_storage.dart';
import 'studio_tasks_ews_sync.dart';

Widget buildStudioTasks(String title, VoidCallback close) =>
    StudioTasksPage(title: title, onClose: close);

const _davProfiles = [
  CalDavServerProfile.generic,
  CalDavServerProfile.mailboxOrg,
  CalDavServerProfile.openXchange,
  CalDavServerProfile.nextcloud,
  CalDavServerProfile.owncloud,
];

bool _isTaskCloud(String provider) =>
    provider == 'graph' || provider == 'google';

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
  });
  final String title;
  final VoidCallback? onClose;
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
  static const _accountKey = 'crispoffice.tasks.account.v1';
  static final _device = TaskAccountId('personal', provider: 'local');
  static final _personal = TaskList(
    id: TaskListId('personal', account: _device),
    name: 'On this device',
  );

  late final _credentialStorage =
      widget.credentialStorage ?? StudioCredentialStorage.instance;
  Database? _database;
  TaskPullStore? _store;
  TaskAccountLease? _deviceLease;
  TaskAccountLease? _syncLease;
  SecureStorage? _vault;
  Map<String, Object?>? _record;
  List<_Selection> _lists = [];
  TaskListId _selected = _personal.id;
  List<RemoteTask> _cached = [];
  List<LocalTaskEdit> _edits = [];
  Timer? _timer;
  Future<void>? _running;
  VoidCallback? _closeConnection;
  String? _notice;
  int? _vaultRevision;
  String _query = '';
  bool _includeCompleted = true;

  Future<Database> _openDatabase() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return sqlite3.open(path.join(directory.path, 'tasks.sqlite3'));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _credentialStorage.addListener(_credentialsChanged);
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
    final database = await (widget.openDatabase ?? _openDatabase)();
    if (!mounted) {
      database.close();
      return;
    }
    _database = database;
    final store = _store = TaskPullStore(database);
    _deviceLease = _require(store.connect(_device));
    if (widget.openDatabase != null && widget.credentialStorage == null) return;
    await _restore();
  }

  Future<void> _restore() async {
    final vault = _vault = await _credentialStorage.storage;
    _vaultRevision = _credentialStorage.revision;
    final saved = await vault.read(_accountKey);
    if (!mounted || saved == null) return;
    final record = jsonDecode(saved) as Map<String, Object?>;
    final provider = record['provider'] as String;
    final account = TaskAccountId(record['id'] as String, provider: provider);
    _record = record;
    _syncLease = _require(_store!.connect(account));
    _lists = [
      for (final row in (record['lists'] as List<Object?>? ?? []))
        (list: _decodeList(account, row), sync: null),
    ];
    if (_lists.isNotEmpty) {
      final remembered = _lists
          .where((entry) => entry.list.id.value == record['selected'])
          .firstOrNull;
      _selected = (remembered ?? _lists.first).list.id;
      _reload();
    }
    await _resumeConnection(record, vault, account);
    final selected = record['selected'];
    if (selected is String &&
        _lists.any((entry) => entry.list.id.value == selected)) {
      _selected = TaskListId(selected, account: account);
    }
    await _syncSelected();
  }

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
    await vault.write(_accountKey, jsonEncode(persisted));
    if (!mounted || _vaultRevision != _credentialStorage.revision) return;
    _record = persisted;
    _syncLease = lease;
    _lists = lists;
    if (!_lists.any((entry) => entry.list.id == _selected)) {
      _selected = _lists.firstOrNull?.list.id ?? _personal.id;
    }
  }

  Future<void> _connectDav(
    Map<String, Object?> record,
    SecureStorage vault,
    TaskAccountId account,
  ) async {
    final client = widget.openDavClient?.call() ?? createNativeCalDavClient();
    _closeConnection = client.close;
    final url = Uri.parse(record['url'] as String);
    final exact = record['collection'] as String?;
    final provider = CalDavTaskProvider(
      account: account,
      settings: CalDavConnectionSettings(
        profile:
            _davProfiles
                .where((profile) => profile.id == record['davProfile'])
                .firstOrNull ??
            (url.origin == 'https://dav.mailbox.org'
                ? CalDavServerProfile.mailboxOrg
                : CalDavServerProfile.generic),
        username: record['login'] as String,
        discoveryUrl: url,
        collectionUrl: exact == null ? null : Uri.parse(exact),
      ),
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
    final credentials = _EwsTaskCredentials(reference, () {
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
    final configuration = MailOAuthConfiguration(
      service: microsoft
          ? MailCloudService.microsoft365
          : MailCloudService.gmail,
      clientId: record['client'] as String,
      clientSecret: record['googleDesktopSecret'] as String?,
      tasksOnly: true,
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
    final enableWrites = microsoft && record['writes'] == true;
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
      );
      closeProvider = provider.close;
      fetchLists = (cursor) => provider.lists(session.begin(), cursor: cursor);
      sync = (lease, list) => TaskPullWorker(_store!).refresh(
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
      (list: _personal, sync: null);

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
    if (background || _selected == _personal.id) {
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
    _vault = null;
    _vaultRevision = null;
    _syncLease = null;
    _lists = [];
    _selected = _personal.id;
    _notice = 'Credential storage changed. Connect the task account again.';
    _reload();
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
      final record = {...proposed, 'id': id};
      try {
        if (_isTaskCloud(provider)) {
          await _connectTaskCloud(record, vault, account);
        } else if (provider == 'ews') {
          await _connectEws(record, vault, account);
        } else {
          await _connectDav(record, vault, account);
        }
        await _syncSelected();
      } on Object {
        _closeConnection?.call();
        if (_isTaskCloud(provider) && _record?['id'] != id) {
          await vault.delete(_refreshKey(account));
        }
        rethrow;
      }
    });
  }

  void _disconnect() => _run(() async {
    final lease = _syncLease;
    if (lease != null) {
      _require(_store!.disconnect(lease));
      _closeConnection?.call();
      if (_isTaskCloud(lease.account.provider)) {
        await _vault!.delete(_refreshKey(lease.account));
      }
    }
    await _vault!.delete(_accountKey);
    _record = null;
    _syncLease = null;
    _lists = [];
    _selected = _personal.id;
    _notice = null;
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
      if (record != null && id != _personal.id) {
        record['selected'] = id.value;
        await _vault!.write(_accountKey, jsonEncode(record));
      }
      await _syncSelected();
    });
  }

  void _save(TaskFields? value, LocalTaskEdit? edit, RemoteTask? remote) {
    final lease = _selected == _personal.id ? _deviceLease : _syncLease;
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
      builder: (_) => _TaskFieldsDialog(fields: existing),
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
              if (fields.due case final due?) Text('Due ${_taskDueDate(due)}'),
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

  @override
  Widget build(BuildContext context) {
    final busy = _running != null;
    final ready = _store != null;
    final connected = _record != null;
    final overlays = {
      for (final edit in _edits)
        if (edit.remoteId != null) edit.remoteId!: edit,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: widget.onClose == null
            ? null
            : BackButton(onPressed: widget.onClose),
        actions: [
          if (connected)
            TextButton(
              onPressed: busy ? null : _disconnect,
              child: const Text('Disconnect'),
            )
          else
            TextButton(
              onPressed: !ready || busy ? null : _connect,
              child: const Text('Connect account'),
            ),
          IconButton(
            tooltip: 'Sync now',
            onPressed: busy || !connected ? null : () => _refresh(),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: !ready || _selection.list.readOnly
          ? null
          : FloatingActionButton(
              tooltip: 'Add task',
              onPressed: () => _edit(null),
              child: const Icon(Icons.add),
            ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (_notice case final notice?)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(notice, key: const ValueKey('tasks-status')),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButton<TaskListId>(
              value: _selected,
              onChanged: busy ? null : _select,
              items: [
                DropdownMenuItem(
                  value: _personal.id,
                  child: Text(_personal.name),
                ),
                for (final entry in _lists)
                  DropdownMenuItem(
                    value: entry.list.id,
                    child: Text(entry.list.name),
                  ),
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
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search tasks',
                    ),
                  ),
                ),
                FilterChip(
                  label: const Text('Completed'),
                  selected: _includeCompleted,
                  onSelected: (value) =>
                      setState(() => _includeCompleted = value),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final task in _cached)
                  if (!overlays.containsKey(task.id) && _matches(task.fields))
                    _row(task.fields, remote: task),
                for (final edit in _edits)
                  if (_matches(edit.fields) &&
                      (edit.fields != null ||
                          edit.state != TaskEditState.pending ||
                          _selected != _personal.id))
                    _row(edit.fields, edit: edit),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _matches(TaskFields? fields) =>
      (_includeCompleted || fields?.status != TaskStatus.completed) &&
      (_query.isEmpty ||
          (fields?.title.toLowerCase().contains(_query) ?? false) ||
          (fields?.notes?.value.toLowerCase().contains(_query) ?? false));

  Widget _row(TaskFields? fields, {LocalTaskEdit? edit, RemoteTask? remote}) {
    final completed = fields?.status == TaskStatus.completed;
    final editable = fields != null && !_selection.list.readOnly;
    final remoteDeleteAvailable =
        _selected.account.provider != 'ews' || _record?['ewsDeletes'] == true;
    final canDelete =
        editable &&
        (remoteDeleteAvailable || (remote == null && edit?.remoteId == null));
    final local = _selected == _personal.id;
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
    final due = fields?.due;
    return ListTile(
      leading: Checkbox(
        value: completed,
        onChanged: !editable
            ? null
            : (checked) {
                final patch = TaskPatch(
                  status: TaskFieldPatch.set(
                    checked == true
                        ? TaskStatus.completed
                        : TaskStatus.notStarted,
                  ),
                  completedAt: checked == true
                      ? const TaskFieldPatch.unchanged()
                      : const TaskFieldPatch.clear(),
                );
                _save(patch.applyTo(fields), edit, remote);
              },
      ),
      title: Text(fields?.title ?? 'Deleted task'),
      subtitle: status == null && due == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (due != null) Text('Due ${_taskDueDate(due)}'),
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
  }
}

final class _EwsTaskCredentials implements MailCredentialStore {
  const _EwsTaskCredentials(this.reference, this.readPassword);

  final MailCredentialReference reference;
  final String? Function() readPassword;

  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference request,
  ) async {
    final secret =
        request.account == reference.account && request.key == reference.key
        ? readPassword()
        : null;
    return MailSuccess(
      secret == null
          ? null
          : MailCredentialRecord(
              reference: reference,
              opaqueData: MailBytes(Uint8List.fromList(utf8.encode(secret))),
            ),
    );
  }

  @override
  Future<MailResult<MailUnit>> store(MailCredentialRecord record) async =>
      const MailFailure(MailProblem(MailProblemCode.unsupported));

  @override
  Future<MailResult<MailUnit>> delete(
    MailCredentialReference reference,
  ) async => const MailFailure(MailProblem(MailProblemCode.unsupported));

  @override
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account) async =>
      const MailFailure(MailProblem(MailProblemCode.unsupported));
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
  bool _ewsDeletes = false;

  @override
  void dispose() {
    for (final field in [
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
                    child: Text('Google Tasks (read-only)'),
                  ),
                  DropdownMenuItem(value: 'ews', child: Text('Exchange EWS')),
                ],
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
                      for (final profile in _davProfiles)
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
                    'client': _client.text.trim(),
                    'writes': _graphWrites,
                  }
                : _google
                ? {
                    'provider': 'google',
                    'client': _googleClient.text.trim(),
                    if (_googleSecret.text.trim().isNotEmpty)
                      'googleDesktopSecret': _googleSecret.text.trim(),
                  }
                : {
                    'provider': _provider,
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

String _taskDueDate(TaskDateValue date) => switch (date) {
  TaskDate(:final year, :final month, :final day) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
  TaskDateTime(:final localDateTime) => localDateTime.substring(0, 10),
};

class _TaskFieldsDialog extends StatefulWidget {
  const _TaskFieldsDialog({this.fields});
  final TaskFields? fields;
  @override
  State<_TaskFieldsDialog> createState() => _TaskFieldsDialogState();
}

class _TaskFieldsDialogState extends State<_TaskFieldsDialog> {
  late final _title = TextEditingController(text: widget.fields?.title);
  late final _notes = TextEditingController(text: widget.fields?.notes?.value);
  TaskDateValue? _due;
  bool _dueChanged = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final due = _dueChanged ? _due : widget.fields?.due;
    return AlertDialog(
      title: Text(widget.fields == null ? 'New task' : 'Edit task'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2200),
                      initialDate:
                          due is TaskDate &&
                              due.year >= 1900 &&
                              due.year <= 2200
                          ? DateTime(due.year, due.month, due.day)
                          : DateTime.now(),
                    );
                    if (mounted && picked != null) {
                      setState(() {
                        _dueChanged = true;
                        _due = TaskDate(picked.year, picked.month, picked.day);
                      });
                    }
                  },
                  child: Text(due == null ? 'Set due date' : _taskDueDate(due)),
                ),
                if (due != null)
                  IconButton(
                    tooltip: 'Clear due date',
                    onPressed: () => setState(() {
                      _dueChanged = true;
                      _due = null;
                    }),
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) return;
            final fields = widget.fields ?? const TaskFields(title: '');
            final notes = _notes.text;
            final patch = TaskPatch(
              title: TaskFieldPatch.set(title),
              notes: notes == (fields.notes?.value ?? '')
                  ? const TaskFieldPatch.unchanged()
                  : notes.isEmpty
                  ? const TaskFieldPatch.clear()
                  : TaskFieldPatch.set(TaskText(notes)),
              due: !_dueChanged
                  ? const TaskFieldPatch.unchanged()
                  : due == null
                  ? const TaskFieldPatch.clear()
                  : TaskFieldPatch.set(due),
            );
            Navigator.pop(context, patch.applyTo(fields));
          },
          child: const Text('Save task'),
        ),
      ],
    );
  }
}
