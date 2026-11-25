/// A provider claim is separate from functionality implemented by this codec.
enum CalDavCapability { documented, discover, disabled }

enum CalDavFeature {
  recurrence,
  participants,
  sharedTaskLists,
  subtasks,
  attachments,
  collectionCreation,
  syncTokens,
}

enum CalDavLoginMethod { appPassword, nextcloudLoginFlowV2 }

/// Connection hints and conservative feature defaults, not a certification.
///
/// Always query supported-calendar-component-set and the actual collection's
/// privileges. These presets never grant access or prove a deployment's version.
final class CalDavServerProfile {
  const CalDavServerProfile._({
    required this.id,
    required this.label,
    required this.loginMethods,
    required this.capabilities,
    required this.sourceUrls,
    this.defaultDiscoveryUrl,
    this.notes = '',
  });

  final String id;
  final String label;
  final String? defaultDiscoveryUrl;
  final Set<CalDavLoginMethod> loginMethods;
  final Map<CalDavFeature, CalDavCapability> capabilities;
  final List<String> sourceUrls;
  final String notes;

  CalDavCapability supportFor(CalDavFeature feature) =>
      capabilities[feature] ?? CalDavCapability.discover;

  static const generic = CalDavServerProfile._(
    id: 'caldav',
    label: 'CalDAV',
    loginMethods: {CalDavLoginMethod.appPassword},
    capabilities: {},
    sourceUrls: [
      'https://www.rfc-editor.org/rfc/rfc4791',
      'https://www.rfc-editor.org/rfc/rfc5545',
      'https://www.rfc-editor.org/rfc/rfc6578',
    ],
    notes: 'Discover VTODO collections and privileges on the chosen server.',
  );

  static const nextcloud = CalDavServerProfile._(
    id: 'nextcloud',
    label: 'Nextcloud Tasks',
    loginMethods: {
      CalDavLoginMethod.appPassword,
      CalDavLoginMethod.nextcloudLoginFlowV2,
    },
    capabilities: {
      CalDavFeature.subtasks: CalDavCapability.documented,
      CalDavFeature.syncTokens: CalDavCapability.documented,
    },
    sourceUrls: [
      'https://github.com/nextcloud/tasks',
      'https://docs.nextcloud.com/server/stable/developer_manual/client_apis/LoginFlow/index.html',
      'https://docs.nextcloud.com/server/stable/admin_manual/groupware/calendar.html',
    ],
    notes:
        'Accept the installation URL or an explicit DAV URL. The usual DAV '
        'root is remote.php/dav/ under that installation. Tasks use VTODO.',
  );

  static const owncloud = CalDavServerProfile._(
    id: 'owncloud',
    label: 'ownCloud CalDAV',
    loginMethods: {CalDavLoginMethod.appPassword},
    capabilities: {},
    sourceUrls: [
      'https://marketplace.owncloud.com/apps/tasks/',
      'https://github.com/owncloud/ocis-groupware',
      'https://owncloud.com/blogs/oc-classic-10-reaches-end-of-support-on-31-december-2026-your-two-paths-forward/',
    ],
    notes:
        'Check the actual edition and version. Classic and Infinite Scale '
        'are different deployments. As of 2026-11-25, ownCloud describes '
        'ocis-groupware as work in progress. No production certification.',
  );

  static const openXchange = CalDavServerProfile._(
    id: 'open-xchange',
    label: 'Open-Xchange CalDAV',
    loginMethods: {CalDavLoginMethod.appPassword},
    capabilities: _oxCapabilities,
    sourceUrls: [_oxDocumentation],
    notes: _oxNotes,
  );

  static const mailboxOrg = CalDavServerProfile._(
    id: 'mailbox.org',
    label: 'mailbox.org / Open-Xchange',
    defaultDiscoveryUrl: 'https://dav.mailbox.org/',
    loginMethods: {CalDavLoginMethod.appPassword},
    capabilities: _oxCapabilities,
    sourceUrls: [
      'https://kb.mailbox.org/en/private/addressbook-and-calendar/caldav-korganizer/',
      'https://kb.mailbox.org/en/private/addressbook-and-calendar/caldav-in-thunderbird/',
      'https://kb.mailbox.org/en/private/security-and-privacy/application-passwords-for-external-programs/',
      _oxDocumentation,
    ],
    notes:
        'Use the main mailbox email and a CalDAV/CardDAV app credential. '
        'A direct task-list URL can be copied from Properties. '
        '$_oxNotes',
  );

  static const _oxDocumentation =
      'https://documentation.open-xchange.com/8/middleware/miscellaneous/caldav_carddav/caldav_clients.html';
  static const _oxNotes =
      'Conservative defaults follow OX CalDAV task documentation, which is '
      'marked deprecated: simple personal tasks only. Validate the actual '
      'server before enabling recurrence, delegation, or shared task lists. '
      'Native OX HTTP API availability is not implied by DAV access.';
  static const _oxCapabilities = {
    CalDavFeature.recurrence: CalDavCapability.disabled,
    CalDavFeature.participants: CalDavCapability.disabled,
    CalDavFeature.sharedTaskLists: CalDavCapability.disabled,
    CalDavFeature.subtasks: CalDavCapability.disabled,
    CalDavFeature.attachments: CalDavCapability.disabled,
  };
}

/// Non-secret configuration. Credentials belong in the host's credential store.
final class CalDavConnectionSettings {
  CalDavConnectionSettings({
    required this.profile,
    required this.username,
    Uri? discoveryUrl,
    this.collectionUrl,
    bool allowLoopbackHttp = false,
  }) : discoveryUrl =
           discoveryUrl ??
           (profile.defaultDiscoveryUrl == null
               ? throw ArgumentError('A discovery URL is required.')
               : Uri.parse(profile.defaultDiscoveryUrl!)) {
    if (username.trim().isEmpty || username.contains(RegExp(r'[\r\n\x00]'))) {
      throw ArgumentError('A non-empty DAV username is required.');
    }
    _validateUrl(this.discoveryUrl, allowLoopbackHttp);
    if (collectionUrl != null) {
      _validateUrl(collectionUrl!, allowLoopbackHttp);
      if (collectionUrl!.origin != this.discoveryUrl.origin) {
        throw ArgumentError('The collection must use the discovery origin.');
      }
    }
  }

  final CalDavServerProfile profile;
  final String username;
  final Uri discoveryUrl;
  final Uri? collectionUrl;

  static void _validateUrl(Uri uri, bool allowLoopbackHttp) {
    final loopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(uri.host);
    final transportAllowed =
        uri.scheme == 'https' ||
        (allowLoopbackHttp && loopback && uri.scheme == 'http');
    if (!transportAllowed ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError(
        'DAV URLs need HTTPS, a host, and no credentials, query, or fragment.',
      );
    }
  }
}
