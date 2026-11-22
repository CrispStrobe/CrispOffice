import '../model/archive_settings.dart';
import '../model/identity.dart';
import '../model/result.dart';

/// Optional durable account-owned Archive preferences. These methods perform
/// no provider work, create no folders, and authorize no message mutation.
abstract interface class MailArchiveSettingsRepository {
  /// Missing settings return revision-zero defaults only for an existing owner.
  Future<MailResult<MailArchiveDestinationSettings>> loadArchiveSettings(
    MailAccountId account,
  );

  /// Save only if both revisions match the current account snapshot. A null
  /// destination is a saved reset, not deletion of the revision history.
  Future<MailResult<MailArchiveDestinationSettings>> saveArchiveSettings(
    MailArchiveDestinationSettings settings, {
    required int expectedRevision,
  });
}
