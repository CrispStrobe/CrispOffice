import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:test/test.dart';

const _origin = 'https://dav.example';
const _list = '/home/tasks/';
const _a = '/home/tasks/a.ics';
const _b = '/home/tasks/b.ics';
const _c = '/home/tasks/c.ics';
const _todo =
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VTODO\r\nUID:keep\r\n'
    'DTSTAMP:20261125T000000Z\r\nSUMMARY:Original\r\nX-CUSTOM:Keep me\r\n'
    'END:VTODO\r\nEND:VCALENDAR\r\n';
const _event =
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:event\r\n'
    'END:VEVENT\r\nEND:VCALENDAR\r\n';
const _ns = 'xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"';
const _calendar =
    '<d:resourcetype><d:collection/><c:calendar/></d:resourcetype>';
const _tasks =
    '<c:supported-calendar-component-set><c:comp name="VTODO"/>'
    '</c:supported-calendar-component-set>';
const _rights =
    '<d:current-user-privilege-set><d:privilege><d:write/></d:privilege>'
    '</d:current-user-privilege-set>';
const _sync =
    '<d:supported-report-set><d:supported-report><d:report>'
    '<d:sync-collection/></d:report></d:supported-report></d:supported-report-set>';

http.Response _multi(String inner) => http.Response(
  '<d:multistatus $_ns>$inner</d:multistatus>',
  207,
  headers: {'content-type': 'application/xml; charset=utf-8'},
);

String _props(String href, String values, {int status = 200}) =>
    '<d:response><d:href>$href</d:href><d:propstat><d:prop>$values</d:prop>'
    '<d:status>HTTP/1.1 $status Test</d:status></d:propstat></d:response>';

String _status(String href, int status) =>
    '<d:response><d:href>$href</d:href><d:status>HTTP/1.1 $status Test</d:status></d:response>';

String _etag(String version) => '<d:getetag>"$version"</d:getetag>';

String _data(String text) =>
    '<c:calendar-data>${const HtmlEscape().convert(text)}</c:calendar-data>';

CalDavTaskProvider _provider(
  Future<http.Response> Function(http.Request request) handle, {
  String owner = 'account',
  bool exact = true,
  String? password = 'app-password',
}) {
  final client = MockClient(handle);
  addTearDown(client.close);
  return CalDavTaskProvider(
    account: TaskAccountId(owner, provider: 'caldav'),
    settings: CalDavConnectionSettings(
      profile: CalDavServerProfile.generic,
      username: 'dav-user',
      discoveryUrl: Uri.parse('$_origin/'),
      collectionUrl: exact ? Uri.parse('$_origin$_list') : null,
    ),
    client: client,
    appPassword: () async => password,
  );
}

T _value<T>(TaskResult<T> result) {
  expect(
    result,
    isA<TaskSuccess<T>>(),
    reason: '${result is TaskFailure<T> ? result.problem.code : result}',
  );
  return (result as TaskSuccess<T>).value;
}

TaskProblem _problem<T>(TaskResult<T> result) =>
    (result as TaskFailure<T>).problem;

Future<CalDavTaskList> _discover(CalDavTaskProvider provider) async =>
    _value(await provider.discoverLists()).single;

TaskId _task(CalDavTaskList list, String path) =>
    TaskId('$_origin$path', list: list.id);

void main() {
  test(
    'follows same-origin discovery, filters component sets and reads privileges',
    () async {
      final paths = <String>[];
      final provider = _provider((request) async {
        paths.add(request.url.path);
        expect(request.method, 'PROPFIND');
        expect(request.followRedirects, isFalse);
        expect(
          request.headers['authorization'],
          'Basic ${base64.encode(utf8.encode('dav-user:app-password'))}',
        );
        return switch (request.url.path) {
          '/' => http.Response('', 308, headers: {'location': '/dav/'}),
          '/dav/' => _multi(
            _props(
              '/dav/',
              '<d:current-user-principal><d:href>/principals/me/</d:href></d:current-user-principal>',
            ),
          ),
          '/principals/me/' => _multi(
            _props(
              '/principals/me/',
              '<c:calendar-home-set><d:href>/home/</d:href></c:calendar-home-set>',
            ),
          ),
          '/home/' => _multi(
            _props(
                  '/home/',
                  '<d:resourcetype><d:collection/></d:resourcetype>',
                ) +
                _props(
                  _list,
                  '$_calendar$_tasks$_sync<d:displayname>My Tasks</d:displayname>'
                  '<d:current-user-privilege-set><d:privilege><d:write-content/></d:privilege></d:current-user-privilege-set>',
                ) +
                _props(
                  '/home/events/',
                  '$_calendar<c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>',
                ) +
                _props(
                  '/home/spoof/',
                  '$_calendar<c:supported-calendar-component-set xmlns:c="urn:foreign"><c:comp name="VTODO"/></c:supported-calendar-component-set>',
                ),
          ),
          _ => throw StateError('Unexpected request'),
        };
      }, exact: false);
      final result = await _discover(provider);
      expect(paths, ['/', '/dav/', '/principals/me/', '/home/']);
      expect(result.list.name, 'My Tasks');
      expect(result.supportsSyncCollection, isTrue);
      expect(result.canUpdate, isTrue);
      expect(result.canCreate, isFalse);
      expect(result.canDelete, isFalse);
    },
  );

  test(
    'rejects cross-origin redirects before sending credentials there',
    () async {
      var calls = 0;
      final provider = _provider((request) async {
        calls++;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://other.example/dav/'},
        );
      }, exact: false);
      expect(
        _problem(await provider.discoverLists()).code,
        TaskProblemCode.invalidResponse,
      );
      expect(calls, 1);
    },
  );

  test('standard absent component property permits a mixed calendar', () async {
    final provider = _provider(
      (_) async => _multi(
        '${_props(_list, _calendar).replaceFirst('</d:response>', '')}'
        '<d:propstat><d:prop><c:supported-calendar-component-set/></d:prop>'
        '<d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response>',
      ),
    );
    final list = await _discover(provider);
    expect(list.id.value, '$_origin$_list');
  });

  test('missing credentials fail before HTTP dispatch', () async {
    final provider = _provider(
      (_) async => throw StateError('Unexpected request'),
      password: null,
    );
    expect(
      _problem(await provider.discoverLists()).code,
      TaskProblemCode.authenticationRequired,
    );
  });

  test('reports a DAV retry deadline without retrying the request', () async {
    var requests = 0;
    final provider = _provider((_) async {
      requests++;
      return http.Response('', 429, headers: {'retry-after': '120'});
    });
    final problem = _problem(await provider.discoverLists());
    expect(problem.code, TaskProblemCode.throttled);
    expect(problem.retryAfter, const Duration(minutes: 2));
    expect(requests, 1);
  });

  test(
    'exact collection verifies VTODO support and enforces read-only discovery',
    () async {
      var calls = 0;
      final provider = _provider((request) async {
        calls++;
        expect(request.url.path, _list);
        expect(request.headers['depth'], '0');
        return _multi(_props(_list, '$_calendar$_tasks'));
      });
      final list = await _discover(provider);
      expect(list.list.readOnly, isTrue);
      final failure = _problem(
        await provider.create(
          list,
          operationId: 'one',
          fields: const TaskFields(title: 'Title'),
          timestamp: DateTime.utc(2026),
        ),
      );
      expect(failure.code, TaskProblemCode.permissionDenied);
      expect(calls, 1);
    },
  );

  test(
    'rejects DTD, malformed XML, excessive nesting and duplicate hrefs',
    () async {
      final responses = [
        http.Response(
          '<!DOCTYPE x [<!ENTITY ext SYSTEM "https://other.example">]><d:multistatus $_ns/>',
          207,
        ),
        http.Response('<d:multistatus $_ns><x>', 207),
        http.Response('<!--empty-->', 207),
        http.Response(
          '<d:multistatus $_ns>${'<x>' * 30}${'</x>' * 30}</d:multistatus>',
          207,
        ),
        _multi(
          _props(_list, '$_calendar$_tasks') +
              _props(_list, '$_calendar$_tasks'),
        ),
      ];
      final provider = _provider((_) async => responses.removeAt(0));
      while (responses.isNotEmpty) {
        expect(
          _problem(await provider.discoverLists()).code,
          TaskProblemCode.invalidResponse,
        );
      }
    },
  );

  test(
    'baseline uses ETag comparison and infers deletion only after complete read',
    () async {
      final provider = _provider((request) async {
        if (request.method == 'PROPFIND') {
          return _multi(_props(_list, '$_calendar$_tasks'));
        }
        if (request.body.contains('calendar-query')) {
          expect(request.headers['depth'], '1');
          expect(request.body, contains('name="VTODO"'));
          return _multi(_props(_a, _etag('same')) + _props(_b, _etag('new')));
        }
        expect(request.body, contains('calendar-multiget'));
        expect(request.body, contains(_b));
        expect(request.body, isNot(contains(_a)));
        return _multi(_props(_b, _etag('new') + _data(_todo)));
      });
      final list = await _discover(provider);
      final page = _value(
        await provider.pull(
          list,
          knownRevisions: {
            _task(list, _a): '"same"',
            _task(list, _c): '"removed"',
          },
        ),
      );
      expect(page.checkpoint, isNotNull);
      expect(page.tombstones, [_task(list, _c)]);
      expect(page.upserts.single.id, _task(list, _b));
      expect(
        page.upserts.single.providerData?.raw,
        contains('X-CUSTOM:Keep me'),
      );
    },
  );

  test('truncated incremental sync continues and filters events', () async {
    final calls = <String>[];
    final provider = _provider((request) async {
      if (request.method == 'PROPFIND') {
        if (request.body.contains('<D:sync-token/>')) {
          calls.add('token');
          return _multi(
            _props(_list, '<d:sync-token>urn:sync:1</d:sync-token>'),
          );
        }
        return _multi(_props(_list, '$_calendar$_tasks$_sync'));
      }
      if (request.body.contains('calendar-query')) {
        calls.add('baseline');
        return _multi('');
      }
      if (request.body.contains('calendar-multiget')) {
        return _multi(
          _props(_a, _etag('v2') + _data(_todo)) +
              _props(_b, _etag('event') + _data(_event)),
        );
      }
      if (request.body.contains('urn:sync:1')) {
        return _multi(
          '${_props(_a, _etag('v2'))}${_props(_b, _etag('event'))}${_status(_list, 507)}<d:sync-token>urn:sync:2</d:sync-token>',
        );
      }
      expect(request.body, contains('urn:sync:2'));
      return _multi(
        '${_status(_c, 404)}<d:sync-token>urn:sync:3</d:sync-token>',
      );
    });
    final list = await _discover(provider);
    final initial = _value(await provider.pull(list, knownRevisions: {}));
    expect(calls, ['token', 'baseline']);
    final first = _value(
      await provider.pull(list, knownRevisions: {}, cursor: initial.checkpoint),
    );
    expect(first.complete, isFalse);
    expect(first.checkpoint, isNull);
    expect(first.upserts.single.id, _task(list, _a));
    expect(first.tombstones, isEmpty);
    final second = _value(
      await provider.pull(list, knownRevisions: {}, cursor: first.nextCursor),
    );
    expect(second.complete, isTrue);
    expect(second.checkpoint, isNotNull);
    expect(second.tombstones, [_task(list, _c)]);
  });

  test('expired token signals reset, foreign cursor stays local', () async {
    var reports = 0;
    Future<http.Response> server(http.Request request) async {
      if (request.method == 'PROPFIND') {
        return _multi(
          _props(
            _list,
            '$_calendar$_tasks$_sync<d:sync-token>urn:sync:old</d:sync-token>',
          ),
        );
      }
      reports++;
      if (request.body.contains('calendar-query')) return _multi('');
      return http.Response(
        '<d:error $_ns><d:valid-sync-token/></d:error>',
        403,
      );
    }

    final provider = _provider(server);
    final list = await _discover(provider);
    final baseline = _value(await provider.pull(list, knownRevisions: {}));
    final foreign = _provider(server, owner: 'different');
    final other = await _discover(foreign);
    expect(
      _problem(
        await foreign.pull(
          other,
          knownRevisions: {},
          cursor: baseline.checkpoint,
        ),
      ).code,
      TaskProblemCode.invalidInput,
    );
    expect(reports, 1);
    final expired = _value(
      await provider.pull(
        list,
        knownRevisions: {},
        cursor: baseline.checkpoint,
      ),
    );
    expect(expired.resetRequired, isTrue);
    expect(expired.tombstones, isEmpty);
    expect(expired.checkpoint, isNull);
  });

  test('unsupported sync report falls back to a complete ETag query', () async {
    var queries = 0;
    final provider = _provider((request) async {
      if (request.method == 'PROPFIND') {
        return _multi(
          _props(
            _list,
            '$_calendar$_tasks$_sync<d:sync-token>urn:sync:1</d:sync-token>',
          ),
        );
      }
      if (request.body.contains('calendar-query')) {
        queries++;
        return _multi('');
      }
      return http.Response('', 501);
    });
    final list = await _discover(provider);
    final baseline = _value(await provider.pull(list, knownRevisions: {}));
    final fallback = _value(
      await provider.pull(
        list,
        knownRevisions: {_task(list, _a): '"gone"'},
        cursor: baseline.checkpoint,
      ),
    );
    expect(fallback.checkpoint, isNotNull);
    expect(fallback.tombstones, [_task(list, _a)]);
    expect(queries, 2);
  });

  test(
    'partial, changed, and cross-collection report rows fail a baseline',
    () async {
      final responses = [
        _multi(_props('/home/other/a.ics', _etag('tag'))),
        _multi(_props(_a, _etag('tag'), status: 403)),
        _multi(_props(_a, _etag('tag'))),
        _multi(_props(_a, _etag('changed') + _data(_todo))),
        _multi(_props(_a, _etag('tag'))),
        _multi(''),
      ];
      final provider = _provider((request) async {
        if (request.method == 'PROPFIND') {
          return _multi(_props(_list, '$_calendar$_tasks'));
        }
        return responses.removeAt(0);
      });
      final list = await _discover(provider);
      for (final code in [
        TaskProblemCode.invalidResponse,
        TaskProblemCode.permissionDenied,
        TaskProblemCode.conflict,
        TaskProblemCode.invalidResponse,
      ]) {
        expect(
          _problem(
            await provider.pull(
              list,
              knownRevisions: {_task(list, _b): '"keep"'},
            ),
          ).code,
          code,
        );
      }
    },
  );

  test(
    'update preserves resource data and an intervening edit fails If-Match',
    () async {
      var puts = 0;
      final provider = _provider((request) async {
        if (request.method == 'PROPFIND') {
          return _multi(_props(_list, '$_calendar$_tasks$_rights'));
        }
        if (request.method == 'GET') {
          return http.Response(_todo, 200, headers: {'etag': '"v1"'});
        }
        expect(request.method, 'PUT');
        puts++;
        expect(request.headers['if-match'], '"v1"');
        expect(request.body, contains('UID:keep'));
        expect(request.body, contains('X-CUSTOM:Keep me'));
        expect(request.body, contains('SUMMARY:New'));
        return http.Response('', 412);
      });
      final list = await _discover(provider);
      final failed = _problem(
        await provider.update(
          list,
          _task(list, _a),
          expectedRevision: '"v1"',
          patch: const TaskPatch(title: TaskFieldPatch.set('New')),
        ),
      );
      expect(failed.code, TaskProblemCode.conflict);
      expect(failed.mutationMayHaveOccurred, isFalse);
      expect(puts, 1);
      expect(
        _problem(
          await provider.delete(
            list,
            _task(list, _a),
            expectedRevision: 'W/"v1"',
          ),
        ).code,
        TaskProblemCode.invalidInput,
      );
    },
  );

  test(
    'unsupported readback after a successful update stays uncertain',
    () async {
      var wrote = false;
      final provider = _provider((request) async {
        if (request.method == 'PROPFIND') {
          return _multi(_props(_list, '$_calendar$_tasks$_rights'));
        }
        if (request.method == 'PUT') {
          wrote = true;
          return http.Response('', 204);
        }
        final source = wrote
            ? _todo.replaceFirst(
                'END:VTODO',
                'STATUS:UNRECOGNIZED\r\nEND:VTODO',
              )
            : _todo;
        return http.Response(
          source,
          200,
          headers: {'etag': wrote ? '"two"' : '"one"'},
        );
      });
      final list = await _discover(provider);
      final problem = _problem(
        await provider.update(
          list,
          _task(list, _a),
          expectedRevision: '"one"',
          patch: const TaskPatch(title: TaskFieldPatch.set('New')),
        ),
      );
      expect(problem.code, TaskProblemCode.unsupported);
      expect(problem.mutationMayHaveOccurred, isTrue);
    },
  );

  test(
    'uncertain create is reconciled with read-only deterministic recovery',
    () async {
      String? stored;
      var puts = 0;
      final provider = _provider((request) async {
        if (request.method == 'PROPFIND') {
          return _multi(_props(_list, '$_calendar$_tasks$_rights'));
        }
        expect(request.url.path, '${_list}crispoffice-stable_op.ics');
        if (request.method == 'PUT') {
          puts++;
          expect(request.headers['if-none-match'], '*');
          stored = request.body;
          throw http.ClientException('Connection closed after commit');
        }
        expect(request.method, 'GET');
        return http.Response(stored!, 200, headers: {'etag': '"created"'});
      });
      final list = await _discover(provider);
      final failed = _problem(
        await provider.create(
          list,
          operationId: 'stable_op',
          fields: const TaskFields(title: 'Created'),
          timestamp: DateTime.utc(2026),
        ),
      );
      expect(failed.code, TaskProblemCode.unavailable);
      expect(failed.mutationMayHaveOccurred, isTrue);
      final found = _value(
        await provider.recoverCreate(list, operationId: 'stable_op'),
      );
      expect(found?.fields.title, 'Created');
      expect(found?.revision, '"created"');
      expect(puts, 1);
      stored = _todo;
      expect(
        _problem(
          await provider.recoverCreate(list, operationId: 'stable_op'),
        ).code,
        TaskProblemCode.conflict,
      );
    },
  );
}
