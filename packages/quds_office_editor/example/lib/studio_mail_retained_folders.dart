import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_mailbox_store.dart';

/// One account's retained folder, keeping browse and synchronization coverage
/// separate. Neither source establishes the current state of the server.
final class StudioMailRetainedFolder {
  const StudioMailRetainedFolder._({
    required this.mailbox,
    this.browse,
    this.synchronized,
  });

  /// Synchronization catalog metadata wins when both observations are present.
  /// A later browse capture may still determine this row's activity ordering.
  final MailMailbox mailbox;
  final MailCachedMailboxSummary? browse;
  final MailMailboxSyncSummary? synchronized;

  MailMailboxId get id => mailbox.id;

  int get _activity {
    final captured = browse?.capturedAt.millisecondsSinceEpoch;
    final updated = synchronized?.updatedAt.millisecondsSinceEpoch;
    if (captured == null) return updated!;
    if (updated == null) return captured;
    return captured > updated ? captured : updated;
  }
}

const _maxRetainedFolders = 1000;
const _maxSafeInteger = 9007199254740991;
const _maxStoredTime = 8640000000000000;
const _maxCatalogMetadata = 2 * 1024 * 1024;
final _folderControls = RegExp(r'[\x00-\x1f\x7f]');

Never _fail(MailProblemCode code) =>
    throw StudioMailMailboxStoreException(code);

int _validateMailbox(MailAccountId account, MailMailbox mailbox) {
  final id = mailbox.id;
  if (id.account != account ||
      id.value.isEmpty ||
      id.value.length > 1024 ||
      _folderControls.hasMatch(id.value) ||
      mailbox.displayName.length > 4096) {
    _fail(MailProblemCode.conflict);
  }
  return id.value.length + mailbox.displayName.length;
}

void _validateObservation(
  int revision,
  DateTime time,
  int count,
  int maxCount,
) {
  final milliseconds = time.millisecondsSinceEpoch;
  if (revision < 1 ||
      revision > _maxSafeInteger ||
      milliseconds < 0 ||
      milliseconds > _maxStoredTime ||
      count < 0 ||
      count > maxCount) {
    _fail(MailProblemCode.conflict);
  }
}

/// Merges bounded local catalogs by exact account/folder identity.
///
/// Every supplied observation is validated before any result is returned.
/// Duplicate identities within one source, foreign accounts and conflicting
/// folder/label semantics fail explicitly. Renames between sources are allowed:
/// the synchronization catalog supplies the current local display metadata.
/// Results are immutable and ordered by the newest retained activity, then ID.
/// This function never acquires credentials, accesses bodies or calls providers.
List<StudioMailRetainedFolder> studioMailRetainedFolders({
  required MailAccountId account,
  required List<MailCachedMailboxSummary> browsing,
  required List<MailMailboxSyncSummary> synchronized,
}) {
  if (browsing.length > _maxRetainedFolders ||
      synchronized.length > _maxRetainedFolders) {
    _fail(MailProblemCode.quotaExceeded);
  }
  final browseSnapshot = List<MailCachedMailboxSummary>.of(browsing);
  final syncSnapshot = List<MailMailboxSyncSummary>.of(synchronized);
  final merged = <MailMailboxId, StudioMailRetainedFolder>{};
  var metadata = 0;

  for (final view in browseSnapshot) {
    metadata += _validateMailbox(account, view.mailbox);
    if (metadata > _maxCatalogMetadata) _fail(MailProblemCode.quotaExceeded);
    _validateObservation(
      view.revision,
      view.capturedAt,
      view.headerCount,
      1000,
    );
    if (merged.containsKey(view.mailbox.id)) _fail(MailProblemCode.conflict);
    merged[view.mailbox.id] = StudioMailRetainedFolder._(
      mailbox: view.mailbox,
      browse: view,
    );
  }

  final synchronizedIds = <MailMailboxId>{};
  for (final checkpoint in syncSnapshot) {
    metadata += _validateMailbox(account, checkpoint.mailbox);
    if (metadata > _maxCatalogMetadata) _fail(MailProblemCode.quotaExceeded);
    _validateObservation(
      checkpoint.revision,
      checkpoint.updatedAt,
      checkpoint.headerCount,
      _maxSafeInteger,
    );
    final id = checkpoint.mailbox.id;
    if (!synchronizedIds.add(id)) _fail(MailProblemCode.conflict);
    final previous = merged[id];
    if (previous != null &&
        previous.mailbox.isLabel != checkpoint.mailbox.isLabel) {
      _fail(MailProblemCode.conflict);
    }
    if (previous == null && merged.length == _maxRetainedFolders) {
      _fail(MailProblemCode.quotaExceeded);
    }
    merged[id] = StudioMailRetainedFolder._(
      mailbox: checkpoint.mailbox,
      browse: previous?.browse,
      synchronized: checkpoint,
    );
  }

  final result = merged.values.toList()
    ..sort((a, b) {
      final activity = b._activity.compareTo(a._activity);
      return activity == 0 ? a.id.value.compareTo(b.id.value) : activity;
    });
  return List<StudioMailRetainedFolder>.unmodifiable(result);
}
