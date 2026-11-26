import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';

final class StudioEwsCredentials implements MailCredentialStore {
  const StudioEwsCredentials(this.reference, this.readPassword);

  final MailCredentialReference reference;
  final FutureOr<String?> Function() readPassword;

  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference request,
  ) async {
    final secret =
        request.account == reference.account && request.key == reference.key
        ? await readPassword()
        : null;
    return MailSuccess(
      secret == null
          ? null
          : MailCredentialRecord(
              reference: reference,
              opaqueData: MailBytes(Uint8List.fromList(utf8.encode(secret))),
            ),
    );
  }

  @override
  Future<MailResult<MailUnit>> store(MailCredentialRecord record) async =>
      const MailFailure(MailProblem(MailProblemCode.unsupported));

  @override
  Future<MailResult<MailUnit>> delete(
    MailCredentialReference reference,
  ) async => const MailFailure(MailProblem(MailProblemCode.unsupported));

  @override
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account) async =>
      const MailFailure(MailProblem(MailProblemCode.unsupported));
}
