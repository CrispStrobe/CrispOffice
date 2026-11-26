import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

final class _ProbeCredentials implements MailCredentialStore {
  _ProbeCredentials(this.secret);
  final String secret;
  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference reference,
  ) async => MailSuccess(
    MailCredentialRecord(
      reference: reference,
      opaqueData: MailBytes(Uint8List.fromList(utf8.encode(secret))),
    ),
  );
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

Future<void> main(List<String> args) async {
  final calendar = args.contains('--calendar');
  final files = args.where((arg) => arg != '--calendar').toList();
  if (files.length > 1) {
    stderr.writeln(
      'Usage: dart run example/ews_tasks_probe.dart [--calendar] [credential file]',
    );
    exitCode = 2;
    return;
  }
  final values = <String, String>{...Platform.environment};
  final lines = files.isEmpty
      ? const <String>[]
      : await File(files.single).readAsLines();
  for (final line in lines) {
    final match = RegExp(
      r'^\s*(?:export\s+)?(EWS_[A-Z]+)\s*=\s*(.*?)\s*$',
    ).firstMatch(line);
    if (match == null) continue;
    final raw = match[2]!;
    values[match[1]!] =
        raw.length >= 2 &&
            raw[0] == raw[raw.length - 1] &&
            (raw[0] == '"' || raw[0] == "'")
        ? raw.substring(1, raw.length - 1)
        : raw;
  }
  final server = values['EWS_SERVER'];
  final login = values['EWS_ACCOUNT'];
  final password = values['EWS_PW'];
  if (server == null || login == null || password == null) {
    stderr.writeln('Provide EWS_SERVER, EWS_ACCOUNT and EWS_PW.');
    exitCode = 2;
    return;
  }
  final endpoint = Uri.parse(
    server.contains('://') ? server : 'https://$server',
  );
  final parts = login.split(r'\');
  final mail = MailAccountId(
    'test',
    profile: MailProfileId('tasks', hostId: 'crispoffice'),
  );
  final session = MailAccountSession(mail);
  final account = TaskAccountId('test', provider: 'ews');
  final configuration = MailEwsConfiguration(
    account: mail,
    endpoint: endpoint.path.toLowerCase().endsWith('/exchange.asmx')
        ? endpoint
        : endpoint.replace(path: '/EWS/Exchange.asmx'),
    username: parts.last,
    domain: parts.length == 2 ? parts.first : '',
    credential: MailCredentialReference(account: mail, key: 'test'),
  );
  final credentials = _ProbeCredentials(password);
  if (calendar) {
    await _probeCalendar(account, configuration, credentials, session);
    return;
  }
  final reader = createEwsTaskReader(
    account: account,
    configuration: configuration,
    credentialStore: credentials,
  );
  final list = await reader.taskLists(session.begin());
  if (list case TaskFailure(:final problem)) {
    stdout.writeln('EWS task-list discovery failed: ${problem.code.name}');
    exitCode = 1;
    return;
  }
  final lists = (list as TaskSuccess<List<TaskList>>).value;
  stdout.writeln('EWS task folders discovered: ${lists.length}.');
  final id = lists.first.id;
  String? cursor;
  var total = 0;
  for (var page = 0; page < 10; page++) {
    final result = await reader.pullTasks(
      id,
      cursor: cursor,
      lease: session.begin(),
    );
    if (result case TaskFailure(:final problem)) {
      stdout.writeln('EWS Tasks sync failed: ${problem.code.name}');
      exitCode = 1;
      return;
    }
    final data = (result as TaskSuccess<TaskSyncPage>).value;
    total += data.upserts.length;
    cursor = data.nextCursor;
    if (cursor == null && data.checkpoint != null) {
      final repeat = await reader.pullTasks(
        id,
        cursor: data.checkpoint,
        lease: session.begin(),
      );
      if (repeat case TaskFailure(:final problem)) {
        stdout.writeln(
          'EWS Tasks incremental sync failed: ${problem.code.name}',
        );
        exitCode = 1;
        return;
      }
      final delta = (repeat as TaskSuccess<TaskSyncPage>).value;
      stdout.writeln(
        'Default EWS Tasks list synced: $total tasks across ${page + 1} baseline pages. Incremental read: ${delta.upserts.length} changes, ${delta.tombstones.length} deletions.',
      );
      return;
    }
  }
  stdout.writeln('EWS Tasks sync exceeded the probe page limit.');
  exitCode = 1;
}

Future<void> _probeCalendar(
  TaskAccountId account,
  MailEwsConfiguration configuration,
  MailCredentialStore credentials,
  MailAccountSession session,
) async {
  final reader =
      createEwsCalendarReader(
            account: account,
            configuration: configuration,
            credentialStore: credentials,
          )
          as EwsCalendarWriter;
  final discovered = await reader.calendars(session.begin());
  if (discovered case TaskFailure(:final problem)) {
    stdout.writeln('EWS calendar discovery failed: ${problem.code.name}');
    exitCode = 1;
    return;
  }
  final calendars = (discovered as TaskSuccess<List<EwsCalendar>>).value;
  final now = DateTime.now().toUtc();
  final start = now.subtract(const Duration(days: 7));
  final end = now.add(const Duration(days: 23));
  var events = 0;
  var eligible = 0;
  var opened = false;
  for (final calendar in calendars) {
    final result = await reader.agenda(
      calendar.id,
      start: start,
      end: end,
      lease: session.begin(),
    );
    if (result case TaskFailure(:final problem)) {
      stdout.writeln('EWS CalendarView failed: ${problem.code.name}');
      exitCode = 1;
      return;
    }
    final entries = (result as TaskSuccess<List<EwsCalendarEvent>>).value;
    events += entries.length;
    final appointments = entries.where(
      (event) => event.appointmentRevision != null,
    );
    eligible += appointments.length;
    if (!opened && appointments.isNotEmpty) {
      final result = await reader.openAppointment(
        calendar.id,
        appointments.first,
        session.begin(),
      );
      if (result case TaskFailure(:final problem)) {
        stdout.writeln('EWS appointment read failed: ${problem.code.name}');
        exitCode = 1;
        return;
      }
      opened = true;
    }
  }
  stdout.writeln(
    'EWS calendars: ${calendars.length}, 30-day events: $events, eligible appointments: $eligible, appointment opened: $opened.',
  );
}
