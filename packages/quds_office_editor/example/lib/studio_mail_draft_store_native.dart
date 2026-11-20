import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';

import 'studio_mail_draft_store.dart';

/// Opens the shared SQLite mail store in the host application-support container.
/// Each stable account uses its own profile ownership lease, permitting multiple
/// independent accounts while rejecting two concurrent owners of one draft.
/// Stored mail content is local and unencrypted; credentials are never stored.
Future<StudioMailDraftStore> openStudioMailDraftStore(
  StudioMailDraftAccount identity, {
  Directory? appDirectory,
  MailStoreLimits limits = const MailStoreLimits(),
  MailStoreFaultInjector? faultInjector,
}) async {
  SqliteMailRepository? repository;
  try {
    final directory = appDirectory ?? await getApplicationSupportDirectory();
    final opened = await openNativeMailStore(
      appDirectory: directory,
      profile: identity.profile,
      limits: limits,
      faultInjector: faultInjector,
    );
    repository = switch (opened) {
      MailSuccess<SqliteMailRepository>(:final value) => value,
      MailFailure<SqliteMailRepository>(:final problem) =>
        throw StudioMailDraftStoreException(problem.code),
    };
    final accounts = switch (await repository.listAccounts()) {
      MailSuccess<List<MailStoreAccount>>(:final value) => value,
      MailFailure<List<MailStoreAccount>>(:final problem) =>
        throw StudioMailDraftStoreException(problem.code),
    };
    if (accounts.isEmpty) {
      final created = await repository.createAccount(
        MailStoreAccount(
          id: identity.account,
          provider: identity.provider,
          displayName: 'Local mail draft',
        ),
      );
      if (created case MailFailure<MailUnit>(:final problem)) {
        throw StudioMailDraftStoreException(problem.code);
      }
    } else if (accounts.length != 1 ||
        accounts.single.id != identity.account ||
        accounts.single.provider != identity.provider) {
      throw const StudioMailDraftStoreException(MailProblemCode.conflict);
    }
    return SqliteStudioMailDraftStore(
      repository: repository,
      account: identity.account,
      ownsRepository: true,
    );
  } on Object catch (error) {
    try {
      await repository?.close();
    } on Object {
      // Cleanup never replaces the original content-redacted storage failure.
    }
    if (error is StudioMailDraftStoreException) rethrow;
    throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
  }
}
