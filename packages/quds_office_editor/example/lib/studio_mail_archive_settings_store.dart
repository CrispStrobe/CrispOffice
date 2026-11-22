import 'package:quds_mail_core/quds_mail_core.dart';

/// Optional account-owned Archive routing preferences. The owner serializes
/// accepted operations with draft/journal writes and drains them before close.
/// All mailbox IDs use this stable local account, never a live provider account.
abstract interface class StudioMailArchiveSettingsStore {
  MailAccountId get account;
  Future<MailArchiveDestinationSettings> loadArchiveSettings();
  Future<MailArchiveDestinationSettings> saveArchiveSettings(
    MailArchiveDestinationSettings settings, {
    required int expectedRevision,
  });
}
