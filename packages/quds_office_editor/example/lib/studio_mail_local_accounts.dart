import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';

import 'credentials/utils/async_lock.dart';
import 'studio_mail_draft_store.dart';

/// Indexes successful connections without retaining authentication material.
/// Custom draft stores opt in by supplying a matching directory implementation.
abstract interface class StudioMailLocalAccountStore {
  Future<List<MailLocalAccountRecord>> load();
  Future<void> remember(StudioMailDraftAccount identity);
  Future<void> forget(MailLocalAccountRecord record);
}

/// Reconstruct the historical draft namespace exactly; reject a redirected row.
StudioMailDraftAccount studioMailLocalAccountIdentity(
  MailLocalAccountRecord record,
) {
  if (!record.isValid) {
    throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
  }
  final identity = StudioMailDraftAccount(
    provider: record.provider.name,
    endpoint: record.endpoint,
    login: record.login,
    sender: record.sender,
  );
  if (identity.account.value != record.id) {
    throw const StudioMailDraftStoreException(MailProblemCode.permissionDenied);
  }
  return identity;
}

/// Short-lived exclusive SQLite transactions in a separate app-container
/// profile. Like local drafts, this non-secret directory is not encrypted.
/// The directory never contains message content, passwords or OAuth tokens.
final class NativeStudioMailLocalAccountStore
    implements StudioMailLocalAccountStore {
  NativeStudioMailLocalAccountStore({
    this.appDirectory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static final instance = NativeStudioMailLocalAccountStore();
  static final _operations = AsyncLock();
  static final profile = MailProfileId(
    'local-account-directory-v1',
    hostId: 'quds-office-studio',
  );
  final Directory? appDirectory;
  final DateTime Function() _clock;

  T _value<T>(MailResult<T> result) => switch (result) {
    MailSuccess<T>(:final value) => value,
    MailFailure<T>(:final problem) => throw StudioMailDraftStoreException(
      problem.code,
    ),
  };

  Future<T> _withStore<T>(
    Future<T> Function(SqliteMailRepository) action,
  ) => _operations.synchronized(() async {
    SqliteMailRepository? repository;
    try {
      final opened = _value<SqliteMailRepository>(
        await openNativeMailStore(
          appDirectory: appDirectory ?? await getApplicationSupportDirectory(),
          profile: profile,
        ),
      );
      repository = opened;
      return await action(opened);
    } on StudioMailDraftStoreException {
      rethrow;
    } on Object {
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    } finally {
      try {
        await repository?.close();
      } on Object {
        throw const StudioMailDraftStoreException(
          MailProblemCode.storageFailure,
        );
      }
    }
  });

  @override
  Future<List<MailLocalAccountRecord>> load() => _withStore((repository) async {
    final rows = _value(await repository.listLocalAccounts());
    for (final row in rows) {
      studioMailLocalAccountIdentity(row);
    }
    return rows;
  });

  @override
  Future<void> remember(StudioMailDraftAccount identity) {
    final record = MailLocalAccountRecord(
      id: identity.account.value,
      provider: identity.provider,
      endpoint: identity.endpoint,
      login: identity.login,
      sender: identity.sender,
      lastConnectedAt: _clock().toUtc(),
    );
    studioMailLocalAccountIdentity(record);
    return _withStore((repository) async {
      for (final existing in _value(await repository.listLocalAccounts())) {
        studioMailLocalAccountIdentity(existing);
      }
      _value(await repository.rememberLocalAccount(record));
    });
  }

  @override
  Future<void> forget(MailLocalAccountRecord record) {
    studioMailLocalAccountIdentity(record);
    return _withStore((repository) async {
      _value(await repository.forgetLocalAccount(record));
    });
  }
}
