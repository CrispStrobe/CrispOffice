import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:quds_tasks_caldav/quds_tasks_caldav_native.dart';
import 'package:quds_tasks_caldav/src/dav_http.dart';
import 'package:quds_tasks_caldav/src/dav_uri.dart';
import 'package:quds_tasks_caldav/src/dav_xml.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

T value<T>(TaskResult<T> result, String stage) {
  if (result is TaskFailure<T>) {
    throw StateError('$stage: ${result.problem.code.name}');
  }
  return (result as TaskSuccess<T>).value;
}

void main(List<String> args) async {
  final settings = <String, String>{};
  final useIsolated = args.contains('--isolated');
  final files = args.where((arg) => arg != '--isolated').toList();
  if (files.length > 1) {
    stderr.writeln('Supply one credential file and optionally --isolated.');
    exitCode = 2;
    return;
  }
  if (files.isNotEmpty) {
    for (final line in File(files.single).readAsLinesSync()) {
      final match = RegExp(
        r'^\s*(?:export\s+)?(MBOX_LOGIN|MBOX_PW|MBOX_TASK_TEST_URL)\s*=\s*(.*?)\s*$',
      ).firstMatch(line);
      if (match == null) continue;
      final raw = match[2]!;
      final quoted =
          raw.length >= 2 &&
          raw[0] == raw[raw.length - 1] &&
          (raw[0] == '"' || raw[0] == "'");
      settings[match[1]!] = quoted ? raw.substring(1, raw.length - 1) : raw;
    }
  }
  final login = settings['MBOX_LOGIN'] ?? Platform.environment['MBOX_LOGIN'];
  final password = settings['MBOX_PW'] ?? Platform.environment['MBOX_PW'];
  final testUrl =
      settings['MBOX_TASK_TEST_URL'] ??
      Platform.environment['MBOX_TASK_TEST_URL'];
  if (login == null || password == null) {
    stderr.writeln('Mailbox credential variables are required.');
    exitCode = 2;
    return;
  }
  if (useIsolated && testUrl != null) {
    stderr.writeln(
      'Choose either --isolated or a designated MBOX_TASK_TEST_URL.',
    );
    exitCode = 2;
    return;
  }
  final client = createNativeCalDavClient();
  final transport = Platform.environment['CRISPOFFICE_DAV_TRACE'] == '1'
      ? _TraceClient(client)
      : client;
  final config = CalDavConnectionSettings(
    profile: CalDavServerProfile.mailboxOrg,
    username: login,
  );
  final dav = DavHttp(config, transport, () async => password);
  _LiveFixture? fixture;
  try {
    if (useIsolated) {
      fixture = await _LiveFixture.create(dav, config.discoveryUrl);
    }
    final exact =
        fixture?.canonical ?? (testUrl == null ? null : Uri.parse(testUrl));
    final provider = CalDavTaskProvider(
      account: TaskAccountId('live-mailbox-fixture', provider: 'caldav'),
      settings: CalDavConnectionSettings(
        profile: CalDavServerProfile.mailboxOrg,
        username: login,
        collectionUrl: exact,
      ),
      client: transport,
      appPassword: () async => password,
    );
    final lists = value(await provider.discoverLists(), 'discovery');
    stdout.writeln(
      'Authenticated discovery succeeded. Task collections: ${lists.length}.',
    );
    if (exact == null) return;
    final list = lists.single;
    if (!list.canCreate || !list.canUpdate || !list.canDelete) {
      throw StateError(
        'The dedicated live test list needs create, update and delete privileges.',
      );
    }
    final baseline = value(
      await provider.pull(list, knownRevisions: {}),
      'baseline',
    );
    if (baseline.upserts.isNotEmpty) {
      throw StateError('The dedicated live test list must be empty.');
    }
    final id = 'fixture-${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().toUtc();
    try {
      var task = value(
        await provider.create(
          list,
          operationId: id,
          fields: TaskFields(
            title: 'CrispOffice live task fixture',
            due: TaskDate(2030, 1, 2),
          ),
          timestamp: DateTime.utc(
            now.year,
            now.month,
            now.day,
            now.hour,
            now.minute,
            now.second,
          ),
        ),
        'create',
      );
      final recovered = value(
        await provider.recoverCreate(list, operationId: id),
        'recover',
      );
      if (recovered?.id != task.id) {
        throw StateError('Created task could not be recovered.');
      }
      final prior = task.revision!;
      task = value(
        await provider.update(
          list,
          task.id,
          expectedRevision: prior,
          patch: const TaskPatch(
            title: TaskFieldPatch.set('CrispOffice updated fixture'),
          ),
        ),
        'update',
      );
      final stale = await provider.delete(
        list,
        task.id,
        expectedRevision: prior,
      );
      if (stale is! TaskFailure<TaskUnit> ||
          stale.problem.code != TaskProblemCode.conflict) {
        throw StateError('A stale revision did not report a conflict.');
      }
      final resource = Uri.parse(task.id.value);
      if (resource.origin != 'https://dav.mailbox.org') {
        throw StateError('Unexpected fixture resource origin.');
      }
      final staleResponse = await dav.send(
        'DELETE',
        resource,
        headers: {'if-match': prior},
      );
      if (staleResponse.statusCode != 412) {
        throw StateError(
          'Live server returned HTTP ${staleResponse.statusCode} for a stale If-Match.',
        );
      }
      final page = value(
        await provider.pull(
          list,
          knownRevisions: {},
          cursor: baseline.checkpoint,
        ),
        'incremental pull',
      );
      if (!page.upserts.any((row) => row.id == task.id)) {
        throw StateError(
          'The fixture task was absent from incremental results.',
        );
      }
      value(
        await provider.delete(list, task.id, expectedRevision: task.revision!),
        'delete',
      );
      final deleted = value(
        await provider.pull(
          list,
          knownRevisions: {task.id: task.revision},
          cursor: page.checkpoint,
        ),
        'deletion pull',
      );
      if (!deleted.tombstones.contains(task.id)) {
        throw StateError('The live deletion did not appear as a tombstone.');
      }
      if (value(await provider.read(list, task.id), 'confirmed deletion') !=
          null) {
        throw StateError('The live fixture still exists after deletion.');
      }
      stdout.writeln(
        'Live create, recovery, update, server If-Match rejection, sync and deletion passed.',
      );
    } finally {
      final remaining = value(
        await provider.recoverCreate(list, operationId: id),
        'fixture cleanup lookup',
      );
      if (remaining != null) {
        value(
          await provider.delete(
            list,
            remaining.id,
            expectedRevision: remaining.revision!,
          ),
          'fixture cleanup',
        );
        if (value(
              await provider.read(list, remaining.id),
              'fixture deletion verification',
            ) !=
            null) {
          throw StateError('The fixture still exists after deletion.');
        }
        stdout.writeln('Live fixture cleanup verified.');
      }
    }
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } finally {
    try {
      await fixture?.cleanup(dav);
    } on StateError catch (error) {
      stderr.writeln(error.message);
      exitCode = 1;
    } finally {
      client.close();
    }
  }
}

class _TraceClient extends http.BaseClient {
  _TraceClient(this.client);
  final http.Client client;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await client.send(request);
    stdout.writeln(
      'DAV ${request.method} HTTP ${response.statusCode} '
      'Location=${response.headers.containsKey('location')} '
      'ETag=${response.headers.containsKey('etag')}',
    );
    return response;
  }
}

final class _LiveFixture {
  const _LiveFixture(this.requested, this.canonical, this.name);

  final Uri requested;
  final Uri canonical;
  final String name;

  static Future<_LiveFixture> create(DavHttp http, Uri origin) async {
    final root = await _properties(
      http,
      origin,
      '<D:current-user-principal/><C:calendar-home-set/>',
    );
    var homes = root.property(cal, 'calendar-home-set');
    if (homes == null) {
      final current = root.property(dav, 'current-user-principal');
      final principal = current == null
          ? null
          : xmlValue(child(current, dav, 'href'));
      final resolved = principal == null ? null : davHref(origin, principal);
      if (resolved == null) {
        throw StateError('The fixture account has no discoverable principal.');
      }
      final props = await _properties(http, resolved, '<C:calendar-home-set/>');
      homes = props.property(cal, 'calendar-home-set');
    }
    final addresses = homes?.childElements.where(
      (element) => named(element, dav, 'href'),
    );
    final address = addresses?.firstOrNull;
    final home = address == null
        ? null
        : davHref(origin, xmlValue(address) ?? '');
    if (home == null) {
      throw StateError(
        'The fixture account has no discoverable calendar home.',
      );
    }

    final random = Random.secure();
    final nonce = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final name = 'CrispOffice test $nonce';
    final requested = collectionUri(
      home,
    ).resolve('crispoffice-fixture-$nonce/');
    final created = await http.send(
      'MKCALENDAR',
      requested,
      headers: {
        'if-none-match': '*',
        'content-type': 'application/xml; charset=utf-8',
      },
      body:
          '<C:mkcalendar $namespaces><D:set><D:prop><D:displayname>$name</D:displayname>'
          '<C:supported-calendar-component-set><C:comp name="VTODO"/></C:supported-calendar-component-set>'
          '</D:prop></D:set></C:mkcalendar>',
    );
    if (created.statusCode != 201) {
      throw StateError(
        'Isolated fixture provisioning returned HTTP ${created.statusCode}.',
      );
    }
    final confirmed = await _properties(http, requested, '<D:displayname/>');
    final canonical = davHref(requested, confirmed.href);
    if (canonical == null ||
        xmlValue(confirmed.property(dav, 'displayname')) != name) {
      throw StateError(
        'The server did not confirm ownership of the new fixture list.',
      );
    }
    stdout.writeln('Isolated live task list created.');
    return _LiveFixture(requested, canonical, name);
  }

  Future<void> cleanup(DavHttp http) async {
    final current = await _properties(http, requested, '<D:displayname/>');
    if (xmlValue(current.property(dav, 'displayname')) != name ||
        davHref(requested, current.href) != canonical) {
      throw StateError('Fixture ownership changed before cleanup.');
    }
    final deleted = await http.send('DELETE', requested);
    if (deleted.statusCode != 204 && deleted.statusCode != 200) {
      throw StateError('Fixture cleanup returned HTTP ${deleted.statusCode}.');
    }
    final remaining = await http.send(
      'PROPFIND',
      canonical,
      headers: {'depth': '0'},
    );
    if (remaining.statusCode != 404 && remaining.statusCode != 410) {
      throw StateError('Fixture collection absence could not be confirmed.');
    }
    stdout.writeln('Isolated live task list deletion verified.');
  }
}

Future<DavRow> _properties(DavHttp http, Uri uri, String names) async {
  final response = await http.send(
    'PROPFIND',
    uri,
    headers: {'depth': '0', 'content-type': 'application/xml; charset=utf-8'},
    body: '<D:propfind $namespaces><D:prop>$names</D:prop></D:propfind>',
  );
  if (response.statusCode != 207) {
    throw StateError(
      'Fixture property lookup returned HTTP ${response.statusCode}.',
    );
  }
  final rows = DavMultistatus(response.bodyBytes).rows;
  if (rows.length != 1) {
    throw StateError('Unexpected fixture property response.');
  }
  return rows.single;
}
