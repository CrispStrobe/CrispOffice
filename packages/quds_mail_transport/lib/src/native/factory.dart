import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';

import '../configuration.dart';
import 'provider.dart';

/// Creates a foreground provider. Every call loads current vault credentials.
MailProvider createMailImapProvider({
  required MailImapConfiguration configuration,
  required MailCredentialStore credentialStore,
  MailCodec? codec,
  MailTransportLimits limits = const MailTransportLimits(),
}) => NativeMailImapProvider(
  configuration: configuration,
  credentialStore: credentialStore,
  codec: codec ?? const QudsMimeCodec(),
  limits: limits,
);
