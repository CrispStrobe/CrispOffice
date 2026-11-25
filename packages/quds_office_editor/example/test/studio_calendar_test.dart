import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quds_office_studio/credentials/secure_storage_service.dart';
import 'package:quds_office_studio/studio_calendar.dart';
import 'package:quds_office_studio/studio_credential_storage.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_productivity_accounts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _login = 'mailbox@example.test';
const _password = 'dav-fixture-password';

Future<void> _seedDav(SecureStorage vault) => vault.write(
  studioTasksLegacyKey,
  jsonEncode({
    'id': 'saved',
    'provider': 'caldav',
    'url': 'https://dav.example.test/',
    'collection': 'https://dav.example.test/home/tasks/',
    'login': _login,
    'secret': _password,
    'davProfile': 'caldav',
  }),
);

String _multi(String href, String props) =>
    '<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
    '<D:response><D:href>$href</D:href><D:propstat><D:prop>$props</D:prop>'
    '<D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>'
    '</D:multistatus>';

void main() {
  test(
    'connections group matching Mail and DAV accounts without exposing secrets',
    () async {
      final vault = InMemorySecureStorage();
      await _seedDav(vault);
      final saved = await StudioMailAccountsStore(storage: () async => vault)
          .saveAccount(
            const StudioMailCredentials(
              email: _login,
              password: 'mail-fixture-password',
              imapHost: 'imap.example.test',
              smtpHost: 'smtp.example.test',
              manual: true,
              startTls: false,
            ),
          );
      expect(saved.isSuccess, isTrue);
      final result = await loadStudioProductivityAccounts(vault);
      expect(result.single.label, _login);
      expect(result.single.services, StudioProductivityService.values.toSet());
      expect(result.toString(), isNot(contains('password')));
      expect(await vault.read(studioTasksLegacyKey), isNotNull);
    },
  );

  testWidgets('Calendar reads the saved Tasks DAV account and shows its events', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final vault = InMemorySecureStorage();
    await _seedDav(vault);
    final storage = StudioCredentialStorage(
      systemStorageFactory: () async => vault,
    );
    addTearDown(storage.dispose);
    final paths = <String>[];
    const event =
        'BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VEVENT\n'
        'UID:fixture\nDTSTART;VALUE=DATE:20261125\nSUMMARY:Fixture appointment\n'
        'END:VEVENT\nEND:VCALENDAR';

    await tester.pumpWidget(
      MaterialApp(
        home: StudioCalendarPage(
          title: 'Calendar',
          chromeBuilder: (_) => const Text('Shared window chrome'),
          openConnections: () {},
          credentialStorage: storage,
          openDavClient: () => MockClient((request) async {
            paths.add(request.url.path);
            expect(
              request.headers['authorization'],
              'Basic ${base64.encode(utf8.encode('$_login:$_password'))}',
            );
            final response = switch (request.url.path) {
              '/' => _multi(
                '/',
                '<C:calendar-home-set><D:href>/home/</D:href></C:calendar-home-set>',
              ),
              '/home/' => _multi(
                '/home/events/',
                '<D:resourcetype><C:calendar/></D:resourcetype>'
                    '<D:displayname>Personal calendar</D:displayname>'
                    '<C:supported-calendar-component-set><C:comp name="VEVENT"/></C:supported-calendar-component-set>',
              ),
              '/home/events/' => _multi(
                '/home/events/fixture.ics',
                '<C:calendar-data>$event</C:calendar-data>',
              ),
              _ => throw StateError('Unexpected calendar request.'),
            };
            if (request.method == 'REPORT') {
              expect(request.body, contains('<C:expand'));
            }
            return http.Response(response, 207, request: request);
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Shared window chrome'), findsOneWidget);
    expect(find.text('Personal calendar'), findsOneWidget);
    expect(find.text('Fixture appointment'), findsOneWidget);
    expect(paths, ['/', '/home/', '/home/events/']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
