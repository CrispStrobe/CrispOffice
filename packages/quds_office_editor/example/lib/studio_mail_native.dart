import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_chrome.dart';
import 'studio_credential_biometric_strings.dart';
import 'studio_credential_settings.dart';
import 'studio_credential_storage.dart';
import 'studio_credential_vault_unlock.dart';
import 'studio_mail_archive_action.dart';
import 'studio_mail_account_navigation.dart';
import 'studio_mail_account_navigation_strings.dart';
import 'studio_mail_bulk_status.dart';
import 'studio_mail_body_download.dart';
import 'studio_mail_flag_journal.dart';
import 'studio_mail_journal_dialog.dart';
import 'studio_mail_journal_strings.dart';
import 'studio_mail_archive_folder_action.dart';
import 'studio_mail_cloud.dart';
import 'studio_mail_cached_strings.dart';
import 'studio_mail_compose.dart';
import 'studio_mail_compose_tools.dart';
import 'studio_mail_credentials.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_draft_store_native.dart';
import 'studio_mail_drafts_dialog.dart';
import 'studio_mail_drafts_strings.dart';
import 'studio_mail_local_accounts.dart';
import 'studio_mail_local_accounts_dialog.dart';
import 'studio_mail_local_accounts_strings.dart';
import 'studio_mail_ews.dart';
import 'studio_mail_local_drafts.dart';
import 'studio_mail_message_loader.dart';
import 'studio_mail_mutation_strings.dart';
import 'studio_mail_mailbox_store.dart';
import 'studio_mail_mailbox_session.dart';
import 'studio_mail_operation.dart';
import 'studio_mail_organization_dialog.dart';
import 'studio_mail_outbox.dart';
import 'studio_mail_outbox_dialog.dart';
import 'studio_mail_outbox_strings.dart';
import 'studio_mail_presets.dart';
import 'studio_mail_remote_images.dart';
import 'studio_mail_reply.dart';
import 'studio_mail_strings.dart';
import 'studio_mail_workspace_strings.dart';
import 'studio_mail_submission.dart';
import 'studio_mail_sync_dialog.dart';
import 'studio_mail_sync_strings.dart';
import 'studio_saved_mail.dart';
import 'studio_strings.dart';
import 'studio_mail_reader_labels.dart';

/// Never salvage a partial or oversized References header from an IMAP page.
/// The shared conversation index validates every token before creating a link.
List<String> _studioMailLoadedReferences(String? raw) {
  if (raw == null || raw.length > 8192) return const <String>[];
  final value = raw.trim();
  if (value.isEmpty) return const <String>[];
  final tokens = value.split(RegExp(r'\s+'));
  return tokens.length <= MailConversationEntry.maxReferences
      ? tokens
      : const <String>[];
}

StudioMailDraftAccount _imapLocalIdentity(mail.MailAccount account) {
  final incoming = account.incoming.serverConfig;
  final authentication = account.incoming.authentication;
  return StudioMailDraftAccount(
    provider: 'imap',
    endpoint: Uri(
      scheme: incoming.socketType == mail.SocketType.ssl ? 'imaps' : 'imap',
      host: incoming.hostname,
      port: incoming.port,
    ).toString(),
    login: authentication is mail.UserNameBasedAuthentication
        ? authentication.userName
        : account.email,
    sender: account.email,
  );
}

/// A selected sign-in route expired while an asynchronous connection step ran.
/// Keep this separate from an ordinary draft-storage failure: the host must
/// retire the pending connection instead of publishing a partially opened view.
final class _StudioMailNavigationExpired implements Exception {
  const _StudioMailNavigationExpired();
}

/// IMAP/SMTP client with optional host-managed account persistence.
///
/// Account setup is explicit. Remembered credentials use the selected backend;
/// session-only storage keeps them in memory for the current process.
/// Discovery and provider presets require verified encrypted transports. Every
/// network operation reports its own failure instead of presenting an empty
/// inbox.
class StudioMailDialog extends StatefulWidget {
  const StudioMailDialog({
    super.key,
    required this.strings,
    this.chromeBuilder,
    this.onClose,
    this.clientFactory,
    this.messageLoaderFactory,
    this.autoConnectSavedAccount,
    this.accountDiscovery,
    this.credentialStore,
    this.credentialSettingsOpener,
    this.archiveWriter,
    this.archiveFolderWriter,
    this.draftStoreFactory,
    this.localAccountStore,
    this.remoteImageLoaderFactory,
    this.initialAccount,
    this.accountDestinationBuilder,
  });

  final StudioStrings strings;
  final WidgetBuilder? chromeBuilder;

  /// Closes an embedded Mail pane. A pushed route falls back to Navigator.pop.
  final VoidCallback? onClose;

  /// Tests supply the keychain boundary without reading a platform credential.
  final StudioMailCredentialStore? credentialStore;

  /// Hosts can provide credential settings without accessing a platform store.
  /// Returns true only when the selected backend changed.
  final Future<bool> Function(BuildContext context)? credentialSettingsOpener;
  final StudioMailArchiveWriter? archiveWriter;
  final StudioMailArchiveFolderWriter? archiveFolderWriter;
  final StudioMailDraftStoreFactory? draftStoreFactory;
  final StudioMailLocalAccountStore? localAccountStore;

  /// A verified non-secret destination; choosing it never starts a connection.
  final StudioMailAccountNavigationTarget? initialAccount;

  /// Embedders may supply provider setup while retaining the guarded router.
  /// The callback is invoked only after the preceding session has drained.
  final Widget Function(
    BuildContext context,
    MailProviderKind provider,
    StudioMailAccountNavigationTarget? target,
    ValueChanged<StudioMailAccountNavigationTarget> onNavigate,
  )?
  accountDestinationBuilder;
  final StudioMailRemoteImageLoader Function()? remoteImageLoaderFactory;

  /// Creates a fresh client for each connection attempt. Tests use this seam
  /// to control network completions without contacting an external account.
  final mail.MailClient Function(mail.MailAccount account)? clientFactory;

  /// Connect after adopting remembered credentials. Built-in clients enable
  /// this by default; hosts supplying their own factories can opt in explicitly.
  final bool? autoConnectSavedAccount;

  /// Resolves endpoint settings only; credentials are supplied after the
  /// discovery origin and IMAP/SMTP server types have been checked.
  final Future<mail.ClientConfig?> Function(String email)? accountDiscovery;

  /// Owns exact, bounded UID reads for this foreground account session.
  final StudioMailMessageLoader Function(mail.MailAccount account)?
  messageLoaderFactory;

  @override
  State<StudioMailDialog> createState() => _StudioMailDialogState();
}

class _StudioMailDialogState extends State<StudioMailDialog>
    with WidgetsBindingObserver {
  StudioMailLocalAccountStore? get _localAccounts =>
      widget.localAccountStore ??
      (widget.draftStoreFactory == null
          ? NativeStudioMailLocalAccountStore.instance
          : null);

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _imapHost = TextEditingController();
  final _smtpHost = TextEditingController();
  static const _pageSize = 50;
  static const _maxHeaders = 1000;
  final _messageListKey = GlobalKey(debugLabel: 'mail-imap-list');
  final _usedHeaderCursors = <String>{};
  final _confirmedFlags =
      Map<mail.MimeMessage, ({bool? read, bool? flagged})>.identity();
  final _repositoryFlags = Map<mail.MimeMessage, MailMessageFlags?>.identity();
  MailCursor? _nextHeaders;
  bool _needsRefresh = false;
  int _mailboxGeneration = 0;
  Future<void>? _pendingFlagWrite;
  MailCancellationSource? _bulkCancellation;
  MailBulkFlagReport? _bulkReport;
  Map<MailRemoteIdentity, String> _bulkSubjects = const {};
  final _primaryLogin = TextEditingController();
  StudioMailImapPreset? _preset;
  bool _icloudFullAddressLogin = false;
  late final StudioMailCredentialStore _credentials;
  late final StudioMailAccountCatalogStore? _accountCatalogStore;
  StudioMailAccountCatalog? _accountCatalog;
  String? _selectedSavedAccountId;
  bool _remember = true;
  StudioMailCredentials? _lastCredentialSnapshot;
  bool _credentialSettingsOpen = false;
  bool _vaultUnlockPromptOpen = false;
  bool _credentialStoreChangePending = false;
  int _credentialStoreRevision = 0;
  bool _startTls = false;
  bool _hasSavedCredentials = false;
  bool _credentialPending = false;
  bool _accountNavigationPending = false;
  bool _navigationOwnerPending = false;
  bool _explicitAccountNavigation = false;
  StudioMailAccountNavigationTarget? _navigationTarget;
  Future<void> _transportClosing = Future<void>.value();
  StudioMailDraftStore? _retiredNavigationStore;
  StudioMailMailboxSession? _retiredNavigationView;
  StreamSubscription<StudioMailMailboxSnapshot>? _retiredNavigationSubscription;
  Future<void>? _retiredNavigationClosing;
  Object? _autoConnectTicket;
  bool _remoteImagesLoading = false;
  StudioMailRemoteImageLoader? _remoteImageLoader;
  MailReaderController? _remoteImageOwner;
  int _settingsRevision = 0;
  int _credentialGeneration = 0;

  mail.MailClient? _client;
  mail.MailClient? _pendingClient;
  StudioMailMessageLoader? _messageLoader;
  MailCapabilities _membershipCapabilities = const MailCapabilities.none();
  StudioMailMessageLoader? _pendingLoader;
  mail.Mailbox? _messageMailbox;
  int _sessionGeneration = 0;
  mail.MailAccount? _account;
  List<mail.Mailbox> _mailboxes = const <mail.Mailbox>[];
  mail.Mailbox? _mailbox;
  List<mail.MimeMessage> _messages = const <mail.MimeMessage>[];
  mail.MimeMessage? _selected;
  MailReaderController? _reader;
  StudioMailDraft? _draft;
  StudioMailDraftStore? _draftStore;
  StudioMailMailboxCapture? _mailboxCapture;
  StudioMailMailboxSession? _mailboxViewSession;
  StreamSubscription<StudioMailMailboxSnapshot>? _mailboxViewSubscription;
  Future<void> _mailboxViewClosing = Future<void>.value();
  Future<void> _draftStoreClosing = Future<void>.value();
  Future<void>? _draftRestoreInFlight;
  final _unreleasedDraftStores = <StudioMailDraftStore>[];
  bool _submissionUncertain = false;
  bool _busy = false;
  bool _dialogOpen = false;
  bool _manual = false;
  bool _connecting = false;
  bool _showSavedMessages = false;
  bool _savedMessagesVisited = false;
  bool _showCompactMessage = false;
  String? _error;
  String? _notice;
  String? _localAccountWarning;
  String? _cacheViewWarning;
  String? _cacheBodyWarning;
  String? get _cacheWarning => _cacheViewWarning ?? _cacheBodyWarning;
  String? _credentialError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _credentials = widget.credentialStore ?? StudioMailCredentialStore();
    _accountCatalogStore = switch (_credentials) {
      StudioMailAccountCatalogStore store => store,
      _ => null,
    };
    for (final controller in [
      _email,
      _password,
      _imapHost,
      _smtpHost,
      _primaryLogin,
    ]) {
      controller.addListener(_settingsEdited);
    }
    if (widget.credentialStore == null) {
      StudioCredentialStorage.instance.addListener(_credentialStorageChanged);
    }
    final initialAccount = widget.initialAccount;
    if (initialAccount != null) {
      _prefillNavigationTarget(initialAccount);
    }
    unawaited(_loadCredentials());
  }

  void _settingsEdited() {
    _settingsRevision++;
    _autoConnectTicket = null;
    // Keep the offline action in sync with the effective saved-account route.
    // Password edits retain the route; endpoint/sender/login edits may not.
    if (mounted && _selectedSavedAccountId != null) setState(() {});
  }

  Future<void> _loadCredentials() async {
    if (_accountCatalogStore != null) {
      await _loadAccounts();
      return;
    }
    final generation = _sessionGeneration;
    final settings = _settingsRevision;
    final credentialGeneration = _credentialGeneration;
    final StudioMailCredentials? saved;
    try {
      saved = await _credentials.load();
    } on Object {
      // Missing or locked keychains do not prevent explicit account setup.
      return;
    }
    if (!_currentAttempt(generation) ||
        credentialGeneration != _credentialGeneration) {
      return;
    }
    var adopted = false;
    setState(() {
      _hasSavedCredentials = saved != null;
      if (saved == null ||
          _connecting ||
          _accountNavigationPending ||
          _client != null ||
          settings != _settingsRevision) {
        return;
      }
      if (_navigationTarget case final target?) {
        if (!_credentialMatchesTarget(saved, target)) return;
      }
      _applyCredentials(saved);
      adopted = true;
    });
    if (adopted) _scheduleAutoConnect();
  }

  bool get _autoConnectEnabled =>
      !_explicitAccountNavigation &&
      !_accountNavigationPending &&
      _retiredNavigationStore == null &&
      _navigationTarget == null &&
      (widget.autoConnectSavedAccount ??
          (widget.clientFactory == null &&
              widget.messageLoaderFactory == null));

  void _scheduleAutoConnect() {
    if (!_autoConnectEnabled ||
        _autoConnectTicket != null ||
        !_hasSavedCredentials ||
        _credentialPending ||
        _credentialSettingsOpen ||
        _credentialStoreChangePending ||
        _showSavedMessages ||
        _client != null ||
        _connecting ||
        _busy ||
        _dialogOpen ||
        _email.text.trim().isEmpty ||
        _password.text.isEmpty) {
      return;
    }
    final ticket = Object();
    _autoConnectTicket = ticket;
    final settings = _settingsRevision;
    final credentials = _credentialGeneration;
    final store = _credentialStoreRevision;
    final session = _sessionGeneration;
    final account = _selectedSavedAccountId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(_autoConnectTicket, ticket)) return;
      _autoConnectTicket = null;
      if (!mounted ||
          !_autoConnectEnabled ||
          settings != _settingsRevision ||
          credentials != _credentialGeneration ||
          store != _credentialStoreRevision ||
          session != _sessionGeneration ||
          account != _selectedSavedAccountId ||
          !_hasSavedCredentials ||
          _credentialPending ||
          _credentialSettingsOpen ||
          _credentialStoreChangePending ||
          _showSavedMessages ||
          _client != null ||
          _connecting ||
          _busy ||
          _dialogOpen ||
          _email.text.trim().isEmpty ||
          _password.text.isEmpty) {
        return;
      }
      unawaited(_connect());
    });
  }

  void _applyCredentials(StudioMailCredentials saved) {
    _email.text = saved.email;
    _password.text = saved.password;
    _imapHost.text = saved.imapHost;
    _smtpHost.text = saved.smtpHost;
    _manual = saved.manual;
    _startTls = saved.startTls;
    _preset = saved.preset;
    _primaryLogin.text = saved.primaryLogin;
    _icloudFullAddressLogin = saved.icloudFullAddressLogin;
  }

  void _applySavedAccount(StudioMailSavedAccount saved) {
    _applyCredentials(saved.credentials);
    _selectedSavedAccountId = saved.id;
    _hasSavedCredentials = true;
    _remember = true;
  }

  void _clearAccountSettings() {
    _settingsEdited();
    _selectedSavedAccountId = null;
    _hasSavedCredentials = false;
    _email.clear();
    _password.clear();
    _imapHost.clear();
    _smtpHost.clear();
    _primaryLogin.clear();
    _preset = null;
    _manual = false;
    _startTls = false;
    _icloudFullAddressLogin = false;
    _remember = true;
    _error = null;
    _notice = null;
    _credentialError = null;
  }

  Future<void> _loadAccounts() async {
    final store = _accountCatalogStore!;
    final session = _sessionGeneration;
    final settings = _settingsRevision;
    final generation = ++_credentialGeneration;
    setState(() => _credentialPending = true);
    StudioMailAccountCatalogResult result;
    try {
      result = await store.loadAccounts();
    } on Object {
      result = const StudioMailAccountCatalogResult.failure(
        StudioMailAccountCatalogProblem.unavailable,
      );
    }
    if (!mounted || generation != _credentialGeneration) return;
    var adopted = false;
    var unlockVault = false;
    setState(() {
      _credentialPending = false;
      final current =
          session == _sessionGeneration &&
          settings == _settingsRevision &&
          !_connecting &&
          !_accountNavigationPending &&
          _client == null;
      if (!result.isSuccess) {
        if (current) {
          _credentialError = widget.strings.mailAccountsLoadFailed;
          // An encrypted vault is intentionally locked on process start.
          // Offer its master password instead of presenting a permanently
          // unavailable catalog; the user can still cancel and set up a new
          // account manually.
          unlockVault = true;
        }
        return;
      }
      _accountCatalog = result.catalog!;
      if (current) {
        _credentialError = null;
        final target = _navigationTarget;
        final matches = target == null
            ? const <StudioMailSavedAccount>[]
            : result.catalog!.accounts
                  .where(
                    (entry) =>
                        _credentialMatchesTarget(entry.credentials, target),
                  )
                  .toList();
        final saved = target == null
            ? result.catalog!.selectedAccount
            : matches.length == 1
            ? matches.single
            : null;
        if (saved != null) {
          _applySavedAccount(saved);
          adopted = true;
        } else if (target != null) {
          _notice = widget.strings.mailAccountNavigationRouteUnavailable;
        }
      }
    });
    if (unlockVault) _scheduleVaultUnlockPrompt();
    if (adopted) _scheduleAutoConnect();
  }

  Future<void> _selectSavedAccount(String id) async {
    final store = _accountCatalogStore;
    if (store == null ||
        _credentialPending ||
        _connecting ||
        _busy ||
        _dialogOpen ||
        _client != null) {
      return;
    }
    final session = _sessionGeneration;
    final settings = _settingsRevision;
    final generation = ++_credentialGeneration;
    setState(() {
      _credentialPending = true;
      _credentialError = null;
    });
    StudioMailAccountCatalogResult result;
    try {
      result = await store.selectAccount(id);
    } on Object {
      result = const StudioMailAccountCatalogResult.failure(
        StudioMailAccountCatalogProblem.unavailable,
      );
    }
    if (!mounted || generation != _credentialGeneration) return;
    setState(() {
      _credentialPending = false;
      final current =
          session == _sessionGeneration &&
          settings == _settingsRevision &&
          !_connecting &&
          _client == null;
      if (result.isSuccess) _accountCatalog = result.catalog!;
      if (!current) {
        // A committed keychain selection may finish after the form was edited.
        // Keep the catalog, but never replace those newer account settings.
        _selectedSavedAccountId = null;
        _hasSavedCredentials = false;
        return;
      }
      final saved = result.catalog?.selectedAccount;
      if (!result.isSuccess || saved == null || saved.id != id) {
        _credentialError = widget.strings.mailAccountSelectFailed;
        return;
      }
      _applySavedAccount(saved);
      _error = null;
      _notice = null;
    });
  }

  void _newAccount() {
    if (_credentialPending ||
        _connecting ||
        _busy ||
        _dialogOpen ||
        _client != null) {
      return;
    }
    setState(() {
      _navigationTarget = null;
      _explicitAccountNavigation = true;
      _clearAccountSettings();
    });
  }

  Future<StudioMailAccountCatalogResult> _saveAccountChoice(
    StudioMailCredentials credentials,
    bool remember,
  ) async {
    final store = _accountCatalogStore!;
    if (remember) return store.saveAccount(credentials);
    // Opting out belongs to the account that actually connected. A new account
    // must not erase an unrelated profile that happened to be selected earlier.
    final revision = _credentialStoreRevision;
    final loaded = await store.loadAccounts();
    if (revision != _credentialStoreRevision) {
      return const StudioMailAccountCatalogResult.failure(
        StudioMailAccountCatalogProblem.unavailable,
      );
    }
    if (!loaded.isSuccess ||
        !loaded.catalog!.accounts.any(
          (entry) => entry.id == credentials.accountId,
        )) {
      return loaded;
    }
    return store.forgetAccount(credentials.accountId);
  }

  Future<void> _persistCredentials(
    mail.MailClient client,
    int sessionGeneration,
    StudioMailCredentials credentials,
    bool remember, {
    int? storeRevision,
  }) async {
    if (!_currentSession(client, sessionGeneration)) return;
    _lastCredentialSnapshot = remember
        ? StudioMailCredentials.fromJson(credentials.toJson())
        : null;
    if (storeRevision != null && storeRevision != _credentialStoreRevision) {
      setState(() {
        _credentialError = remember
            ? widget.strings.mailKeychainSaveFailed
            : widget.strings.mailKeychainClearFailed;
      });
      return;
    }
    final generation = ++_credentialGeneration;
    setState(() => _credentialPending = true);
    bool success;
    StudioMailAccountCatalogResult? catalogResult;
    try {
      if (_accountCatalogStore != null) {
        catalogResult = await _saveAccountChoice(credentials, remember);
        success = catalogResult.isSuccess;
      } else {
        success = remember
            ? await _credentials.save(credentials)
            : await _credentials.clear();
      }
    } on Object {
      success = false;
    }
    if (!mounted || generation != _credentialGeneration) return;
    setState(() {
      _credentialPending = false;
      if (success) {
        _hasSavedCredentials = remember;
        if (catalogResult != null) {
          _accountCatalog = catalogResult.catalog!;
          if (_currentSession(client, sessionGeneration)) {
            _selectedSavedAccountId = remember ? credentials.accountId : null;
          } else {
            // The catalog write still belongs to the retired connection. Its
            // completion must not make an older profile the form's Forget
            // target after disconnect or newer account edits.
            _selectedSavedAccountId = null;
            _hasSavedCredentials = false;
          }
        }
      }
      if (_currentSession(client, sessionGeneration)) {
        // Credential feedback must not replace a confirmed SMTP receipt or
        // another mailbox operation's status while the keychain is pending.
        _credentialError = success
            ? null
            : catalogResult?.problem ==
                  StudioMailAccountCatalogProblem.limitReached
            ? widget.strings.mailAccountLimitReached
            : remember
            ? widget.strings.mailKeychainSaveFailed
            : widget.strings.mailKeychainClearFailed;
      }
    });
  }

  Future<void> _forgetCredentials() async {
    if (_connecting || _busy || _dialogOpen) return;
    if (_accountCatalogStore != null) {
      await _forgetSavedAccount();
      return;
    }
    final generation = ++_credentialGeneration;
    final session = _sessionGeneration;
    final settings = _settingsRevision;
    setState(() => _credentialPending = true);
    bool success;
    try {
      success = await _credentials.clear();
    } on Object {
      success = false;
    }
    if (!mounted || generation != _credentialGeneration) return;
    setState(() {
      _credentialPending = false;
      if (success) {
        _hasSavedCredentials = false;
        _credentialError = null;
        if (session == _sessionGeneration && settings == _settingsRevision) {
          _password.clear();
        }
      } else if (session == _sessionGeneration &&
          settings == _settingsRevision) {
        _credentialError = widget.strings.mailKeychainClearFailed;
      }
    });
  }

  Future<void> _forgetSavedAccount() async {
    final id = _selectedSavedAccountId;
    if (id == null ||
        _credentialPending ||
        _connecting ||
        _busy ||
        _dialogOpen ||
        _client != null) {
      return;
    }
    final session = _sessionGeneration;
    final settings = _settingsRevision;
    final generation = ++_credentialGeneration;
    setState(() => _credentialPending = true);
    StudioMailAccountCatalogResult result;
    try {
      result = await _accountCatalogStore!.forgetAccount(id);
    } on Object {
      result = const StudioMailAccountCatalogResult.failure(
        StudioMailAccountCatalogProblem.unavailable,
      );
    }
    if (!mounted || generation != _credentialGeneration) return;
    setState(() {
      _credentialPending = false;
      final current =
          session == _sessionGeneration && settings == _settingsRevision;
      if (!result.isSuccess) {
        if (current) _credentialError = widget.strings.mailKeychainClearFailed;
        return;
      }
      _accountCatalog = result.catalog!;
      _selectedSavedAccountId = null;
      _hasSavedCredentials = false;
      if (current) {
        _clearAccountSettings();
        final saved = result.catalog!.selectedAccount;
        if (saved != null) _applySavedAccount(saved);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep the current mailbox and open message intact when the app returns
    // from another desktop. An eager refresh cleared the reader before its
    // network round-trip completed, which looked like a disconnect.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.credentialStore == null) {
      StudioCredentialStorage.instance.removeListener(
        _credentialStorageChanged,
      );
    }
    _bulkCancellation?.cancel(MailCancellationReason.disposed);
    _remoteImageLoader?.cancel();
    _sessionGeneration++;
    unawaited(_stopCachedView());
    _mailboxCapture?.dispose();
    _credentialGeneration++;
    _email.dispose();
    _password.dispose();
    _imapHost.dispose();
    _smtpHost.dispose();
    _primaryLogin.dispose();
    _reader?.dispose();
    _messageLoader?.dispose();
    _pendingLoader?.dispose();
    unawaited(_closeDraftStore(_draftStore));
    unawaited(
      _releaseRetiredNavigationAccount().catchError(
        (Object _, StackTrace _) {},
      ),
    );
    _draftStore = null;
    unawaited(_disconnectQuietly(_client));
    unawaited(_disconnectQuietly(_pendingClient));
    super.dispose();
  }

  bool _currentAttempt(int generation) =>
      mounted && generation == _sessionGeneration;

  bool _currentSession(mail.MailClient client, int generation) =>
      _currentAttempt(generation) && identical(client, _client);

  Future<void> _closeDraftStore(StudioMailDraftStore? store) async {
    // Keep the owner alive until an in-flight server reply has a durable receipt.
    // Cancelling the connection still prevents every subsequent dispatch.
    final mailboxStore = switch (store) {
      StudioMailMailboxStoreOwner owner => owner.mailboxStore,
      _ => null,
    };
    try {
      if (mailboxStore != null &&
          identical(_mailboxViewSession?.store, mailboxStore)) {
        await _stopCachedView();
      }
      await _mailboxViewClosing;
      await _pendingFlagWrite;
      if (mailboxStore != null &&
          identical(_mailboxCapture?.store, mailboxStore)) {
        _mailboxCapture?.dispose();
        _mailboxCapture = null;
      }
      await store?.close();
      _unreleasedDraftStores.removeWhere((owner) => identical(owner, store));
    } on Object {
      // A failed close does not prove that the exclusive owner was released.
      // Retain it for the next explicit transition; opening another account
      // must never silently overlap that failed release.
      if (store != null &&
          !_unreleasedDraftStores.any((owner) => identical(owner, store))) {
        _unreleasedDraftStores.add(store);
      }
    }
  }

  Future<void> _requireReleasedDraftStores() async {
    await _draftStoreClosing;
    // A preceding restoration can acquire a stale owner while this transition
    // waits. A failed release still needs the explicit release control even
    // when no retained owner existed at this transition's entry check.
    if (_retiredNavigationStore != null ||
        _retiredNavigationView != null ||
        _retiredNavigationSubscription != null) {
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    }
    for (final owner in List<StudioMailDraftStore>.of(_unreleasedDraftStores)) {
      await _closeDraftStore(owner);
      if (_unreleasedDraftStores.any((store) => identical(store, owner))) {
        throw const StudioMailDraftStoreException(
          MailProblemCode.storageFailure,
        );
      }
    }
  }

  Future<bool> _restoreDraftStore(
    mail.MailClient client,
    mail.MailAccount account,
    int generation, {
    StudioMailAccountNavigationTarget? expectedTarget,
    Future<void> Function()? validateNavigation,
    Future<void> Function(StudioMailDraftAccount identity)? rememberNavigation,
  }) async {
    if (!_currentSession(client, generation)) return false;
    while (_draftRestoreInFlight != null) {
      await _draftRestoreInFlight;
      if (!_currentSession(client, generation)) return false;
    }
    if (_draftStore != null) return true;
    final restoration = Completer<void>();
    final restorationFinished = restoration.future;
    _draftRestoreInFlight = restorationFinished;
    setState(() {
      _busy = true;
      _navigationOwnerPending = expectedTarget != null;
      _localAccountWarning = null;
    });
    StudioMailDraftStore? candidate;
    try {
      await _requireReleasedDraftStores();
      if (!_currentSession(client, generation)) return false;
      await validateNavigation?.call();
      if (!_currentSession(client, generation)) return false;
      final identity = _imapLocalIdentity(account);
      candidate = await (widget.draftStoreFactory ?? openStudioMailDraftStore)(
        identity,
      );
      await validateNavigation?.call();
      if (!_currentSession(client, generation)) {
        if (expectedTarget != null) {
          await _closeNavigationCandidate(candidate);
        } else {
          await _closeDraftStore(candidate);
        }
        return false;
      }
      if (candidate case StudioMailOutboxStore(
        :final account,
      ) when account != identity.account) {
        throw const StudioMailDraftStoreException(
          MailProblemCode.permissionDenied,
        );
      }
      if (candidate case StudioMailComposeToolsStore(
        :final account,
      ) when account != identity.account) {
        throw const StudioMailDraftStoreException(
          MailProblemCode.permissionDenied,
        );
      }
      if (candidate case StudioMailDraftCatalog(
        :final account,
      ) when account != identity.account) {
        throw const StudioMailDraftStoreException(
          MailProblemCode.permissionDenied,
        );
      }
      if (candidate case StudioMailMailboxStoreOwner(
        :final mailboxStore,
      ) when mailboxStore.account != identity.account) {
        throw const StudioMailDraftStoreException(
          MailProblemCode.permissionDenied,
        );
      }
      if (candidate case StudioMailFlagJournalOwner(
        :final flagJournal,
      ) when flagJournal.account != identity.account) {
        throw const StudioMailDraftStoreException(
          MailProblemCode.permissionDenied,
        );
      }
      final restored = await candidate.load();
      await validateNavigation?.call();
      if (!_currentSession(client, generation)) {
        if (expectedTarget != null) {
          await _closeNavigationCandidate(candidate);
        } else {
          await _closeDraftStore(candidate);
        }
        return false;
      }
      setState(() {
        _draftStore = candidate;
        _draft = restored?.draft;
        _submissionUncertain = restored?.submissionUncertain ?? false;
        _error = _submissionUncertain
            ? widget.strings.mailSubmissionUncertain
            : null;
        if (restored != null) _notice = widget.strings.mailDraftRestored;
      });
      final loader = _messageLoader;
      final mailboxOwner = switch (candidate) {
        StudioMailMailboxStoreOwner owner => owner,
        _ => null,
      };
      final records = switch (loader) {
        StudioMailMailboxRecords value => value,
        _ => null,
      };
      if (mailboxOwner != null && records != null) {
        final owner = candidate;
        await _stopCachedView();
        if (!_currentSession(client, generation) ||
            !identical(owner, _draftStore)) {
          return false;
        }
        await validateNavigation?.call();
        if (!_currentSession(client, generation) ||
            !identical(owner, _draftStore)) {
          return false;
        }
        _mailboxCapture?.dispose();
        _mailboxCapture = StudioMailMailboxCapture(
          store: mailboxOwner.mailboxStore,
          sourceAccount: records.account,
          provider: MailProviderKind.imap,
          isCurrent: () =>
              _currentSession(client, generation) &&
              identical(owner, _draftStore) &&
              identical(loader, _messageLoader),
        );
        await _saveCachedView(client, generation);
      }
      await validateNavigation?.call();
      if (!_currentSession(client, generation)) return false;
      final directory = _localAccounts;
      if (directory != null && candidate is StudioMailDraftCatalog) {
        try {
          if (rememberNavigation == null) {
            await directory.remember(identity);
          } else {
            await rememberNavigation(identity);
          }
        } on Object {
          if (rememberNavigation != null) {
            throw const _StudioMailNavigationExpired();
          }
          if (_currentSession(client, generation)) {
            setState(
              () => _localAccountWarning =
                  widget.strings.mailLocalAccountsSaveFailed,
            );
          }
        }
      }
      return _currentSession(client, generation);
    } on Object catch (error) {
      final expired = error is _StudioMailNavigationExpired;
      final wasCurrent = _currentSession(client, generation);
      if (candidate != null && identical(candidate, _draftStore)) {
        if (expired) {
          // A revoked selected route can already own live repository observers.
          // Keep those handles together until each drain and owner close works.
          _holdNavigationAccount();
          try {
            await _releaseRetiredNavigationAccount();
          } on Object {
            // The explicit release control retains the failed owner/observers.
          }
        }
        // An ordinary local-storage failure does not discard an adopted owner.
      } else if (expectedTarget != null && candidate != null) {
        await _closeNavigationCandidate(candidate);
      } else {
        await _closeDraftStore(candidate);
      }
      if (wasCurrent && (expired || _retiredNavigationStore != null)) {
        if (_currentSession(client, generation)) _disconnect();
        if (mounted) {
          setState(() {
            _navigationTarget = expectedTarget;
            _error = _retiredNavigationStore != null
                ? widget.strings.mailDraftStorageFailed
                : widget.strings.mailAccountNavigationChanged;
          });
        }
      } else if (_currentSession(client, generation)) {
        setState(() => _error = widget.strings.mailDraftStorageFailed);
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _navigationOwnerPending = false;
          if (_currentSession(client, generation)) _busy = false;
        });
      }
      if (identical(_draftRestoreInFlight, restorationFinished)) {
        _draftRestoreInFlight = null;
      }
      restoration.complete();
    }
  }

  Future<void> _closeNavigationCandidate(StudioMailDraftStore candidate) async {
    try {
      await candidate.close();
    } on Object {
      _retiredNavigationStore = candidate;
      if (mounted) {
        setState(() => _error = widget.strings.mailDraftStorageFailed);
      }
    }
  }

  Future<bool> _clearAcceptedDraft(StudioMailDraftStore store) async {
    try {
      await store.clear();
      return true;
    } on Object {
      // The pre-submission marker remains uncertain if cleanup cannot commit.
      return false;
    }
  }

  Future<void> _saveCachedView(mail.MailClient client, int generation) async {
    final capture = _mailboxCapture;
    final loader = switch (_messageLoader) {
      StudioMailMailboxRecords value => value,
      _ => null,
    };
    final mailbox = _messageMailbox;
    if (capture == null ||
        loader == null ||
        mailbox == null ||
        !_currentSession(client, generation)) {
      return;
    }
    final mailboxGeneration = _mailboxGeneration;
    bool current() =>
        _currentSession(client, generation) &&
        mailboxGeneration == _mailboxGeneration &&
        identical(capture, _mailboxCapture) &&
        identical(mailbox, _messageMailbox) &&
        identical(loader, _messageLoader);
    try {
      final records = [
        for (final message in _messages)
          _capturedHeader(loader.observedHeader(mailbox, message), message),
      ];
      final messages = <MailMessageId, mail.MimeMessage>{
        for (var i = 0; i < records.length; i++) records[i].id: _messages[i],
      };
      await _stopCachedView(retainMetadata: true);
      if (!current()) return;
      final saved = await capture.saveView(
        MailMailbox(
          id: MailMailboxId(mailbox.path, account: loader.account),
          displayName: mailbox.name,
        ),
        records,
        hasMore: _nextHeaders != null,
      );
      if (!current()) return;
      final session = StudioMailMailboxSession(
        store: capture.store,
        provider: capture.provider,
      );
      _mailboxViewSession = session;
      void accept(StudioMailMailboxSnapshot snapshot) {
        if (!current() || !identical(session, _mailboxViewSession)) return;
        if (snapshot.phase == StudioMailMailboxPhase.loading) return;
        try {
          final view = snapshot.view;
          if (snapshot.phase != StudioMailMailboxPhase.ready || view == null) {
            throw const StudioMailMailboxStoreException(
              MailProblemCode.storageFailure,
            );
          }
          final projected = capture.projectView(view);
          final ordered = <mail.MimeMessage>[];
          final flags = Map<mail.MimeMessage, MailMessageFlags?>.identity();
          for (final header in projected) {
            final message = messages[header.id];
            if (message == null ||
                loader.observedHeader(mailbox, message).remote !=
                    header.remote) {
              throw const StudioMailMailboxStoreException(
                MailProblemCode.conflict,
              );
            }
            ordered.add(message);
            flags[message] = header.flags;
          }
          setState(() {
            _messages = ordered;
            for (final entry in flags.entries) {
              final observed = entry.value;
              final previous = _repositoryFlags[entry.key];
              final hadPrevious = _repositoryFlags.containsKey(entry.key);
              final confirmed = _confirmedFlags[entry.key];
              if (observed != null && confirmed != null) {
                final read =
                    confirmed.read == observed.isRead ||
                        hadPrevious && previous?.isRead != observed.isRead
                    ? null
                    : confirmed.read;
                final flagged =
                    confirmed.flagged == observed.isFlagged ||
                        hadPrevious && previous?.isFlagged != observed.isFlagged
                    ? null
                    : confirmed.flagged;
                if (read == null && flagged == null) {
                  _confirmedFlags.remove(entry.key);
                } else {
                  _confirmedFlags[entry.key] = (read: read, flagged: flagged);
                }
              }
            }
            _repositoryFlags
              ..clear()
              ..addAll(flags);
            _cacheViewWarning = null;
          });
        } on Object {
          setState(
            () => _cacheViewWarning = widget.strings.mailCacheSaveFailed,
          );
        }
      }

      _mailboxViewSubscription = session.changes.listen(accept);
      await session.select(saved.mailbox.id);
    } on Object {
      if (current()) {
        setState(() => _cacheViewWarning = widget.strings.mailCacheSaveFailed);
      }
    }
  }

  MailHeaderRecord _capturedHeader(
    MailHeaderRecord observed,
    mail.MimeMessage message,
  ) {
    final snapshot = _repositoryFlags.containsKey(message)
        ? _repositoryFlags[message]
        : observed.flags;
    final confirmed = _confirmedFlags[message];
    return MailHeaderRecord(
      id: observed.id,
      remote: observed.remote,
      envelope: observed.envelope,
      // A per-flag confirmation must never invent the remaining unknown bits.
      flags: snapshot == null
          ? null
          : MailMessageFlags(
              isRead: confirmed?.read ?? snapshot.isRead,
              isFlagged: confirmed?.flagged ?? snapshot.isFlagged,
              isAnswered: snapshot.isAnswered,
              isDraft: snapshot.isDraft,
              isDeleted: snapshot.isDeleted,
            ),
    );
  }

  Future<void> _stopCachedView({bool retainMetadata = false}) {
    final session = _mailboxViewSession;
    final subscription = _mailboxViewSubscription;
    _mailboxViewSession = null;
    _mailboxViewSubscription = null;
    if (!retainMetadata) _repositoryFlags.clear();
    _mailboxCapture?.invalidateView();
    final closing = session?.close();
    final previous = _mailboxViewClosing;
    return _mailboxViewClosing = () async {
      try {
        await previous;
      } on Object {
        // Continue retiring all independent subscriptions.
      }
      try {
        await subscription?.cancel();
      } on Object {
        // Identity fencing already rejects late callbacks.
      }
      try {
        await closing;
      } on Object {
        // The owner still closes after every cancellation has settled.
      }
    }();
  }

  Future<void> _disconnectQuietly(
    mail.MailClient? client,
  ) => runStudioMailOperation(() async {
    if (client == null) return;
    Future<void> settle(Future<void> Function() close) async {
      try {
        await close();
      } on Object {
        // Each owned transport must still close if another shutdown fails.
        // Cleanup must not replace the operation's fixed, localized feedback.
      }
    }

    await Future.wait<void>(<Future<void>>[
      // Disconnect can queue behind an in-flight command. Abort both owned
      // transports independently, including while initial connection is pending.
      settle(() => client.lowLevelIncomingMailClient.abort()),
      settle(() => client.lowLevelOutgoingMailClient.abort()),
      settle(client.disconnect),
    ]);
  });

  void _retireReader(MailReaderController? reader) {
    if (reader == null) return;
    if (identical(_remoteImageOwner, reader)) {
      _remoteImageLoader?.cancel();
      _remoteImageLoader = null;
      _remoteImageOwner = null;
      _remoteImagesLoading = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => reader.dispose());
  }

  Future<void> _connect() => runStudioMailOperation(() async {
    if (_connecting ||
        _busy ||
        _dialogOpen ||
        _accountNavigationPending ||
        _retiredNavigationStore != null ||
        _client != null ||
        _accountCatalogStore != null && _credentialPending) {
      return;
    }
    final generation = ++_sessionGeneration;
    final storeRevision = _credentialStoreRevision;
    setState(() {
      _connecting = true;
      _error = null;
      _notice = null;
      _credentialError = null;
    });
    final email = _email.text.trim();
    final domain = email.contains('@') ? email.split('@').last : '';
    final password = _password.text;
    final manual = _manual;
    final startTls = _startTls;
    final remember = _remember;
    final preset = _preset;
    final primaryLogin = _primaryLogin.text.trim();
    final icloudFullAddressLogin = _icloudFullAddressLogin;
    final imapHost = _imapHost.text.trim();
    final smtpHost = _smtpHost.text.trim();
    final target = _navigationTarget;
    final initialTarget = widget.initialAccount;
    final directory = _localAccounts;
    final draftStoreFactory = widget.draftStoreFactory;
    bool sameDestination() =>
        _currentAttempt(generation) &&
        identical(target, _navigationTarget) &&
        identical(initialTarget, widget.initialAccount) &&
        identical(directory, _localAccounts) &&
        identical(draftStoreFactory, widget.draftStoreFactory);
    Future<void> validateNavigation() async {
      if (!sameDestination()) throw const _StudioMailNavigationExpired();
      if (target != null) {
        if (directory == null) throw const _StudioMailNavigationExpired();
        try {
          await target.validateCurrent(directory);
        } on Object {
          throw const _StudioMailNavigationExpired();
        }
        if (!sameDestination()) throw const _StudioMailNavigationExpired();
      }
    }

    mail.MailClient? candidate;
    StudioMailMessageLoader? candidateLoader;
    bool adopted = false;
    try {
      await _draftRestoreInFlight;
      await _transportClosing;
      await _requireReleasedDraftStores();
      await validateNavigation();
      if (!_currentAttempt(generation)) return;
      mail.MailAccount account;
      if (target != null && manual && smtpHost.isEmpty) {
        throw const StudioMailDraftStoreException(MailProblemCode.unavailable);
      }
      if (preset != null) {
        account = createStudioMailPresetAccount(
          preset: preset,
          email: email,
          password: password,
          primaryLogin: primaryLogin,
          icloudFullAddressLogin: icloudFullAddressLogin,
        );
      } else if (manual) {
        account = mail.MailAccount.fromManualSettings(
          name: email,
          email: email,
          incomingHost: imapHost,
          outgoingHost: smtpHost,
          password: password,
          incomingPort: startTls ? 143 : 993,
          outgoingPort: startTls ? 587 : 465,
          incomingSocketType: startTls
              ? mail.SocketType.starttls
              : mail.SocketType.ssl,
          outgoingSocketType: startTls
              ? mail.SocketType.starttls
              : mail.SocketType.ssl,
        );
      } else if (domain.toLowerCase() == 'mailbox.org') {
        account = mail.MailAccount.fromManualSettings(
          name: email,
          email: email,
          incomingHost: 'imap.mailbox.org',
          outgoingHost: 'smtp.mailbox.org',
          password: password,
          incomingPort: 143,
          outgoingPort: 587,
          incomingSocketType: mail.SocketType.starttls,
          outgoingSocketType: mail.SocketType.starttls,
        );
      } else {
        final config =
            await (widget.accountDiscovery?.call(email) ??
                mail.Discover.discover(email, isLogEnabled: false));
        if (!_currentAttempt(generation)) return;
        await validateNavigation();
        if (!_currentAttempt(generation)) return;
        if (config == null ||
            config.isNotValid ||
            config.isFromInsecureSource ||
            config.preferredIncomingImapServer?.type != mail.ServerType.imap ||
            config.preferredOutgoingServer?.type != mail.ServerType.smtp) {
          throw const FormatException(
            'Authenticated IMAP and SMTP discovery is required.',
          );
        }
        config.enforceSecureSockets();
        account = mail.MailAccount.fromDiscoveredSettings(
          name: email,
          email: email,
          password: password,
          config: config,
          userName: email,
        );
      }
      target?.requireMatches(_imapLocalIdentity(account));
      await validateNavigation();
      if (!_currentAttempt(generation)) return;
      final client =
          widget.clientFactory?.call(account) ??
          mail.MailClient(account, isLogEnabled: false);
      candidate = client;
      _pendingClient = client;
      final loader =
          widget.messageLoaderFactory?.call(account) ??
          NativeStudioMailMessageLoader(
            account,
            persistentAccount: _imapLocalIdentity(account).account,
          );
      candidateLoader = loader;
      _pendingLoader = loader;
      await client.connect();
      if (!_currentAttempt(generation)) return;
      await validateNavigation();
      if (!_currentAttempt(generation)) return;
      final boxes = await client.listMailboxes();
      if (!_currentAttempt(generation)) return;
      await validateNavigation();
      if (!_currentAttempt(generation)) return;
      final inbox =
          boxes.where((b) => b.isInbox && !b.isNotSelectable).firstOrNull ??
          boxes.where((b) => !b.isNotSelectable).firstOrNull;
      if (inbox == null) {
        throw const FormatException('The account has no selectable mailbox.');
      }
      final StudioMailHeaderPage page;
      final mail.Mailbox observedMailbox;
      if (loader is StudioMailMailboxBrowser) {
        final selected = await client.selectMailbox(inbox);
        if (!_currentAttempt(generation)) return;
        await validateNavigation();
        if (!_currentAttempt(generation)) return;
        observedMailbox = (client.selectedMailbox ?? selected).copyWith();
        page = await (loader as StudioMailMailboxBrowser).fetchHeaders(
          observedMailbox,
          limit: _pageSize,
        );
      } else {
        // Existing reader-only host adapters retain their bounded first page.
        final messages = await client.fetchMessages(
          mailbox: inbox,
          count: _pageSize,
          fetchPreference: mail.FetchPreference.envelope,
        );
        observedMailbox = (client.selectedMailbox ?? inbox).copyWith();
        page = StudioMailHeaderPage(messages: messages);
      }
      if (!_currentAttempt(generation)) return;
      await validateNavigation();
      if (!_currentAttempt(generation)) return;
      _validateHeaderPage(page, observedMailbox, limit: _pageSize);
      final membershipCapabilities = await _readMembershipCapabilities(loader);
      if (!_currentAttempt(generation)) return;
      await validateNavigation();
      if (!_currentAttempt(generation)) return;
      final previous = _reader;
      setState(() {
        _client = client;
        _pendingClient = null;
        _messageLoader = loader;
        _membershipCapabilities = membershipCapabilities;
        _pendingLoader = null;
        _messageMailbox = observedMailbox;
        _account = account;
        _mailboxes = boxes;
        _mailbox = inbox;
        _messages = page.messages;
        _nextHeaders = page.next;
        _usedHeaderCursors.clear();
        _confirmedFlags.clear();
        _needsRefresh = false;
        _bulkReport = null;
        _bulkSubjects = const {};
        _selected = null;
        _reader = null;
        _connecting = false;
        _notice = null;
      });
      adopted = true;
      _retireReader(previous);
      final restored = await _restoreDraftStore(
        client,
        account,
        generation,
        expectedTarget: target,
        validateNavigation: validateNavigation,
        rememberNavigation: target == null || directory == null
            ? null
            : (identity) => target.rememberConnection(
                directory,
                identity,
                isCurrent: sameDestination,
              ),
      );
      if (!_currentSession(client, generation)) return;
      if (!restored) await validateNavigation();
      if (!sameDestination()) throw const _StudioMailNavigationExpired();
      // Only a fully validated session may fulfil the selected sign-in intent.
      // Remembering it can advance the directory revision, so later explicit
      // reconnects must not reuse this now-completed selection receipt.
      _navigationTarget = null;
      await _persistCredentials(
        client,
        generation,
        StudioMailCredentials(
          email: email,
          password: password,
          imapHost: account.incoming.serverConfig.hostname,
          smtpHost: account.outgoing.serverConfig.hostname,
          manual:
              manual || preset == null && domain.toLowerCase() == 'mailbox.org',
          startTls:
              account.incoming.serverConfig.socketType ==
              mail.SocketType.starttls,
          preset: preset,
          primaryLogin: primaryLogin,
          icloudFullAddressLogin: icloudFullAddressLogin,
        ),
        remember,
        storeRevision: storeRevision,
      );
    } on Object catch (error) {
      if (!_currentAttempt(generation)) return;
      if (adopted && error is _StudioMailNavigationExpired) _disconnect();
      setState(() {
        _connecting = false;
        _error = _retiredNavigationStore != null
            ? widget.strings.mailDraftStorageFailed
            : error is _StudioMailNavigationExpired
            ? widget.strings.mailAccountNavigationChanged
            : error is StudioMailDraftStoreException && target != null
            ? error.code == MailProblemCode.permissionDenied
                  ? widget.strings.mailAccountNavigationIdentityMismatch
                  : error.code == MailProblemCode.unavailable
                  ? widget.strings.mailAccountNavigationRouteUnavailable
                  : widget.strings.mailAccountNavigationChanged
            : widget.strings.mailConnectionFailed;
        if (preset == null && !manual && domain.isNotEmpty) {
          _imapHost.text = 'imap.$domain';
          _smtpHost.text = 'smtp.$domain';
          _manual = true;
          if (domain.toLowerCase() == 'mailbox.org') _startTls = true;
        }
      });
    } finally {
      if (identical(_pendingClient, candidate)) _pendingClient = null;
      if (identical(_pendingLoader, candidateLoader)) _pendingLoader = null;
      if (!adopted) {
        candidateLoader?.dispose();
        await _disconnectQuietly(candidate);
      }
    }
  });

  void _validateHeaderPage(
    StudioMailHeaderPage page,
    mail.Mailbox mailbox, {
    MailCursor? cursor,
    required int limit,
  }) {
    final next = page.next;
    if (page.messages.length > limit ||
        _usedHeaderCursors.length >= _maxHeaders) {
      throw const StudioMailMessageLoadException(MailProblemCode.quotaExceeded);
    }
    if (page.messages
                .map((message) => _messageKey(message, mailbox: mailbox))
                .toSet()
                .length !=
            page.messages.length ||
        next != null &&
            (next.mailbox.value != mailbox.path ||
                next.value.isEmpty ||
                cursor != null && next.mailbox != cursor.mailbox ||
                next.value == cursor?.value ||
                _usedHeaderCursors.contains(next.value))) {
      throw const StudioMailMessageLoadException(MailProblemCode.conflict);
    }
  }

  Future<MailCapabilities> _readMembershipCapabilities(
    StudioMailMessageLoader loader,
  ) async {
    if (loader is! StudioMailMembershipActions) {
      return const MailCapabilities.none();
    }
    try {
      return await (loader as StudioMailMembershipActions)
          .membershipCapabilities();
    } on Object {
      // Reading remains usable when optional organization discovery fails.
      // A folder refresh or an explicit reader action can check again.
      return const MailCapabilities.none();
    }
  }

  Future<void> _selectMailbox(mail.Mailbox mailbox, {bool more = false}) =>
      runStudioMailOperation(() async {
        final client = _client;
        final loader = _messageLoader;
        if (client == null ||
            loader == null ||
            _accountNavigationPending ||
            _retiredNavigationStore != null ||
            _busy ||
            _dialogOpen ||
            more &&
                (_needsRefresh ||
                    _nextHeaders == null ||
                    _messages.length >= _maxHeaders ||
                    _messageMailbox == null ||
                    mailbox.path != _mailbox?.path ||
                    loader is! StudioMailMailboxBrowser)) {
          return;
        }
        final generation = _sessionGeneration;
        final previous = more ? null : _reader;
        final cursor = more ? _nextHeaders : null;
        setState(() => _busy = true);
        await _stopCachedView(retainMetadata: more);
        if (!_currentSession(client, generation)) return;
        setState(() {
          _busy = true;
          _error = null;
          _notice = null;
          if (!more) {
            _mailboxGeneration++;
            _bulkReport = null;
            _bulkSubjects = const {};
            _mailbox = mailbox;
            _messageMailbox = null;
            _selected = null;
            _messages = const <mail.MimeMessage>[];
            _nextHeaders = null;
            _usedHeaderCursors.clear();
            _confirmedFlags.clear();
            _reader = null;
            _showCompactMessage = false;
          }
        });
        _retireReader(previous);
        try {
          final mail.Mailbox observedMailbox;
          if (more) {
            observedMailbox = _messageMailbox!;
          } else {
            final selected = await client.selectMailbox(mailbox);
            if (!_currentSession(client, generation)) return;
            observedMailbox = (client.selectedMailbox ?? selected).copyWith();
          }
          final remaining = _maxHeaders - (more ? _messages.length : 0);
          final limit = remaining < _pageSize ? remaining : _pageSize;
          final StudioMailHeaderPage page;
          if (loader is StudioMailMailboxBrowser) {
            page = await (loader as StudioMailMailboxBrowser).fetchHeaders(
              observedMailbox,
              cursor: cursor,
              limit: limit,
            );
          } else {
            page = StudioMailHeaderPage(
              messages: await client.fetchMessages(
                mailbox: mailbox,
                count: limit,
                fetchPreference: mail.FetchPreference.envelope,
              ),
            );
          }
          if (!_currentSession(client, generation)) return;
          _validateHeaderPage(
            page,
            observedMailbox,
            cursor: cursor,
            limit: limit,
          );
          final membershipCapabilities = more
              ? _membershipCapabilities
              : await _readMembershipCapabilities(loader);
          if (!_currentSession(client, generation)) return;
          final messages = <String, mail.MimeMessage>{
            if (more)
              for (final message in _messages) _messageKey(message): message,
            for (final message in page.messages)
              _messageKey(message, mailbox: observedMailbox): message,
          };
          setState(() {
            if (cursor != null) _usedHeaderCursors.add(cursor.value);
            _messages = messages.values.toList();
            _membershipCapabilities = membershipCapabilities;
            final retained = Set<mail.MimeMessage>.identity()
              ..addAll(_messages);
            _confirmedFlags.removeWhere(
              (message, _) => !retained.contains(message),
            );
            _repositoryFlags.removeWhere(
              (message, _) => !retained.contains(message),
            );
            if (more && _selected != null) {
              _selected = messages[_messageKey(_selected!)];
            }
            _messageMailbox = observedMailbox;
            _nextHeaders = page.next;
            _needsRefresh = false;
            _bulkReport = null;
            _bulkSubjects = const {};
          });
          await _saveCachedView(client, generation);
          if (_currentSession(client, generation)) {
            setState(() => _busy = false);
          }
        } on Object catch (error) {
          if (_currentSession(client, generation)) {
            setState(() {
              _busy = false;
              if (error is StudioMailMessageLoadException &&
                  error.code == MailProblemCode.conflict) {
                _needsRefresh = true;
                _error = widget.strings.mailWorkspaceRefreshRequired;
              } else {
                _error = widget.strings.mailMailboxFailed;
              }
            });
          }
        }
      });

  Future<void> _openMessage(mail.MimeMessage message) =>
      runStudioMailOperation(() async {
        final client = _client;
        final loader = _messageLoader;
        final mailbox = _messageMailbox;
        if (client == null ||
            loader == null ||
            mailbox == null ||
            _busy ||
            _dialogOpen) {
          return;
        }
        final generation = _sessionGeneration;
        setState(() {
          _busy = true;
          _error = null;
          _notice = null;
        });
        try {
          final MailMessage? observed;
          final MailHeaderRecord? header;
          final records = switch (loader) {
            StudioMailMailboxRecords value => value,
            _ => null,
          };
          if (records != null) {
            header = records.observedHeader(mailbox, message);
            observed = await records.fetchMessage(mailbox, message);
            if (observed.remoteIdentity != header.remote ||
                observed.localId != null && observed.localId != header.id) {
              throw const StudioMailMessageLoadException(
                MailProblemCode.conflict,
              );
            }
          } else {
            header = null;
            observed = null;
          }
          final raw =
              observed?.raw.copyBytes() ?? await loader.fetch(mailbox, message);
          if (!_currentSession(client, generation)) return;
          final reader = MailReaderController.fromBytes(
            raw,
            codec: const QudsMimeCodec(),
            preferHtml: false,
            includeHeaders: false,
            labels: StudioMailReaderLabels(widget.strings.language),
          );
          final previous = _reader;
          setState(() {
            _selected = message;
            _reader = reader;
            _showCompactMessage = true;
          });
          _retireReader(previous);
          final capture = _mailboxCapture;
          if (capture != null && header != null && observed != null) {
            try {
              await capture.cacheMessage(header, observed);
              if (_currentSession(client, generation)) {
                setState(() => _cacheBodyWarning = null);
              }
            } on Object {
              if (_currentSession(client, generation)) {
                setState(
                  () => _cacheBodyWarning = widget.strings.mailCacheSaveFailed,
                );
              }
            }
          }
          if (_currentSession(client, generation)) {
            setState(() => _busy = false);
          }
        } on Object {
          if (_currentSession(client, generation)) {
            setState(() {
              _busy = false;
              _error = widget.strings.mailMessageFailed;
            });
          }
        }
      });

  Future<void> _compose() => _openComposer(null);

  Future<void> _openDrafts() => runStudioMailOperation(() async {
    final client = _client;
    final account = _account;
    if (client == null || account == null || _busy || _dialogOpen) return;
    final generation = _sessionGeneration;
    if (!await _restoreDraftStore(client, account, generation)) return;
    if (!_currentSession(client, generation)) return;
    final store = _draftStore!;
    final catalog = switch (store) {
      StudioMailDraftCatalog value => value,
      _ => null,
    };
    if (catalog == null) {
      setState(() => _error = widget.strings.mailDraftListFailed);
      return;
    }
    bool current() =>
        _currentSession(client, generation) && identical(store, _draftStore);
    StudioMailStoredDraft? chosen;
    var catalogOpened = false;
    setState(() => _dialogOpen = true);
    try {
      final retained = _draft;
      if (retained != null) {
        await store.save(retained, submissionUncertain: _submissionUncertain);
      }
      if (!mounted || !current()) return;
      catalogOpened = true;
      chosen = await showDialog<StudioMailStoredDraft>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StudioMailDraftsDialog(
          strings: widget.strings,
          catalog: catalog,
          isCurrent: current,
        ),
      );
      if (!current()) return;
      final selected = chosen ?? await store.load();
      if (!current()) return;
      setState(() {
        _draft = selected?.draft;
        _submissionUncertain = selected?.submissionUncertain ?? false;
        _error = _submissionUncertain
            ? widget.strings.mailSubmissionUncertain
            : null;
        _notice = null;
      });
    } on Object {
      if (current()) {
        setState(() {
          _error = widget.strings.mailDraftListFailed;
          if (catalogOpened) {
            // The chooser may have changed/deleted the selected record. Never
            // save the old in-memory snapshot into an unknown current ID.
            _draftStore = null;
            _draft = null;
            _submissionUncertain = false;
          }
        });
        if (catalogOpened) {
          _draftStoreClosing = _draftStoreClosing.then(
            (_) => _closeDraftStore(store),
          );
          await _draftStoreClosing;
        }
      }
      chosen = null;
    } finally {
      if (_currentSession(client, generation)) {
        setState(() => _dialogOpen = false);
      }
    }
    if (chosen != null && current()) await _openComposer(null);
  });

  StudioMailOutboxSubmit _outboxSubmit(
    mail.MailClient client,
    mail.MailAccount account,
    StudioMailOutboxStore store,
    int generation,
  ) => (message, {required attemptId}) async {
    if (!_currentSession(client, generation) ||
        message.account != store.account ||
        message.envelope.sender != account.email) {
      return MailSubmissionResult(
        attemptId: attemptId,
        outcome: MailSubmissionOutcome.rejected,
      );
    }
    return submitStudioMailNativeOutbox(client, message, attemptId: attemptId);
  };

  Future<void> _openOutbox() => runStudioMailOperation(() async {
    final client = _client;
    final account = _account;
    if (client == null || account == null || _busy || _dialogOpen) return;
    final generation = _sessionGeneration;
    if (!await _restoreDraftStore(client, account, generation)) return;
    if (!mounted || !_currentSession(client, generation)) return;
    final store = switch (_draftStore) {
      StudioMailOutboxStore value => value,
      _ => null,
    };
    if (store == null) {
      setState(() => _error = widget.strings.mailOutboxFailed);
      return;
    }
    final draftOwner = _draftStore!;
    final catalog = draftOwner is StudioMailDraftCatalog
        ? draftOwner as StudioMailDraftCatalog
        : null;
    final originalEpoch = catalog?.selectionEpoch;
    StudioMailDraft? edited;
    var opened = false;
    bool current() =>
        _currentSession(client, generation) && identical(store, _draftStore);
    setState(() => _dialogOpen = true);
    try {
      final retained = _draft;
      if (retained != null) {
        await draftOwner.save(
          retained,
          submissionUncertain: _submissionUncertain,
        );
      }
      if (!mounted || !current()) return;
      opened = true;
      edited = await showDialog<StudioMailDraft>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StudioMailOutboxDialog(
          strings: widget.strings,
          store: store,
          submit: _outboxSubmit(client, account, store, generation),
          isCurrent: current,
        ),
      );
      if (!current()) return;
      if (edited != null || catalog?.selectionEpoch != originalEpoch) {
        final selected = edited == null
            ? await draftOwner.load()
            : StudioMailStoredDraft(draft: edited, submissionUncertain: false);
        if (!current()) return;
        setState(() {
          _draft = selected?.draft;
          _submissionUncertain = selected?.submissionUncertain ?? false;
          _error = null;
          _notice = null;
        });
      }
    } on Object {
      if (current()) {
        setState(() {
          _error = widget.strings.mailOutboxFailed;
          if (opened && catalog?.selectionEpoch != originalEpoch) {
            _draftStore = null;
            _draft = null;
            _submissionUncertain = false;
          }
        });
        if (opened && catalog?.selectionEpoch != originalEpoch) {
          _draftStoreClosing = _draftStoreClosing.then(
            (_) => _closeDraftStore(draftOwner),
          );
          await _draftStoreClosing;
        }
      }
      edited = null;
    } finally {
      if (_currentSession(client, generation)) {
        setState(() => _dialogOpen = false);
      }
    }
    if (edited != null && current()) await _openComposer(null);
  });

  Future<void> _sendThroughOutbox(
    StudioMailDraft draft,
    StudioMailOutboxStore store,
    mail.MailClient client,
    mail.MailAccount account,
    int generation,
  ) async {
    final priorUncertainty = _submissionUncertain;
    setState(() {
      _draft = draft;
      _busy = true;
      _error = null;
      _notice = null;
    });
    var queued = false;
    try {
      final entry = await store.enqueueOutbox(draft, account.email);
      queued = true;
      if (!_currentSession(client, generation)) return;
      setState(() {
        _draft = null;
        _submissionUncertain = false;
        _notice = widget.strings.sending;
      });
      final completed = await submitStudioMailOutbox(
        store: store,
        entry: entry,
        submit: _outboxSubmit(client, account, store, generation),
        isCurrent: () =>
            _currentSession(client, generation) &&
            identical(store, _draftStore),
        acknowledgeUncertain: priorUncertainty,
      );
      if (!_currentSession(client, generation)) return;
      setState(() {
        _notice = completed.state == MailOutboxState.submitted
            ? widget.strings.mailSubmissionAccepted
            : '${widget.strings.mailOutboxState(completed.state)}. ${widget.strings.mailOutboxInspect}';
        if (completed.state == MailOutboxState.uncertain ||
            (completed.priorSubmissionUncertain &&
                completed.state != MailOutboxState.submitted)) {
          _error = widget.strings.mailOutboxUncertainExplanation;
        }
      });
    } on Object {
      if (_currentSession(client, generation)) {
        setState(() {
          _notice = null;
          _error = queued
              ? widget.strings.mailOutboxFailed
              : widget.strings.mailQueueFailed;
        });
      }
    } finally {
      if (_currentSession(client, generation)) setState(() => _busy = false);
    }
  }

  Future<void> _openComposer(
    StudioMailDraft? initial,
  ) => runStudioMailOperation(() async {
    final client = _client;
    final account = _account;
    if (client == null || account == null || _busy || _dialogOpen) return;
    final generation = _sessionGeneration;
    if (!await _restoreDraftStore(client, account, generation)) return;
    if (!mounted || !_currentSession(client, generation)) return;
    final store = _draftStore!;
    final outbox = switch (store) {
      StudioMailOutboxStore value => value,
      _ => null,
    };
    final catalog = switch (store) {
      StudioMailDraftCatalog value => value,
      _ => null,
    };
    if (initial != null && (catalog != null || _draft == null)) {
      setState(() => _busy = true);
      try {
        final retained = _draft;
        if (retained != null) {
          await store.save(retained, submissionUncertain: _submissionUncertain);
        }
        if (!_currentSession(client, generation)) return;
        final prepared = await prepareStudioMailComposeDraft(
          store,
          initial,
          replyOrForward: true,
          isCurrent: () =>
              _currentSession(client, generation) &&
              identical(store, _draftStore),
        );
        if (!_currentSession(client, generation)) return;
        final created = catalog == null
            ? StudioMailStoredDraft(draft: prepared, submissionUncertain: false)
            : await catalog.createDraft(prepared);
        if (!_currentSession(client, generation)) return;
        setState(() {
          _draft = created.draft;
          _submissionUncertain = created.submissionUncertain;
          _error = null;
          _notice = null;
        });
      } on Object {
        if (_currentSession(client, generation)) {
          setState(() => _error = widget.strings.mailDraftListFailed);
        }
        return;
      } finally {
        if (_currentSession(client, generation)) setState(() => _busy = false);
      }
    } else if (initial != null && _draft != null) {
      setState(() {
        _error = widget.strings.mailRetainedDraft;
        _notice = null;
      });
      return;
    }
    if (!mounted || !_currentSession(client, generation)) return;
    final selectedId = catalog?.selectedDraftId;
    final selectionEpoch = catalog?.selectionEpoch;
    final mailbox = switch (store) {
      StudioMailMailboxStoreOwner value => value.mailboxStore,
      _ => null,
    };
    bool currentDraft() =>
        _currentSession(client, generation) &&
        identical(store, _draftStore) &&
        catalog?.selectedDraftId == selectedId &&
        catalog?.selectionEpoch == selectionEpoch;
    if (!StudioMailDraft.isSupportedAddress(account.email)) {
      setState(() => _error = widget.strings.mailInvalidSender);
      return;
    }
    StudioMailDraft? draft;
    setState(() => _dialogOpen = true);
    try {
      draft = await showDialog<StudioMailDraft>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StudioMailComposeDialog(
          strings: widget.strings,
          from: account.email,
          initialDraft: _draft ?? initial,
          previousSubmissionUncertain: _submissionUncertain,
          composeToolsStore: switch (store) {
            StudioMailComposeToolsStore value => value,
            _ => null,
          },
          isComposeToolsCurrent: currentDraft,
          onClearMailCache: mailbox == null
              ? null
              : () async {
                  if (!currentDraft()) {
                    throw const StudioMailDraftStoreException(
                      MailProblemCode.unavailable,
                    );
                  }
                  return mailbox.clearCache();
                },
          onQueueDraft: outbox != null
              ? (snapshot) async {
                  if (!currentDraft()) {
                    throw const StudioMailDraftStoreException(
                      MailProblemCode.unavailable,
                    );
                  }
                  await outbox.enqueueOutbox(snapshot, account.email);
                  if (_currentSession(client, generation)) {
                    setState(() {
                      _draft = null;
                      _submissionUncertain = false;
                      _error = null;
                      _notice = widget.strings.mailQueued;
                    });
                  }
                }
              : null,
          onSaveDraft: (snapshot) async {
            if (!currentDraft()) {
              throw const StudioMailDraftStoreException(
                MailProblemCode.unavailable,
              );
            }
            setState(() => _draft = snapshot);
            await store.save(
              snapshot,
              submissionUncertain: _submissionUncertain,
            );
          },
        ),
      );
    } finally {
      if (_currentSession(client, generation)) {
        setState(() => _dialogOpen = false);
      }
    }
    if (draft == null || !currentDraft()) return;
    if (outbox != null) {
      await _sendThroughOutbox(draft, outbox, client, account, generation);
      return;
    }
    // Preserve the immutable draft before handing anything to the transport.
    // An uncertain attempt is never automatically retried.
    setState(() {
      _draft = draft;
      _busy = true;
      _error = null;
      _notice = widget.strings.sending;
    });
    var attempted = false;
    try {
      final message = buildStudioMailMessage(draft, account.email);
      await store.save(draft, submissionUncertain: true);
      if (!_currentSession(client, generation)) return;
      _submissionUncertain = true;
      attempted = true;
      await client.sendMessage(
        message,
        appendToSent: false,
        recipients: [
          for (final address in draft.recipients.envelope)
            mail.MailAddress('', address),
        ],
      );
      final cleared = await _clearAcceptedDraft(store);
      if (_currentSession(client, generation)) {
        setState(() {
          _busy = false;
          _draft = cleared ? null : draft;
          _submissionUncertain = !cleared;
          _notice = cleared
              ? widget.strings.mailSubmissionAccepted
              : widget.strings.mailDraftAcceptedCleanupFailed;
        });
      }
    } on mail.MailSendPostSubmissionException catch (error) {
      final cleared = identical(error.mailClient, client)
          ? await _clearAcceptedDraft(store)
          : false;
      if (_currentSession(client, generation)) {
        setState(() {
          _busy = false;
          if (identical(error.mailClient, client)) {
            // SMTP acceptance is final for this draft even when subsequent
            // connection cleanup fails. Retrying would duplicate submission.
            _draft = cleared ? null : draft;
            _submissionUncertain = !cleared;
            _error = null;
            _notice = cleared
                ? widget.strings.mailSubmissionFollowUpFailed
                : widget.strings.mailDraftAcceptedCleanupFailed;
          } else {
            // An outcome from another client cannot confirm this submission.
            _notice = null;
            _submissionUncertain = attempted;
            _error = widget.strings.mailSubmissionUncertain;
          }
        });
      }
    } on Object catch (error) {
      if (_currentSession(client, generation)) {
        setState(() {
          _busy = false;
          _notice = null;
          _submissionUncertain = _submissionUncertain || attempted;
          _error = attempted
              ? widget.strings.mailSubmissionUncertain
              : error is StudioMailDraftStoreException
              ? widget.strings.mailDraftStorageFailed
              : widget.strings.mailInvalidSender;
        });
      }
    }
  });

  Future<void> _loadRemoteImages() async {
    final reader = _reader;
    if (reader == null ||
        reader.isDisposed ||
        _remoteImagesLoading ||
        reader.presentation.remoteImageUrls.isEmpty) {
      return;
    }
    final result = reader.result;
    final generation = _sessionGeneration;
    final loader =
        widget.remoteImageLoaderFactory?.call() ??
        StudioMailRemoteImageLoader();
    _remoteImageLoader = loader;
    _remoteImageOwner = reader;
    bool current() =>
        mounted &&
        !reader.isDisposed &&
        generation == _sessionGeneration &&
        identical(reader, _reader) &&
        identical(result, reader.result) &&
        identical(loader, _remoteImageLoader);
    setState(() {
      _remoteImagesLoading = true;
      _error = null;
    });
    try {
      await loader.loadInto(reader, isCurrent: current);
    } finally {
      if (mounted && identical(loader, _remoteImageLoader)) {
        setState(() {
          _remoteImagesLoading = false;
          _remoteImageLoader = null;
          _remoteImageOwner = null;
        });
      }
    }
  }

  Future<void> _reply() => _composeFromMessage(forward: false);

  Future<void> _replyAll() =>
      _composeFromMessage(forward: false, replyAll: true);

  Future<void> _forward() => _composeFromMessage(forward: true);

  Future<void> _forwardWithAttachments() =>
      _composeFromMessage(forward: true, includeAttachments: true);

  Future<void> _composeFromMessage({
    required bool forward,
    bool replyAll = false,
    bool includeAttachments = false,
  }) => runStudioMailOperation(() async {
    final account = _account;
    if (_busy || _dialogOpen || _client == null || account == null) return;
    if (_draft != null && _draftStore is! StudioMailDraftCatalog) {
      setState(() {
        _error = widget.strings.mailRetainedDraft;
        _notice = null;
      });
      return;
    }
    // The list item contains only an envelope. Quote the authoritative
    // bounded raw-message parse, never the reader's header presentation.
    final result = _reader?.result;
    final message = result?.message;
    if (result == null || message == null) return;
    try {
      final draft = includeAttachments
          ? buildStudioMailForwardWithAttachmentsDraft(
              result,
              truncationNotice: widget.strings.mailQuotedTextTruncated,
              forwardNotice: widget.strings.mailAttachedForwardNotice,
            )
          : replyAll
          ? buildStudioMailReplyAllDraft(
              message,
              sender: account.email,
              sourceStatus: result.status,
              truncationNotice: widget.strings.mailQuotedTextTruncated,
            )
          : buildStudioMailReplyDraft(
              message,
              forward: forward,
              sourceStatus: result.status,
              truncationNotice: widget.strings.mailQuotedTextTruncated,
              forwardNotice: widget.strings.mailTextOnlyForward,
            );
      await _openComposer(draft);
    } on StudioMailForwardAttachmentsUnavailable {
      setState(() {
        _error = widget.strings.mailForwardAttachmentsUnavailable;
        _notice = null;
      });
    } on StudioMailReplyRecipientsUnavailable {
      setState(() {
        _error = widget.strings.mailReplyRecipientsUnavailable;
        _notice = null;
      });
    } on StudioMailReplyUnavailable {
      setState(() {
        _error = widget.strings.mailPlainTextUnavailable;
        _notice = null;
      });
    }
  });

  Future<void> _discardDraft() async {
    final client = _client;
    final retained = _draft;
    if (client == null || retained == null || _busy || _dialogOpen) return;
    final generation = _sessionGeneration;
    bool? discard;
    setState(() => _dialogOpen = true);
    try {
      discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(widget.strings.mailDiscardDraft),
          content: Text(widget.strings.mailDiscardDraftExplanation),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(widget.strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.strings.mailDiscardDraft),
            ),
          ],
        ),
      );
    } finally {
      if (_currentSession(client, generation)) {
        setState(() => _dialogOpen = false);
      }
    }
    if (discard != true ||
        !_currentSession(client, generation) ||
        !identical(_draft, retained)) {
      return;
    }
    final store = _draftStore;
    if (store == null) return;
    setState(() => _busy = true);
    try {
      await store.clear();
    } on Object {
      if (_currentSession(client, generation)) {
        setState(() {
          _busy = false;
          _error = widget.strings.mailDraftSaveFailed;
        });
      }
      return;
    }
    if (!_currentSession(client, generation)) return;
    setState(() {
      _busy = false;
      _draft = null;
      _submissionUncertain = false;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _markRead() => _changeMessageFlags(read: true);

  Future<void> _changeMessageFlags({
    bool? read,
    bool? flagged,
  }) => runStudioMailOperation(() async {
    final client = _client;
    final loader = _messageLoader;
    final mailbox = _messageMailbox;
    final message = _selected;
    final actions = loader is StudioMailMessageActions
        ? loader as StudioMailMessageActions
        : null;
    if (client == null ||
        loader == null ||
        mailbox == null ||
        message == null ||
        _busy ||
        _dialogOpen ||
        _needsRefresh ||
        (read == null) == (flagged == null) ||
        actions == null && (read != true || message.isSeen)) {
      return;
    }
    if (loader is StudioMailMailboxRecords && actions != null) {
      await _changeCommands(
        read != null
            ? (read
                  ? MailBulkFlagAction.markRead
                  : MailBulkFlagAction.markUnread)
            : (flagged! ? MailBulkFlagAction.flag : MailBulkFlagAction.unflag),
        [_messageKey(message)],
        mailboxGeneration: _mailboxGeneration,
      );
      return;
    }
    final generation = _sessionGeneration;
    final uid = message.uid;
    final uidValidity = mailbox.uidValidity;
    final mailboxPath = mailbox.path;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (actions == null) {
        await loader.markRead(mailbox, message);
      } else if (read != null) {
        await actions.setRead(mailbox, message, read: read);
      } else {
        await actions.setFlagged(mailbox, message, flagged: flagged!);
      }
      if (!_currentSession(client, generation)) return;
      if (!identical(_selected, message) ||
          !identical(_messageLoader, loader) ||
          !identical(_messageMailbox, mailbox) ||
          message.uid != uid ||
          mailbox.uidValidity != uidValidity ||
          mailbox.path != mailboxPath) {
        throw const StudioMailMessageLoadException(MailProblemCode.conflict);
      }
      setState(() {
        _confirmedFlags[message] = (
          read: read ?? _observedRead(message),
          flagged: flagged ?? _observedFlagged(message),
        );
        if (read != null) message.setFlag(mail.MessageFlags.seen, read);
        if (flagged != null) {
          message.setFlag(mail.MessageFlags.flagged, flagged);
        }
        _busy = false;
        _notice = actions == null
            ? null
            : widget.strings.mailWorkspaceActionConfirmed;
      });
    } on Object {
      if (!_currentSession(client, generation)) return;
      setState(() {
        _busy = false;
        // An unconfirmed write may have reached the server. A new folder
        // observation is required; there is no automatic mutation retry.
        _needsRefresh = actions != null;
        _error = actions == null
            ? widget.strings.mailMarkReadFailed
            : widget.strings.mailWorkspaceRefreshRequired;
      });
    }
  });

  Future<void> _organizeSelected({required bool delete}) async {
    final client = _client;
    final loader = _messageLoader;
    final mailbox = _messageMailbox;
    final message = _selected;
    if (client == null ||
        loader is! StudioMailMembershipActions ||
        loader is! StudioMailMailboxRecords ||
        mailbox == null ||
        message == null ||
        _busy ||
        _dialogOpen ||
        _needsRefresh) {
      return;
    }
    final membership = loader as StudioMailMembershipActions;
    final records = loader as StudioMailMailboxRecords;
    final generation = _sessionGeneration;
    final mailboxGeneration = _mailboxGeneration;
    final path = mailbox.path;
    final validity = mailbox.uidValidity;
    final MailHeaderRecord header;
    try {
      header = records.observedHeader(mailbox, message);
      final remote = header.remote;
      if (remote is! MailImapIdentity ||
          remote.account != records.account ||
          remote.mailbox.value != path ||
          remote.uidValidity != validity ||
          remote.uid != message.uid) {
        throw const StudioMailMessageLoadException(MailProblemCode.conflict);
      }
    } on Object {
      setState(() {
        _needsRefresh = true;
        _error = widget.strings.mailWorkspaceRefreshRequired;
      });
      return;
    }
    final destinations = <MailMailbox>[
      for (final box in _mailboxes)
        if (!box.isNotSelectable &&
            box.path != path &&
            !(box.path.toUpperCase() == 'INBOX' &&
                path.toUpperCase() == 'INBOX'))
          MailMailbox(
            id: MailMailboxId(box.path, account: records.account),
            displayName: box.name,
          ),
    ];
    bool hostCurrent() =>
        _currentSession(client, generation) &&
        identical(loader, _messageLoader) &&
        mailboxGeneration == _mailboxGeneration;
    bool current() {
      if (!hostCurrent() ||
          !identical(message, _selected) ||
          !identical(mailbox, _messageMailbox) ||
          mailbox.path != path ||
          mailbox.uidValidity != validity) {
        return false;
      }
      try {
        return records.observedHeader(mailbox, message).remote == header.remote;
      } on Object {
        return false;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    MailMailboxId? destination;
    var accepted = false;
    try {
      final capabilities = await membership.membershipCapabilities();
      if (!mounted || !current()) return;
      setState(() => _membershipCapabilities = capabilities);
      if (!capabilities.supports(
            delete ? MailCapability.delete : MailCapability.move,
          ) ||
          !delete && destinations.isEmpty) {
        setState(() => _error = widget.strings.mailMutationUnavailable);
        return;
      }
      setState(() {
        _busy = false;
        _dialogOpen = true;
      });
      if (delete) {
        accepted =
            await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                key: const ValueKey('studio-mail-confirm-delete'),
                title: Text(widget.strings.mailMarkDeleted),
                content: Text(widget.strings.mailMarkDeletedExplanation),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(widget.strings.cancel),
                  ),
                  FilledButton(
                    key: const ValueKey('studio-mail-confirm-delete-apply'),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(widget.strings.mailMarkDeleted),
                  ),
                ],
              ),
            ) ==
            true;
      } else {
        destination = await showDialog<MailMailboxId>(
          context: context,
          builder: (context) => AlertDialog(
            key: const ValueKey('studio-mail-move-picker'),
            title: Text(widget.strings.mailMoveMessage),
            content: SizedBox(
              width: 480,
              height: 320,
              child: ListView.builder(
                itemCount: destinations.length,
                itemBuilder: (context, index) {
                  final folder = destinations[index];
                  return ListTile(
                    key: ValueKey('studio-mail-move-destination-$index'),
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(folder.displayName),
                    subtitle: Text(folder.id.value),
                    onTap: () => Navigator.pop(context, folder.id),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(widget.strings.cancel),
              ),
            ],
          ),
        );
        accepted = destination != null;
      }
    } on Object {
      if (hostCurrent()) {
        setState(() => _error = widget.strings.mailMutationCheckFailed);
      }
    } finally {
      if (hostCurrent()) {
        setState(() {
          _busy = false;
          _dialogOpen = false;
        });
      }
    }
    if (!accepted || !current()) return;
    await _changeCommands(
      delete ? MailBulkFlagAction.delete : MailBulkFlagAction.move,
      [_messageKey(message)],
      mailboxGeneration: mailboxGeneration,
      destination: destination,
      membershipConfirmed: true,
    );
  }

  Future<void> _organizeMessages(
    MailBulkFlagAction action,
    List<String> selectedIds, {
    required int mailboxGeneration,
    mail.MimeMessage? selectedMessage,
  }) async {
    final client = _client;
    final loader = _messageLoader;
    final mailbox = _messageMailbox;
    final account = _account;
    if (!mounted ||
        action.isFlagAction ||
        client == null ||
        account == null ||
        loader is! StudioMailMembershipActions ||
        loader is! StudioMailMailboxRecords ||
        mailbox == null ||
        _busy ||
        _dialogOpen ||
        _needsRefresh ||
        mailboxGeneration != _mailboxGeneration ||
        selectedIds.isEmpty ||
        selectedIds.length > MailBulkFlagPlan.maxMessages ||
        selectedIds.toSet().length != selectedIds.length) {
      return;
    }
    final membership = loader as StudioMailMembershipActions;
    final records = loader as StudioMailMailboxRecords;
    final ids = List<String>.unmodifiable(selectedIds);
    final archive = action == MailBulkFlagAction.archive;
    final generation = _sessionGeneration;
    final path = mailbox.path;
    final validity = mailbox.uidValidity;
    final source = MailMailbox(
      id: MailMailboxId(path, account: records.account),
      displayName: mailbox.name,
    );
    final targets = <mail.MimeMessage>[];
    final headers = <MailHeaderRecord>[];
    try {
      for (final id in ids) {
        final matches = _messages.where(
          (message) => _messageKey(message) == id,
        );
        if (matches.length != 1) return;
        final message = matches.single;
        final header = records.observedHeader(mailbox, message);
        final remote = header.remote;
        if (remote is! MailImapIdentity ||
            remote.account != records.account ||
            remote.mailbox != source.id ||
            remote.uidValidity != validity ||
            remote.uid != message.uid) {
          throw const StudioMailMessageLoadException(MailProblemCode.conflict);
        }
        targets.add(message);
        headers.add(header);
      }
    } on Object {
      setState(() {
        _needsRefresh = true;
        _error = widget.strings.mailWorkspaceRefreshRequired;
      });
      return;
    }
    final destinations = <MailMailbox>[
      for (final box in _mailboxes)
        if (!box.isNotSelectable &&
            box.path != path &&
            !(box.path.toUpperCase() == 'INBOX' &&
                path.toUpperCase() == 'INBOX'))
          MailMailbox(
            id: MailMailboxId(box.path, account: records.account),
            displayName: box.name,
          ),
    ];
    bool hostCurrent() =>
        _currentSession(client, generation) &&
        identical(loader, _messageLoader) &&
        identical(account, _account) &&
        mailboxGeneration == _mailboxGeneration;
    bool current() {
      if (!hostCurrent() ||
          (selectedMessage != null && !identical(_selected, selectedMessage)) ||
          !identical(mailbox, _messageMailbox) ||
          mailbox.path != path ||
          mailbox.uidValidity != validity ||
          records.account != source.id.account) {
        return false;
      }
      try {
        final loaded = Set<mail.MimeMessage>.identity()..addAll(_messages);
        for (var i = 0; i < targets.length; i++) {
          final message = targets[i];
          if (!loaded.contains(message) || _messageKey(message) != ids[i]) {
            return false;
          }
          final latest = records.observedHeader(mailbox, message);
          if (latest.id != headers[i].id ||
              latest.remote != headers[i].remote) {
            return false;
          }
        }
        return true;
      } on Object {
        return false;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    MailMailboxId? destination;
    MailMailbox? resolvedArchive;
    MailAccountSession? archiveResolutionSession;
    var accepted = false;
    try {
      final capabilities = await membership.membershipCapabilities();
      if (!mounted || !current()) return;
      setState(() => _membershipCapabilities = capabilities);
      if (!capabilities.supports(
            action == MailBulkFlagAction.move || archive
                ? MailCapability.move
                : MailCapability.delete,
          ) ||
          action == MailBulkFlagAction.move && destinations.isEmpty) {
        setState(() => _error = widget.strings.mailMutationUnavailable);
        return;
      }
      if (archive && loader is MailArchiveDestinationResolver) {
        archiveResolutionSession = MailAccountSession(records.account);
        final resolution = await (loader as MailArchiveDestinationResolver)
            .resolveArchiveDestination(archiveResolutionSession.begin());
        if (!mounted || !current()) return;
        switch (resolution) {
          case MailSuccess<MailMailbox>(:final value):
            if (value.id.account != records.account || value.isLabel) {
              setState(() => _error = widget.strings.mailMutationCheckFailed);
              return;
            }
            if (value.id == source.id ||
                value.id.value.toUpperCase() == 'INBOX' &&
                    path.toUpperCase() == 'INBOX') {
              setState(() => _notice = widget.strings.mailArchiveSameFolder);
              return;
            }
            resolvedArchive = value;
          case MailFailure<MailMailbox>(:final problem):
            if (problem.code != MailProblemCode.unsupported) {
              setState(() => _error = widget.strings.mailMutationCheckFailed);
              return;
            }
        }
      }
      setState(() {
        _busy = false;
        _dialogOpen = true;
      });
      if (archive) {
        destination = await showStudioMailArchiveSelection(
          context,
          strings: widget.strings,
          count: ids.length,
          accountLabel: account.email,
          source: source,
          destinations: destinations,
          resolvedDestination: resolvedArchive,
        );
        accepted = destination != null;
      } else if (action == MailBulkFlagAction.move) {
        destination = await showStudioMailMoveSelection(
          context,
          strings: widget.strings,
          count: ids.length,
          accountLabel: account.email,
          source: source,
          destinations: destinations,
        );
        accepted = destination != null;
      } else {
        accepted = await confirmStudioMailDeleteSelection(
          context,
          strings: widget.strings,
          count: ids.length,
          accountLabel: account.email,
          source: source,
          provider: MailProviderKind.imap,
        );
      }
    } on Object {
      if (hostCurrent()) {
        setState(() => _error = widget.strings.mailMutationCheckFailed);
      }
    } finally {
      archiveResolutionSession?.dispose();
      if (hostCurrent()) {
        setState(() {
          _busy = false;
          _dialogOpen = false;
        });
      }
    }
    if (!accepted || !current()) return;
    await _changeCommands(
      archive ? MailBulkFlagAction.move : action,
      ids,
      mailboxGeneration: mailboxGeneration,
      destination: destination,
      membershipConfirmed: true,
      resolvedArchiveDestination: resolvedArchive?.id,
    );
  }

  Future<void> _changeCommands(
    MailBulkFlagAction action,
    List<String> ids, {
    required int mailboxGeneration,
    MailMailboxId? destination,
    bool membershipConfirmed = false,
    MailMailboxId? resolvedArchiveDestination,
  }) => runStudioMailOperation(() async {
    final client = _client;
    final loader = _messageLoader;
    final mailbox = _messageMailbox;
    if (!mounted ||
        client == null ||
        (action.isFlagAction && loader is! StudioMailMessageActions) ||
        loader is! StudioMailMailboxRecords ||
        mailbox == null ||
        _busy ||
        _dialogOpen ||
        _needsRefresh ||
        mailboxGeneration != _mailboxGeneration ||
        ids.isEmpty ||
        ids.length > MailBulkFlagPlan.maxMessages ||
        ids.toSet().length != ids.length ||
        (!action.isFlagAction &&
            (!membershipConfirmed || loader is! StudioMailMembershipActions)) ||
        (action == MailBulkFlagAction.move &&
            (destination == null ||
                destination.value == mailbox.path ||
                (destination != resolvedArchiveDestination &&
                    !_mailboxes.any(
                      (folder) =>
                          !folder.isNotSelectable &&
                          folder.path == destination.value,
                    )) ||
                destination.account !=
                    (loader as StudioMailMailboxRecords).account)) ||
        (action != MailBulkFlagAction.move && destination != null)) {
      return;
    }
    final records = loader as StudioMailMailboxRecords;
    final generation = _sessionGeneration;
    final mailboxPath = mailbox.path;
    final uidValidity = mailbox.uidValidity;
    final account = records.account;
    final targets = <mail.MimeMessage>[];
    final observed = <MailHeaderRecord>[];
    final MailBulkFlagPlan plan;
    try {
      for (final id in ids) {
        final matches = _messages.where(
          (message) => _messageKey(message) == id,
        );
        if (matches.length != 1) return;
        final message = matches.single;
        final header = records.observedHeader(mailbox, message);
        final remote = header.remote;
        if (remote is! MailImapIdentity ||
            remote.account != account ||
            remote.mailbox.value != mailboxPath ||
            remote.uidValidity != uidValidity ||
            remote.uid != message.uid) {
          throw const StudioMailMessageLoadException(MailProblemCode.conflict);
        }
        targets.add(message);
        observed.add(header);
      }
      plan = MailBulkFlagPlan(
        id: newStudioMailFlagOperationId(),
        mailbox: MailMailboxId(mailboxPath, account: account),
        provider: MailProviderKind.imap,
        messages: [for (final header in observed) header.remote],
        action: action,
        destination: destination,
      );
    } on Object {
      if (_currentSession(client, generation)) {
        setState(() {
          _needsRefresh = true;
          _error = widget.strings.mailWorkspaceRefreshRequired;
        });
      }
      return;
    }

    bool currentHost() =>
        _currentSession(client, generation) &&
        identical(_messageLoader, loader) &&
        mailboxGeneration == _mailboxGeneration &&
        identical(_messageMailbox, mailbox);

    bool currentSelection() {
      if (!currentHost() ||
          records.account != account ||
          mailbox.path != mailboxPath ||
          mailbox.uidValidity != uidValidity) {
        return false;
      }
      try {
        final loaded = Set<mail.MimeMessage>.identity()..addAll(_messages);
        for (var i = 0; i < targets.length; i++) {
          final message = targets[i];
          final remote = observed[i].remote as MailImapIdentity;
          if (!loaded.contains(message) || message.uid != remote.uid) {
            return false;
          }
          final latest = records.observedHeader(mailbox, message);
          if (latest.id != observed[i].id || latest.remote != remote) {
            return false;
          }
        }
      } on Object {
        return false;
      }
      return true;
    }

    // This lease scopes the coordinator; the native loader retains ownership
    // of its own transport lease. Cancel stops later dispatches only.
    final session = MailAccountSession(account);
    final cancellation = MailCancellationSource();
    final owner = _draftStore;
    final settled = Completer<void>();
    _pendingFlagWrite = settled.future;
    final frozenMailbox = mailbox.copyWith();
    final byRemote = {
      for (var i = 0; i < targets.length; i++) observed[i].remote: targets[i],
    };
    setState(() {
      _bulkCancellation = cancellation;
      _bulkReport = null;
      _bulkSubjects = Map.unmodifiable({
        for (var i = 0; i < targets.length; i++)
          observed[i].remote: targets[i].decodeSubject() ?? '',
      });
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (!action.isFlagAction) {
        await _stopCachedView(retainMetadata: true);
      }
      final report = await MailBulkFlagCoordinator().run(
        plan: plan,
        lease: session.begin(),
        cancellation: cancellation.token,
        isScopeCurrent: currentSelection,
        journal: studioMailFlagJournal(
          owner: owner,
          requireDurable: widget.draftStoreFactory == null,
          sourceAccount: account,
          provider: MailProviderKind.imap,
          subjects: [for (final header in observed) header.envelope.subject],
          isCurrent: () => currentSelection() && identical(owner, _draftStore),
        ),
        onProgress: (report) {
          if (currentSelection() &&
              identical(_bulkCancellation, cancellation)) {
            setState(() => _bulkReport = report);
          }
        },
        apply: (operation, lease) async {
          if (operation is MailMove || operation is MailDelete) {
            if (loader is StudioMailMembershipReceiptActions) {
              return MailBulkFlagAttempt.fromReceiptResult(
                await (loader as StudioMailMembershipReceiptActions)
                    .applyMembershipWithReceipt(operation, lease),
              );
            }
            return MailBulkFlagAttempt.fromResult(
              await (loader as StudioMailMembershipActions).applyMembership(
                operation,
                lease,
              ),
            );
          }
          if (loader is StudioMailBulkMessageActions) {
            return MailBulkFlagAttempt.fromResult(
              await (loader as StudioMailBulkMessageActions).applyBulkFlag(
                operation,
                lease,
              ),
            );
          }
          final message = byRemote[operation.message]!;
          try {
            final actions = loader as StudioMailMessageActions;
            if (operation is MailSetRead) {
              await actions.setRead(
                frozenMailbox,
                message,
                read: operation.read,
              );
            } else if (operation is MailSetFlagged) {
              await actions.setFlagged(
                frozenMailbox,
                message,
                flagged: operation.flagged,
              );
            } else {
              return const MailBulkFlagAttempt.failed(
                MailProblem(MailProblemCode.unsupported),
              );
            }
            return const MailBulkFlagAttempt.confirmed();
          } on StudioMailMessageLoadException catch (error) {
            return MailBulkFlagAttempt.fromResult(
              MailFailure<MailUnit>(
                MailProblem(
                  error.code,
                  mutationMayHaveOccurred: error.mutationMayHaveOccurred,
                ),
              ),
            );
          }
        },
      );
      if (!currentHost()) return;
      if (!currentSelection()) {
        setState(() {
          // Keep evidence for the frozen identities even if their mailbox
          // generation changed. Never project its flags into the new scope.
          _bulkReport = report;
          _needsRefresh = true;
          _error = widget.strings.mailWorkspaceRefreshRequired;
        });
        return;
      }
      MailReaderController? retiredReader;
      setState(() {
        _bulkReport = report;
        for (var i = 0; i < report.items.length; i++) {
          final result = report.items[i];
          if (result.outcome != MailBulkFlagOutcome.confirmed) continue;
          final message = targets[i];
          final operation = result.operation;
          if (operation is MailMove || operation is MailDelete) {
            _nextHeaders = null;
            if (operation is MailMove) {
              _messages = _messages
                  .where((row) => !identical(row, message))
                  .toList();
              _confirmedFlags.remove(message);
              _repositoryFlags.remove(message);
              if (identical(_selected, message)) {
                retiredReader = _reader;
                _reader = null;
                _selected = null;
                _showCompactMessage = false;
              }
            } else {
              // IMAP Delete is a confirmed Deleted flag, never EXPUNGE.
              // Setting that bit must preserve unknown read/flag observations.
              _confirmedFlags[message] = (
                read: _observedRead(message),
                flagged: _observedFlagged(message),
              );
              message.setFlag(mail.MessageFlags.deleted, true);
            }
            continue;
          }
          _confirmedFlags[message] = (
            read: operation is MailSetRead
                ? operation.read
                : _observedRead(message),
            flagged: operation is MailSetFlagged
                ? operation.flagged
                : _observedFlagged(message),
          );
          if (operation is MailSetRead) {
            message.setFlag(mail.MessageFlags.seen, operation.read);
          } else if (operation is MailSetFlagged) {
            message.setFlag(mail.MessageFlags.flagged, operation.flagged);
          }
        }
        _notice = widget.strings.mailBulkSummary(report);
        if (report.requiresRefresh) {
          _needsRefresh = true;
          _error = widget.strings.mailWorkspaceRefreshRequired;
        }
      });
      if (retiredReader != null) _retireReader(retiredReader);
    } finally {
      session.dispose();
      settled.complete();
      if (identical(_pendingFlagWrite, settled.future)) {
        _pendingFlagWrite = null;
      }
      if (_currentSession(client, generation) &&
          identical(_bulkCancellation, cancellation)) {
        setState(() {
          _bulkCancellation = null;
          _busy = false;
        });
      }
    }
  });

  Future<void> _openFlagHistory() async {
    final client = _client;
    final owner = _draftStore;
    final loader = _messageLoader;
    if (client == null ||
        owner is! StudioMailFlagJournalOwner ||
        _busy ||
        _dialogOpen) {
      return;
    }
    final generation = _sessionGeneration;
    bool current() =>
        _currentSession(client, generation) &&
        identical(owner, _draftStore) &&
        identical(loader, _messageLoader);
    final store = (owner as StudioMailFlagJournalOwner).flagJournal;
    setState(() => _dialogOpen = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => StudioMailJournalDialog(
          strings: widget.strings,
          store: store,
          isCurrent: current,
          onReconcile: studioMailFlagRecovery(
            store: store,
            observer: loader,
            provider: MailProviderKind.imap,
            isCurrent: current,
            onChecked: () => setState(() {
              _needsRefresh = true;
              _error = widget.strings.mailWorkspaceRefreshRequired;
            }),
          ),
          onReconcileMembership: studioMailMembershipRecovery(
            store: store,
            observer: loader,
            provider: MailProviderKind.imap,
            isCurrent: current,
            onChecked: () => setState(() {
              _needsRefresh = true;
              _error = widget.strings.mailWorkspaceRefreshRequired;
            }),
          ),
        ),
      );
    } finally {
      if (current()) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _openSynchronization() async {
    final client = _client;
    final owner = _draftStore;
    final loader = _messageLoader;
    final selected = _messageMailbox;
    final store = switch (owner) {
      StudioMailMailboxStoreOwner value => value.mailboxStore,
      _ => null,
    };
    if (client == null ||
        selected == null ||
        selected.path != _mailbox?.path ||
        store == null ||
        store is! StudioMailSyncStore ||
        loader is! StudioMailMailboxSynchronizer ||
        (loader as StudioMailMailboxSynchronizer).account != store.account ||
        _busy ||
        _dialogOpen) {
      return;
    }
    final syncStore = store as StudioMailSyncStore;
    final synchronizer = loader as StudioMailMailboxSynchronizer;
    final generation = _sessionGeneration;
    final mailboxGeneration = _mailboxGeneration;
    final frozen = selected.copyWith();
    bool current() =>
        _currentSession(client, generation) &&
        mailboxGeneration == _mailboxGeneration &&
        identical(owner, _draftStore) &&
        identical(loader, _messageLoader);
    final mailbox = MailMailbox(
      id: MailMailboxId(frozen.path, account: store.account),
      displayName: frozen.name,
    );
    setState(() => _dialogOpen = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StudioMailSyncDialog(
          strings: widget.strings,
          mailboxStore: store,
          syncStore: syncStore,
          mailbox: mailbox,
          isCurrent: current,
          download: loader is StudioMailBodyDownloader
              ? ({
                  required headers,
                  required cancellation,
                  required onProgress,
                }) => (loader as StudioMailBodyDownloader).downloadMessages(
                  frozen,
                  headers: headers,
                  cache: StudioMailBodyDownloadCache(store),
                  cancellation: cancellation,
                  onProgress: onProgress,
                  isCurrent: current,
                )
              : null,
          run: ({required cancellation, required onProgress}) async {
            if (!current()) {
              throw const StudioMailMessageLoadException(
                MailProblemCode.staleOperation,
              );
            }
            final saved = await syncStore.saveSyncMailbox(mailbox);
            if (saved case MailFailure<MailUnit>(:final problem)) {
              throw StudioMailMessageLoadException(problem.code);
            }
            if (!current()) {
              throw const StudioMailMessageLoadException(
                MailProblemCode.staleOperation,
              );
            }
            return synchronizer.synchronizeMailbox(
              frozen,
              repository: syncStore,
              cancellation: cancellation,
              onProgress: onProgress,
            );
          },
        ),
      );
    } finally {
      if (current()) setState(() => _dialogOpen = false);
    }
  }

  bool _credentialMatchesTarget(
    StudioMailCredentials credentials,
    StudioMailAccountNavigationTarget target,
  ) {
    if (target.provider != MailProviderKind.imap) return false;
    final route = credentials.connectionIdentity;
    try {
      final identity = StudioMailDraftAccount(
        provider: 'imap',
        endpoint: Uri(
          scheme: route.imapStartTls ? 'imap' : 'imaps',
          host: route.imapHost,
          port: route.imapPort,
        ).toString(),
        login: route.imapLogin,
        sender: route.sender,
      );
      return identity.account == target.identity.account;
    } on Object {
      return false;
    }
  }

  void _prefillNavigationTarget(StudioMailAccountNavigationTarget target) {
    if (target.provider != MailProviderKind.imap) {
      throw const StudioMailDraftStoreException(MailProblemCode.invalidInput);
    }
    _clearAccountSettings();
    _navigationTarget = target;
    _explicitAccountNavigation = true;
    _autoConnectTicket = null;
    _email.text = target.identity.sender;
    final endpoint = Uri.parse(target.identity.endpoint);
    _imapHost.text = endpoint.host;
    _manual = true;
    _startTls = endpoint.scheme == 'imap';
    // The local directory has no SMTP route or password. Discovery/manual
    // setup remains explicit and its resulting identity must match the target.
    _notice = widget.strings.mailAccountNavigationReconnectHelp;
  }

  Future<void> _loadNavigationTarget(
    StudioMailAccountNavigationTarget target,
  ) async {
    final directory = _localAccounts;
    if (directory == null) {
      throw const StudioMailDraftStoreException(MailProblemCode.unavailable);
    }
    final entryGeneration = _sessionGeneration;
    final entryCredentials = _credentialStoreRevision;
    await target.validateCurrent(directory);
    if (!_currentAttempt(entryGeneration) ||
        entryCredentials != _credentialStoreRevision) {
      return;
    }
    setState(() => _prefillNavigationTarget(target));
    final generation = _sessionGeneration;
    final storeRevision = _credentialStoreRevision;
    final settingsRevision = _settingsRevision;
    final credentialGeneration = ++_credentialGeneration;
    bool current() =>
        _currentAttempt(generation) &&
        storeRevision == _credentialStoreRevision &&
        credentialGeneration == _credentialGeneration &&
        settingsRevision == _settingsRevision &&
        identical(_navigationTarget, target);
    final catalogStore = _accountCatalogStore;
    try {
      if (catalogStore != null) {
        final result = await catalogStore.loadAccounts();
        if (!current()) return;
        if (!result.isSuccess) {
          setState(
            () => _credentialError = widget.strings.mailAccountsLoadFailed,
          );
          return;
        }
        final catalog = result.catalog!;
        final matches = catalog.accounts
            .where(
              (entry) => _credentialMatchesTarget(entry.credentials, target),
            )
            .toList();
        setState(() {
          _accountCatalog = catalog;
          if (matches.length == 1) {
            _applySavedAccount(matches.single);
          } else {
            // Several SMTP routes can own the same existing draft namespace.
            // Leave the remembered chooser available for an explicit choice.
            _notice = widget.strings.mailAccountNavigationRouteUnavailable;
          }
        });
      } else {
        final saved = await _credentials.load();
        if (!current()) return;
        if (saved != null && _credentialMatchesTarget(saved, target)) {
          setState(() {
            _applyCredentials(saved);
            _hasSavedCredentials = true;
          });
        }
      }
    } on Object {
      if (current()) {
        setState(
          () => _credentialError = widget.strings.mailAccountsLoadFailed,
        );
      }
    }
  }

  Future<void> _openAccountNavigation() async {
    final directory = _localAccounts;
    if (directory == null ||
        _accountNavigationPending ||
        _retiredNavigationStore != null ||
        _busy ||
        _dialogOpen ||
        _connecting ||
        _credentialPending) {
      return;
    }
    final generation = _sessionGeneration;
    final credentialRevision = _credentialStoreRevision;
    bool current() =>
        _currentAttempt(generation) &&
        credentialRevision == _credentialStoreRevision;
    setState(() {
      _accountNavigationPending = true;
      _dialogOpen = true;
      _autoConnectTicket = null;
    });
    try {
      final target = await showStudioMailAccountNavigation(
        context: context,
        strings: widget.strings,
        store: directory,
        currentAccount: _account == null ? null : _imapLocalIdentity(_account!),
        isCurrent: current,
      );
      if (!current() || target == null) return;
      await target.validateCurrent(directory);
      if (!current()) return;
      final draft = _draft;
      if (draft != null) {
        final store = _draftStore;
        if (store == null) {
          throw const StudioMailDraftStoreException(
            MailProblemCode.unavailable,
          );
        }
        try {
          await store.save(draft, submissionUncertain: _submissionUncertain);
        } on Object {
          if (current()) {
            setState(() => _error = widget.strings.mailDraftSaveFailed);
          }
          return;
        }
      }
      if (!current()) return;
      // A selection can be forgotten while the old draft is being saved.
      await target.validateCurrent(directory);
      if (!current()) return;
      try {
        await _draftRestoreInFlight;
        await _requireReleasedDraftStores();
        if (!current()) return;
        await _stopCachedViewForNavigation();
        await _mailboxViewClosing;
        await _pendingFlagWrite;
        if (!current()) return;
        await _draftStore?.close();
      } on Object {
        if (current()) _holdNavigationAccount();
        rethrow;
      }
      if (!current()) return;
      _draftStore = null;
      _explicitAccountNavigation = true;
      _disconnect();
      await _transportClosing;
      await _draftStoreClosing;
      if (!mounted) return;
      await target.validateCurrent(directory);
      if (!mounted) return;
      if (target.provider == MailProviderKind.imap) {
        await _loadNavigationTarget(target);
      } else {
        _navigationTarget = null;
        await _routeProviderAccounts(target.provider, target: target);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = _retiredNavigationStore == null
              ? widget.strings.mailAccountNavigationFailed
              : widget.strings.mailDraftStorageFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _accountNavigationPending = false;
          _dialogOpen = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _openProviderSetup(MailProviderKind provider) async {
    if (_accountNavigationPending ||
        _retiredNavigationStore != null ||
        _busy ||
        _dialogOpen ||
        _connecting ||
        _credentialPending ||
        _client != null) {
      return;
    }
    setState(() {
      _accountNavigationPending = true;
      _explicitAccountNavigation = true;
      _autoConnectTicket = null;
      _dialogOpen = true;
    });
    try {
      await _draftRestoreInFlight;
      await _requireReleasedDraftStores();
      await _transportClosing;
      if (mounted) await _routeProviderAccounts(provider);
    } on Object {
      if (mounted) {
        setState(() => _error = widget.strings.mailAccountNavigationFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _accountNavigationPending = false;
          _dialogOpen = false;
        });
      }
    }
  }

  Future<void> _stopCachedViewForNavigation() async {
    final session = _mailboxViewSession;
    final subscription = _mailboxViewSubscription;
    _mailboxCapture?.invalidateView();
    await _mailboxViewClosing;
    // A visible account transition cannot discard a failed cancellation's
    // ownership handles. Only retire them after both independent drains finish.
    await Future.wait<void>([
      if (session != null) session.close(),
      if (subscription != null) subscription.cancel(),
    ]);
    if (identical(_mailboxViewSession, session)) _mailboxViewSession = null;
    if (identical(_mailboxViewSubscription, subscription)) {
      _mailboxViewSubscription = null;
    }
    _repositoryFlags.clear();
  }

  Future<void> _retryNavigationRelease() async {
    if (_retiredNavigationStore == null ||
        _accountNavigationPending ||
        _connecting) {
      return;
    }
    setState(() => _accountNavigationPending = true);
    try {
      await _releaseRetiredNavigationAccount();
      if (mounted) setState(() => _error = null);
    } on Object {
      if (mounted) {
        setState(() => _error = widget.strings.mailDraftStorageFailed);
      }
    } finally {
      if (mounted) setState(() => _accountNavigationPending = false);
    }
  }

  void _holdNavigationAccount() {
    _retiredNavigationStore = _draftStore;
    _retiredNavigationView = _mailboxViewSession;
    _retiredNavigationSubscription = _mailboxViewSubscription;
    _draftStore = null;
    _mailboxViewSession = null;
    _mailboxViewSubscription = null;
    _explicitAccountNavigation = true;
    // Normal disconnection may retire transport and UI state, but must never
    // lose failed observer handles or close the owner they still reference.
    _disconnect();
  }

  Future<void> _releaseRetiredNavigationAccount() {
    if (_retiredNavigationClosing case final closing?) return closing;
    final owner = _retiredNavigationStore;
    final session = _retiredNavigationView;
    final subscription = _retiredNavigationSubscription;
    if (owner == null && session == null && subscription == null) {
      return Future<void>.value();
    }
    late final Future<void> result;
    result =
        () async {
          await _mailboxViewClosing;
          await Future.wait<void>([
            if (session != null) session.close(),
            if (subscription != null) subscription.cancel(),
          ]);
          if (identical(_retiredNavigationView, session)) {
            _retiredNavigationView = null;
          }
          if (identical(_retiredNavigationSubscription, subscription)) {
            _retiredNavigationSubscription = null;
          }
          // A transport reply can still owe the repository its durable receipt.
          // Drain those operations before releasing the held exclusive owner.
          await _transportClosing;
          await _pendingFlagWrite;
          await _draftStoreClosing;
          await owner?.close();
          if (identical(_retiredNavigationStore, owner)) {
            _retiredNavigationStore = null;
          }
        }().whenComplete(() {
          if (identical(_retiredNavigationClosing, result)) {
            _retiredNavigationClosing = null;
          }
        });
    return _retiredNavigationClosing = result;
  }

  void _disconnectFromUi() {
    if (_accountNavigationPending ||
        _navigationOwnerPending ||
        _retiredNavigationStore != null) {
      return;
    }
    _disconnect();
  }

  Future<void> _refreshMailbox() async {
    final mailbox = _mailbox;
    if (mailbox == null ||
        _accountNavigationPending ||
        _navigationOwnerPending ||
        _retiredNavigationStore != null) {
      return;
    }
    await _selectMailbox(mailbox);
  }

  Future<void> _routeProviderAccounts(
    MailProviderKind provider, {
    StudioMailAccountNavigationTarget? target,
  }) async {
    var nextProvider = provider;
    var nextTarget = target;
    while (mounted) {
      final chosenProvider = nextProvider;
      final chosenTarget = nextTarget;
      var routeRetired = false;
      final returned = await showDialog<StudioMailAccountNavigationTarget>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          void navigate(StudioMailAccountNavigationTarget value) {
            if (routeRetired ||
                !dialogContext.mounted ||
                ModalRoute.of(dialogContext)?.isCurrent != true) {
              return;
            }
            routeRetired = true;
            Navigator.of(dialogContext).pop(value);
          }

          final builder = widget.accountDestinationBuilder;
          if (builder != null) {
            return builder(
              dialogContext,
              chosenProvider,
              chosenTarget,
              navigate,
            );
          }
          if (chosenProvider == MailProviderKind.ews) {
            return StudioMailEwsDialog(
              strings: widget.strings,
              initialAccount: chosenTarget,
              onAccountNavigation: navigate,
              draftStoreFactory: widget.draftStoreFactory,
              localAccountStore: _localAccounts,
            );
          }
          return StudioMailCloudDialog(
            strings: widget.strings,
            service: chosenProvider == MailProviderKind.gmail
                ? MailCloudService.gmail
                : MailCloudService.microsoft365,
            initialAccount: chosenTarget,
            onAccountNavigation: navigate,
            draftStoreFactory: widget.draftStoreFactory,
            localAccountStore: _localAccounts,
          );
        },
      ).whenComplete(() => routeRetired = true);
      if (!mounted || returned == null) return;
      final directory = _localAccounts;
      if (directory == null) {
        throw const StudioMailDraftStoreException(MailProblemCode.unavailable);
      }
      await returned.validateCurrent(directory);
      if (!mounted) return;
      if (returned.provider == MailProviderKind.imap) {
        await _loadNavigationTarget(returned);
        return;
      }
      nextProvider = returned.provider;
      nextTarget = returned;
    }
  }

  Future<void> _switchAccount() async {
    final client = _client;
    if (client == null ||
        _busy ||
        _dialogOpen ||
        _connecting ||
        _credentialPending) {
      return;
    }
    final generation = _sessionGeneration;
    final draft = _draft;
    setState(() => _busy = true);
    try {
      if (draft != null) {
        final store = _draftStore;
        if (store == null) {
          throw const StudioMailDraftStoreException(
            MailProblemCode.unavailable,
          );
        }
        // A composer may retain edits after a failed autosave. Switching must
        // first commit those edits to the current account's own draft store.
        await store.save(draft, submissionUncertain: _submissionUncertain);
      }
      if (!_currentSession(client, generation)) return;
      _disconnect();
      final saved = _accountCatalog?.accounts
          .where((entry) => entry.id == _selectedSavedAccountId)
          .firstOrNull;
      if (saved != null) setState(() => _applySavedAccount(saved));
    } on Object {
      if (_currentSession(client, generation)) {
        setState(() => _error = widget.strings.mailDraftSaveFailed);
      }
    } finally {
      if (_currentSession(client, generation)) setState(() => _busy = false);
    }
  }

  void _disconnect() {
    _mailboxGeneration++;
    _bulkCancellation?.cancel(MailCancellationReason.accountChanged);
    _bulkCancellation = null;
    _sessionGeneration++;
    unawaited(_stopCachedView());
    _mailboxCapture?.dispose();
    _mailboxCapture = null;
    final draftStore = _draftStore;
    _draftStore = null;
    final client = _client;
    final pending = _pendingClient;
    final loader = _messageLoader;
    final pendingLoader = _pendingLoader;
    final previous = _reader;
    setState(() {
      _client = null;
      _pendingClient = null;
      _messageLoader = null;
      _membershipCapabilities = const MailCapabilities.none();
      _pendingLoader = null;
      _messageMailbox = null;
      _reader = null;
      _busy = false;
      _dialogOpen = false;
      _connecting = false;
      _account = null;
      _draft = null;
      _submissionUncertain = false;
      _password.clear();
      _lastCredentialSnapshot = null;
      _mailboxes = const <mail.Mailbox>[];
      _mailbox = null;
      _messages = const <mail.MimeMessage>[];
      _nextHeaders = null;
      _usedHeaderCursors.clear();
      _confirmedFlags.clear();
      _needsRefresh = false;
      _bulkReport = null;
      _bulkSubjects = const {};
      _selected = null;
      _showCompactMessage = false;
      _error = null;
      _notice = null;
      _cacheViewWarning = null;
      _cacheBodyWarning = null;
    });
    _retireReader(previous);
    loader?.dispose();
    pendingLoader?.dispose();
    _transportClosing = Future.wait<void>([
      _transportClosing,
      _disconnectQuietly(client),
      _disconnectQuietly(pending),
    ]).then<void>((_) {});
    unawaited(_transportClosing);
    _draftStoreClosing = _draftStoreClosing.then(
      (_) => _closeDraftStore(draftStore),
    );
    unawaited(_draftStoreClosing);
  }

  Future<void> _openLocalAccounts() async {
    final directory = _localAccounts;
    if (directory == null ||
        _retiredNavigationStore != null ||
        _accountNavigationPending ||
        _client != null ||
        _busy ||
        _dialogOpen ||
        _connecting ||
        _credentialPending) {
      return;
    }
    final generation = _sessionGeneration;
    bool current() => _currentAttempt(generation) && _client == null;
    setState(() {
      _busy = true;
      _dialogOpen = true;
    });
    try {
      await _draftStoreClosing;
      if (!mounted || !current()) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StudioMailLocalAccountsDialog(
          strings: widget.strings,
          store: directory,
          isCurrent: current,
          draftStoreFactory: widget.draftStoreFactory,
        ),
      );
    } on Object {
      if (current()) {
        setState(() => _error = widget.strings.mailLocalAccountsFailed);
      }
    } finally {
      if (current()) {
        setState(() {
          _busy = false;
          _dialogOpen = false;
        });
      }
    }
  }

  /// Only explicit server settings/presets reproduce the connected draft key.
  /// Historical autodiscovery records do not retain custom ports or logins.
  StudioMailSavedAccount? get _localDraftSavedAccount {
    final saved = _accountCatalog?.accounts
        .where((entry) => entry.id == _selectedSavedAccountId)
        .firstOrNull;
    if (saved == null ||
        !saved.credentials.manual && saved.credentials.preset == null ||
        _manual != saved.credentials.manual ||
        _preset != saved.credentials.preset) {
      return null;
    }
    final form = StudioMailCredentials(
      email: _email.text,
      password: '',
      imapHost: _imapHost.text,
      smtpHost: _smtpHost.text,
      manual: _manual,
      startTls: _startTls,
      preset: _preset,
      primaryLogin: _primaryLogin.text,
      icloudFullAddressLogin: _icloudFullAddressLogin,
    ).connectionIdentity;
    return form == saved.credentials.connectionIdentity ? saved : null;
  }

  Future<void> _openLocalDrafts() async {
    final saved = _localDraftSavedAccount;
    if (saved == null ||
        _retiredNavigationStore != null ||
        _accountNavigationPending ||
        _client != null ||
        _busy ||
        _dialogOpen ||
        _connecting ||
        _credentialPending) {
      return;
    }
    final generation = _sessionGeneration;
    final settings = _settingsRevision;
    final credentials = _credentialStoreRevision;
    final connection = saved.credentials.connectionIdentity;
    final StudioMailDraftAccount identity;
    try {
      identity = StudioMailDraftAccount(
        provider: 'imap',
        endpoint: Uri(
          scheme: connection.imapStartTls ? 'imap' : 'imaps',
          host: connection.imapHost,
          port: connection.imapPort,
        ).toString(),
        login: connection.imapLogin,
        sender: connection.sender,
      );
    } on Object {
      setState(() => _error = widget.strings.mailDraftStorageFailed);
      return;
    }
    bool current() =>
        _currentAttempt(generation) &&
        _client == null &&
        _settingsRevision == settings &&
        _credentialStoreRevision == credentials &&
        _selectedSavedAccountId == saved.id;
    setState(() {
      _busy = true;
      _dialogOpen = true;
      _error = null;
    });
    try {
      await _draftStoreClosing;
      if (!mounted || !current()) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StudioMailLocalDraftsDialog(
          strings: widget.strings,
          identity: identity,
          sender: connection.sender,
          isCurrent: current,
          draftStoreFactory: widget.draftStoreFactory,
        ),
      );
    } on Object {
      if (current()) {
        setState(() => _error = widget.strings.mailDraftStorageFailed);
      }
    } finally {
      if (_currentAttempt(generation)) {
        setState(() {
          _busy = false;
          _dialogOpen = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(
    absorbing: _accountNavigationPending,
    child: ExcludeFocus(
      excluding: _accountNavigationPending,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Column(
          children: [
            if (widget.chromeBuilder != null)
              widget.chromeBuilder!(context)
            else if (Theme.of(context).platform == TargetPlatform.macOS)
              const SizedBox(height: 32),
            _mailChrome(context),
            if (_retiredNavigationStore != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    Text(widget.strings.mailAccountNavigationReleaseHelp),
                    OutlinedButton.icon(
                      key: const ValueKey('studio-mail-navigation-release'),
                      onPressed: _accountNavigationPending
                          ? null
                          : _retryNavigationRelease,
                      icon: const Icon(Icons.refresh),
                      label: Text(widget.strings.mailAccountNavigationRelease),
                    ),
                  ],
                ),
              ),
            if (_accountNavigationPending) const LinearProgressIndicator(),
            Expanded(
              child: RepaintBoundary(
                child: LayoutBuilder(
                  builder: (context, constraints) => IndexedStack(
                    index: _showSavedMessages ? 1 : 0,
                    children: <Widget>[
                      _accountView(
                        context,
                        compact: constraints.maxWidth < 800,
                      ),
                      if (_savedMessagesVisited)
                        StudioSavedMailView(
                          strings: widget.strings,
                          onClose: widget.onClose,
                          onAccounts: () =>
                              setState(() => _showSavedMessages = false),
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  bool get _hasCredentialSettings =>
      widget.credentialStore == null || widget.credentialSettingsOpener != null;

  bool get _vaultUnlockAvailable =>
      widget.credentialStore == null &&
      StudioCredentialStorage.instance.mode ==
          StudioCredentialMode.encryptedVault;

  bool get _canChangeCredentialStorage =>
      _hasCredentialSettings &&
      !_credentialPending &&
      !_credentialSettingsOpen &&
      !_connecting &&
      !_busy &&
      !_dialogOpen &&
      !_accountNavigationPending;

  void _credentialStorageChanged() {
    if (!mounted) return;
    _credentialStoreRevision++;
    if (_credentialSettingsOpen) {
      _credentialStoreChangePending = true;
      return;
    }
    unawaited(_reloadSelectedCredentialStore());
  }

  Future<void> _reloadSelectedCredentialStore() async {
    if (!mounted) return;
    _credentialGeneration++;
    setState(() {
      _credentialPending = false;
      _accountCatalog = null;
      _selectedSavedAccountId = null;
      _hasSavedCredentials = false;
      if (_client == null) {
        // An empty or unavailable newly selected store must never leave the
        // previous store's password or Forget target in the account form.
        _clearAccountSettings();
      }
      _credentialError = _client != null && _lastCredentialSnapshot != null
          ? 'Save this connected account to the selected credential store.'
          : null;
    });
    await _loadCredentials();
  }

  void _scheduleVaultUnlockPrompt() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_promptVaultUnlock());
    });
  }

  /// Unlocks the selected encrypted vault after the password-protected catalog
  /// could not be read. The selection is never changed and no fallback store is
  /// used; cancelling leaves the explicit manual-account path available.
  Future<void> _promptVaultUnlock() async {
    if (!mounted ||
        _vaultUnlockPromptOpen ||
        _dialogOpen ||
        _credentialPending ||
        _connecting ||
        _busy ||
        _client != null ||
        widget.credentialStore != null) {
      return;
    }
    final manager = StudioCredentialStorage.instance;
    try {
      await manager.loadSelection();
    } on Object {
      return;
    }
    if (!mounted || manager.mode != StudioCredentialMode.encryptedVault) {
      return;
    }
    final bool exists;
    try {
      exists = await manager.vaultExists();
    } on Object {
      return;
    }
    if (!exists || !mounted) return;
    // If another path already unlocked the vault, the load failure is not a
    // lock problem. Do not retry in a loop or ask for the password.
    try {
      await manager.storage;
      return;
    } on Object {
      // Locked, as expected. Continue with the prompt.
    }
    if (!mounted || _dialogOpen || _credentialPending) return;
    _vaultUnlockPromptOpen = true;
    setState(() => _dialogOpen = true);
    var outcome = StudioVaultUnlockOutcome.cancelled;
    try {
      // Touch ID first when turned on; the master password otherwise.
      outcome = await unlockStudioCredentialVault(
        context,
        manager: manager,
        strings: widget.strings,
      );
    } finally {
      _vaultUnlockPromptOpen = false;
      if (mounted) setState(() => _dialogOpen = false);
    }
    if (outcome == StudioVaultUnlockOutcome.cancelled || !mounted) return;
    await _loadCredentials();
    if (mounted &&
        outcome == StudioVaultUnlockOutcome.unlockedTouchIdNotEnabled) {
      setState(
        () => _credentialError = manager.biometricCleanupPending
            ? widget.strings.vaultTouchIdCleanupPending
            : widget.strings.vaultTouchIdEnableFailed,
      );
    }
  }

  Future<void> _openCredentialStorage() async {
    if (!_canChangeCredentialStorage) return;
    setState(() {
      _credentialSettingsOpen = true;
      _dialogOpen = true;
    });
    var changed = false;
    try {
      final open =
          widget.credentialSettingsOpener ??
          (context) =>
              showStudioCredentialSettings(context, strings: widget.strings);
      changed = await open(context);
    } on Object {
      if (mounted) {
        setState(
          () => _credentialError = widget.strings.mailAccountsLoadFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _credentialSettingsOpen = false;
          _dialogOpen = false;
        });
      }
    }
    if (!mounted || !changed && !_credentialStoreChangePending) return;
    _credentialStoreChangePending = false;
    await _reloadSelectedCredentialStore();
  }

  Widget _mailChrome(BuildContext context) {
    final theme = Theme.of(context);
    final Color foreground = theme.colorScheme.onSurface;
    Widget command({
      Key? key,
      required IconData icon,
      required String tooltip,
      VoidCallback? onPressed,
      bool selected = false,
    }) => IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      iconSize: 19,
      icon: Icon(
        icon,
        color: onPressed == null
            ? theme.disabledColor
            : selected
            ? theme.colorScheme.primary
            : foreground,
      ),
    );
    Widget imagesCommand() => command(
      key: const ValueKey('studio-mail-show-images'),
      icon: _remoteImagesLoading ? Icons.hourglass_top : Icons.image_outlined,
      tooltip: 'Show remote images',
      onPressed:
          _reader == null ||
              _remoteImagesLoading ||
              _reader!.presentation.remoteImageUrls.isEmpty
          ? null
          : _loadRemoteImages,
    );
    final groups = <StudioRibbonGroup>[
      StudioRibbonGroup(
        id: 'compose',
        title: 'Compose',
        children: <Widget>[
          TextButton.icon(
            key: const ValueKey('studio-mail-compose'),
            onPressed: _client == null || _busy ? null : _compose,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(widget.strings.compose),
          ),
          if (_draft != null)
            command(
              icon: Icons.delete_outline,
              tooltip: widget.strings.mailDiscardDraft,
              onPressed: _busy || _dialogOpen ? null : _discardDraft,
            ),
        ],
      ),
      StudioRibbonGroup(
        id: 'mailbox',
        title: 'Mailbox',
        children: <Widget>[
          if (_localAccounts != null)
            command(
              key: const ValueKey('studio-mail-navigate-account'),
              icon: Icons.manage_accounts_outlined,
              tooltip: widget.strings.mailAccountNavigationTitle,
              onPressed:
                  _busy ||
                      _dialogOpen ||
                      _connecting ||
                      _credentialPending ||
                      _retiredNavigationStore != null ||
                      _accountNavigationPending
                  ? null
                  : _openAccountNavigation,
            ),
          if (_messageLoader is StudioMailMailboxSynchronizer &&
              _draftStore is StudioMailMailboxStoreOwner)
            command(
              key: const ValueKey('studio-mail-open-sync'),
              icon: Icons.sync,
              tooltip: widget.strings.mailSync,
              onPressed: _busy || _dialogOpen || _mailbox == null
                  ? null
                  : _openSynchronization,
            ),
          command(
            icon: Icons.refresh,
            tooltip: widget.strings.refresh,
            onPressed: _client != null && !_busy && _mailbox != null
                ? _refreshMailbox
                : null,
          ),
          command(
            key: const ValueKey('studio-mail-open-drafts'),
            icon: Icons.drafts_outlined,
            tooltip: widget.strings.mailDrafts,
            onPressed: _client == null || _busy || _dialogOpen
                ? null
                : _openDrafts,
          ),
          command(
            key: const ValueKey('studio-mail-open-outbox'),
            icon: Icons.outbox_outlined,
            tooltip: widget.strings.mailOutbox,
            onPressed: _client == null || _busy || _dialogOpen
                ? null
                : _openOutbox,
          ),
          if (_draftStore is StudioMailFlagJournalOwner)
            command(
              key: const ValueKey('studio-mail-open-activity'),
              icon: Icons.history,
              tooltip: widget.strings.mailActivity,
              onPressed: _busy || _dialogOpen ? null : _openFlagHistory,
            ),
          if (_accountCatalogStore != null)
            command(
              key: const ValueKey('studio-mail-switch-account'),
              icon: Icons.switch_account_outlined,
              tooltip: widget.strings.mailSwitchAccount,
              onPressed: _busy || _dialogOpen || _credentialPending
                  ? null
                  : _switchAccount,
            ),
          command(
            icon: Icons.logout,
            tooltip: widget.strings.disconnect,
            onPressed:
                _client == null ||
                    _accountNavigationPending ||
                    _navigationOwnerPending
                ? null
                : _disconnectFromUi,
          ),
        ],
      ),
      StudioRibbonGroup(
        id: 'view',
        title: 'View',
        children: <Widget>[
          if (_reader case final reader?)
            ListenableBuilder(
              listenable: reader,
              builder: (context, child) => imagesCommand(),
            )
          else
            imagesCommand(),
          command(
            key: const ValueKey('studio-mail-saved-messages'),
            icon: Icons.folder_open_outlined,
            tooltip: widget.strings.savedMessages,
            selected: _showSavedMessages,
            onPressed: _busy || _connecting
                ? null
                : () => setState(() {
                    _savedMessagesVisited = true;
                    _showSavedMessages = true;
                  }),
          ),
          if (_hasCredentialSettings)
            command(
              key: const ValueKey('studio-mail-credential-storage'),
              icon: Icons.key,
              tooltip: 'Credential storage',
              onPressed: _canChangeCredentialStorage
                  ? _openCredentialStorage
                  : null,
            ),
          // The saved-message view brings its own Close (it is shared with
          // browser Studio); offering a second one here duplicates the action.
          if (!_showSavedMessages)
            command(
              icon: Icons.close,
              tooltip: widget.strings.close,
              onPressed:
                  widget.onClose ?? () => Navigator.of(context).maybePop(),
            ),
        ],
      ),
    ];
    return StudioRibbonStyle(
      compact: false,
      showCommandLabels: false,
      showGroupLabels: true,
      child: Material(
        color: theme.colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 38,
              padding: const EdgeInsetsDirectional.only(start: 8),
              alignment: AlignmentDirectional.centerStart,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: StudioTabChip(
                label: 'Home',
                selected: true,
                accent: theme.colorScheme.primary,
                onTap: () {},
              ),
            ),
            SizedBox(
              height: StudioRibbonStrip.preferredHeight(
                context,
                compact: false,
                showCommandLabels: false,
                showGroupLabels: true,
              ),
              child: StudioRibbonStrip(groups: groups),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountView(BuildContext context, {required bool compact}) {
    // Catalog selection, saving and forgetting retain the editable setup form.
    // Automatic restoration owns the progress screen only while loading or
    // connecting the saved account.
    if (_client == null &&
        _accountCatalogStore != null &&
        _autoConnectEnabled &&
        (_accountCatalog == null && _credentialPending ||
            _hasSavedCredentials &&
                (_autoConnectTicket != null || _connecting))) {
      return _restoringAccount(context);
    }
    return _client == null
        ? _accountSetup(context)
        : _inbox(context, compact: compact);
  }

  Widget _restoringAccount(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          _email.text.trim().isEmpty
              ? 'Connecting to your saved account…'
              : 'Connecting to ${_email.text.trim()}…',
          key: const ValueKey('studio-mail-restoring-account'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Your Mail workspace is kept open while you work in other apps.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _accountSetup(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.mail_outline,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.strings.mailTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.strings.mailSetupHelp,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_navigationTarget case final target?) ...[
                  Text(
                    target.identity.sender,
                    key: const ValueKey('studio-mail-navigation-target'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(target.description),
                  const SizedBox(height: 8),
                  Text(widget.strings.mailAccountNavigationReconnectHelp),
                  if (_notice ==
                          widget
                              .strings
                              .mailAccountNavigationRouteUnavailable &&
                      _error != _notice)
                    Text(
                      _notice!,
                      key: const ValueKey(
                        'studio-mail-navigation-route-choice',
                      ),
                    ),
                  TextButton(
                    key: const ValueKey('studio-mail-navigation-clear-target'),
                    onPressed: _connecting || _busy || _credentialPending
                        ? null
                        : _newAccount,
                    child: Text(widget.strings.mailNewAccount),
                  ),
                  const Divider(height: 24),
                ],
                if (_accountCatalogStore != null) ...[
                  _rememberedAccounts(context),
                  if (_localDraftSavedAccount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        key: const ValueKey('studio-mail-open-local-drafts'),
                        onPressed:
                            _busy ||
                                _dialogOpen ||
                                _connecting ||
                                _retiredNavigationStore != null ||
                                _credentialPending
                            ? null
                            : _openLocalDrafts,
                        icon: const Icon(Icons.drafts_outlined),
                        label: Text(widget.strings.mailLocalDrafts),
                      ),
                    ),
                  const Divider(height: 24),
                ],
                if (_localAccounts != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      key: const ValueKey('studio-mail-known-drafts'),
                      onPressed:
                          _connecting ||
                              _busy ||
                              _dialogOpen ||
                              _retiredNavigationStore != null ||
                              _credentialPending
                          ? null
                          : _openLocalAccounts,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(widget.strings.mailLocalAccounts),
                    ),
                  ),
                if (_hasCredentialSettings)
                  TextButton.icon(
                    onPressed: _canChangeCredentialStorage
                        ? _openCredentialStorage
                        : null,
                    icon: const Icon(Icons.key),
                    label: Text(
                      'Credential storage: ${StudioCredentialStorage.instance.label}',
                    ),
                  ),
                for (final service in MailCloudService.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      key: ValueKey('studio-mail-open-${service.name}'),
                      onPressed:
                          _connecting ||
                              _credentialPending ||
                              _retiredNavigationStore != null
                          ? null
                          : () => _openProviderSetup(
                              service == MailCloudService.gmail
                                  ? MailProviderKind.gmail
                                  : MailProviderKind.graph,
                            ),
                      icon: const Icon(Icons.cloud_outlined),
                      label: Text(
                        service == MailCloudService.gmail
                            ? 'Gmail'
                            : 'Microsoft 365 / Outlook',
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey<String>('studio-mail-open-ews'),
                  onPressed:
                      _connecting ||
                          _credentialPending ||
                          _retiredNavigationStore != null
                      ? null
                      : () => _openProviderSetup(MailProviderKind.ews),
                  icon: const Icon(Icons.dns_outlined),
                  label: Text(widget.strings.ewsTitle),
                ),
                const Divider(height: 24),
                KeyedSubtree(
                  key: const ValueKey('studio-mail-provider-preset'),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_preset?.name ?? 'other'),
                    initialValue: _preset?.name ?? 'other',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: widget.strings.mailProvider,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'other',
                        child: Text(widget.strings.mailOtherProvider),
                      ),
                      for (final preset in StudioMailImapPreset.values)
                        DropdownMenuItem(
                          value: preset.name,
                          child: Text(preset.label),
                        ),
                    ],
                    onChanged: _connecting
                        ? null
                        : (value) => setState(() {
                            _settingsEdited();
                            _preset = StudioMailImapPreset.values
                                .where((entry) => entry.name == value)
                                .firstOrNull;
                            _manual = false;
                            _password.clear();
                            _primaryLogin.clear();
                            _icloudFullAddressLogin = false;
                            _error = null;
                            _credentialError = null;
                          }),
                  ),
                ),
                if (_preset case final preset?) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.strings.mailPresetPasswordHelp,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${preset.imapHost}:993 TLS\n${preset.smtpHost}:${preset.smtpPort} ${preset == StudioMailImapPreset.icloud ? 'STARTTLS' : 'TLS'}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const <String>[AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: widget.strings.emailAddress,
                    prefixIcon: const Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const <String>[AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: _preset == null
                        ? widget.strings.password
                        : widget.strings.mailAppPassword,
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
                if (_preset != null) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('studio-mail-primary-login'),
                    controller: _primaryLogin,
                    enabled: !_connecting,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: widget.strings.mailPrimaryLogin,
                    ),
                  ),
                ],
                if (_preset == StudioMailImapPreset.icloud)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    key: const ValueKey('studio-mail-icloud-full-login'),
                    value: _icloudFullAddressLogin,
                    title: Text(widget.strings.mailIcloudFullLogin),
                    onChanged: _connecting
                        ? null
                        : (value) => setState(() {
                            _settingsEdited();
                            _icloudFullAddressLogin = value ?? false;
                          }),
                  ),
                const SizedBox(height: 8),
                if (_preset == null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.strings.manualServers),
                    value: _manual,
                    onChanged: _connecting
                        ? null
                        : (value) => setState(() {
                            _settingsEdited();
                            _manual = value;
                          }),
                  ),
                if (_manual) ...<Widget>[
                  TextField(
                    controller: _imapHost,
                    decoration: InputDecoration(
                      labelText: widget.strings.imapHost,
                      hintText: 'imap.example.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpHost,
                    decoration: InputDecoration(
                      labelText: widget.strings.smtpHost,
                      hintText: 'smtp.example.com',
                    ),
                  ),
                  SwitchListTile(
                    key: const ValueKey('studio-mail-starttls'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.strings.useStartTls),
                    value: _startTls,
                    onChanged: _connecting
                        ? null
                        : (value) => setState(() {
                            _settingsEdited();
                            _startTls = value;
                          }),
                  ),
                  const SizedBox(height: 12),
                ],
                SwitchListTile(
                  key: const ValueKey('studio-mail-remember'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.credentialStore != null ||
                            StudioCredentialStorage.instance.persistent
                        ? widget.strings.rememberAccount
                        : 'Remember this account for this session',
                  ),
                  value: _remember,
                  onChanged: _connecting
                      ? null
                      : (value) => setState(() {
                          _settingsEdited();
                          _remember = value;
                        }),
                ),
                _forgetAccountButton(),
                if (_credentialError != null) _credentialFeedback(context),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SelectableText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed:
                      _connecting ||
                          _busy ||
                          _dialogOpen ||
                          _retiredNavigationStore != null ||
                          _accountCatalogStore != null && _credentialPending
                      ? null
                      : _connect,
                  icon: _connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(widget.strings.connect),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.strings.mailSessionNotice,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  String _accountTransport(int port, bool startTls) =>
      '$port ${startTls ? 'STARTTLS' : 'TLS'}';

  String _savedAccountDetails(StudioMailCredentials credentials) {
    final identity = credentials.connectionIdentity;
    return '${widget.strings.mailAccountSender(identity.sender)}\n'
        '${widget.strings.mailAccountImapLogin(identity.imapLogin)} · '
        '${identity.imapHost}:${_accountTransport(identity.imapPort, identity.imapStartTls)}\n'
        '${widget.strings.mailAccountSmtpLogin(identity.smtpLogin)} · '
        '${identity.smtpHost}:${_accountTransport(identity.smtpPort, identity.smtpStartTls)}';
  }

  String _savedAccountSummary(
    StudioMailSavedAccount saved,
    List<StudioMailSavedAccount> accounts,
  ) {
    final identity = saved.credentials.connectionIdentity;
    final peers = accounts
        .map((entry) => entry.credentials.connectionIdentity)
        .where(
          (entry) =>
              entry.sender == identity.sender &&
              entry.imapHost == identity.imapHost,
        )
        .toList();
    final details = <String>[];
    final imapLoginDiffers =
        peers.map((entry) => entry.imapLogin).toSet().length > 1;
    final smtpLoginDiffers =
        peers.map((entry) => entry.smtpLogin).toSet().length > 1;
    if (imapLoginDiffers &&
        smtpLoginDiffers &&
        peers.every((entry) => entry.imapLogin == entry.smtpLogin)) {
      details.add(widget.strings.mailAccountLogin(identity.imapLogin));
    } else {
      if (imapLoginDiffers) {
        details.add(widget.strings.mailAccountImapLogin(identity.imapLogin));
      }
      if (smtpLoginDiffers) {
        details.add(widget.strings.mailAccountSmtpLogin(identity.smtpLogin));
      }
    }
    if (peers
            .map((entry) => (entry.imapPort, entry.imapStartTls))
            .toSet()
            .length >
        1) {
      details.add(
        'IMAP: ${_accountTransport(identity.imapPort, identity.imapStartTls)}',
      );
    }
    if (peers
            .map(
              (entry) => (entry.smtpHost, entry.smtpPort, entry.smtpStartTls),
            )
            .toSet()
            .length >
        1) {
      details.add(
        'SMTP: ${identity.smtpHost}:${_accountTransport(identity.smtpPort, identity.smtpStartTls)}',
      );
    }
    return [identity.sender, ...details, identity.imapHost].join(' · ');
  }

  Widget _forgetAccountButton() {
    final button = TextButton.icon(
      key: const ValueKey('studio-mail-forget'),
      onPressed:
          _connecting ||
              _accountCatalogStore != null &&
                  (_credentialPending || _selectedSavedAccountId == null)
          ? null
          : _forgetCredentials,
      icon: Icon(
        _credentialPending
            ? Icons.hourglass_empty
            : _hasSavedCredentials
            ? Icons.key_off_outlined
            : Icons.delete_outline,
        size: 18,
      ),
      label: Text(widget.strings.forgetAccount),
    );
    final selected = _accountCatalog?.accounts
        .where((entry) => entry.id == _selectedSavedAccountId)
        .firstOrNull;
    if (selected == null) return button;
    final details = _savedAccountDetails(selected.credentials);
    return Tooltip(
      key: const ValueKey('studio-mail-forget-tooltip'),
      message: '${widget.strings.forgetAccount}\n$details',
      excludeFromSemantics: true,
      child: MergeSemantics(
        child: Semantics(
          key: const ValueKey('studio-mail-forget-description'),
          label: details,
          child: button,
        ),
      ),
    );
  }

  Widget _rememberedAccounts(BuildContext context) {
    final accounts =
        _accountCatalog?.accounts ?? const <StudioMailSavedAccount>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: const ValueKey('studio-mail-saved-account'),
          child: DropdownButtonFormField<String>(
            key: ValueKey((_selectedSavedAccountId, _credentialGeneration)),
            initialValue: _selectedSavedAccountId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: widget.strings.mailSavedAccounts,
              hintText: widget.strings.mailChooseAccount,
            ),
            items: [
              for (final saved in accounts)
                DropdownMenuItem(
                  value: saved.id,
                  child: Tooltip(
                    key: ValueKey('studio-mail-account-tooltip-${saved.id}'),
                    message: _savedAccountDetails(saved.credentials),
                    excludeFromSemantics: true,
                    child: Semantics(
                      key: ValueKey(
                        'studio-mail-account-description-${saved.id}',
                      ),
                      label: _savedAccountDetails(saved.credentials),
                      excludeSemantics: true,
                      child: Text(
                        _savedAccountSummary(saved, accounts),
                        key: ValueKey('studio-mail-account-label-${saved.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
            ],
            onChanged: _connecting || _credentialPending || accounts.isEmpty
                ? null
                : (value) {
                    if (value != null) unawaited(_selectSavedAccount(value));
                  },
          ),
        ),
        if (_selectedSavedAccountId != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('studio-mail-new-account'),
              onPressed: _connecting || _credentialPending ? null : _newAccount,
              icon: const Icon(Icons.person_add_alt_outlined),
              label: Text(widget.strings.mailNewAccount),
            ),
          ),
        Text(
          widget.strings.mailSavedAccountsHelp,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _credentialFeedback(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            _credentialError!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          if (_client != null && _lastCredentialSnapshot != null)
            TextButton.icon(
              onPressed: _credentialPending || _credentialSettingsOpen
                  ? null
                  : () => _persistCredentials(
                      _client!,
                      _sessionGeneration,
                      _lastCredentialSnapshot!,
                      true,
                    ),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Retry saving account'),
            ),
          if (_client == null && _vaultUnlockAvailable)
            TextButton.icon(
              key: const ValueKey('studio-mail-unlock-vault'),
              onPressed:
                  _credentialPending ||
                      _credentialSettingsOpen ||
                      _vaultUnlockPromptOpen ||
                      _dialogOpen
                  ? null
                  : _promptVaultUnlock,
              icon: const Icon(Icons.lock_open),
              label: const Text('Unlock saved accounts'),
            ),
        ],
      ),
    ),
  );

  Widget _inbox(BuildContext context, {required bool compact}) {
    return Column(
      children: <Widget>[
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        _folderArchiveAction(),
        if (_credentialError != null) _credentialFeedback(context),
        if (_localAccountWarning case final warning?)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(warning),
            ),
          ),
        if (_cacheWarning case final warning?)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                warning,
                key: const ValueKey('studio-mail-cache-warning'),
              ),
            ),
          ),
        if (_error != null || _notice != null)
          Material(
            color: _error == null
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_notice != null) SelectableText(_notice!),
                          if (_error != null) SelectableText(_error!),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: compact
              ? _compactInbox(context)
              : Row(
                  children: <Widget>[
                    SizedBox(
                      width: 220,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _account?.email ?? '',
                              style: Theme.of(context).textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView(
                              children: <Widget>[
                                for (final box in _mailboxes)
                                  ListTile(
                                    dense: true,
                                    selected: box.path == _mailbox?.path,
                                    leading: Icon(
                                      box.isInbox
                                          ? Icons.inbox_outlined
                                          : box.isSent
                                          ? Icons.send_outlined
                                          : box.isDrafts
                                          ? Icons.edit_note
                                          : box.isJunk
                                          ? Icons.report_gmailerrorred_outlined
                                          : box.isTrash
                                          ? Icons.delete_outline
                                          : Icons.folder_outlined,
                                      size: 18,
                                    ),
                                    title: Text(
                                      box.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: !box.isNotSelectable
                                        ? () => _selectMailbox(box)
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 360, child: _messageList()),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _reader == null
                          ? Center(child: Text(widget.strings.noMessage))
                          : Column(
                              children: <Widget>[
                                _messageActions(),
                                Expanded(
                                  child: MailMessageView(controller: _reader!),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _folderArchiveAction() {
    final loader = _messageLoader;
    final mailbox = _mailbox;
    final account = _account;
    if (loader == null ||
        loader is! StudioMailMailboxArchiver ||
        mailbox == null ||
        account == null) {
      return const SizedBox.shrink();
    }
    final incoming = account.incoming;
    final source = account.email;
    final archiver = loader as StudioMailMailboxArchiver;
    final authentication = incoming.authentication;
    final login = authentication is mail.PlainAuthentication
        ? authentication.userName
        : source;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              mailbox.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          StudioArchiveFolderButton(
            strings: widget.strings,
            source: source,
            folder: mailbox.path,
            profileId: studioArchiveFolderProfileId(
              'imap:${incoming.serverConfig.hostname.toLowerCase()}:${incoming.serverConfig.port}:$login',
              source,
              mailbox.path,
            ),
            sessionKey: archiver,
            enabled: !_busy && !_dialogOpen,
            writer: widget.archiveFolderWriter,
            onDialogChanged: (open) {
              if (mounted) setState(() => _dialogOpen = open);
            },
            runner: (archive, profile, {cancellation, onProgress}) =>
                archiver.archiveMailbox(
                  mailbox,
                  archive: archive,
                  profile: profile,
                  cancellation: cancellation,
                  onProgress: onProgress,
                ),
          ),
        ],
      ),
    );
  }

  Widget _archiveMessageAction() {
    final message = _selected;
    final generation = _mailboxGeneration;
    return IconButton(
      key: const ValueKey('studio-mail-archive-message'),
      tooltip: widget.strings.mailArchiveMessages,
      icon: const Icon(Icons.archive_outlined),
      onPressed: _busy || _dialogOpen || _needsRefresh || message == null
          ? null
          : () {
              if (!identical(message, _selected) ||
                  generation != _mailboxGeneration) {
                return;
              }
              unawaited(
                _organizeMessages(
                  MailBulkFlagAction.archive,
                  [_messageKey(message)],
                  mailboxGeneration: generation,
                  selectedMessage: message,
                ),
              );
            },
    );
  }

  Widget _messageActions() => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: Wrap(
      children: <Widget>[
        StudioArchiveMessageButton(
          strings: widget.strings,
          message: _busy ? null : _reader?.result.message,
          origin: MailArchiveOrigin(
            source: _account?.email ?? 'IMAP',
            folder: _messageMailbox?.path ?? '/',
            sourceMessageId:
                'imap:${_messageMailbox?.uidValidity ?? 0}:${_selected?.uid ?? 0}',
          ),
          writer: widget.archiveWriter,
        ),
        IconButton(
          onPressed: _busy ? null : _reply,
          tooltip: widget.strings.reply,
          icon: const Icon(Icons.reply_outlined),
        ),
        IconButton(
          onPressed: _busy ? null : _replyAll,
          tooltip: widget.strings.replyAll,
          icon: const Icon(Icons.reply_all_outlined),
        ),
        IconButton(
          onPressed: _busy ? null : _forward,
          tooltip: widget.strings.forward,
          icon: const Icon(Icons.forward_outlined),
        ),
        IconButton(
          onPressed: _busy ? null : _forwardWithAttachments,
          tooltip: widget.strings.mailForwardWithAttachments,
          icon: const Icon(Icons.attach_email_outlined),
        ),
        if (_messageLoader is StudioMailMessageActions) ...[
          IconButton(
            onPressed:
                _busy || _dialogOpen || _needsRefresh || _selected == null
                ? null
                : () => _changeMessageFlags(
                    read: _observedRead(_selected!) != true,
                  ),
            tooltip: _selected != null && _observedRead(_selected!) == true
                ? widget.strings.ewsMarkUnread
                : widget.strings.markRead,
            icon: Icon(
              _selected != null && _observedRead(_selected!) == true
                  ? Icons.mark_email_unread_outlined
                  : Icons.mark_email_read_outlined,
            ),
          ),
          IconButton(
            onPressed:
                _busy || _dialogOpen || _needsRefresh || _selected == null
                ? null
                : () => _changeMessageFlags(
                    flagged: _observedFlagged(_selected!) != true,
                  ),
            tooltip: _selected != null && _observedFlagged(_selected!) == true
                ? widget.strings.ewsUnflag
                : widget.strings.ewsFlag,
            icon: Icon(
              _selected != null && _observedFlagged(_selected!) == true
                  ? Icons.flag
                  : Icons.outlined_flag,
            ),
          ),
        ] else
          IconButton(
            onPressed: _busy || _dialogOpen || (_selected?.isSeen ?? true)
                ? null
                : _markRead,
            tooltip: widget.strings.markRead,
            icon: const Icon(Icons.mark_email_read_outlined),
          ),
        if (_messageLoader is StudioMailMembershipActions &&
            _messageLoader is StudioMailMailboxRecords) ...[
          if (_membershipCapabilities.supports(MailCapability.move))
            _archiveMessageAction(),
          IconButton(
            key: const ValueKey('studio-mail-move-message'),
            tooltip: widget.strings.mailMoveMessage,
            icon: const Icon(Icons.drive_file_move_outline),
            onPressed:
                _busy || _dialogOpen || _needsRefresh || _selected == null
                ? null
                : () => _organizeSelected(delete: false),
          ),
          IconButton(
            key: const ValueKey('studio-mail-delete-message'),
            tooltip: widget.strings.mailMarkDeleted,
            icon: const Icon(Icons.delete_outline),
            onPressed:
                _busy || _dialogOpen || _needsRefresh || _selected == null
                ? null
                : () => _organizeSelected(delete: true),
          ),
        ],
        const SizedBox(width: 8),
      ],
    ),
  );

  bool? _observedRead(mail.MimeMessage message) {
    final confirmed = _confirmedFlags[message];
    if (confirmed?.read case final read?) return read;
    if (_repositoryFlags.containsKey(message)) {
      return _repositoryFlags[message]?.isRead;
    }
    return confirmed != null || message.flags == null ? null : message.isSeen;
  }

  bool? _observedFlagged(mail.MimeMessage message) {
    final confirmed = _confirmedFlags[message];
    if (confirmed?.flagged case final flagged?) return flagged;
    if (_repositoryFlags.containsKey(message)) {
      return _repositoryFlags[message]?.isFlagged;
    }
    return confirmed != null || message.flags == null
        ? null
        : message.isFlagged;
  }

  String _messageKey(mail.MimeMessage message, {mail.Mailbox? mailbox}) {
    final observed = mailbox ?? _messageMailbox;
    // Production browser rows always have a validated UID. Legacy injected
    // readers may omit it; their row stays local to this in-memory snapshot.
    return 'imap-message-${observed?.uidValidity}:${message.uid ?? identityHashCode(message)}';
  }

  Widget? _bulkStatus() {
    final report = _bulkReport;
    if (report == null) return null;
    final mailboxGeneration = _mailboxGeneration;
    final cancellation = _bulkCancellation;
    final running = cancellation != null;
    return StudioMailBulkStatus(
      strings: widget.strings,
      report: report,
      running: running,
      subjects: _bulkSubjects,
      showStop: false,
      onStop: cancellation == null
          ? null
          : () {
              if (mounted && identical(_bulkCancellation, cancellation)) {
                cancellation.cancel();
              }
            },
      onDismiss: running || report.requiresRefresh
          ? null
          : () {
              if (!mounted ||
                  mailboxGeneration != _mailboxGeneration ||
                  !identical(_bulkReport, report) ||
                  _bulkCancellation != null) {
                return;
              }
              setState(() {
                _bulkReport = null;
                _bulkSubjects = const {};
                if (_notice == widget.strings.mailBulkSummary(report)) {
                  _notice = null;
                }
              });
            },
    );
  }

  Widget _messageList() {
    final mailboxGeneration = _mailboxGeneration;
    final cancellation = _bulkCancellation;
    return MailMessageList(
      key: _messageListKey,
      scopeId: '$_sessionGeneration:${_mailbox?.path}',
      selectionScopeId: '$mailboxGeneration',
      bulkStatus: _bulkStatus(),
      strings: widget.strings.mailMessageListStrings,
      items: [
        for (final message in _messages)
          MailMessageListItem(
            id: _messageKey(message),
            subject: message.decodeSubject() ?? '(no subject)',
            accountId: 'imap-session-$_sessionGeneration',
            messageId: message.getHeaderValue('Message-ID'),
            inReplyTo: message.getHeaderValue('In-Reply-To'),
            references: _studioMailLoadedReferences(
              message.getHeaderValue('References'),
            ),
            sender:
                message.from
                    ?.map(
                      (address) =>
                          address.personalName == null ||
                              address.personalName!.isEmpty
                          ? address.email
                          : '${address.personalName} <${address.email}>',
                    )
                    .join(', ') ??
                '',
            to:
                message.to
                    ?.map(
                      (address) => address.personalName?.isNotEmpty == true
                          ? '${address.personalName} <${address.email}>'
                          : address.email,
                    )
                    .join(', ') ??
                '',
            cc:
                message.cc
                    ?.map(
                      (address) => address.personalName?.isNotEmpty == true
                          ? '${address.personalName} <${address.email}>'
                          : address.email,
                    )
                    .join(', ') ??
                '',
            date: message.decodeDate(),
            dateLabel: studioMailListDate(
              message.decodeDate(),
              widget.strings.language,
            ),
            isRead: _observedRead(message),
            isFlagged: _observedFlagged(message),
          ),
      ],
      selectedId: _selected == null ? null : _messageKey(_selected!),
      busy: _busy || _dialogOpen,
      supportedBulkActions: {
        if (_messageLoader is StudioMailMessageActions) ...[
          MailBulkFlagAction.markRead,
          MailBulkFlagAction.markUnread,
          MailBulkFlagAction.flag,
          MailBulkFlagAction.unflag,
        ],
        if (_messageLoader is StudioMailMembershipActions) ...[
          if (_membershipCapabilities.supports(MailCapability.move))
            MailBulkFlagAction.move,
          if (_membershipCapabilities.supports(MailCapability.move))
            MailBulkFlagAction.archive,
          if (_membershipCapabilities.supports(MailCapability.delete))
            MailBulkFlagAction.delete,
        ],
      },
      onBulkAction:
          _messageLoader is StudioMailMailboxRecords &&
              (_messageLoader is StudioMailMessageActions ||
                  _messageLoader is StudioMailMembershipActions)
          ? (action, ids) => unawaited(
              action.isFlagAction
                  ? _changeCommands(
                      action,
                      ids,
                      mailboxGeneration: mailboxGeneration,
                    )
                  : _organizeMessages(
                      action,
                      ids,
                      mailboxGeneration: mailboxGeneration,
                    ),
            )
          : null,
      bulkActionsEnabled: !_needsRefresh,
      onCancelBulk: cancellation == null
          ? null
          : () {
              if (identical(_bulkCancellation, cancellation)) {
                cancellation.cancel();
              }
            },
      hasMore: _nextHeaders != null && _messages.length < _maxHeaders,
      loadMoreKey: const ValueKey('imap-load-more'),
      onLoadMore: _needsRefresh || _mailbox == null
          ? null
          : () => unawaited(_selectMailbox(_mailbox!, more: true)),
      limitNotice: _messages.length >= _maxHeaders && _nextHeaders != null
          ? widget.strings.mailWorkspaceLimit
          : null,
      onOpen: (id) {
        final message = _messages
            .where((message) => _messageKey(message) == id)
            .firstOrNull;
        if (message != null) unawaited(_openMessage(message));
      },
    );
  }

  Widget _compactInbox(BuildContext context) => IndexedStack(
    index: _reader != null && _showCompactMessage ? 1 : 0,
    children: [
      ExcludeFocus(
        excluding: _reader != null && _showCompactMessage,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButton<String>(
                isExpanded: true,
                value: _mailbox?.path,
                items: [
                  for (final box in _mailboxes)
                    if (!box.isNotSelectable)
                      DropdownMenuItem(
                        value: box.path,
                        child: Text(
                          box.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                ],
                onChanged: _busy || _dialogOpen
                    ? null
                    : (path) {
                        if (path != null) {
                          unawaited(
                            _selectMailbox(
                              _mailboxes.firstWhere((box) => box.path == path),
                            ),
                          );
                        }
                      },
              ),
            ),
            Expanded(child: _messageList()),
          ],
        ),
      ),
      if (_reader != null)
        Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _showCompactMessage = false),
                  tooltip: widget.strings.backToMessages,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    _selected?.decodeSubject() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            _messageActions(),
            Expanded(child: MailMessageView(controller: _reader!)),
          ],
        ),
    ],
  );
}
