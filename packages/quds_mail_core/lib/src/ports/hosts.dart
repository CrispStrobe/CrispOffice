import '../model/bytes.dart';
import '../model/identity.dart';
import '../model/message.dart';
import '../model/result.dart';
import '../sync/cancellation.dart';

/// Ordinary account rows contain this locator, never opaque vault bytes.
final class MailCredentialReference {
  const MailCredentialReference({required this.account, required this.key});
  final MailAccountId account;
  final String key;
}

/// Opaque vault payload: no token/password strings are model fields or log data.
final class MailCredentialRecord {
  const MailCredentialRecord({
    required this.reference,
    required this.opaqueData,
  });
  final MailCredentialReference reference;
  final MailBytes opaqueData;
}

abstract interface class MailCredentialStore {
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference reference,
  );
  Future<MailResult<MailUnit>> store(MailCredentialRecord record);
  Future<MailResult<MailUnit>> delete(MailCredentialReference reference);
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account);
}

/// The host owns the separate editable document. It exports an immutable copy;
/// attaching that copy never marks the source document clean or saved.
final class MailWorkingCopySnapshot {
  const MailWorkingCopySnapshot({
    required this.workingCopyId,
    required this.revision,
    required this.attachment,
  });
  final String workingCopyId;
  final int revision;
  final MailAttachment attachment;
}

abstract interface class MailAttachmentHost {
  Future<MailResult<MailAttachment?>> pick({
    required int maxBytes,
    MailCancellationToken? cancellation,
  });
  Future<MailResult<MailUnit>> previewReadOnly(MailAttachment attachment);
  Future<MailResult<MailWorkingCopySnapshot?>> editWorkingCopy(
    MailAttachment attachment,
  );
  Future<MailResult<MailUnit>> exportCopy(MailAttachment attachment);
  Future<MailResult<MailUnit>> shareCopy(MailAttachment attachment);
}

enum MailResourceDecision { allow, deny }

/// Implementations see only an explicit action. A message cannot grant itself
/// permission. Redirect targets require another policy evaluation by the host.
abstract interface class MailExternalResourcePolicy {
  Future<MailResourceDecision> openLink(Uri target);
  Future<MailResourceDecision> loadRemoteResource(Uri target);
}

/// Default policy has no IO and unconditionally refuses external resources.
final class MailDenyExternalResources implements MailExternalResourcePolicy {
  const MailDenyExternalResources();
  @override
  Future<MailResourceDecision> openLink(Uri target) async =>
      MailResourceDecision.deny;
  @override
  Future<MailResourceDecision> loadRemoteResource(Uri target) async =>
      MailResourceDecision.deny;
}

enum MailLifecycleOpportunity { foreground, resume, background }

final class MailLifecycleBudget {
  const MailLifecycleBudget({
    required this.opportunity,
    required this.deadline,
    required this.cancellation,
  });
  final MailLifecycleOpportunity opportunity;
  final DateTime deadline;
  final MailCancellationToken cancellation;
}

abstract interface class MailLifecycleHost {
  Stream<MailLifecycleBudget> get opportunities;
}

enum MailNotificationPermission { unsupported, notDetermined, denied, allowed }

abstract interface class MailNotificationHost {
  Future<MailNotificationPermission> permission();
  Future<MailNotificationPermission> requestPermission();

  /// The host decides disclosure. Core passes identifiers, never body/subject.
  Future<MailResult<MailUnit>> notify(
    MailAccountId account,
    MailMessageId message,
  );
}
