import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';

import '../configuration.dart';
import 'provider.dart';

/// Connects directly to Exchange Server EWS using host-owned credentials.
/// Nothing is sent until a provider operation is requested with a current lease.
MailEwsProvider createMailEwsProvider({
  required MailEwsConfiguration configuration,
  required MailCredentialStore credentialStore,
  MailCodec codec = const QudsMimeCodec(),
  MailEwsLimits limits = const MailEwsLimits(),
}) => NativeMailEwsProvider(
  configuration: configuration,
  credentialStore: credentialStore,
  codec: codec,
  limits: limits,
);
