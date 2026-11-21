import 'package:quds_mail_core/quds_mail_core.dart';

/// Named criteria over current saved headers, never message/result snapshots.
/// Implementations preserve exact account IDs and compare persisted revisions
/// before replacing or deleting a definition. Removing a definition cannot
/// remove mail, account records, retained bodies or folder memberships.
abstract interface class StudioMailSavedSearchStore {
  Future<List<MailSavedHeaderSearch>> loadSavedSearches();

  Future<MailSavedHeaderSearch> saveSavedSearch(
    MailSavedHeaderSearch search, {
    int? expectedRevision,
  });

  Future<void> deleteSavedSearch(String id, {required int expectedRevision});
}
