import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_tasks_store/quds_tasks_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _url = 'https://dav.example/tasks/';
const _path = '/tasks/opaque%20name';
const _todo =
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VTODO\r\n'
    'UID:uid\r\nSUMMARY:Reminder\r\nEND:VTODO\r\nEND:VCALENDAR\r\n';

T _value<T>(TaskResult<T> result) {
  expect(result, isA<TaskSuccess<T>>());
  return (result as TaskSuccess<T>).value;
}

String _response(String path, String properties) =>
    '<d:response><d:href>$path</d:href><d:propstat><d:prop>$properties</d:prop>'
    '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';

void main() {
  test(
    'DAV ETag mode skips unchanged content during a persisted refresh',
    () async {
      var fetched = 0;
      var exists = true;
      final client = MockClient((request) async {
        expect(request.url.path, '/tasks/');
        final String results;
        if (request.method == 'PROPFIND') {
          results = _response(
            '/tasks/',
            '<d:resourcetype><c:calendar/></d:resourcetype>'
                '<c:supported-calendar-component-set><c:comp name="VTODO"/>'
                '</c:supported-calendar-component-set>',
          );
        } else if (request.body.contains('calendar-query')) {
          results = exists
              ? _response(_path, '<d:getetag>"one"</d:getetag>')
              : '';
        } else {
          fetched++;
          expect(request.body, contains('<D:href>$_path</D:href>'));
          results = _response(
            _path,
            '<d:getetag>"one"</d:getetag><c:calendar-data>$_todo</c:calendar-data>',
          );
        }
        return http.Response(
          '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
          '$results</d:multistatus>',
          207,
        );
      });
      addTearDown(client.close);
      final database = sqlite3.openInMemory();
      addTearDown(database.close);
      final account = TaskAccountId('dav', provider: 'caldav');
      final provider = CalDavTaskProvider(
        account: account,
        settings: CalDavConnectionSettings(
          profile: CalDavServerProfile.generic,
          username: 'fixture',
          discoveryUrl: Uri.parse(_url),
          collectionUrl: Uri.parse(_url),
        ),
        client: client,
        appPassword: () async => 'fixture',
      );
      final list = _value(await provider.discoverLists()).single;
      final store = TaskPullStore(database);
      final lease = _value(store.connect(account));
      final worker = TaskPullWorker(store);
      Future<bool> refresh() async => _value(
        await worker.refresh(
          lease,
          list.id,
          (position) => provider.pull(
            list,
            cursor: position.cursor,
            knownRevisions: position.knownRevisions,
          ),
        ),
      );

      expect(await refresh(), isTrue);
      final stored = _value(store.tasks(list.id)).single;
      expect(stored.id.value, 'https://dav.example$_path');
      expect(stored.fields.title, 'Reminder');
      expect(stored.revision, '"one"');
      expect(await refresh(), isTrue);
      expect(fetched, 1);
      exists = false;
      expect(await refresh(), isTrue);
      expect(_value(store.tasks(list.id)), isEmpty);
    },
  );
}
