import 'dart:async';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';

/// Test boundary only. Production never replaces failed durable storage with it.
final class MemoryMailLocalAccounts implements StudioMailLocalAccountStore {
  final records = <String, MailLocalAccountRecord>{};
  final remembered = <StudioMailDraftAccount>[];
  Completer<void>? loadGate;
  bool failLoad = false;
  bool failRemember = false;
  bool failForget = false;
  int loads = 0;
  void Function(int)? onLoad;

  void seed(StudioMailDraftAccount identity) {
    records[identity.account.value] = MailLocalAccountRecord(
      id: identity.account.value,
      provider: identity.provider,
      endpoint: identity.endpoint,
      login: identity.login,
      sender: identity.sender,
      lastConnectedAt: DateTime.utc(2026, 11, 20),
    );
  }

  @override
  Future<List<MailLocalAccountRecord>> load() async {
    loads++;
    onLoad?.call(loads);
    await loadGate?.future;
    if (failLoad) _fail();
    return List.unmodifiable(records.values);
  }

  @override
  Future<void> remember(StudioMailDraftAccount identity) async {
    if (failRemember) _fail();
    remembered.add(identity);
    seed(identity);
  }

  @override
  Future<void> forget(MailLocalAccountRecord record) async {
    if (failForget) _fail();
    records.remove(record.id);
  }

  Never _fail() =>
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
}
