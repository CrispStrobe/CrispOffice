import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

Future<void> main() async {
  const source =
      'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//portable-test//EN\r\n'
      'BEGIN:VTODO\r\nUID:portable\r\nSUMMARY:Original\r\n'
      'DUE;VALUE=DATE:20261125\r\nX-KEEP:opaque-data\r\n'
      'END:VTODO\r\nEND:VCALENDAR\r\n';
  final document = CalDavTodoDocument.parse(source);
  if (document.encode() != source) {
    throw StateError('Portable VTODO no-op changed the source.');
  }
  final patched = document.apply(
    const TaskPatch(title: TaskFieldPatch.set('Portable ä 🗂️')),
  );
  final reparsed = CalDavTodoDocument.parse(patched.encode());
  if (reparsed.summary != 'Portable ä 🗂️' ||
      reparsed.toTaskFields().due != TaskDate(2026, 11, 25) ||
      !reparsed.encode().contains('X-KEEP:opaque-data\r\n') ||
      reparsed.uid != document.uid) {
    throw StateError('Portable VTODO patch round-trip failed.');
  }
  print('Portable VTODO preservation and date projection passed.');

  const url = 'https://dav.example/tasks/';
  final client = MockClient((request) async {
    final values = request.method == 'PROPFIND'
        ? '<d:response><d:href>/tasks/</d:href><d:propstat><d:prop>'
              '<d:resourcetype><c:calendar/></d:resourcetype>'
              '<c:supported-calendar-component-set><c:comp name="VTODO"/>'
              '</c:supported-calendar-component-set></d:prop>'
              '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>'
        : '';
    return http.Response(
      '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
      '$values</d:multistatus>',
      207,
    );
  });
  try {
    final provider = CalDavTaskProvider(
      account: TaskAccountId('portable', provider: 'caldav'),
      settings: CalDavConnectionSettings(
        profile: CalDavServerProfile.generic,
        username: 'portable',
        discoveryUrl: Uri.parse(url),
        collectionUrl: Uri.parse(url),
      ),
      client: client,
      appPassword: () async => 'fixture',
    );
    final lists = await provider.discoverLists();
    if (lists is! TaskSuccess<List<CalDavTaskList>>) {
      throw StateError('Portable DAV discovery failed.');
    }
    final page = await provider.pull(lists.value.single, knownRevisions: {});
    if (page is! TaskSuccess<TaskSyncPage> ||
        page.value.upserts.isNotEmpty ||
        page.value.checkpoint == null) {
      throw StateError('Portable DAV snapshot failed.');
    }
    print('Portable CalDAV discovery and snapshot passed.');
  } finally {
    client.close();
  }
}
