import 'package:flutter/material.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';

import 'studio_mail_ews.dart';
import 'studio_strings.dart';

/// Browser authorization and the shared guarded foreground mailbox view.
/// Tokens and downloaded content belong only to this dialog's session.
class StudioMailCloudDialog extends StatelessWidget {
  const StudioMailCloudDialog({
    super.key,
    required this.strings,
    required this.service,
    this.authorizer,
    this.providerFactory,
    this.openBrowser,
    this.initialClientId,
  });

  final StudioStrings strings;
  final MailCloudService service;
  final StudioCloudAuthorizer? authorizer;
  final StudioCloudProviderFactory? providerFactory;
  final Future<bool> Function(Uri)? openBrowser;
  final String? initialClientId;

  @override
  Widget build(BuildContext context) => StudioMailEwsDialog.cloud(
    strings: strings,
    service: service,
    cloudAuthorizer: authorizer,
    cloudProviderFactory: providerFactory,
    openBrowser: openBrowser,
    initialClientId: initialClientId,
  );
}
