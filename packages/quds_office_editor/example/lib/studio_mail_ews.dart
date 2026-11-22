import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'studio_mail_account_navigation.dart';
import 'studio_mail_account_navigation_strings.dart';
import 'studio_mail_archive_action.dart';
import 'studio_mail_bulk_status.dart';
import 'studio_mail_body_download.dart';
import 'studio_mail_flag_journal.dart';
import 'studio_mail_journal_dialog.dart';
import 'studio_mail_journal_strings.dart';
import 'studio_mail_archive_folder_action.dart';
import 'studio_mail_compose.dart';
import 'studio_mail_compose_tools.dart';
import 'studio_mail_outbox.dart';
import 'studio_mail_outbox_dialog.dart';
import 'studio_mail_outbox_strings.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_cached_strings.dart';
import 'studio_mail_mailbox_store.dart';
import 'studio_mail_mailbox_session.dart';
import 'studio_mail_draft_store_native.dart';
import 'studio_mail_drafts_dialog.dart';
import 'studio_mail_drafts_strings.dart';
import 'studio_mail_local_accounts.dart';
import 'studio_mail_local_accounts_dialog.dart';
import 'studio_mail_local_accounts_strings.dart';
import 'studio_mail_mutation_strings.dart';
import 'studio_mail_operation.dart';
import 'studio_mail_organization_dialog.dart';
import 'studio_mail_reply.dart';
import 'studio_mail_strings.dart';
import 'studio_mail_workspace_strings.dart';
import 'studio_mail_submission.dart';
import 'studio_mail_sync_dialog.dart';
import 'studio_mail_sync_strings.dart';
import 'studio_strings.dart';
import 'studio_mail_reader_labels.dart';

typedef StudioEwsProviderFactory =
    MailEwsProvider Function(
      MailEwsConfiguration configuration,
      MailCredentialStore credentials,
    );

typedef StudioCloudAuthorizer =
    Future<MailResult<MailCloudTokenSource>> Function({
      required MailOAuthConfiguration configuration,
      required MailAccountId account,
      required Future<bool> Function(Uri) openBrowser,
      required MailOperationLease lease,
      MailCloudLogSink? log,
    });

typedef StudioCloudProviderFactory =
    MailCloudProvider Function({
      required MailCloudConfiguration configuration,
      required MailCloudTokenSource tokenSource,
      MailCloudLogSink? log,
    });

/// Foreground Exchange Server or cloud mailbox host. Credentials belong to the
/// session; drafts, visited views and explicitly opened messages use optional
/// account-scoped local storage.
class StudioMailEwsDialog extends StatefulWidget {
  const StudioMailEwsDialog({
    super.key,
    required this.strings,
    this.providerFactory,
    this.archiveWriter,
    this.archiveFolderWriter,
    this.draftStoreFactory,
    this.localAccountStore,
    this.initialAccount,
    this.onAccountNavigation,
  }) : cloudService = null,
       cloudAuthorizer = null,
       cloudProviderFactory = null,
       openBrowser = null,
       initialClientId = null;

  const StudioMailEwsDialog.cloud({
    super.key,
    required this.strings,
    required MailCloudService service,
    this.cloudAuthorizer,
    this.cloudProviderFactory,
    this.openBrowser,
    this.initialClientId,
    this.archiveWriter,
    this.archiveFolderWriter,
    this.draftStoreFactory,
    this.localAccountStore,
    this.initialAccount,
    this.onAccountNavigation,
  }) : cloudService = service,
       providerFactory = null;

  final StudioStrings strings;

  /// Tests inject the provider boundary, not sockets or authenticated clients.
  final StudioEwsProviderFactory? providerFactory;
  final MailCloudService? cloudService;
  final StudioCloudAuthorizer? cloudAuthorizer;
  final StudioCloudProviderFactory? cloudProviderFactory;
  final Future<bool> Function(Uri)? openBrowser;
  final String? initialClientId;
  final StudioMailArchiveWriter? archiveWriter;
  final StudioMailArchiveFolderWriter? archiveFolderWriter;
  final StudioMailDraftStoreFactory? draftStoreFactory;
  final StudioMailLocalAccountStore? localAccountStore;
  final StudioMailAccountNavigationTarget? initialAccount;
  final ValueChanged<StudioMailAccountNavigationTarget>? onAccountNavigation;

  @override
  State<StudioMailEwsDialog> createState() => _StudioMailEwsDialogState();
}

class _StudioMailEwsDialogState extends State<StudioMailEwsDialog> {
  StudioMailLocalAccountStore? get _localAccounts =>
      widget.localAccountStore ??
      (widget.draftStoreFactory == null
          ? NativeStudioMailLocalAccountStore.instance
          : null);

  static const _pageSize = 50;
  static const _maxHeaders = 1000;
  final _endpoint = TextEditingController();
  final _email = TextEditingController();
  final _login = TextEditingController();
  final _domain = TextEditingController();
  final _password = TextEditingController();
  final _messageListKey = GlobalKey(debugLabel: 'mail-provider-list');
  final _usedHeaderCursors = <String>{};
  // A confirmed mutation observes only its target flag. Keep that observation
  // separate from a possibly unobserved provider flag snapshot.
  final _confirmedRead = <MailRemoteIdentity, bool>{};
  final _confirmedFlagged = <MailRemoteIdentity, bool>{};
  MailEwsAuthentication _authentication = MailEwsAuthentication.ntlm;
  MailProvider? _provider;
  MailSubmissionProvider? _submission;
  MailCloudProvider? _cloudProvider;
  MailCloudTokenSource? _tokens;
  final _clientId = TextEditingController();
  final _tenant = TextEditingController(text: 'common');
  final _clientSecret = TextEditingController();
  bool _diagnostics = false;
  MailAccountSession? _session;
  _SessionCredentials? _credentials;
  MailCapabilities _capabilities = const MailCapabilities.none();
  List<MailMailbox> _mailboxes = const [];
  MailMailbox? _mailbox;
  List<MailHeaderRecord> _headers = const [];
  MailCursor? _next;
  MailHeaderRecord? _selected;
  MailReaderController? _reader;
  StudioMailDraft? _draft;
  StudioMailDraftStore? _draftStore;
  StudioMailMailboxCapture? _mailboxCapture;
  StudioMailMailboxSession? _mailboxViewSession;
  StreamSubscription<StudioMailMailboxSnapshot>? _mailboxViewSubscription;
  Future<void> _mailboxViewClosing = Future<void>.value();
  bool _mailboxViewReleaseFailed = false;
  int _mailboxViewGeneration = 0;
  Future<void> _draftStoreClosing = Future<void>.value();
  StudioMailDraftStore? _retiredDraftStore;
  Future<void>? _navigationClosing;
  Future<void> _draftRestoration = Future<void>.value();
  final _unreleasedDraftStores = <StudioMailDraftStore>[];
  StudioMailDraftAccount? _draftIdentity;
  bool _submissionUncertain = false;
  bool _connected = false;
  bool _busy = false;
  bool _dialogOpen = false;
  bool _navigating = false;
  bool _routeRetired = false;
  bool _allowPop = false;
  int _accountEpoch = 0;
  StudioMailAccountNavigationTarget? _initialAccountSource;
  StudioMailAccountNavigationTarget? _expectedAccount;
  StudioMailAccountNavigationTarget? _connectionTarget;
  StudioMailLocalAccountStore? _connectionDirectory;
  bool _showMessage = false;
  bool _needsRefresh = false;
  int _mailboxGeneration = 0;
  Future<void>? _pendingFlagWrite;
  MailCancellationSource? _bulkCancellation;
  MailBulkFlagReport? _bulkReport;
  Map<MailRemoteIdentity, String> _bulkSubjects = const {};
  String? _error;
  String? _notice;
  String? _localAccountWarning;
  String? _cacheViewWarning;
  String? _cacheBodyWarning;
  String? get _cacheWarning => _cacheViewWarning ?? _cacheBodyWarning;
  String _sender = '';
  int _serial = 0;

  bool get _cloud => widget.cloudService != null;
  MailProviderKind get _providerKind => switch (widget.cloudService) {
    MailCloudService.gmail => MailProviderKind.gmail,
    MailCloudService.microsoft365 => MailProviderKind.graph,
    null => MailProviderKind.ews,
  };
  String get _title => switch (widget.cloudService) {
    MailCloudService.gmail => 'Gmail',
    MailCloudService.microsoft365 => 'Microsoft 365 / Outlook',
    null => widget.strings.ewsTitle,
  };

  @override
  void initState() {
    super.initState();
    _prefillAccount();
    _prefillClientId();
  }

  void _prefillClientId() {
    _clientId.text =
        widget.initialClientId ??
        switch (widget.cloudService) {
          MailCloudService.gmail => const String.fromEnvironment(
            'CRISPOFFICE_GOOGLE_CLIENT_ID',
          ),
          MailCloudService.microsoft365 => const String.fromEnvironment(
            'CRISPOFFICE_MICROSOFT_CLIENT_ID',
          ),
          null => '',
        };
  }

  void _prefillAccount() {
    final target = widget.initialAccount;
    _initialAccountSource = target;
    _expectedAccount = target;
    _email.clear();
    _endpoint.clear();
    _domain.clear();
    _login.clear();
    _tenant.text = 'common';
    if (target != null && target.provider == _providerKind) {
      _email.text = target.identity.sender;
      if (target.provider == MailProviderKind.ews) {
        _endpoint.text = target.identity.endpoint;
        _domain.text = target.ewsDomain ?? '';
        _login.text = target.ewsLogin ?? '';
      } else if (target.provider == MailProviderKind.graph) {
        _tenant.text = target.graphTenant ?? 'common';
      }
    }
  }

  @override
  void didUpdateWidget(covariant StudioMailEwsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initialAccount, widget.initialAccount) ||
        !identical(oldWidget.localAccountStore, widget.localAccountStore) ||
        !identical(oldWidget.draftStoreFactory, widget.draftStoreFactory) ||
        oldWidget.cloudService != widget.cloudService ||
        oldWidget.initialClientId != widget.initialClientId) {
      // The host replaced a routing or storage dependency. Retire pending
      // callbacks and keep a late owner in the release queue before allowing
      // explicit sign-in with the new settings.
      _accountEpoch++;
      _disconnect(
        forNavigation: true,
        deferLocalClose:
            _retiredDraftStore != null ||
            _navigationClosing != null ||
            _mailboxViewReleaseFailed,
      );
      _navigating = false;
      _routeRetired = false;
      if (_retiredDraftStore != null || _mailboxViewReleaseFailed) {
        _error = widget.strings.mailAccountNavigationReleaseFailed;
      }
      _prefillAccount();
      if (oldWidget.cloudService != widget.cloudService ||
          oldWidget.initialClientId != widget.initialClientId) {
        _prefillClientId();
      }
    }
  }

  void _closeCloud() {
    final provider = _cloudProvider;
    final tokens = _tokens;
    _cloudProvider = null;
    _tokens = null;
    try {
      provider?.dispose();
    } on Object {
      /* Complete independent cleanup. */
    }
    try {
      tokens?.dispose();
    } on Object {
      /* Never expose a credential error. */
    }
  }

  bool get _blocked =>
      _busy ||
      _dialogOpen ||
      _navigating ||
      _routeRetired ||
      _mailboxViewReleaseFailed ||
      _unreleasedDraftStores.isNotEmpty ||
      _retiredDraftStore != null;
  bool get _canSend => _capabilities.supports(MailCapability.send);

  bool get _canArchive => widget.cloudService == MailCloudService.gmail
      ? _capabilities.supports(MailCapability.archive) &&
            _mailbox?.id.value == 'INBOX'
      : _capabilities.supports(MailCapability.move);
  bool? _isRead(MailHeaderRecord? header) => header == null
      ? null
      : _confirmedRead[header.remote] ?? header.flags?.isRead;
  bool? _isFlagged(MailHeaderRecord? header) => header == null
      ? null
      : _confirmedFlagged[header.remote] ?? header.flags?.isFlagged;
  bool _current(MailProvider provider, MailOperationLease lease) =>
      mounted &&
      identical(_provider, provider) &&
      lease.isCurrent &&
      identical(_initialAccountSource, widget.initialAccount) &&
      (_connectionTarget == null ||
          identical(_connectionDirectory, _localAccounts));

  Future<bool> _prepareConnection(StudioMailDraftAccount identity) async {
    final target = _expectedAccount;
    final directory = _localAccounts;
    final epoch = ++_accountEpoch;
    final service = widget.cloudService;
    bool current() =>
        mounted &&
        epoch == _accountEpoch &&
        identical(target, _expectedAccount) &&
        identical(_initialAccountSource, widget.initialAccount) &&
        identical(directory, _localAccounts) &&
        service == widget.cloudService &&
        !_connected &&
        !_navigating &&
        !_routeRetired;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _connectionTarget = target;
      _connectionDirectory = directory;
    });
    try {
      target?.requireMatches(identity);
    } on Object {
      if (current()) {
        setState(() {
          _busy = false;
          _error = widget.strings.mailAccountNavigationIdentityMismatch;
        });
      }
      return false;
    }
    try {
      await _draftRestoration;
      if (!current()) return false;
      await _requireReleasedDraftStores();
      if (!current()) return false;
      if (target != null) {
        if (directory == null || target.provider != _providerKind) {
          throw const StudioMailDraftStoreException(
            MailProblemCode.permissionDenied,
          );
        }
        await target.validateCurrent(directory);
      }
      return current();
    } on Object catch (error) {
      if (current()) {
        setState(() {
          _busy = false;
          _error = error is _AccountOwnerReleaseFailure
              ? widget.strings.mailAccountNavigationReleaseFailed
              : widget.strings.mailAccountNavigationChanged;
        });
      }
      return false;
    }
  }

  Future<void> _validateActiveAccount() async {
    final target = _connectionTarget;
    if (target == null) return;
    final directory = _connectionDirectory;
    final identity = _draftIdentity;
    bool current() =>
        directory != null &&
        identity != null &&
        identical(target, _expectedAccount) &&
        identical(target, _connectionTarget) &&
        identical(_initialAccountSource, widget.initialAccount) &&
        identical(directory, _localAccounts) &&
        target.provider == _providerKind;
    if (directory == null || identity == null || !current()) {
      throw const _AccountNavigationExpired();
    }
    try {
      target.requireMatches(identity);
      await target.validateCurrent(directory);
    } on Object {
      throw const _AccountNavigationExpired();
    }
    if (!current()) throw const _AccountNavigationExpired();
  }

  T _value<T>(MailResult<T> result) => switch (result) {
    MailSuccess<T>(:final value) => value,
    MailFailure<T>(:final problem) => throw _EwsUiFailure(problem),
  };

  String _problem(MailProblem problem, String fallback) {
    final delay = problem.retryAfter;
    if (_cloud && delay != null && delay > Duration.zero) {
      return widget.strings.mailCloudRetryAfter(
        (delay.inMilliseconds + 999) ~/ 1000,
      );
    }
    return switch (problem.code) {
      MailProblemCode.authenticationRequired =>
        _cloud
            ? widget.strings.mailCloudAuthenticationFailed
            : widget.strings.ewsAuthenticationFailed,
      MailProblemCode.permissionDenied =>
        _cloud
            ? widget.strings.mailCloudAccessFailed
            : widget.strings.ewsAccessFailed,
      MailProblemCode.unsupported =>
        _cloud
            ? widget.strings.mailCloudUnsupported
            : widget.strings.ewsUnsupported,
      MailProblemCode.quotaExceeded => widget.strings.ewsBudgetExceeded,
      _ => fallback,
    };
  }

  void _retire(MailReaderController? reader) {
    if (reader != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => reader.dispose());
    }
  }

  @override
  void dispose() {
    _accountEpoch++;
    _bulkCancellation?.cancel(MailCancellationReason.disposed);
    unawaited(
      _stopCachedView().catchError((Object _) {
        // Retained observation handles still prevent a failed drain from
        // releasing its storage owner during best-effort widget disposal.
      }),
    );
    _mailboxCapture?.dispose();
    _session?.dispose();
    _credentials?.clear();
    _closeCloud();
    _reader?.dispose();
    _reader = null;
    _draft = null;
    unawaited(_closeDraftStore(_draftStore));
    if (_navigationClosing == null) {
      unawaited(_closeDraftStore(_retiredDraftStore));
    }
    _draftStore = null;
    _headers = const [];
    _confirmedRead.clear();
    _confirmedFlagged.clear();
    _password.clear();
    for (final controller in [
      _endpoint,
      _email,
      _login,
      _domain,
      _password,
      _clientId,
      _tenant,
      _clientSecret,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() => runStudioMailOperation(() async {
    if (_blocked || _connected) return;
    if (_cloud) {
      await _connectCloud();
      return;
    }
    final sender = _email.text.trim();
    final password = _password.text;
    late final StudioMailDraftAccount identity;
    MailEwsConfiguration configuration;
    try {
      if (!StudioMailDraft.isSupportedAddress(sender) || password.isEmpty) {
        throw const FormatException();
      }
      identity = StudioMailDraftAccount(
        provider: 'ews',
        endpoint: Uri.parse(_endpoint.text.trim()).toString(),
        login: jsonEncode([
          _domain.text.trim(),
          _login.text.trim().isEmpty ? sender : _login.text.trim(),
        ]),
        sender: sender,
      );
      final account = identity.account;
      configuration = MailEwsConfiguration(
        account: account,
        endpoint: Uri.parse(_endpoint.text.trim()),
        username: _login.text.trim().isEmpty ? sender : _login.text.trim(),
        domain: _domain.text.trim(),
        mailboxAddress: sender,
        authentication: _authentication,
        credential: MailCredentialReference(
          account: account,
          key: 'session-password',
        ),
      );
    } on Object {
      setState(() => _error = widget.strings.ewsInvalidSettings);
      return;
    }
    if (!await _prepareConnection(identity)) return;
    final credentials = _SessionCredentials(
      MailCredentialRecord(
        reference: configuration.credential,
        opaqueData: MailBytes(utf8.encode(password)),
      ),
    );
    final session = MailAccountSession(configuration.account);
    MailEwsProvider provider;
    try {
      provider =
          widget.providerFactory?.call(configuration, credentials) ??
          createMailEwsProvider(
            configuration: configuration,
            credentialStore: credentials,
          );
      if (provider.account != configuration.account) {
        throw const FormatException();
      }
    } on Object {
      credentials.clear();
      session.dispose();
      setState(() {
        _busy = false;
        _error = widget.strings.mailConnectionFailed;
      });
      return;
    }
    final lease = session.begin();
    setState(() {
      _provider = provider;
      _submission = provider;
      _session = session;
      _credentials = credentials;
      _draftIdentity = identity;
      _busy = true;
      _error = null;
      _notice = null;
    });
    await _establish(provider, session, lease, sender);
  });

  Future<void> _establish(
    MailProvider provider,
    MailAccountSession session,
    MailOperationLease lease,
    String sender,
  ) async {
    try {
      await _validateActiveAccount();
      if (!_current(provider, lease)) return;
      final capabilities = await provider.capabilities(lease);
      if (!_current(provider, lease)) return;
      final supported = _value(capabilities);
      if (!supported.supports(MailCapability.mail)) {
        throw const _EwsUiFailure(MailProblem(MailProblemCode.unsupported));
      }
      await _validateActiveAccount();
      if (!_current(provider, lease)) return;
      final folders = await provider.listMailboxes(lease);
      if (!_current(provider, lease)) return;
      final boxes = _value(folders);
      if (boxes.isEmpty) {
        throw const _EwsUiFailure(MailProblem(MailProblemCode.unavailable));
      }
      final inbox =
          boxes
              .where(
                (box) => const {
                  'inbox',
                  'posteingang',
                  'علبة الوارد',
                }.contains(box.displayName.toLowerCase()),
              )
              .firstOrNull ??
          boxes.first;
      await _validateActiveAccount();
      if (!_current(provider, lease)) return;
      final response = await provider.fetchHeaders(
        inbox.id,
        limit: _pageSize,
        lease: lease,
      );
      if (!_current(provider, lease)) return;
      final page = _value(response);
      _validateHeaderPage(page, inbox.id, limit: _pageSize);
      await _validateActiveAccount();
      if (!_current(provider, lease)) return;
      setState(() {
        _usedHeaderCursors.clear();
        _confirmedRead.clear();
        _confirmedFlagged.clear();
        _connected = true;
        _capabilities = supported;
        _busy = true;
        _sender = sender;
        _mailboxes = boxes;
        _mailbox = inbox;
        _headers = page.messages;
        _next = page.next;
        _password.clear();
        _clientSecret.clear();
      });
      await _restoreDraftStore(provider, session, lease);
      await _validateActiveAccount();
      if (_current(provider, lease)) {
        // The selected sign-in intent is fulfilled. Remembering this successful
        // connection may advance its directory revision; later explicit
        // reconnects must not reject that revision as a stale pending choice.
        _expectedAccount = null;
        _connectionTarget = null;
        _connectionDirectory = null;
        setState(() => _busy = false);
      }
    } on Object catch (error) {
      if (!_current(provider, lease)) return;
      if (error is _AccountNavigationExpired) {
        _disconnect(
          forNavigation: true,
          deferLocalClose: _retiredDraftStore != null,
        );
        setState(() {
          _navigating = false;
          _error = _retiredDraftStore == null
              ? widget.strings.mailAccountNavigationChanged
              : widget.strings.mailAccountNavigationReleaseFailed;
        });
        return;
      }
      _disconnect();
      setState(() {
        _error = error is _EwsUiFailure
            ? _problem(error.problem, widget.strings.mailConnectionFailed)
            : widget.strings.mailConnectionFailed;
      });
    }
  }

  Future<void> _connectCloud() async {
    final sender = _email.text.trim();
    late final StudioMailDraftAccount identity;
    late final MailOAuthConfiguration authorization;
    late final MailCloudConfiguration configuration;
    try {
      authorization = MailOAuthConfiguration(
        service: widget.cloudService!,
        clientId: _clientId.text.trim(),
        tenant: _tenant.text.trim(),
        clientSecret: _clientSecret.text.isEmpty ? null : _clientSecret.text,
      );
      identity = StudioMailDraftAccount(
        provider: widget.cloudService == MailCloudService.gmail
            ? 'gmail'
            : 'graph',
        endpoint: widget.cloudService == MailCloudService.gmail
            ? 'https://gmail.googleapis.com/gmail/v1'
            : 'https://graph.microsoft.com/v1.0',
        login: widget.cloudService == MailCloudService.gmail
            ? sender
            : jsonEncode([authorization.tenant, sender]),
        sender: sender,
      );
      configuration = MailCloudConfiguration(
        account: identity.account,
        service: widget.cloudService!,
        mailboxAddress: sender,
      );
    } on Object {
      setState(() => _error = widget.strings.mailCloudInvalidSettings);
      return;
    }
    if (!await _prepareConnection(identity)) return;
    final session = MailAccountSession(configuration.account);
    final lease = session.begin();
    final MailCloudLogSink? log = _diagnostics
        ? (event) => debugPrint(jsonEncode(event.toJson()))
        : null;
    bool current() =>
        mounted &&
        identical(_session, session) &&
        lease.isCurrent &&
        identical(_initialAccountSource, widget.initialAccount) &&
        (_connectionTarget == null ||
            identical(_connectionDirectory, _localAccounts));
    setState(() {
      _session = session;
      _draftIdentity = identity;
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await (widget.cloudAuthorizer ?? authorizeMailCloud)(
        configuration: authorization,
        account: configuration.account,
        openBrowser:
            widget.openBrowser ??
            (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
        lease: lease,
        log: log,
      );
      if (!current()) {
        if (result case MailSuccess<MailCloudTokenSource>(:final value)) {
          try {
            value.dispose();
          } on Object {
            /* Stale tokens must be retired. */
          }
        }
        return;
      }
      final tokens = _value(result);
      _tokens = tokens;
      await _validateActiveAccount();
      if (!current()) return;
      final provider = (widget.cloudProviderFactory ?? createMailCloudProvider)(
        configuration: configuration,
        tokenSource: tokens,
        log: log,
      );
      _cloudProvider = provider;
      if (provider.account != configuration.account) {
        throw const FormatException();
      }
      setState(() {
        _provider = provider;
        _submission = provider;
      });
      await _establish(provider, session, lease, sender);
    } on Object catch (error) {
      if (!current()) return;
      session.dispose();
      _closeCloud();
      setState(() {
        _session = null;
        _provider = null;
        _submission = null;
        _busy = false;
        _clientSecret.clear();
        _error = error is _AccountNavigationExpired
            ? widget.strings.mailAccountNavigationChanged
            : error is _EwsUiFailure
            ? _problem(error.problem, widget.strings.mailCloudSignInFailed)
            : widget.strings.mailCloudSignInFailed;
      });
    }
  }

  Future<void> _disconnectFromUi() async {
    if (_session == null ||
        _dialogOpen ||
        _navigating ||
        _routeRetired ||
        _retiredDraftStore != null ||
        _mailboxViewReleaseFailed) {
      return;
    }
    final epoch = ++_accountEpoch;
    bool current() => mounted && epoch == _accountEpoch;
    // Cancel provider work immediately, including authorization or a pending
    // draft factory. A later sign-in still waits for every acquired local owner.
    _disconnect(forNavigation: true, deferLocalClose: true);
    var observerReleased = true;
    final observerDrain = _stopCachedView().catchError((
      Object _,
      StackTrace _,
    ) {
      observerReleased = false;
    });
    try {
      // Closing the observer also resolves a restoration waiting for its first
      // cache snapshot. Drain both before owner close, preserving the first
      // failed cancellation for explicit Close instead of silently retrying it.
      await _draftRestoration;
      await observerDrain;
      if (!current()) return;
      if (!observerReleased) throw const _AccountOwnerReleaseFailure();
      await _releaseRetiredAccount();
      _checkDraftStoresReleased();
    } on Object {
      if (current()) {
        setState(
          () => _error = widget.strings.mailAccountNavigationReleaseFailed,
        );
      }
    } finally {
      if (current()) setState(() => _navigating = false);
    }
  }

  void _disconnect({bool forNavigation = false, bool deferLocalClose = false}) {
    if (!forNavigation &&
        (_navigating || _routeRetired || _retiredDraftStore != null)) {
      return;
    }
    if (!forNavigation) _accountEpoch++;
    _mailboxGeneration++;
    _bulkCancellation?.cancel(MailCancellationReason.accountChanged);
    _bulkCancellation = null;
    _mailboxCapture?.dispose();
    _mailboxCapture = null;
    final draftStore = _draftStore;
    _draftStore = null;
    _draftIdentity = null;
    _connectionTarget = null;
    _connectionDirectory = null;
    _session?.dispose();
    _credentials?.clear();
    _closeCloud();
    final old = _reader;
    setState(() {
      _session = null;
      _provider = null;
      _submission = null;
      _credentials = null;
      _capabilities = const MailCapabilities.none();
      _connected = false;
      _busy = false;
      _dialogOpen = false;
      _navigating = forNavigation;
      _mailboxes = const [];
      _mailbox = null;
      _headers = const [];
      _confirmedRead.clear();
      _confirmedFlagged.clear();
      _next = null;
      _selected = null;
      _reader = null;
      _draft = null;
      _submissionUncertain = false;
      _showMessage = false;
      _needsRefresh = false;
      _bulkReport = null;
      _bulkSubjects = const {};
      _password.clear();
      _clientSecret.clear();
      _usedHeaderCursors.clear();
      _error = null;
      _notice = null;
      _cacheViewWarning = null;
      _cacheBodyWarning = null;
      _sender = '';
    });
    _retire(old);
    if (deferLocalClose) {
      _retiredDraftStore ??= draftStore;
    } else {
      _draftStoreClosing = _draftStoreClosing.then(
        (_) => _closeDraftStore(draftStore),
      );
      unawaited(_draftStoreClosing);
    }
  }

  Future<void> _releaseRetiredAccount() {
    if (_navigationClosing case final pending?) return pending;
    final releasing = () async {
      await _draftStoreClosing;
      final owner = _retiredDraftStore;
      // Retain both handles until their cleanup succeeds. Unlike best-effort
      // widget disposal, a visible account transition must report a failed
      // release and must not open the next account while the owner is held.
      await _stopCachedView(retryFailed: true);
      await _pendingFlagWrite;
      await owner?.close();
      if (identical(_retiredDraftStore, owner)) _retiredDraftStore = null;
    }();
    _navigationClosing = releasing;
    unawaited(
      releasing.then<void>(
        (_) {
          if (identical(_navigationClosing, releasing)) {
            _navigationClosing = null;
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_navigationClosing, releasing)) {
            _navigationClosing = null;
          }
        },
      ),
    );
    return releasing;
  }

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
      // A custom owner may still hold an exclusive lease after failure. Keep
      // the reference and require an explicit retry before another sign-in.
      if (store != null &&
          !_unreleasedDraftStores.any((owner) => identical(owner, store))) {
        _unreleasedDraftStores.add(store);
      }
    }
  }

  Future<void> _requireReleasedDraftStores({bool allowRetired = false}) async {
    try {
      await _navigationClosing;
    } on Object {
      throw const _AccountOwnerReleaseFailure();
    }
    await _draftStoreClosing;
    for (final store in List<StudioMailDraftStore>.of(_unreleasedDraftStores)) {
      await _closeDraftStore(store);
    }
    _checkDraftStoresReleased(allowRetired: allowRetired);
  }

  void _checkDraftStoresReleased({bool allowRetired = false}) {
    if (_unreleasedDraftStores.isNotEmpty ||
        _mailboxViewReleaseFailed ||
        (!allowRetired && _retiredDraftStore != null)) {
      throw const _AccountOwnerReleaseFailure();
    }
  }

  Future<bool> _restoreDraftStore(
    MailProvider provider,
    MailAccountSession session,
    MailOperationLease lease,
  ) {
    final restoring = _restoreDraftStoreForConnection(provider, session, lease);
    _draftRestoration = () async {
      try {
        await restoring;
      } on Object {
        // The connection caller reports failures. A new sign-in still waits
        // for this attempt to finish releasing any late acquired owner.
      }
    }();
    return restoring;
  }

  Future<bool> _restoreDraftStoreForConnection(
    MailProvider provider,
    MailAccountSession session,
    MailOperationLease lease,
  ) async {
    if (!_current(provider, lease)) return false;
    if (_draftStore != null) return true;
    final identity = _draftIdentity;
    if (identity == null) return false;
    StudioMailDraftStore? candidate;
    var adopted = false;
    setState(() {
      _busy = true;
      _localAccountWarning = null;
    });
    try {
      await _requireReleasedDraftStores();
      if (!_current(provider, lease)) return false;
      await _validateActiveAccount();
      if (!_current(provider, lease)) return false;
      candidate = await (widget.draftStoreFactory ?? openStudioMailDraftStore)(
        identity,
      );
      await _validateActiveAccount();
      if (!_current(provider, lease)) {
        if (!identical(candidate, _retiredDraftStore)) {
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
      await _validateActiveAccount();
      if (!_current(provider, lease)) {
        if (!identical(candidate, _retiredDraftStore)) {
          await _closeDraftStore(candidate);
        }
        return false;
      }
      adopted = true;
      setState(() {
        _draftStore = candidate;
        _draft = restored?.draft;
        _submissionUncertain = restored?.submissionUncertain ?? false;
        _error = _submissionUncertain
            ? widget.strings.mailSubmissionUncertain
            : null;
        if (restored != null) _notice = widget.strings.mailDraftRestored;
      });
      final mailboxOwner = switch (candidate) {
        StudioMailMailboxStoreOwner owner => owner,
        _ => null,
      };
      if (mailboxOwner != null) {
        final owner = candidate;
        await _stopCachedView();
        await _validateActiveAccount();
        if (!_current(provider, lease) || !identical(owner, _draftStore)) {
          return false;
        }
        _mailboxCapture?.dispose();
        _mailboxCapture = StudioMailMailboxCapture(
          store: mailboxOwner.mailboxStore,
          sourceAccount: provider.account,
          provider: identity.provider,
          isCurrent: () =>
              _current(provider, lease) && identical(owner, _draftStore),
        );
        await _saveCachedView(provider, lease);
        await _validateActiveAccount();
        if (!_current(provider, lease)) return false;
      }
      final directory = _localAccounts;
      if (directory != null && candidate is StudioMailDraftCatalog) {
        final target = _connectionTarget;
        if (target != null) {
          try {
            await target.rememberConnection(
              directory,
              identity,
              isCurrent: () => _current(provider, lease),
            );
          } on Object {
            throw const _AccountNavigationExpired();
          }
          if (!_current(provider, lease)) return false;
          // An atomic refresh advances the selected revision. Fulfill the
          // intent here so the final validation does not reject our own write.
          _expectedAccount = null;
          _connectionTarget = null;
          _connectionDirectory = null;
          return true;
        }
        try {
          await _validateActiveAccount();
          if (!_current(provider, lease)) return false;
          await directory.remember(identity);
        } on _AccountNavigationExpired {
          rethrow;
        } on Object {
          if (_current(provider, lease)) {
            setState(
              () => _localAccountWarning =
                  widget.strings.mailLocalAccountsSaveFailed,
            );
          }
        }
      }
      return _current(provider, lease);
    } on Object catch (error) {
      if (candidate != null && identical(candidate, _retiredDraftStore)) {
        // An explicit transition already owns this adopted candidate. Its
        // release attempt alone decides success or exposes a retryable failure.
        if (error is _AccountNavigationExpired) rethrow;
        return false;
      }
      final ownsCandidate =
          candidate != null && (!adopted || identical(candidate, _draftStore));
      if (ownsCandidate && identical(candidate, _draftStore)) {
        _draftStore = null;
        _draft = null;
        _submissionUncertain = false;
      }
      if (error is _AccountNavigationExpired) {
        if (ownsCandidate) {
          _mailboxCapture?.dispose();
          _mailboxCapture = null;
          // Keep observer cancellation and owner close in one release path.
          // A detached adopted candidate is already owned by disconnect.
          _retiredDraftStore = candidate;
          try {
            await _releaseRetiredAccount();
          } on Object {
            // Retain the owner for explicit Close recovery. The outer handler
            // retires the provider and blocks another account from opening.
          }
        }
        rethrow;
      }
      if (ownsCandidate) await _closeDraftStore(candidate);
      if (_current(provider, lease)) {
        setState(() => _error = widget.strings.mailDraftStorageFailed);
      }
      return false;
    } finally {
      if (_current(provider, lease)) setState(() => _busy = false);
    }
  }

  Future<bool> _clearAcceptedDraft(StudioMailDraftStore store) async {
    try {
      await store.clear();
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _saveCachedView(
    MailProvider provider,
    MailOperationLease lease,
  ) async {
    final capture = _mailboxCapture;
    final mailbox = _mailbox;
    if (capture == null || mailbox == null || !_current(provider, lease)) {
      return;
    }
    final generation = _mailboxGeneration;
    final headers = [for (final header in _headers) _capturedHeader(header)];
    bool current() =>
        _current(provider, lease) &&
        generation == _mailboxGeneration &&
        identical(capture, _mailboxCapture) &&
        identical(mailbox, _mailbox);
    try {
      await _stopCachedView();
      if (!current()) return;
      final saved = await capture.saveView(
        mailbox,
        headers,
        hasMore: _next != null,
      );
      if (!current()) return;
      final session = StudioMailMailboxSession(
        store: capture.store,
        provider: capture.provider,
      );
      _mailboxViewSession = session;
      final viewGeneration = _mailboxViewGeneration;
      final repositoryFlags = <MailRemoteIdentity, MailMessageFlags?>{};
      void accept(StudioMailMailboxSnapshot snapshot) {
        if (!current() ||
            viewGeneration != _mailboxViewGeneration ||
            !identical(session, _mailboxViewSession)) {
          return;
        }
        if (snapshot.phase == StudioMailMailboxPhase.loading) return;
        try {
          final view = snapshot.view;
          if (snapshot.phase != StudioMailMailboxPhase.ready || view == null) {
            throw const StudioMailMailboxStoreException(
              MailProblemCode.storageFailure,
            );
          }
          final projected = capture.projectView(view);
          setState(() {
            _headers = projected;
            if (_selected case final selected?) {
              _selected = projected
                  .where((header) => header.remote == selected.remote)
                  .firstOrNull;
            }
            for (final header in projected) {
              final flags = header.flags;
              final previous = repositoryFlags[header.remote];
              final hadPrevious = repositoryFlags.containsKey(header.remote);
              if (flags != null) {
                if (_confirmedRead[header.remote] == flags.isRead ||
                    hadPrevious && previous?.isRead != flags.isRead) {
                  _confirmedRead.remove(header.remote);
                }
                if (_confirmedFlagged[header.remote] == flags.isFlagged ||
                    hadPrevious && previous?.isFlagged != flags.isFlagged) {
                  _confirmedFlagged.remove(header.remote);
                }
              }
              repositoryFlags[header.remote] = flags;
            }
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

  MailHeaderRecord _capturedHeader(MailHeaderRecord observed) {
    final flags = observed.flags;
    return MailHeaderRecord(
      id: observed.id,
      remote: observed.remote,
      envelope: observed.envelope,
      flags: flags == null
          ? null
          : MailMessageFlags(
              isRead: _confirmedRead[observed.remote] ?? flags.isRead,
              isFlagged: _confirmedFlagged[observed.remote] ?? flags.isFlagged,
              isAnswered: flags.isAnswered,
              isDraft: flags.isDraft,
              isDeleted: flags.isDeleted,
            ),
    );
  }

  Future<void> _stopCachedView({bool retryFailed = false}) {
    _mailboxViewGeneration++;
    _mailboxCapture?.invalidateView();
    final previous = _mailboxViewClosing;
    final stopping = () async {
      await previous;
      if (_mailboxViewReleaseFailed && !retryFailed) {
        throw const _AccountOwnerReleaseFailure();
      }
      final session = _mailboxViewSession;
      final subscription = _mailboxViewSubscription;
      try {
        await Future.wait<void>([
          if (session != null) session.close(),
          if (subscription != null) subscription.cancel(),
        ]);
      } on Object {
        _mailboxViewReleaseFailed = true;
        if (mounted) {
          setState(
            () => _error = widget.strings.mailAccountNavigationReleaseFailed,
          );
        }
        throw const _AccountOwnerReleaseFailure();
      }
      if (identical(_mailboxViewSession, session)) _mailboxViewSession = null;
      if (identical(_mailboxViewSubscription, subscription)) {
        _mailboxViewSubscription = null;
      }
      _mailboxViewReleaseFailed = false;
    }();
    // Later cleanup must reach the retained handles, not inherit a poisoned
    // future. Only an explicit release may retry a failed ordinary replacement.
    _mailboxViewClosing = stopping.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return stopping;
  }

  void _validateHeaderPage(
    MailHeaderPage page,
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
  }) {
    final next = page.next;
    final kind = switch (widget.cloudService) {
      MailCloudService.gmail => MailProviderKind.gmail,
      MailCloudService.microsoft365 => MailProviderKind.graph,
      null => MailProviderKind.ews,
    };
    if (page.messages.length > limit ||
        _usedHeaderCursors.length >= _maxHeaders) {
      throw const _EwsUiFailure(MailProblem(MailProblemCode.quotaExceeded));
    }
    if (page.messages.any(
          (header) =>
              header.remote.account != mailbox.account ||
              header.remote.provider != kind,
        ) ||
        page.messages.map((header) => header.remote).toSet().length !=
            page.messages.length ||
        page.messages.map((header) => header.id).toSet().length !=
            page.messages.length ||
        next != null &&
            (next.mailbox != mailbox ||
                next.value.isEmpty ||
                next.value == cursor?.value ||
                _usedHeaderCursors.contains(next.value))) {
      throw const _EwsUiFailure(MailProblem(MailProblemCode.conflict));
    }
  }

  Future<void> _loadHeaders(MailMailbox mailbox, {bool more = false}) async {
    final provider = _provider;
    final session = _session;
    if (provider == null ||
        session == null ||
        _blocked ||
        more &&
            (_needsRefresh ||
                _next == null ||
                _headers.length >= _maxHeaders)) {
      return;
    }
    final lease = session.begin();
    final old = more ? null : _reader;
    final cursor = more ? _next : null;
    setState(() => _busy = true);
    try {
      await _stopCachedView();
    } on _AccountOwnerReleaseFailure {
      if (_current(provider, lease)) setState(() => _busy = false);
      return;
    }
    if (!_current(provider, lease)) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      if (!more) {
        _mailboxGeneration++;
        _bulkReport = null;
        _bulkSubjects = const {};
        _mailbox = mailbox;
        _selected = null;
        _reader = null;
        _headers = const [];
        _confirmedRead.clear();
        _confirmedFlagged.clear();
        _next = null;
        _usedHeaderCursors.clear();
        _showMessage = false;
      }
    });
    _retire(old);
    final remaining = _maxHeaders - (more ? _headers.length : 0);
    final limit = remaining < _pageSize ? remaining : _pageSize;
    try {
      final response = await provider.fetchHeaders(
        mailbox.id,
        cursor: cursor,
        limit: limit,
        lease: lease,
      );
      if (!_current(provider, lease)) return;
      final page = _value(response);
      _validateHeaderPage(page, mailbox.id, cursor: cursor, limit: limit);
      final byId = <MailRemoteIdentity, MailHeaderRecord>{
        if (more)
          for (final header in _headers) header.remote: header,
        for (final header in page.messages) header.remote: header,
      };
      if (byId.values.map((header) => header.id).toSet().length !=
          byId.length) {
        throw const _EwsUiFailure(MailProblem(MailProblemCode.conflict));
      }
      setState(() {
        if (cursor != null) _usedHeaderCursors.add(cursor.value);
        for (final header in page.messages) {
          // A later observed snapshot supersedes a confirmed local command.
          // An omitted snapshot has observed neither flag and cannot do so.
          if (header.flags != null) {
            _confirmedRead.remove(header.remote);
            _confirmedFlagged.remove(header.remote);
          }
        }
        _headers = byId.values.toList();
        if (more && _selected != null) _selected = byId[_selected!.remote];
        _next = page.next;
        if (!more) _needsRefresh = false;
        if (_headers.length >= _maxHeaders && _next != null) {
          _notice = widget.strings.mailWorkspaceLimit;
        }
      });
      await _saveCachedView(provider, lease);
      if (_current(provider, lease)) setState(() => _busy = false);
    } on Object catch (error) {
      if (!_current(provider, lease)) return;
      setState(() {
        _busy = false;
        if (error is _EwsUiFailure &&
            error.problem.code == MailProblemCode.conflict) {
          _needsRefresh = true;
          _error = widget.strings.mailWorkspaceRefreshRequired;
        } else {
          _error = error is _EwsUiFailure
              ? _problem(error.problem, widget.strings.mailMailboxFailed)
              : widget.strings.mailMailboxFailed;
        }
      });
    }
  }

  Future<void> _openMessage(MailHeaderRecord header) async {
    final provider = _provider;
    final session = _session;
    if (provider == null || session == null || _blocked) return;
    final lease = session.begin();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await provider.fetchMessage(
        header.remote,
        budget: const MailReadBudget(),
        lease: lease,
      );
      if (!_current(provider, lease)) return;
      final message = _value(result);
      if (message.remoteIdentity != header.remote ||
          message.localId != null && message.localId != header.id) {
        throw const _EwsUiFailure(MailProblem(MailProblemCode.conflict));
      }
      final next = MailReaderController(
        result: MailParseResult(
          status: MailParseStatus.complete,
          message: message,
        ),
        preferHtml: false,
        includeHeaders: false,
        labels: StudioMailReaderLabels(widget.strings.language),
      );
      final old = _reader;
      setState(() {
        _reader = next;
        _selected = header;
        _showMessage = true;
      });
      _retire(old);
      final capture = _mailboxCapture;
      if (capture != null) {
        try {
          await capture.cacheMessage(header, message);
          if (_current(provider, lease)) {
            setState(() => _cacheBodyWarning = null);
          }
        } on Object {
          if (_current(provider, lease)) {
            setState(
              () => _cacheBodyWarning = widget.strings.mailCacheSaveFailed,
            );
          }
        }
      }
      if (_current(provider, lease)) setState(() => _busy = false);
    } on Object catch (error) {
      if (!_current(provider, lease)) return;
      setState(() {
        _busy = false;
        _error = error is _EwsUiFailure
            ? _problem(error.problem, widget.strings.mailMessageFailed)
            : widget.strings.mailMessageFailed;
      });
    }
  }

  Future<void> _apply(MailOperation command) async {
    final provider = _provider;
    final session = _session;
    final selected = _selected;
    if (provider == null ||
        session == null ||
        selected == null ||
        _blocked ||
        _needsRefresh ||
        command.message != selected.remote) {
      return;
    }
    await _applyCommands(
      switch (command) {
        MailSetRead(:final read) =>
          read ? MailBulkFlagAction.markRead : MailBulkFlagAction.markUnread,
        MailSetFlagged(:final flagged) =>
          flagged ? MailBulkFlagAction.flag : MailBulkFlagAction.unflag,
        MailMove() => MailBulkFlagAction.move,
        MailDelete() => MailBulkFlagAction.delete,
        MailArchive() => MailBulkFlagAction.archive,
      },
      ['ews-message-${selected.id.value}'],
      mailboxGeneration: _mailboxGeneration,
      singleMessage: true,
      membershipConfirmed: true,
      destination: command is MailMove ? command.destination : null,
    );
  }

  Future<void> _applyBulkAction(
    MailBulkFlagAction action,
    List<String> ids, {
    required int mailboxGeneration,
    bool singleMessage = false,
  }) async {
    if (action.isFlagAction) {
      await _applyCommands(action, ids, mailboxGeneration: mailboxGeneration);
      return;
    }
    final provider = _provider;
    final session = _session;
    final mailbox = _mailbox;
    final owner = _draftStore;
    if (!mounted ||
        provider == null ||
        session == null ||
        mailbox == null ||
        _blocked ||
        _needsRefresh ||
        mailboxGeneration != _mailboxGeneration ||
        ids.isEmpty ||
        ids.length > MailBulkFlagPlan.maxMessages ||
        ids.toSet().length != ids.length ||
        (action == MailBulkFlagAction.move &&
            (widget.cloudService == MailCloudService.gmail ||
                !_capabilities.supports(MailCapability.move))) ||
        (action == MailBulkFlagAction.delete &&
            !_capabilities.supports(MailCapability.delete)) ||
        (action == MailBulkFlagAction.archive && !_canArchive)) {
      return;
    }
    final frozenIds = List<String>.unmodifiable(ids);
    final selected = <MailHeaderRecord>[];
    for (final id in frozenIds) {
      final matches = _headers.where(
        (header) => 'ews-message-${header.id.value}' == id,
      );
      if (matches.length != 1) return;
      selected.add(matches.single);
    }
    final frozenSelection = List<MailHeaderRecord>.unmodifiable(selected);
    if (singleMessage &&
        (frozenSelection.length != 1 ||
            !identical(_selected, frozenSelection.single))) {
      return;
    }
    final archive = action == MailBulkFlagAction.archive;
    final gmailArchive =
        archive && widget.cloudService == MailCloudService.gmail;
    final lease = session.begin();
    bool currentScope() {
      if (!_current(provider, lease) ||
          !identical(_session, session) ||
          !identical(_draftStore, owner) ||
          !identical(_mailbox, mailbox) ||
          mailboxGeneration != _mailboxGeneration ||
          (singleMessage && !identical(_selected, frozenSelection.single)) ||
          _busy ||
          _needsRefresh) {
        return false;
      }
      final current = {for (final header in _headers) header.id: header.remote};
      return frozenSelection.every(
        (target) => current[target.id] == target.remote,
      );
    }

    MailMailboxId? destination;
    MailMailbox? resolvedArchive;
    var confirmed = false;
    setState(() => _dialogOpen = true);
    try {
      if (archive &&
          !gmailArchive &&
          provider is MailArchiveDestinationResolver) {
        final resolution = await (provider as MailArchiveDestinationResolver)
            .resolveArchiveDestination(lease);
        if (!currentScope()) return;
        switch (resolution) {
          case MailSuccess<MailMailbox>(:final value):
            if (value.id.account != provider.account || value.isLabel) {
              setState(() => _error = widget.strings.mailMutationCheckFailed);
              return;
            }
            if (value.id == mailbox.id) {
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
      if (!mounted || !currentScope()) return;
      if (gmailArchive) {
        confirmed = await confirmStudioMailGmailArchiveSelection(
          context,
          strings: widget.strings,
          count: frozenSelection.length,
          accountLabel: _sender,
          source: mailbox,
        );
      } else if (archive) {
        destination = await showStudioMailArchiveSelection(
          context,
          strings: widget.strings,
          count: frozenSelection.length,
          accountLabel: _sender,
          source: mailbox,
          destinations: List<MailMailbox>.unmodifiable(_mailboxes),
          resolvedDestination: resolvedArchive,
        );
        confirmed = destination != null;
      } else if (action == MailBulkFlagAction.move) {
        destination = await showStudioMailMoveSelection(
          context,
          strings: widget.strings,
          count: frozenSelection.length,
          accountLabel: _sender,
          source: mailbox,
          destinations: List<MailMailbox>.unmodifiable(_mailboxes),
        );
        confirmed = destination != null;
      } else {
        confirmed = await confirmStudioMailDeleteSelection(
          context,
          strings: widget.strings,
          count: frozenSelection.length,
          accountLabel: _sender,
          source: mailbox,
          provider: frozenSelection.first.remote.provider,
        );
      }
    } on Object {
      if (currentScope()) {
        setState(() => _error = widget.strings.mailMutationCheckFailed);
      }
    } finally {
      if (mounted &&
          identical(_provider, provider) &&
          identical(_session, session)) {
        setState(() => _dialogOpen = false);
      }
    }
    if (!confirmed || !currentScope()) return;
    await _applyCommands(
      archive && !gmailArchive ? MailBulkFlagAction.move : action,
      frozenIds,
      mailboxGeneration: mailboxGeneration,
      membershipConfirmed: true,
      frozenSelection: frozenSelection,
      destination: destination,
      singleMessage: singleMessage,
      resolvedArchiveDestination: resolvedArchive?.id,
    );
  }

  Future<void> _applyCommands(
    MailBulkFlagAction action,
    List<String> ids, {
    required int mailboxGeneration,
    bool singleMessage = false,
    bool membershipConfirmed = false,
    List<MailHeaderRecord>? frozenSelection,
    MailMailboxId? destination,
    MailMailboxId? resolvedArchiveDestination,
  }) async {
    final provider = _provider;
    final session = _session;
    final mailbox = _mailbox;
    if (!mounted ||
        provider == null ||
        session == null ||
        mailbox == null ||
        _blocked ||
        _needsRefresh ||
        mailboxGeneration != _mailboxGeneration ||
        ids.isEmpty ||
        ids.length > MailBulkFlagPlan.maxMessages ||
        ids.toSet().length != ids.length ||
        (!action.isFlagAction && !membershipConfirmed) ||
        (action == MailBulkFlagAction.move &&
            (widget.cloudService == MailCloudService.gmail ||
                !_capabilities.supports(MailCapability.move) ||
                destination == null ||
                destination == mailbox.id ||
                destination.account != provider.account ||
                (destination != resolvedArchiveDestination &&
                    !_mailboxes.any((folder) => folder.id == destination)))) ||
        (action == MailBulkFlagAction.delete &&
            !_capabilities.supports(MailCapability.delete)) ||
        (action == MailBulkFlagAction.archive && !_canArchive) ||
        (action != MailBulkFlagAction.move && destination != null)) {
      return;
    }
    if (frozenSelection != null && frozenSelection.length != ids.length) {
      return;
    }
    final selected = <MailHeaderRecord>[];
    for (var index = 0; index < ids.length; index++) {
      final matches = _headers.where(
        (header) => 'ews-message-${header.id.value}' == ids[index],
      );
      if (matches.length != 1) return;
      final frozen = frozenSelection?[index];
      if (frozen != null &&
          (frozen.id != matches.single.id ||
              frozen.remote != matches.single.remote)) {
        return;
      }
      selected.add(frozen ?? matches.single);
    }
    final lease = session.begin();
    final plan = MailBulkFlagPlan(
      id: newStudioMailFlagOperationId(),
      mailbox: mailbox.id,
      provider: selected.first.remote.provider,
      messages: [for (final header in selected) header.remote],
      action: action,
      destination: destination,
    );
    bool currentScope() {
      if (!_current(provider, lease) ||
          !identical(_session, session) ||
          mailboxGeneration != _mailboxGeneration ||
          !identical(_mailbox, mailbox)) {
        return false;
      }
      final current = {for (final header in _headers) header.id: header.remote};
      return selected.every((target) => current[target.id] == target.remote);
    }

    final cancellation = MailCancellationSource();
    final owner = _draftStore;
    final settled = Completer<void>();
    _pendingFlagWrite = settled.future;
    setState(() {
      _bulkCancellation = cancellation;
      _bulkReport = null;
      _bulkSubjects = Map.unmodifiable({
        for (final header in selected) header.remote: header.envelope.subject,
      });
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (!action.isFlagAction) {
        // Retire the saved observation before a membership change. Neither a
        // late cache event nor a stale capture can restore a moved row.
        await _stopCachedView();
      }
      final report = await MailBulkFlagCoordinator().run(
        plan: plan,
        lease: lease,
        cancellation: cancellation.token,
        isScopeCurrent: currentScope,
        journal: studioMailFlagJournal(
          owner: owner,
          requireDurable: widget.draftStoreFactory == null,
          sourceAccount: provider.account,
          provider: plan.provider,
          subjects: [for (final header in selected) header.envelope.subject],
          isCurrent: () => currentScope() && identical(owner, _draftStore),
        ),
        onProgress: (report) {
          if (currentScope() && identical(_bulkCancellation, cancellation)) {
            setState(() => _bulkReport = report);
          }
        },
        apply: (operation, operationLease) async {
          if (provider is MailMutationReceiptProvider) {
            return MailBulkFlagAttempt.fromReceiptResult(
              await (provider as MailMutationReceiptProvider).applyWithReceipt(
                operation,
                operationLease,
              ),
            );
          }
          return MailBulkFlagAttempt.fromResult(
            await provider.apply(operation, operationLease),
          );
        },
      );
      if (!currentScope()) return;
      MailReaderController? retiredReader;
      setState(() {
        _bulkReport = report;
        final updates = <MailRemoteIdentity, MailHeaderRecord>{};
        for (var i = 0; i < report.items.length; i++) {
          final result = report.items[i];
          if (result.outcome != MailBulkFlagOutcome.confirmed) continue;
          final header = selected[i];
          final operation = result.operation;
          if (operation is MailMove ||
              operation is MailDelete ||
              operation is MailArchive) {
            _confirmedRead.remove(header.remote);
            _confirmedFlagged.remove(header.remote);
            _headers = _headers
                .where((row) => row.remote != header.remote)
                .toList();
            if (_selected?.remote == header.remote) {
              retiredReader = _reader;
              _reader = null;
              _selected = null;
              _showMessage = false;
            }
            _next = null;
            continue;
          }
          if (operation is MailSetRead) {
            _confirmedRead[header.remote] = operation.read;
          } else if (operation is MailSetFlagged) {
            _confirmedFlagged[header.remote] = operation.flagged;
          }
          final flags = header.flags;
          updates[header.remote] = MailHeaderRecord(
            id: header.id,
            remote: header.remote,
            envelope: header.envelope,
            flags: flags == null
                ? null
                : MailMessageFlags(
                    isRead: operation is MailSetRead
                        ? operation.read
                        : flags.isRead,
                    isFlagged: operation is MailSetFlagged
                        ? operation.flagged
                        : flags.isFlagged,
                    isAnswered: flags.isAnswered,
                    isDraft: flags.isDraft,
                    isDeleted: flags.isDeleted,
                  ),
          );
        }
        _headers = [
          for (final header in _headers) updates[header.remote] ?? header,
        ];
        if (_selected case final opened?) {
          _selected = updates[opened.remote] ?? opened;
        }
        _notice = !action.isFlagAction && report.confirmedCount == 1
            ? (_cloud
                  ? widget.strings.mailCloudFolderChanged
                  : widget.strings.ewsFolderChanged)
            : singleMessage && report.confirmedCount == 1
            ? (_cloud
                  ? widget.strings.mailCloudActionConfirmed
                  : widget.strings.ewsActionConfirmed)
            : widget.strings.mailBulkSummary(report);
        if (report.requiresRefresh) {
          _needsRefresh = true;
          final problem =
              report.items.singleOrNull?.problem ?? report.stopProblem;
          _error = !action.isFlagAction && report.confirmedCount == 1
              ? null
              : singleMessage
              ? (problem == null
                    ? widget.strings.ewsMutationFailed
                    : _problem(problem, widget.strings.ewsMutationFailed))
              : widget.strings.mailWorkspaceRefreshRequired;
        }
      });
      _retire(retiredReader);
      // These are per-command confirmations. Persisting a synthetic full snapshot
      // here would turn unknown flags into invented observations.
    } on _AccountOwnerReleaseFailure {
      // The cache stop reports the failure and retains its observer handles.
      // No membership command may dispatch until explicit cleanup succeeds.
    } finally {
      settled.complete();
      if (identical(_pendingFlagWrite, settled.future)) {
        _pendingFlagWrite = null;
      }
      if (_current(provider, lease) &&
          identical(_bulkCancellation, cancellation)) {
        setState(() {
          _bulkCancellation = null;
          _busy = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final provider = _provider;
    final session = _session;
    final selected = _selected;
    if (provider == null ||
        session == null ||
        selected == null ||
        _blocked ||
        _needsRefresh ||
        !_capabilities.supports(MailCapability.delete)) {
      return;
    }
    final mailboxGeneration = _mailboxGeneration;
    final lease = session.begin();
    setState(() => _dialogOpen = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _cloud ? widget.strings.mailCloudDelete : widget.strings.ewsDelete,
        ),
        content: Text(
          _cloud
              ? widget.strings.mailCloudDeleteExplanation
              : widget.strings.ewsDeleteExplanation,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _cloud
                  ? widget.strings.mailCloudDelete
                  : widget.strings.ewsDelete,
            ),
          ),
        ],
      ),
    );
    if (!_current(provider, lease)) return;
    setState(() => _dialogOpen = false);
    if (confirmed == true &&
        mailboxGeneration == _mailboxGeneration &&
        _selected?.id == selected.id &&
        _selected?.remote == selected.remote) {
      await _apply(
        MailDelete(id: 'delete-${++_serial}', message: selected.remote),
      );
    }
  }

  StudioMailOutboxSubmit _outboxSubmit(
    MailProvider provider,
    MailSubmissionProvider submission,
    MailOperationLease lease,
    StudioMailOutboxStore store,
    String sender,
  ) => (message, {required attemptId}) async {
    if (!_current(provider, lease) ||
        message.account != store.account ||
        message.envelope.sender != sender) {
      return MailSubmissionResult(
        attemptId: attemptId,
        outcome: MailSubmissionOutcome.rejected,
      );
    }
    // The disk identity is stable across connections; provider identities belong
    // to this verified live session. Rebind only identity, never MIME/envelope.
    return submission.submit(
      MailPreparedMessage(
        account: provider.account,
        draftId: message.draftId,
        draftRevision: message.draftRevision,
        wire: message.wire,
        envelope: message.envelope,
      ),
      attemptId: attemptId,
      lease: lease,
    );
  };

  Future<void> _openOutbox() => runStudioMailOperation(() async {
    final provider = _provider;
    final session = _session;
    final submission = _submission;
    if (provider == null ||
        session == null ||
        submission == null ||
        !_connected ||
        _blocked) {
      return;
    }
    final lease = session.begin();
    if (!await _restoreDraftStore(provider, session, lease)) return;
    if (!mounted || !_current(provider, lease)) return;
    final store = switch (_draftStore) {
      StudioMailOutboxStore value => value,
      _ => null,
    };
    if (store == null) {
      setState(() => _error = widget.strings.mailOutboxFailed);
      return;
    }
    final sender = _sender;
    final draftOwner = _draftStore!;
    final catalog = draftOwner is StudioMailDraftCatalog
        ? draftOwner as StudioMailDraftCatalog
        : null;
    final originalEpoch = catalog?.selectionEpoch;
    StudioMailDraft? edited;
    var opened = false;
    bool current() =>
        _current(provider, lease) && identical(store, _draftStore);
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
          submit: _outboxSubmit(provider, submission, lease, store, sender),
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
          await _closeDraftStore(draftOwner);
        }
      }
      edited = null;
    } finally {
      if (_current(provider, lease)) setState(() => _dialogOpen = false);
    }
    if (edited != null && current()) await _compose();
  });

  Future<void> _sendThroughOutbox(
    StudioMailDraft draft,
    StudioMailOutboxStore store,
    MailProvider provider,
    MailOperationLease lease,
  ) async {
    final priorUncertainty = _submissionUncertain;
    final sender = _sender;
    final submission = _submission!;
    final accountEpoch = _accountEpoch;
    setState(() {
      _draft = draft;
      _busy = true;
      _error = null;
      _notice = null;
    });
    var queued = false;
    try {
      final entry = await store.enqueueOutbox(draft, sender);
      queued = true;
      if (!_current(provider, lease)) return;
      setState(() {
        _draft = null;
        _submissionUncertain = false;
        _notice = widget.strings.sending;
      });
      final completed = await submitStudioMailOutbox(
        store: store,
        entry: entry,
        submit: _outboxSubmit(provider, submission, lease, store, sender),
        isCurrent: () =>
            !_navigating &&
            accountEpoch == _accountEpoch &&
            _current(provider, lease) &&
            identical(store, _draftStore),
        acknowledgeUncertain: priorUncertainty,
      );
      if (!_current(provider, lease)) return;
      setState(() {
        _notice = completed.state == MailOutboxState.submitted
            ? (_cloud
                  ? widget.strings.mailCloudSubmissionAccepted
                  : widget.strings.ewsSubmissionAccepted)
            : '${widget.strings.mailOutboxState(completed.state)}. ${widget.strings.mailOutboxInspect}';
        if (completed.state == MailOutboxState.uncertain ||
            (completed.priorSubmissionUncertain &&
                completed.state != MailOutboxState.submitted)) {
          _error = widget.strings.mailOutboxUncertainExplanation;
        }
      });
    } on Object {
      if (_current(provider, lease)) {
        setState(() {
          _notice = null;
          _error = queued
              ? widget.strings.mailOutboxFailed
              : widget.strings.mailQueueFailed;
        });
      }
    } finally {
      if (_current(provider, lease)) setState(() => _busy = false);
    }
  }

  Future<void> _openDrafts() => runStudioMailOperation(() async {
    final provider = _provider;
    final session = _session;
    if (provider == null || session == null || !_connected || _blocked) return;
    final lease = session.begin();
    if (!await _restoreDraftStore(provider, session, lease)) return;
    if (!_current(provider, lease)) return;
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
        _current(provider, lease) && identical(store, _draftStore);
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
            _draftStore = null;
            _draft = null;
            _submissionUncertain = false;
          }
        });
        if (catalogOpened) await _closeDraftStore(store);
      }
      chosen = null;
    } finally {
      if (_current(provider, lease)) setState(() => _dialogOpen = false);
    }
    if (chosen != null && current()) await _compose();
  });

  Future<void> _compose([
    StudioMailDraft? initial,
  ]) => runStudioMailOperation(() async {
    final provider = _provider;
    final session = _session;
    if (provider == null || session == null || !_connected || _blocked) {
      return;
    }
    final lease = session.begin();
    if (!await _restoreDraftStore(provider, session, lease)) return;
    if (!mounted || !_current(provider, lease)) return;
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
        if (!_current(provider, lease)) return;
        final prepared = await prepareStudioMailComposeDraft(
          store,
          initial,
          replyOrForward: true,
          isCurrent: () =>
              _current(provider, lease) && identical(store, _draftStore),
        );
        if (!_current(provider, lease)) return;
        final created = catalog == null
            ? StudioMailStoredDraft(draft: prepared, submissionUncertain: false)
            : await catalog.createDraft(prepared);
        if (!_current(provider, lease)) return;
        setState(() {
          _draft = created.draft;
          _submissionUncertain = created.submissionUncertain;
          _error = null;
          _notice = null;
        });
      } on Object {
        if (_current(provider, lease)) {
          setState(() => _error = widget.strings.mailDraftListFailed);
        }
        return;
      } finally {
        if (_current(provider, lease)) setState(() => _busy = false);
      }
    } else if (initial != null && _draft != null) {
      setState(() => _error = widget.strings.mailRetainedDraft);
      return;
    }
    if (!mounted || !_current(provider, lease)) return;
    final selectedId = catalog?.selectedDraftId;
    final selectionEpoch = catalog?.selectionEpoch;
    final mailbox = switch (store) {
      StudioMailMailboxStoreOwner value => value.mailboxStore,
      _ => null,
    };
    bool currentDraft() =>
        _current(provider, lease) &&
        identical(store, _draftStore) &&
        catalog?.selectedDraftId == selectedId &&
        catalog?.selectionEpoch == selectionEpoch;
    setState(() => _dialogOpen = true);
    final draft = await showDialog<StudioMailDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StudioMailComposeDialog(
        strings: widget.strings,
        from: _sender,
        canSend: _canSend,
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
        onQueueDraft: outbox != null && _canSend
            ? (snapshot) async {
                if (!currentDraft()) {
                  throw const StudioMailDraftStoreException(
                    MailProblemCode.unavailable,
                  );
                }
                await outbox.enqueueOutbox(snapshot, _sender);
                if (_current(provider, lease)) {
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
          await store.save(snapshot, submissionUncertain: _submissionUncertain);
        },
      ),
    );
    if (!_current(provider, lease)) return;
    setState(() => _dialogOpen = false);
    if (draft == null || !currentDraft() || !_canSend) return;
    if (outbox != null) {
      await _sendThroughOutbox(draft, outbox, provider, lease);
      return;
    }
    setState(() {
      _draft = draft;
      _busy = true;
      _error = null;
      _notice = widget.strings.sending;
    });
    var attempted = false;
    final wasPreviouslyUncertain = _submissionUncertain;
    final accountEpoch = _accountEpoch;
    try {
      final wire = buildStudioMailMessage(draft, _sender).renderMessage();
      final attempt = '${_cloud ? 'cloud' : 'ews'}-send-${++_serial}';
      final message = MailPreparedMessage(
        account: provider.account,
        draftId: 'session-draft',
        draftRevision: _serial,
        wire: MailBytes(utf8.encode(wire)),
        envelope: MailTransportEnvelope(
          sender: _sender,
          recipients: draft.recipients.envelope,
        ),
      );
      lease.checkCurrent();
      await store.save(draft, submissionUncertain: true);
      lease.checkCurrent();
      _submissionUncertain = true;
      // Closing can wait for a separate retained-draft save. Its intent must
      // still stop this first dispatch if that save later fails and the host
      // remains open. A response already in flight keeps its persistence path.
      if (_navigating || accountEpoch != _accountEpoch) {
        setState(() => _notice = null);
        return;
      }
      attempted = true;
      final result = await _submission!.submit(
        message,
        attemptId: attempt,
        lease: lease,
      );
      final outcome = result.attemptId == attempt
          ? result.outcome
          : MailSubmissionOutcome.uncertain;
      if (outcome == MailSubmissionOutcome.rejected ||
          outcome == MailSubmissionOutcome.retryableFailure) {
        // Only a matching, definite provider result can retire this attempt's
        // marker. An earlier uncertain attempt remains guarded independently.
        await store.saveRejectedDraft(
          draft,
          wasPreviouslyUncertain: wasPreviouslyUncertain,
        );
      }
      final cleared = outcome == MailSubmissionOutcome.accepted
          ? await _clearAcceptedDraft(store)
          : false;
      if (!_current(provider, lease)) return;
      setState(() {
        _busy = false;
        _notice = null;
        _submissionUncertain = outcome == MailSubmissionOutcome.accepted
            ? !cleared
            : outcome == MailSubmissionOutcome.uncertain ||
                  wasPreviouslyUncertain;
        if (outcome == MailSubmissionOutcome.accepted) {
          _draft = cleared ? null : draft;
          _notice = !cleared
              ? widget.strings.mailDraftAcceptedCleanupFailed
              : _cloud
              ? widget.strings.mailCloudSubmissionAccepted
              : widget.strings.ewsSubmissionAccepted;
        } else {
          final feedback = _cloud && result.problem != null
              ? _problem(result.problem!, '')
              : '';
          _error = outcome == MailSubmissionOutcome.uncertain
              ? widget.strings.mailSubmissionUncertain
              : [
                  if (feedback.isNotEmpty) feedback,
                  widget.strings.ewsSubmissionRejected,
                ].join(' ');
        }
      });
    } on Object catch (error) {
      if (!_current(provider, lease)) return;
      setState(() {
        _busy = false;
        _notice = null;
        _submissionUncertain = _submissionUncertain || attempted;
        _error = _submissionUncertain
            ? widget.strings.mailSubmissionUncertain
            : error is StudioMailDraftStoreException
            ? widget.strings.mailDraftStorageFailed
            : widget.strings.ewsSubmissionRejected;
      });
    } finally {
      if (_current(provider, lease) && _busy) {
        setState(() => _busy = false);
      }
    }
  });

  Future<void> _reply({
    required bool forward,
    bool replyAll = false,
    bool includeAttachments = false,
  }) async {
    final result = _reader?.result;
    final message = result?.message;
    if (result == null || message == null || !_canSend || _blocked) return;
    // Legacy injected stores expose one slot; catalogs keep independent replies.
    // _compose also guards after asynchronous account-store restoration.
    if (_draft != null && _draftStore is! StudioMailDraftCatalog) {
      setState(() {
        _error = widget.strings.mailRetainedDraft;
        _notice = null;
      });
      return;
    }
    try {
      await _compose(
        includeAttachments
            ? buildStudioMailForwardWithAttachmentsDraft(
                result,
                truncationNotice: widget.strings.mailQuotedTextTruncated,
                forwardNotice: widget.strings.mailAttachedForwardNotice,
              )
            : replyAll
            ? buildStudioMailReplyAllDraft(
                message,
                sender: _sender,
                sourceStatus: result.status,
                truncationNotice: widget.strings.mailQuotedTextTruncated,
              )
            : buildStudioMailReplyDraft(
                message,
                forward: forward,
                sourceStatus: result.status,
                truncationNotice: widget.strings.mailQuotedTextTruncated,
                forwardNotice: widget.strings.mailTextOnlyForward,
              ),
      );
    } on StudioMailForwardAttachmentsUnavailable {
      if (mounted) {
        setState(() {
          _error = widget.strings.mailForwardAttachmentsUnavailable;
          _notice = null;
        });
      }
    } on StudioMailReplyRecipientsUnavailable {
      if (mounted) {
        setState(() => _error = widget.strings.mailReplyRecipientsUnavailable);
      }
    } on StudioMailReplyUnavailable {
      if (mounted) {
        setState(() => _error = widget.strings.mailPlainTextUnavailable);
      }
    }
  }

  Future<void> _openSynchronization() async {
    final provider = _provider;
    final session = _session;
    final owner = _draftStore;
    final mailbox = _mailbox;
    final store = switch (owner) {
      StudioMailMailboxStoreOwner value => value.mailboxStore,
      _ => null,
    };
    if (_blocked ||
        provider == null ||
        session == null ||
        mailbox == null ||
        store == null ||
        store is! StudioMailSyncStore ||
        store.account != provider.account) {
      return;
    }
    final syncStore = store as StudioMailSyncStore;
    final lease = session.begin();
    final mailboxGeneration = _mailboxGeneration;
    bool current() =>
        _current(provider, lease) &&
        mailboxGeneration == _mailboxGeneration &&
        identical(owner, _draftStore) &&
        _mailbox?.id == mailbox.id;
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
          download:
              ({
                required headers,
                required cancellation,
                required onProgress,
              }) =>
                  MailBodyDownloadRunner(
                    provider: provider,
                    cache: StudioMailBodyDownloadCache(store),
                    session: session,
                  ).run(
                    mailbox: mailbox.id,
                    headers: headers,
                    cancellation: cancellation,
                    onProgress: onProgress,
                    isCurrent: current,
                  ),
          run: ({required cancellation, required onProgress}) async {
            lease.checkCurrent();
            if (!current()) {
              throw const _EwsUiFailure(
                MailProblem(MailProblemCode.staleOperation),
              );
            }
            final saved = await syncStore.saveSyncMailbox(mailbox);
            if (saved case MailFailure<MailUnit>(:final problem)) {
              throw _EwsUiFailure(problem);
            }
            lease.checkCurrent();
            return const MailSyncRunner().run(
              provider: provider,
              repository: syncStore,
              session: session,
              mailbox: mailbox.id,
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

  Future<void> _discardDraft() async {
    final provider = _provider;
    final session = _session;
    if (provider == null || session == null || _draft == null || _blocked) {
      return;
    }
    final lease = session.begin();
    setState(() => _dialogOpen = true);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.mailDiscardDraft),
        content: Text(widget.strings.mailDiscardDraftExplanation),
        actions: [
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
    if (!_current(provider, lease)) return;
    if (discard == true) {
      try {
        await _draftStore!.clear();
      } on Object {
        if (_current(provider, lease)) {
          setState(() {
            _dialogOpen = false;
            _error = widget.strings.mailDraftSaveFailed;
          });
        }
        return;
      }
      if (!_current(provider, lease)) return;
    }
    setState(() {
      _dialogOpen = false;
      if (discard == true) {
        _draft = null;
        _submissionUncertain = false;
        _error = null;
        _notice = null;
      }
    });
  }

  Future<void> _openLocalAccounts() async {
    final directory = _localAccounts;
    if (directory == null || _connected || _session != null || _blocked) return;
    bool current() => mounted && !_connected && _session == null;
    setState(() => _dialogOpen = true);
    try {
      await _draftStoreClosing;
      if (!mounted || !current()) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StudioMailLocalAccountsDialog(
          strings: widget.strings,
          store: directory,
          provider: switch (widget.cloudService) {
            MailCloudService.gmail => MailProviderKind.gmail,
            MailCloudService.microsoft365 => MailProviderKind.graph,
            null => MailProviderKind.ews,
          },
          isCurrent: current,
          draftStoreFactory: widget.draftStoreFactory,
        ),
      );
    } on Object {
      if (current()) {
        setState(() => _error = widget.strings.mailLocalAccountsFailed);
      }
    } finally {
      if (current()) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _saveRetainedDraft() async {
    final draft = _draft;
    if (draft == null) return;
    final store = _draftStore;
    if (store == null) {
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    }
    await store.save(draft, submissionUncertain: _submissionUncertain);
  }

  Future<void> _navigateAccount() async {
    final directory = _localAccounts;
    final navigate = widget.onAccountNavigation;
    if (directory == null || navigate == null || _blocked) return;
    final epoch = ++_accountEpoch;
    final provider = _provider;
    final session = _session;
    final owner = _draftStore;
    final initialTarget = widget.initialAccount;
    final service = widget.cloudService;
    bool active() =>
        mounted &&
        epoch == _accountEpoch &&
        widget.onAccountNavigation != null &&
        identical(initialTarget, widget.initialAccount) &&
        service == widget.cloudService &&
        identical(directory, _localAccounts);
    bool current() =>
        active() &&
        identical(provider, _provider) &&
        identical(session, _session) &&
        identical(owner, _draftStore);
    var retired = false;
    var saving = false;
    setState(() => _dialogOpen = true);
    try {
      await _draftRestoration;
      if (!current()) return;
      await _requireReleasedDraftStores();
      if (!mounted || !current()) return;
      final target = await showStudioMailAccountNavigation(
        context: context,
        strings: widget.strings,
        store: directory,
        isCurrent: current,
        currentAccount: _connected ? _draftIdentity : null,
      );
      if (target == null || !current()) return;
      await target.validateCurrent(directory);
      if (!current()) return;
      setState(() => _navigating = true);
      saving = true;
      await _saveRetainedDraft();
      saving = false;
      if (!current()) return;
      // A target can be forgotten or replaced while the current draft saves.
      // Keep the current connection alive until that final pre-retirement check.
      await target.validateCurrent(directory);
      if (!current()) return;
      _disconnect(forNavigation: true, deferLocalClose: true);
      retired = true;
      await _releaseRetiredAccount();
      if (!active()) return;
      await target.validateCurrent(directory);
      if (!active()) return;
      setState(() => _routeRetired = true);
      navigate(target);
    } on Object catch (error) {
      if (active()) {
        setState(() {
          _routeRetired = false;
          _error =
              error is _AccountOwnerReleaseFailure || _retiredDraftStore != null
              ? widget.strings.mailAccountNavigationReleaseFailed
              : saving
              ? widget.strings.mailDraftSaveFailed
              : widget.strings.mailAccountNavigationChanged;
        });
      }
    } finally {
      if (active() && !_routeRetired && (retired || current())) {
        setState(() {
          _dialogOpen = false;
          _navigating = false;
        });
      }
    }
  }

  Future<void> _requestClose() async {
    if (_dialogOpen || _navigating || _routeRetired) {
      return;
    }
    final epoch = ++_accountEpoch;
    // Stop after the current reply even while preserving the retained draft.
    // The strict release below still drains that reply's durable receipt.
    _bulkCancellation?.cancel();
    bool current() => mounted && epoch == _accountEpoch;
    var saving = false;
    setState(() => _navigating = true);
    try {
      await _draftRestoration;
      if (!current()) return;
      if (_mailboxViewReleaseFailed) {
        await _stopCachedView(retryFailed: true);
        if (!current()) return;
      }
      await _requireReleasedDraftStores(allowRetired: true);
      if (!current()) return;
      if (_retiredDraftStore == null) {
        saving = true;
        await _saveRetainedDraft();
        if (!current()) return;
        saving = false;
        _disconnect(forNavigation: true, deferLocalClose: true);
      }
      await _releaseRetiredAccount();
      if (!mounted || !current()) return;
      setState(() => _allowPop = true);
      Navigator.pop(context);
    } on Object catch (error) {
      if (current()) {
        setState(() {
          _navigating = false;
          _error =
              error is _AccountOwnerReleaseFailure || _retiredDraftStore != null
              ? widget.strings.mailAccountNavigationReleaseFailed
              : saving
              ? widget.strings.mailDraftSaveFailed
              : widget.strings.mailAccountNavigationReleaseFailed;
        });
      }
    }
  }

  Future<void> _openFlagHistory() async {
    final provider = _provider;
    final session = _session;
    final owner = _draftStore;
    if (provider == null ||
        session == null ||
        owner is! StudioMailFlagJournalOwner ||
        _blocked) {
      return;
    }
    final lease = session.begin();
    bool current() =>
        _current(provider, lease) && identical(owner, _draftStore);
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
            observer: provider,
            provider: switch (widget.cloudService) {
              MailCloudService.gmail => MailProviderKind.gmail,
              MailCloudService.microsoft365 => MailProviderKind.graph,
              null => MailProviderKind.ews,
            },
            isCurrent: current,
            onChecked: () => setState(() {
              _needsRefresh = true;
              _error = widget.strings.mailWorkspaceRefreshRequired;
            }),
          ),
          onReconcileMembership: studioMailMembershipRecovery(
            store: store,
            observer: provider,
            provider: switch (widget.cloudService) {
              MailCloudService.gmail => MailProviderKind.gmail,
              MailCloudService.microsoft365 => MailProviderKind.graph,
              null => MailProviderKind.ews,
            },
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

  Widget _localAccountsButton() => OutlinedButton.icon(
    key: const ValueKey('studio-mail-known-drafts'),
    onPressed: _blocked ? null : _openLocalAccounts,
    icon: const Icon(Icons.folder_open_outlined),
    label: Text(widget.strings.mailLocalAccounts),
  );

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: _allowPop || _routeRetired,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_requestClose());
    },
    child: Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title, overflow: TextOverflow.ellipsis),
          actions: [
            if (widget.onAccountNavigation != null && _localAccounts != null)
              IconButton(
                key: const ValueKey('studio-mail-switch-account'),
                tooltip: widget.strings.mailAccountNavigationTitle,
                icon: const Icon(Icons.switch_account_outlined),
                onPressed: _blocked ? null : _navigateAccount,
              ),
            if (_connected) ...[
              if (_draftStore is StudioMailMailboxStoreOwner)
                IconButton(
                  key: const ValueKey('studio-mail-open-sync'),
                  tooltip: widget.strings.mailSync,
                  icon: const Icon(Icons.sync),
                  onPressed: _blocked || _mailbox == null
                      ? null
                      : _openSynchronization,
                ),
              IconButton(
                tooltip: widget.strings.compose,
                icon: const Icon(Icons.edit_outlined),
                onPressed: _blocked ? null : () => _compose(),
              ),
              IconButton(
                key: const ValueKey('studio-mail-open-drafts'),
                tooltip: widget.strings.mailDrafts,
                icon: const Icon(Icons.drafts_outlined),
                onPressed: _blocked ? null : _openDrafts,
              ),
              IconButton(
                key: const ValueKey('studio-mail-open-outbox'),
                tooltip: widget.strings.mailOutbox,
                icon: const Icon(Icons.outbox_outlined),
                onPressed: _blocked || !_canSend ? null : _openOutbox,
              ),
              if (_draftStore is StudioMailFlagJournalOwner)
                IconButton(
                  key: const ValueKey('studio-mail-open-activity'),
                  icon: const Icon(Icons.history),
                  tooltip: widget.strings.mailActivity,
                  onPressed: _blocked ? null : _openFlagHistory,
                ),
              IconButton(
                tooltip: widget.strings.refresh,
                icon: const Icon(Icons.refresh),
                onPressed: _blocked || _mailbox == null
                    ? null
                    : () => _loadHeaders(_mailbox!),
              ),
              if (_draft != null)
                IconButton(
                  tooltip: widget.strings.mailDiscardDraft,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _blocked ? null : _discardDraft,
                ),
            ],
            if (_session != null)
              IconButton(
                tooltip: widget.strings.disconnect,
                icon: const Icon(Icons.logout),
                onPressed:
                    _dialogOpen ||
                        _navigating ||
                        _routeRetired ||
                        _mailboxViewReleaseFailed ||
                        _retiredDraftStore != null
                    ? null
                    : _disconnectFromUi,
              ),
            IconButton(
              tooltip: widget.strings.close,
              icon: const Icon(Icons.close),
              onPressed: _dialogOpen || _navigating || _routeRetired
                  ? null
                  : _requestClose,
            ),
          ],
        ),
        body: _connected
            ? _inbox()
            : _cloud
            ? _cloudSetup()
            : _setup(),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String key,
    String label, {
    String? hint,
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: ValueKey(key),
      controller: controller,
      enabled: !_blocked,
      obscureText: secret,
      enableSuggestions: !secret,
      enableIMEPersonalizedLearning: !secret,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _cloudSetup() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_localAccounts != null) _localAccountsButton(),
            const Icon(Icons.cloud_outlined, size: 44),
            const SizedBox(height: 12),
            Text(
              widget.strings.mailCloudSetupHelp,
              textAlign: TextAlign.center,
            ),
            if (widget.initialAccount != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(widget.strings.mailAccountNavigationReconnectHelp),
              ),
            _field(_email, 'cloud-mailbox', widget.strings.emailAddress),
            _field(
              _clientId,
              'cloud-client-id',
              widget.strings.mailCloudClientId,
            ),
            if (widget.cloudService == MailCloudService.microsoft365)
              _field(_tenant, 'cloud-tenant', widget.strings.mailCloudTenant),
            if (widget.cloudService == MailCloudService.gmail)
              _field(
                _clientSecret,
                'cloud-client-secret',
                widget.strings.mailCloudClientSecret,
                secret: true,
              ),
            const SizedBox(height: 8),
            Text(
              widget.cloudService == MailCloudService.gmail
                  ? widget.strings.mailCloudGoogleRegistration
                  : widget.strings.mailCloudMicrosoftRegistration,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            CheckboxListTile(
              key: const ValueKey('cloud-diagnostics'),
              contentPadding: EdgeInsets.zero,
              value: _diagnostics,
              title: Text(widget.strings.mailCloudDiagnostics),
              subtitle: Text(widget.strings.mailCloudDiagnosticsHelp),
              onChanged: _blocked
                  ? null
                  : (value) => setState(() => _diagnostics = value ?? false),
            ),
            if (_busy) ...[
              Text(
                widget.strings.mailCloudBrowserPending,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton.icon(
              key: const ValueKey('cloud-connect'),
              onPressed: _blocked ? null : _connect,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(widget.strings.mailCloudSignIn),
            ),
            if (_busy)
              TextButton(
                onPressed: _disconnect,
                child: Text(widget.strings.cancel),
              ),
            const SizedBox(height: 12),
            Text(
              widget.strings.ewsSessionNotice,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _setup() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_localAccounts != null) _localAccountsButton(),
            const Icon(Icons.dns_outlined, size: 44),
            const SizedBox(height: 12),
            Text(widget.strings.ewsSetupHelp, textAlign: TextAlign.center),
            if (widget.initialAccount != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(widget.strings.mailAccountNavigationReconnectHelp),
              ),
            _field(
              _endpoint,
              'ews-endpoint',
              widget.strings.ewsEndpoint,
              hint: 'https://mail.example.com/EWS/Exchange.asmx',
            ),
            _field(
              _email,
              'ews-mailbox',
              widget.strings.emailAddress,
              hint: 'user@example.com',
            ),
            _field(
              _login,
              'ews-login',
              widget.strings.ewsLogin,
              hint: r'DOMAIN\user or user@example.com',
            ),
            _field(_domain, 'ews-domain', widget.strings.ewsDomain),
            _field(
              _password,
              'ews-password',
              widget.strings.password,
              secret: true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MailEwsAuthentication>(
              initialValue: _authentication,
              decoration: InputDecoration(
                labelText: widget.strings.ewsAuthentication,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: MailEwsAuthentication.ntlm,
                  child: Text(widget.strings.ewsNtlm),
                ),
                DropdownMenuItem(
                  value: MailEwsAuthentication.basic,
                  child: Text(widget.strings.ewsBasic),
                ),
              ],
              onChanged: _blocked
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _authentication = value);
                      }
                    },
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton.icon(
              key: const ValueKey('ews-connect'),
              onPressed: _blocked ? null : _connect,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(widget.strings.connect),
            ),
            const SizedBox(height: 12),
            Text(
              widget.strings.ewsSessionNotice,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _folderArchiveAction() {
    final provider = _provider;
    final session = _session;
    final mailbox = _mailbox;
    if (provider == null || session == null || mailbox == null) {
      return const SizedBox.shrink();
    }
    final source = '${widget.cloudService?.name ?? 'Exchange'} · $_sender';
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              mailbox.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          StudioArchiveFolderButton(
            strings: widget.strings,
            source: source,
            folder: mailbox.displayName,
            profileId: studioArchiveFolderProfileId(
              widget.cloudService?.name ?? 'ews:${_endpoint.text.trim()}',
              source,
              mailbox.id.value,
            ),
            sessionKey: session,
            enabled: !_blocked && !_needsRefresh,
            writer: widget.archiveFolderWriter,
            onDialogChanged: (open) {
              if (mounted) setState(() => _dialogOpen = open);
            },
            runner: (archive, profile, {cancellation, onProgress}) =>
                MailArchiveRunner(
                  archive: archive,
                  provider: provider,
                  session: session,
                ).archiveMailbox(
                  mailbox,
                  profile: profile,
                  cancellation: cancellation,
                  onProgress: onProgress,
                ),
          ),
        ],
      ),
    );
  }

  Widget _inbox() => Column(
    children: [
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      _folderArchiveAction(),
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
              children: [
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_notice != null) Text(_notice!),
                        if (_error != null) Text(_error!),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1000;
            if (compact) {
              return IndexedStack(
                index: _reader != null && _showMessage ? 1 : 0,
                children: [
                  ExcludeFocus(
                    excluding: _reader != null && _showMessage,
                    child: _messageList(compact: true),
                  ),
                  if (_reader != null)
                    Column(
                      children: [
                        _actions(compact: true),
                        Expanded(child: MailMessageView(controller: _reader!)),
                      ],
                    ),
                ],
              );
            }
            return Row(
              children: [
                if (!compact)
                  SizedBox(
                    width: 190,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _sender,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final box in _mailboxes)
                                ListTile(
                                  dense: true,
                                  selected: box.id == _mailbox?.id,
                                  leading: const Icon(
                                    Icons.folder_outlined,
                                    size: 18,
                                  ),
                                  title: Text(
                                    box.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: _blocked
                                      ? null
                                      : () => _loadHeaders(box),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!compact) const VerticalDivider(width: 1),
                if (compact)
                  Expanded(child: _messageList(compact: true))
                else
                  SizedBox(width: 330, child: _messageList(compact: false)),
                if (!compact) ...[
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _reader == null
                        ? Center(child: Text(widget.strings.noMessage))
                        : Column(
                            children: [
                              _actions(compact: false),
                              Expanded(
                                child: MailMessageView(controller: _reader!),
                              ),
                            ],
                          ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ],
  );

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

  Widget _messageList({required bool compact}) {
    final mailboxGeneration = _mailboxGeneration;
    final cancellation = _bulkCancellation;
    return Column(
      children: [
        if (compact)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButton<MailMailboxId>(
              isExpanded: true,
              value: _mailbox?.id,
              items: [
                for (final box in _mailboxes)
                  DropdownMenuItem(
                    value: box.id,
                    child: Text(
                      box.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _blocked
                  ? null
                  : (id) {
                      if (id != null) {
                        unawaited(
                          _loadHeaders(
                            _mailboxes.firstWhere((box) => box.id == id),
                          ),
                        );
                      }
                    },
            ),
          ),
        Expanded(
          child: MailMessageList(
            key: _messageListKey,
            scopeId: '${identityHashCode(_provider)}:${_mailbox?.id.value}',
            selectionScopeId: '$mailboxGeneration',
            bulkStatus: _bulkStatus(),
            strings: widget.strings.mailMessageListStrings,
            items: [
              for (final header in _headers)
                MailMessageListItem(
                  id: 'ews-message-${header.id.value}',
                  subject: header.envelope.subject,
                  accountId: [
                    header.remote.account.profile.hostId,
                    header.remote.account.profile.value,
                    header.remote.account.value,
                  ].map(Uri.encodeComponent).join('/'),
                  messageId: header.envelope.messageId,
                  inReplyTo: header.envelope.inReplyTo,
                  references: header.envelope.references,
                  sender: header.envelope.from
                      .map(
                        (address) =>
                            address.displayName == null ||
                                address.displayName!.isEmpty
                            ? address.address
                            : '${address.displayName} <${address.address}>',
                      )
                      .join(', '),
                  to: header.envelope.to
                      .map(
                        (address) => address.displayName?.isNotEmpty == true
                            ? '${address.displayName} <${address.address}>'
                            : address.address,
                      )
                      .join(', '),
                  cc: header.envelope.cc
                      .map(
                        (address) => address.displayName?.isNotEmpty == true
                            ? '${address.displayName} <${address.address}>'
                            : address.address,
                      )
                      .join(', '),
                  date: header.envelope.sentAt,
                  dateLabel: studioMailListDate(
                    header.envelope.sentAt,
                    widget.strings.language,
                  ),
                  isRead: _isRead(header),
                  isFlagged: _isFlagged(header),
                ),
            ],
            selectedId: _selected == null
                ? null
                : 'ews-message-${_selected!.id.value}',
            busy: _blocked,
            onBulkAction: (action, ids) => unawaited(
              _applyBulkAction(
                action,
                ids,
                mailboxGeneration: mailboxGeneration,
              ),
            ),
            supportedBulkActions: {
              MailBulkFlagAction.markRead,
              MailBulkFlagAction.markUnread,
              MailBulkFlagAction.flag,
              MailBulkFlagAction.unflag,
              if (widget.cloudService != MailCloudService.gmail &&
                  _capabilities.supports(MailCapability.move))
                MailBulkFlagAction.move,
              if (_capabilities.supports(MailCapability.delete))
                MailBulkFlagAction.delete,
              if (_canArchive) MailBulkFlagAction.archive,
            },
            bulkActionsEnabled: !_needsRefresh,
            onCancelBulk: cancellation == null
                ? null
                : () {
                    if (identical(_bulkCancellation, cancellation)) {
                      cancellation.cancel();
                    }
                  },
            hasMore: _next != null && _headers.length < _maxHeaders,
            loadMoreKey: const ValueKey('ews-load-more'),
            onLoadMore: _needsRefresh || _mailbox == null
                ? null
                : () => unawaited(_loadHeaders(_mailbox!, more: true)),
            limitNotice: _headers.length >= _maxHeaders && _next != null
                ? widget.strings.mailWorkspaceLimit
                : null,
            onOpen: (id) {
              final header = _headers
                  .where((item) => 'ews-message-${item.id.value}' == id)
                  .firstOrNull;
              if (header != null) unawaited(_openMessage(header));
            },
          ),
        ),
      ],
    );
  }

  Widget _actions({required bool compact}) {
    final selected = _selected;
    final canChange = selected != null && !_blocked && !_needsRefresh;
    final mailboxGeneration = _mailboxGeneration;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Wrap(
        children: [
          if (compact)
            IconButton(
              tooltip: widget.strings.backToMessages,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _showMessage = false),
            ),
          StudioArchiveMessageButton(
            strings: widget.strings,
            message: _blocked ? null : _reader?.result.message,
            origin: MailArchiveOrigin(
              source: '${widget.cloudService?.name ?? 'Exchange'} · $_sender',
              folder: _mailbox?.displayName ?? '/',
              sourceMessageId: switch (selected?.remote) {
                final MailOpaqueIdentity remote => studioArchiveSourceMessageId(
                  remote.value,
                ),
                final MailImapIdentity remote =>
                  'imap:${remote.uidValidity}:${remote.uid}',
                _ => '',
              },
            ),
            writer: widget.archiveWriter,
          ),
          IconButton(
            tooltip: widget.strings.reply,
            icon: const Icon(Icons.reply_outlined),
            onPressed: _blocked || !_canSend
                ? null
                : () => _reply(forward: false),
          ),
          IconButton(
            tooltip: widget.strings.replyAll,
            icon: const Icon(Icons.reply_all_outlined),
            onPressed: _blocked || !_canSend
                ? null
                : () => _reply(forward: false, replyAll: true),
          ),
          IconButton(
            tooltip: widget.strings.forward,
            icon: const Icon(Icons.forward_outlined),
            onPressed: _blocked || !_canSend
                ? null
                : () => _reply(forward: true),
          ),
          IconButton(
            tooltip: widget.strings.mailForwardWithAttachments,
            icon: const Icon(Icons.attach_email_outlined),
            onPressed: _blocked || !_canSend
                ? null
                : () => _reply(forward: true, includeAttachments: true),
          ),
          IconButton(
            tooltip: _isRead(selected) == true
                ? widget.strings.ewsMarkUnread
                : widget.strings.markRead,
            icon: Icon(
              _isRead(selected) == true
                  ? Icons.mark_email_unread_outlined
                  : Icons.mark_email_read_outlined,
            ),
            onPressed: !canChange
                ? null
                : () => _apply(
                    MailSetRead(
                      id: 'read-${++_serial}',
                      message: selected.remote,
                      read: _isRead(selected) != true,
                    ),
                  ),
          ),
          IconButton(
            tooltip: _isFlagged(selected) == true
                ? widget.strings.ewsUnflag
                : widget.strings.ewsFlag,
            icon: Icon(
              _isFlagged(selected) == true ? Icons.flag : Icons.outlined_flag,
            ),
            onPressed: !canChange
                ? null
                : () => _apply(
                    MailSetFlagged(
                      id: 'flag-${++_serial}',
                      message: selected.remote,
                      flagged: _isFlagged(selected) != true,
                    ),
                  ),
          ),
          if (_canArchive)
            IconButton(
              key: const ValueKey('studio-mail-archive-message'),
              tooltip: widget.strings.mailArchiveMessages,
              icon: const Icon(Icons.archive_outlined),
              onPressed: !canChange
                  ? null
                  : () {
                      if (mailboxGeneration != _mailboxGeneration ||
                          !identical(selected, _selected)) {
                        return;
                      }
                      unawaited(
                        _applyBulkAction(
                          MailBulkFlagAction.archive,
                          ['ews-message-${selected.id.value}'],
                          mailboxGeneration: mailboxGeneration,
                          singleMessage: true,
                        ),
                      );
                    },
            ),
          PopupMenuButton<MailMailbox>(
            tooltip: widget.strings.ewsMove,
            enabled:
                canChange &&
                widget.cloudService != MailCloudService.gmail &&
                _capabilities.supports(MailCapability.move),
            icon: const Icon(Icons.drive_file_move_outline),
            itemBuilder: (context) => [
              for (final box in _mailboxes)
                if (box.id != _mailbox?.id)
                  PopupMenuItem(value: box, child: Text(box.displayName)),
            ],
            onSelected: (box) {
              if (selected != null &&
                  mailboxGeneration == _mailboxGeneration &&
                  identical(selected, _selected)) {
                unawaited(
                  _apply(
                    MailMove(
                      id: 'move-${++_serial}',
                      message: selected.remote,
                      destination: box.id,
                    ),
                  ),
                );
              }
            },
          ),
          IconButton(
            tooltip: _cloud
                ? widget.strings.mailCloudDelete
                : widget.strings.ewsDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed:
                canChange && _capabilities.supports(MailCapability.delete)
                ? _delete
                : null,
          ),
        ],
      ),
    );
  }
}

final class _EwsUiFailure implements Exception {
  const _EwsUiFailure(this.problem);
  final MailProblem problem;
}

final class _AccountNavigationExpired implements Exception {
  const _AccountNavigationExpired();
}

final class _AccountOwnerReleaseFailure implements Exception {
  const _AccountOwnerReleaseFailure();
}

/// Session-scoped vault implementation. No preferences, files or logs are used.
final class _SessionCredentials implements MailCredentialStore {
  _SessionCredentials(MailCredentialRecord record)
    : _record = record,
      _reference = record.reference;
  final MailCredentialReference _reference;
  MailCredentialRecord? _record;
  bool _closed = false;
  void clear() {
    _closed = true;
    _record = null;
  }

  bool _matches(MailCredentialReference reference) =>
      reference.account == _reference.account &&
      reference.key == _reference.key;

  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference reference,
  ) async => MailSuccess(!_closed && _matches(reference) ? _record : null);
  @override
  Future<MailResult<MailUnit>> store(MailCredentialRecord record) async {
    if (_closed || !_matches(record.reference)) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    _record = record;
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> delete(MailCredentialReference reference) async {
    if (_matches(reference)) clear();
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account) async {
    if (account == _reference.account) clear();
    return const MailSuccess(MailUnit.value);
  }
}
