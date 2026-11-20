import 'dart:async';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';

/// An injected host boundary. Production never falls back to memory storage.
final class MemoryStudioMailDrafts {
  final records = <String, StudioMailStoredDraft>{};
  final identities = <StudioMailDraftAccount>[];
  final saved = <StudioMailStoredDraft>[];
  bool failOpen = false;
  bool failSave = false;
  bool failClear = false;
  Completer<void>? openGate;
  Completer<void>? saveGate;
  int closes = 0;
  int clears = 0;

  Future<StudioMailDraftStore> open(StudioMailDraftAccount account) async {
    identities.add(account);
    await openGate?.future;
    if (failOpen) _fail();
    return _MemoryDraftStore(this, account.account.value);
  }

  Never _fail() =>
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
}

final class _MemoryDraftStore implements StudioMailDraftStore {
  _MemoryDraftStore(this.owner, this.key);
  final MemoryStudioMailDrafts owner;
  final String key;
  bool closed = false;

  void _check() {
    if (closed) owner._fail();
  }

  @override
  Future<StudioMailStoredDraft?> load() async {
    _check();
    return owner.records[key];
  }

  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) async {
    _check();
    await owner.saveGate?.future;
    if (owner.failSave) owner._fail();
    final snapshot = StudioMailStoredDraft(
      draft: draft,
      submissionUncertain:
          submissionUncertain ||
          (owner.records[key]?.submissionUncertain ?? false),
    );
    owner.records[key] = snapshot;
    owner.saved.add(snapshot);
  }

  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) async {
    _check();
    if (owner.failSave) owner._fail();
    final snapshot = StudioMailStoredDraft(
      draft: draft,
      submissionUncertain: wasPreviouslyUncertain,
    );
    owner.records[key] = snapshot;
    owner.saved.add(snapshot);
  }

  @override
  Future<void> clear() async {
    _check();
    if (owner.failClear) owner._fail();
    owner.clears++;
    owner.records.remove(key);
  }

  @override
  Future<void> close() async {
    closed = true;
    owner.closes++;
  }
}
