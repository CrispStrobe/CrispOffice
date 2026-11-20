import 'package:quds_mail_core/quds_mail_core.dart';

Future<MailResult<bool>> exportStudioMailOutboxFile(
  String suggestedName,
  MailBytes bytes, {
  required MailCancellationToken cancellation,
  required bool Function() isCurrent,
}) async => const MailFailure(MailProblem(MailProblemCode.unsupported));
