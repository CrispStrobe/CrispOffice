import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_archive_settings_store.dart';

enum StudioMailArchiveDestinationFailure {
  unavailable,
  missing,
  changed,
  stale,
}

/// Fixed diagnostics never expose account routes or server replies.
final class StudioMailArchiveDestinationException implements Exception {
  const StudioMailArchiveDestinationException(this.failure);

  final StudioMailArchiveDestinationFailure failure;

  @override
  String toString() => 'Archive destination is unavailable.';
}

/// Read a preference only from its current, stable account owner.
Future<MailArchiveDestinationSettings> readStudioMailArchiveSettings(
  StudioMailArchiveSettingsStore store, {
  required bool Function() isCurrent,
}) async {
  final account = store.account;
  if (!isCurrent()) {
    throw const StudioMailArchiveDestinationException(
      StudioMailArchiveDestinationFailure.stale,
    );
  }
  final settings = await store.loadArchiveSettings();
  if (!isCurrent() || store.account != account) {
    throw const StudioMailArchiveDestinationException(
      StudioMailArchiveDestinationFailure.stale,
    );
  }
  if (!settings.isValid || settings.account != account) {
    throw const StudioMailArchiveDestinationException(
      StudioMailArchiveDestinationFailure.unavailable,
    );
  }
  return settings;
}

/// A fresh provider catalog supplies identities, never display-name guesses.
/// Labels cannot serve as ordinary folder destinations. Refuse malformed or
/// ambiguous catalogs before presenting a choice or trusting a saved route.
List<MailMailbox> studioMailArchiveDestinations(
  List<MailMailbox> folders,
  MailAccountId account,
) {
  const maxFolders = 10000;
  if (folders.length > maxFolders) {
    throw const StudioMailArchiveDestinationException(
      StudioMailArchiveDestinationFailure.unavailable,
    );
  }
  final ids = <MailMailboxId>{};
  final result = <MailMailbox>[];
  for (final folder in folders) {
    if (folder.id.account != account ||
        !MailArchiveDestinationSettings(
          account: account,
          destination: folder.id,
        ).isValid ||
        !ids.add(folder.id)) {
      throw const StudioMailArchiveDestinationException(
        StudioMailArchiveDestinationFailure.unavailable,
      );
    }
    if (!folder.isLabel) result.add(folder);
  }
  return List<MailMailbox>.unmodifiable(result);
}

/// A custom route takes precedence over provider defaults, including when it
/// becomes unavailable. Missing routes require an explicit change or clear;
/// they never silently fall back to another folder with the same name.
Future<MailMailbox?> resolveStudioMailSavedArchiveDestination({
  required MailArchiveDestinationSettings settings,
  required MailAccountId providerAccount,
  required Future<List<MailMailbox>> Function() loadFolders,
  required bool Function() isCurrent,
}) async {
  if (!settings.isValid) {
    throw const StudioMailArchiveDestinationException(
      StudioMailArchiveDestinationFailure.unavailable,
    );
  }
  if (!isCurrent()) {
    throw const StudioMailArchiveDestinationException(
      StudioMailArchiveDestinationFailure.stale,
    );
  }
  final saved = settings.destination;
  if (saved == null) return null;
  final observed = await loadFolders();
  if (!isCurrent()) {
    throw const StudioMailArchiveDestinationException(
      StudioMailArchiveDestinationFailure.stale,
    );
  }
  final folders = studioMailArchiveDestinations(observed, providerAccount);
  for (final folder in folders) {
    if (folder.id.value == saved.value) return folder;
  }
  throw const StudioMailArchiveDestinationException(
    StudioMailArchiveDestinationFailure.missing,
  );
}

/// Recheck the same preference after confirmation, before any durable intent.
/// A concurrent change or clear cannot authorize the previously reviewed route.
Future<void> verifyStudioMailArchiveSettings(
  StudioMailArchiveSettingsStore store,
  MailArchiveDestinationSettings expected, {
  required bool Function() isCurrent,
}) async {
  final actual = await readStudioMailArchiveSettings(
    store,
    isCurrent: isCurrent,
  );
  if (actual.account != expected.account ||
      actual.revision != expected.revision ||
      actual.destination != expected.destination) {
    throw const StudioMailArchiveDestinationException(
      StudioMailArchiveDestinationFailure.changed,
    );
  }
}
