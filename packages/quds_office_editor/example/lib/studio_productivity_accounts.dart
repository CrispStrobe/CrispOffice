import 'dart:convert';

import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

import 'credentials/secure_storage_service.dart';
import 'studio_mail_credentials.dart';

const studioTasksLegacyKey = 'crispoffice.tasks.account.v1';
const studioTasksAccountsKey = 'crispoffice.tasks.accounts.v2';

final class StudioTaskAccountCatalog {
  StudioTaskAccountCatalog(
    this.records,
    this.active, {
    this.fromLegacy = false,
  });

  final Map<TaskAccountId, Map<String, Object?>> records;
  final TaskAccountId? active;
  final bool fromLegacy;

  static Future<StudioTaskAccountCatalog> load(SecureStorage vault) async {
    final raw = await vault.read(studioTasksAccountsKey);
    if (raw == null) {
      final legacy = await vault.read(studioTasksLegacyKey);
      if (legacy == null) return StudioTaskAccountCatalog({}, null);
      final row = jsonDecode(legacy) as Map<String, Object?>;
      final id = studioTaskAccountId(row);
      return StudioTaskAccountCatalog({id: row}, id, fromLegacy: true);
    }
    final decoded = jsonDecode(raw) as Map<String, Object?>;
    final records = <TaskAccountId, Map<String, Object?>>{};
    TaskAccountId? active;
    for (final value in decoded['accounts'] as List<Object?>) {
      final row = value as Map<String, Object?>;
      final id = studioTaskAccountId(row);
      if (records.containsKey(id)) {
        throw const FormatException('Duplicate saved account.');
      }
      records[id] = row;
      if (decoded['active'] case [
        final provider,
        final account,
      ] when provider == id.provider && account == id.value) {
        active = id;
      }
    }
    return StudioTaskAccountCatalog(
      records,
      active ?? records.keys.firstOrNull,
    );
  }
}

TaskAccountId studioTaskAccountId(Map<String, Object?> record) => TaskAccountId(
  record['id'] as String,
  provider: record['provider'] as String,
);

String studioTaskAccountLabel(TaskAccountId id, Map<String, Object?> record) =>
    record['label'] as String? ??
    record['login'] as String? ??
    (id.provider == 'google' ? 'Google Tasks' : 'Microsoft To Do');

const studioDavProfiles = [
  CalDavServerProfile.generic,
  CalDavServerProfile.mailboxOrg,
  CalDavServerProfile.openXchange,
  CalDavServerProfile.nextcloud,
  CalDavServerProfile.owncloud,
];

CalDavConnectionSettings studioDavSettings(
  Map<String, Object?> record, {
  bool useTaskCollection = true,
}) {
  final url = Uri.parse(record['url'] as String);
  final exact = useTaskCollection ? record['collection'] as String? : null;
  final profile = studioDavProfiles
      .where((profile) => profile.id == record['davProfile'])
      .firstOrNull;
  return CalDavConnectionSettings(
    profile:
        profile ??
        (url.origin == 'https://dav.mailbox.org'
            ? CalDavServerProfile.mailboxOrg
            : CalDavServerProfile.generic),
    username: record['login'] as String,
    discoveryUrl: url,
    collectionUrl: exact == null ? null : Uri.parse(exact),
  );
}

enum StudioProductivityService { mail, tasks, calendar }

typedef StudioProductivityAccount = ({
  String label,
  Set<StudioProductivityService> services,
});

/// Catalog view only. Mail and DAV grants remain protocol specific. An exact
/// email login can group entries for display, without selecting either account.
Future<List<StudioProductivityAccount>> loadStudioProductivityAccounts(
  SecureStorage vault,
) async {
  final mail = await StudioMailAccountsStore(
    storage: () async => vault,
  ).loadAccounts();
  if (!mail.isSuccess) throw StateError('Could not read saved mail accounts.');
  final tasks = await StudioTaskAccountCatalog.load(vault);
  final entries = <String, StudioProductivityAccount>{};
  void add(String key, String label, Set<StudioProductivityService> services) {
    final previous = entries[key];
    entries[key] = (
      label: previous?.label ?? label,
      services: Set.unmodifiable({...?previous?.services, ...services}),
    );
  }

  for (final row in mail.catalog!.accounts) {
    final email = row.credentials.email.trim();
    add('email:$email', email, {StudioProductivityService.mail});
  }
  for (final MapEntry(:key, :value) in tasks.records.entries) {
    final login = value['login'] as String?;
    final email = login?.trim();
    add(
      email != null && email.contains('@')
          ? 'email:$email'
          : 'task:${key.provider}:${key.value}',
      studioTaskAccountLabel(key, value),
      {
        StudioProductivityService.tasks,
        if (key.provider == 'caldav') StudioProductivityService.calendar,
      },
    );
  }
  return List.unmodifiable(entries.values);
}
