import 'package:flutter/material.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';

import 'studio_mail_account_navigation.dart';
import 'studio_mail_archive_action.dart';
import 'studio_mail_archive_folder_action.dart';
import 'studio_mail_ews.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_local_accounts.dart';
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
    this.archiveWriter,
    this.archiveFolderWriter,
    this.draftStoreFactory,
    this.localAccountStore,
    this.initialAccount,
    this.onAccountNavigation,
  });

  final StudioStrings strings;
  final MailCloudService service;
  final StudioCloudAuthorizer? authorizer;
  final StudioCloudProviderFactory? providerFactory;
  final Future<bool> Function(Uri)? openBrowser;
  final String? initialClientId;
  final StudioMailArchiveWriter? archiveWriter;
  final StudioMailArchiveFolderWriter? archiveFolderWriter;
  final StudioMailDraftStoreFactory? draftStoreFactory;
  final StudioMailLocalAccountStore? localAccountStore;
  final StudioMailAccountNavigationTarget? initialAccount;
  final ValueChanged<StudioMailAccountNavigationTarget>? onAccountNavigation;

  @override
  Widget build(BuildContext context) => StudioMailEwsDialog.cloud(
    strings: strings,
    service: service,
    cloudAuthorizer: authorizer,
    cloudProviderFactory: providerFactory,
    openBrowser: openBrowser,
    initialClientId: initialClientId,
    archiveWriter: archiveWriter,
    archiveFolderWriter: archiveFolderWriter,
    draftStoreFactory: draftStoreFactory,
    localAccountStore: localAccountStore,
    initialAccount: initialAccount,
    onAccountNavigation: onAccountNavigation,
  );
}
