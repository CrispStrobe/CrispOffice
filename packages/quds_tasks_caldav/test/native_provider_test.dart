import 'dart:convert';
import 'dart:io';

import 'package:quds_tasks_caldav/quds_tasks_caldav_native.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:test/test.dart';

T _value<T>(TaskResult<T> result) {
  expect(result, isA<TaskSuccess<T>>());
  return (result as TaskSuccess<T>).value;
}

void main() {
  test(
    'native CalDAV round trip uses Basic auth and conditional writes',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = createNativeCalDavClient();
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      final origin = Uri.parse('http://127.0.0.1:${server.port}');
      final requests = <String>[];
      String? stored;
      var version = 0;
      server.listen((request) async {
        expect(
          request.headers.value('authorization'),
          'Basic YWxpY2U6c2VjcmV0',
        );
        final method = request.method;
        requests.add(method);
        final body = await utf8.decoder.bind(request).join();
        final response = request.response;
        final etag = '"v$version"';
        switch (method) {
          case 'PROPFIND':
            expect(request.uri.path, '/tasks/');
            response.statusCode = 207;
            response.write('''
<multistatus xmlns="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <response><href>/tasks/</href><propstat><prop>
    <resourcetype><collection/><c:calendar/></resourcetype>
    <c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>
    <current-user-privilege-set><privilege><write/></privilege></current-user-privilege-set>
  </prop><status>HTTP/1.1 200 OK</status></propstat></response>
</multistatus>
''');
          case 'PUT':
            expect(request.uri.path, '/tasks/crispoffice-op-1.ics');
            if (stored == null) {
              expect(request.headers.value('if-none-match'), '*');
              response.statusCode = 201;
              stored = body.replaceFirst('SUMMARY:First', 'SUMMARY:Normalized');
            } else {
              expect(request.headers.value('if-match'), etag);
              response.statusCode = 204;
              stored = body;
            }
            version++;
          case 'GET':
            if (stored == null) {
              response.statusCode = 404;
            } else {
              response.headers.set('etag', etag);
              response.write(stored);
            }
          case 'DELETE':
            expect(request.headers.value('if-match'), etag);
            stored = null;
            response.statusCode = 204;
          default:
            response.statusCode = 405;
        }
        await response.close();
      });
      final provider = CalDavTaskProvider(
        settings: CalDavConnectionSettings(
          profile: CalDavServerProfile.generic,
          username: 'alice',
          discoveryUrl: origin,
          collectionUrl: origin.resolve('/tasks/'),
          allowLoopbackHttp: true,
        ),
        account: TaskAccountId('native', provider: 'caldav'),
        client: client,
        appPassword: () async => 'secret',
      );

      final list = _value(await provider.discoverLists()).single;
      final created = _value(
        await provider.create(
          list,
          operationId: 'op-1',
          fields: const TaskFields(title: 'First'),
          timestamp: DateTime.utc(2026),
        ),
      );
      expect(created.fields.title, 'Normalized');
      expect(created.revision, '"v1"');

      final updated = _value(
        await provider.update(
          list,
          created.id,
          expectedRevision: created.revision!,
          patch: const TaskPatch(title: TaskFieldPatch.set('Updated')),
        ),
      );
      expect(updated.fields.title, 'Updated');
      expect(updated.revision, '"v2"');
      expect(
        _value(
          await provider.delete(
            list,
            updated.id,
            expectedRevision: updated.revision!,
          ),
        ),
        TaskUnit.value,
      );
      expect(_value(await provider.read(list, updated.id)), isNull);
      expect(requests, [
        'PROPFIND',
        'PUT',
        'GET',
        'GET',
        'PUT',
        'GET',
        'GET',
        'DELETE',
        'GET',
      ]);
    },
  );
}
