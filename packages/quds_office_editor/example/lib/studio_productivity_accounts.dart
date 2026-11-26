import 'dart:convert';

import 'package:flutter/foundation.dart';
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

final studioProductivityAccountChanges = ValueNotifier<int>(0);

String _serviceKey(TaskAccountId account) =>
    'crispoffice.account.services.${base64Url.encode(utf8.encode(jsonEncode([account.provider, account.value])))}';

Set<StudioProductivityService> studioAvailableServices(
  TaskAccountId id,
  Map<String, Object?> record,
) => {
  StudioProductivityService.tasks,
  if (id.provider == 'caldav' || id.provider == 'ews')
    StudioProductivityService.calendar,
  if (id.provider == 'ews' && studioExchangeMailbox(record) != null)
    StudioProductivityService.mail,
};

String? studioExchangeMailbox(Map<String, Object?> record) {
  final address = (record['mailbox'] as String? ?? record['login'] as String?)
      ?.trim();
  if (address == null || !RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(address)) {
    return null;
  }
  return address;
}

Set<StudioProductivityService> studioDefaultServices(
  TaskAccountId id,
  Map<String, Object?> record,
) {
  final available = studioAvailableServices(id, record);
  final values = record['services'] as List<Object?>?;
  return {
    for (final service in available)
      if (values?.contains(service.name) ??
          service != StudioProductivityService.mail)
        service,
  };
}

Future<Set<StudioProductivityService>> studioAccountServices(
  SecureStorage vault,
  TaskAccountId id,
  Map<String, Object?> record,
) async {
  final saved = await vault.read(_serviceKey(id));
  if (saved == null) return studioDefaultServices(id, record);
  final requested = jsonDecode(saved) as List<Object?>;
  return studioAvailableServices(
    id,
    record,
  ).where((service) => requested.contains(service.name)).toSet();
}

Future<void> saveStudioAccountServices(
  SecureStorage vault,
  TaskAccountId id,
  Set<StudioProductivityService> requested,
) async {
  final catalog = await StudioTaskAccountCatalog.load(vault);
  final record = catalog.records[id];
  if (record == null ||
      requested.isEmpty ||
      !studioAvailableServices(id, record).containsAll(requested)) {
    throw StateError('The saved connection or its available services changed.');
  }
  await vault.write(
    _serviceKey(id),
    jsonEncode(requested.map((service) => service.name).toList()),
  );
  studioProductivityAccountChanges.value++;
}

Future<void> resetStudioAccountServices(
  SecureStorage vault,
  TaskAccountId id,
) => vault.delete(_serviceKey(id));

typedef StudioProductivityAccount = ({
  String label,
  TaskAccountId? id,
  Set<StudioProductivityService> services,
  Set<StudioProductivityService> available,
});

final class StudioProductivityAccountGroup {
  StudioProductivityAccountGroup(List<StudioProductivityAccount> connections)
    : connections = List.unmodifiable(connections);

  final List<StudioProductivityAccount> connections;

  String get label => connections.first.label;

  Set<StudioProductivityService> get services => {
    for (final connection in connections) ...connection.services,
  };
}

Future<List<StudioProductivityAccountGroup>> loadStudioProductivityAccounts(
  SecureStorage vault,
) async {
  final mail = await StudioMailAccountsStore(
    storage: () async => vault,
  ).loadAccounts();
  if (!mail.isSuccess) throw StateError('Could not read saved mail accounts.');
  final tasks = await StudioTaskAccountCatalog.load(vault);
  final groups = <String, List<StudioProductivityAccount>>{};
  for (final row in mail.catalog!.accounts) {
    final email = row.credentials.email.trim();
    (groups['email:$email'] ??= []).add((
      label: email,
      id: null,
      services: const {StudioProductivityService.mail},
      available: const <StudioProductivityService>{},
    ));
  }
  for (final MapEntry(:key, :value) in tasks.records.entries) {
    final login = (value['login'] as String?)?.trim();
    final group = login != null && login.contains('@')
        ? 'email:$login'
        : 'service:${key.provider}:${key.value}';
    (groups[group] ??= []).add((
      label: studioTaskAccountLabel(key, value),
      id: key,
      services: await studioAccountServices(vault, key, value),
      available: studioAvailableServices(key, value),
    ));
  }
  return List.unmodifiable(
    groups.values.map(StudioProductivityAccountGroup.new),
  );
}
