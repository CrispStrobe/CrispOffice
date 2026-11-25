import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:test/test.dart';

void main() {
  test('mailbox profile defaults to its documented DAV service', () {
    final settings = CalDavConnectionSettings(
      profile: CalDavServerProfile.mailboxOrg,
      username: 'person@mailbox.org',
    );
    expect(settings.discoveryUrl, Uri.parse('https://dav.mailbox.org/'));
    expect(settings.profile.loginMethods, {CalDavLoginMethod.appPassword});
    for (final feature in [
      CalDavFeature.recurrence,
      CalDavFeature.participants,
      CalDavFeature.sharedTaskLists,
      CalDavFeature.subtasks,
      CalDavFeature.attachments,
    ]) {
      expect(settings.profile.supportFor(feature), CalDavCapability.disabled);
    }
    expect(
      settings.profile.supportFor(CalDavFeature.syncTokens),
      CalDavCapability.discover,
    );
    expect(settings.profile.notes, contains('deprecated'));
  });

  test('Nextcloud and ownCloud are distinct deployment profiles', () {
    expect(
      CalDavServerProfile.nextcloud.loginMethods,
      contains(CalDavLoginMethod.nextcloudLoginFlowV2),
    );
    expect(
      CalDavServerProfile.nextcloud.supportFor(CalDavFeature.subtasks),
      CalDavCapability.documented,
    );
    expect(
      CalDavServerProfile.owncloud.supportFor(CalDavFeature.subtasks),
      CalDavCapability.discover,
    );
    expect(CalDavServerProfile.owncloud.notes, contains('Infinite Scale'));
    expect(CalDavServerProfile.owncloud.notes, contains('work in progress'));
    expect(
      () => CalDavConnectionSettings(
        profile: CalDavServerProfile.nextcloud,
        username: 'alice',
      ),
      throwsArgumentError,
    );
  });

  test(
    'direct task-list paths are opaque and stay within the chosen origin',
    () {
      final url = Uri.parse('https://dav.mailbox.org/caldav/Y2FsOi8vMC80Mg');
      final settings = CalDavConnectionSettings(
        profile: CalDavServerProfile.mailboxOrg,
        username: 'alice@mailbox.org',
        collectionUrl: url,
      );
      expect(settings.collectionUrl, url);
      expect(
        () => CalDavConnectionSettings(
          profile: CalDavServerProfile.mailboxOrg,
          username: 'alice@mailbox.org',
          collectionUrl: Uri.parse('https://other.example/tasks/'),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'credentials, fragments, query strings and cleartext remote URLs are refused',
    () {
      for (final url in [
        'http://dav.example/tasks/',
        'https://alice:secret@dav.example/tasks/',
        'https://dav.example/tasks/?token=secret',
        'https://dav.example/tasks/#secret',
        '/tasks/',
      ]) {
        expect(
          () => CalDavConnectionSettings(
            profile: CalDavServerProfile.generic,
            username: 'alice',
            discoveryUrl: Uri.parse(url),
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => CalDavConnectionSettings(
          profile: CalDavServerProfile.mailboxOrg,
          username: '',
        ),
        throwsArgumentError,
      );
    },
  );

  test('cleartext loopback is an explicit testing-only option', () {
    expect(
      () => CalDavConnectionSettings(
        profile: CalDavServerProfile.generic,
        username: 'alice',
        discoveryUrl: Uri.parse('http://127.0.0.1:5232/'),
      ),
      throwsArgumentError,
    );
    final local = CalDavConnectionSettings(
      profile: CalDavServerProfile.generic,
      username: 'alice',
      discoveryUrl: Uri.parse('http://127.0.0.1:5232/'),
      allowLoopbackHttp: true,
    );
    expect(local.discoveryUrl.port, 5232);
    expect(
      () => CalDavConnectionSettings(
        profile: CalDavServerProfile.generic,
        username: 'alice',
        discoveryUrl: Uri.parse('http://remote.example/'),
        allowLoopbackHttp: true,
      ),
      throwsArgumentError,
    );
  });
}
