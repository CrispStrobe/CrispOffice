import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

import '../configuration.dart';
import '../tasks.dart';
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

/// Creates a task connection. The caller must opt in to deletion because
/// Exchange servers can accept DeleteItem without enforcing its ChangeKey.
EwsTaskProvider createEwsTaskReader({
  required TaskAccountId account,
  required MailEwsConfiguration configuration,
  required MailCredentialStore credentialStore,
  MailEwsLimits limits = const MailEwsLimits(),
  bool enableWrites = false,
  bool enableDeletes = false,
}) => NativeEwsTaskReader(
  account: account,
  enableWrites: enableWrites,
  enableDeletes: enableDeletes,
  connection: NativeMailEwsProvider(
    configuration: configuration,
    credentialStore: credentialStore,
    codec: const QudsMimeCodec(),
    limits: limits,
  ),
);
