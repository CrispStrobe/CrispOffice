import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'studio_mail_archive_action.dart';
import 'studio_mail_archive_folder_action.dart';
import 'studio_mail_compose.dart';
import 'studio_mail_outbox.dart';
import 'studio_mail_outbox_dialog.dart';
import 'studio_mail_outbox_strings.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_cached_strings.dart';
import 'studio_mail_mailbox_store.dart';
import 'studio_mail_draft_store_native.dart';
import 'studio_mail_drafts_dialog.dart';
import 'studio_mail_drafts_strings.dart';
import 'studio_mail_local_accounts.dart';
import 'studio_mail_local_accounts_dialog.dart';
import 'studio_mail_local_accounts_strings.dart';
import 'studio_mail_operation.dart';
import 'studio_mail_reply.dart';
import 'studio_mail_strings.dart';
import 'studio_mail_workspace_strings.dart';
import 'studio_mail_submission.dart';
import 'studio_strings.dart';

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
  Future<void> _draftStoreClosing = Future<void>.value();
  StudioMailDraftAccount? _draftIdentity;
  bool _submissionUncertain = false;
  bool _connected = false;
  bool _busy = false;
  bool _dialogOpen = false;
  bool _showMessage = false;
  bool _needsRefresh = false;
  String? _error;
  String? _notice;
  String? _localAccountWarning;
  String? _cacheViewWarning;
  String? _cacheBodyWarning;
  String? get _cacheWarning => _cacheViewWarning ?? _cacheBodyWarning;
  String _sender = '';
  int _serial = 0;

  bool get _cloud => widget.cloudService != null;
  String get _title => switch (widget.cloudService) {
    MailCloudService.gmail => 'Gmail',
    MailCloudService.microsoft365 => 'Microsoft 365 / Outlook',
    null => widget.strings.ewsTitle,
  };

  @override
  void initState() {
    super.initState();
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

  bool get _blocked => _busy || _dialogOpen;
  bool get _canSend => _capabilities.supports(MailCapability.send);
  bool? _isRead(MailHeaderRecord? header) => header == null
      ? null
      : _confirmedRead[header.remote] ?? header.flags?.isRead;
  bool? _isFlagged(MailHeaderRecord? header) => header == null
      ? null
      : _confirmedFlagged[header.remote] ?? header.flags?.isFlagged;
  bool _current(MailProvider provider, MailOperationLease lease) =>
      mounted && identical(_provider, provider) && lease.isCurrent;

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
    _mailboxCapture?.dispose();
    _session?.dispose();
    _credentials?.clear();
    _closeCloud();
    _reader?.dispose();
    _reader = null;
    _draft = null;
    unawaited(_closeDraftStore(_draftStore));
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
    MailEwsConfiguration configuration;
    try {
      if (!StudioMailDraft.isSupportedAddress(sender) ||
          _password.text.isEmpty) {
        throw const FormatException();
      }
      final profile = MailProfileId('studio-ews', hostId: 'quds-office-studio');
      final account = MailAccountId(
        '${DateTime.now().microsecondsSinceEpoch}-${++_serial}',
        profile: profile,
      );
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
    final credentials = _SessionCredentials(
      MailCredentialRecord(
        reference: configuration.credential,
        opaqueData: MailBytes(utf8.encode(_password.text)),
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
      setState(() => _error = widget.strings.mailConnectionFailed);
      return;
    }
    final lease = session.begin();
    setState(() {
      _provider = provider;
      _submission = provider;
      _session = session;
      _credentials = credentials;
      _draftIdentity = StudioMailDraftAccount(
        provider: 'ews',
        endpoint: configuration.endpoint.toString(),
        login: jsonEncode([configuration.domain, configuration.username]),
        sender: sender,
      );
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
      final capabilities = await provider.capabilities(lease);
      if (!_current(provider, lease)) return;
      final supported = _value(capabilities);
      if (!supported.supports(MailCapability.mail)) {
        throw const _EwsUiFailure(MailProblem(MailProblemCode.unsupported));
      }
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
      final response = await provider.fetchHeaders(
        inbox.id,
        limit: _pageSize,
        lease: lease,
      );
      if (!_current(provider, lease)) return;
      final page = _value(response);
      _validateHeaderPage(page, inbox.id, limit: _pageSize);
      setState(() {
        _usedHeaderCursors.clear();
        _confirmedRead.clear();
        _confirmedFlagged.clear();
        _connected = true;
        _capabilities = supported;
        _busy = false;
        _sender = sender;
        _mailboxes = boxes;
        _mailbox = inbox;
        _headers = page.messages;
        _next = page.next;
        _password.clear();
        _clientSecret.clear();
      });
      await _restoreDraftStore(provider, session, lease);
    } on Object catch (error) {
      if (!_current(provider, lease)) return;
      session.dispose();
      _credentials?.clear();
      _closeCloud();
      setState(() {
        _provider = null;
        _submission = null;
        _session = null;
        _credentials = null;
        _busy = false;
        _clientSecret.clear();
        _error = error is _EwsUiFailure
            ? _problem(error.problem, widget.strings.mailConnectionFailed)
            : widget.strings.mailConnectionFailed;
      });
    }
  }

  Future<void> _connectCloud() async {
    final sender = _email.text.trim();
    late final MailOAuthConfiguration authorization;
    late final MailCloudConfiguration configuration;
    try {
      final profile = MailProfileId(
        'studio-cloud',
        hostId: 'quds-office-studio',
      );
      final account = MailAccountId(
        '${DateTime.now().microsecondsSinceEpoch}-${++_serial}',
        profile: profile,
      );
      configuration = MailCloudConfiguration(
        account: account,
        service: widget.cloudService!,
        mailboxAddress: sender,
      );
      authorization = MailOAuthConfiguration(
        service: widget.cloudService!,
        clientId: _clientId.text.trim(),
        tenant: _tenant.text.trim(),
        clientSecret: _clientSecret.text.isEmpty ? null : _clientSecret.text,
      );
    } on Object {
      setState(() => _error = widget.strings.mailCloudInvalidSettings);
      return;
    }
    final session = MailAccountSession(configuration.account);
    final lease = session.begin();
    final MailCloudLogSink? log = _diagnostics
        ? (event) => debugPrint(jsonEncode(event.toJson()))
        : null;
    bool current() =>
        mounted && identical(_session, session) && lease.isCurrent;
    setState(() {
      _session = session;
      _draftIdentity = StudioMailDraftAccount(
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
        _error = error is _EwsUiFailure
            ? _problem(error.problem, widget.strings.mailCloudSignInFailed)
            : widget.strings.mailCloudSignInFailed;
      });
    }
  }

  void _disconnect() {
    _mailboxCapture?.dispose();
    _mailboxCapture = null;
    final draftStore = _draftStore;
    _draftStore = null;
    _draftIdentity = null;
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
    _draftStoreClosing = _draftStoreClosing.then(
      (_) => _closeDraftStore(draftStore),
    );
    unawaited(_draftStoreClosing);
  }

  Future<void> _closeDraftStore(StudioMailDraftStore? store) async {
    final mailboxStore = switch (store) {
      StudioMailMailboxStoreOwner owner => owner.mailboxStore,
      _ => null,
    };
    if (mailboxStore != null &&
        identical(_mailboxCapture?.store, mailboxStore)) {
      _mailboxCapture?.dispose();
      _mailboxCapture = null;
    }
    try {
      await store?.close();
    } on Object {
      // Local draft content survives releasing the database owner.
    }
  }

  Future<bool> _restoreDraftStore(
    MailProvider provider,
    MailAccountSession session,
    MailOperationLease lease,
  ) async {
    if (!_current(provider, lease)) return false;
    if (_draftStore != null) return true;
    final identity = _draftIdentity;
    if (identity == null) return false;
    StudioMailDraftStore? candidate;
    setState(() {
      _busy = true;
      _localAccountWarning = null;
    });
    try {
      await _draftStoreClosing;
      if (!_current(provider, lease)) return false;
      candidate = await (widget.draftStoreFactory ?? openStudioMailDraftStore)(
        identity,
      );
      if (candidate case StudioMailOutboxStore(
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
      final restored = await candidate.load();
      if (!_current(provider, lease)) {
        await _closeDraftStore(candidate);
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
      final mailboxOwner = switch (candidate) {
        StudioMailMailboxStoreOwner owner => owner,
        _ => null,
      };
      if (mailboxOwner != null) {
        final owner = candidate;
        _mailboxCapture?.dispose();
        _mailboxCapture = StudioMailMailboxCapture(
          store: mailboxOwner.mailboxStore,
          sourceAccount: provider.account,
          provider: identity.provider,
          isCurrent: () =>
              _current(provider, lease) && identical(owner, _draftStore),
        );
        await _saveCachedView(provider, lease);
      }
      final directory = _localAccounts;
      if (directory != null && candidate is StudioMailDraftCatalog) {
        try {
          await directory.remember(identity);
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
    } on Object {
      await _closeDraftStore(candidate);
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
    try {
      await capture.saveView(mailbox, _headers, hasMore: _next != null);
      if (_current(provider, lease)) {
        setState(() => _cacheViewWarning = null);
      }
    } on Object {
      if (_current(provider, lease)) {
        setState(() => _cacheViewWarning = widget.strings.mailCacheSaveFailed);
      }
    }
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
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      if (!more) {
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
        command.message != selected.remote ||
        command is MailMove && !_capabilities.supports(MailCapability.move)) {
      return;
    }
    final lease = session.begin();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await provider.apply(command, lease);
      if (!_current(provider, lease)) return;
      _value(result);
      MailReaderController? old;
      setState(() {
        if (command is MailMove || command is MailDelete) {
          _confirmedRead.remove(selected.remote);
          _confirmedFlagged.remove(selected.remote);
          _headers = _headers
              .where((header) => header.remote != selected.remote)
              .toList();
          old = _reader;
          _reader = null;
          _selected = null;
          _showMessage = false;
          // Removing a row shifts FindItem offsets. The next page must start
          // from a refreshed folder rather than reusing that earlier cursor.
          _next = null;
        } else {
          if (command is MailSetRead) {
            _confirmedRead[selected.remote] = command.read;
          } else if (command is MailSetFlagged) {
            _confirmedFlagged[selected.remote] = command.flagged;
          }
          final flags = selected.flags;
          final updated = MailHeaderRecord(
            id: selected.id,
            remote: selected.remote,
            envelope: selected.envelope,
            flags: flags == null
                ? null
                : MailMessageFlags(
                    isRead: command is MailSetRead
                        ? command.read
                        : flags.isRead,
                    isFlagged: command is MailSetFlagged
                        ? command.flagged
                        : flags.isFlagged,
                    isAnswered: flags.isAnswered,
                    isDraft: flags.isDraft,
                    isDeleted: flags.isDeleted,
                  ),
          );
          _selected = updated;
          _headers = [
            for (final header in _headers)
              header.remote == updated.remote ? updated : header,
          ];
        }
        _busy = false;
        _notice = command is MailMove || command is MailDelete
            ? (_cloud
                  ? widget.strings.mailCloudFolderChanged
                  : widget.strings.ewsFolderChanged)
            : (_cloud
                  ? widget.strings.mailCloudActionConfirmed
                  : widget.strings.ewsActionConfirmed);
      });
      _retire(old);
    } on Object catch (error) {
      if (!_current(provider, lease)) return;
      setState(() {
        _busy = false;
        // Even a failed confirmation can follow an accepted write. Require a
        // fresh mailbox observation before another mutation in this session.
        _needsRefresh = true;
        _error = error is _EwsUiFailure
            ? _problem(error.problem, widget.strings.ewsMutationFailed)
            : widget.strings.ewsMutationFailed;
      });
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
        _needsRefresh) {
      return;
    }
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
    if (confirmed == true && identical(_selected, selected)) {
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
            _current(provider, lease) && identical(store, _draftStore),
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
    if (initial != null && catalog != null) {
      setState(() => _busy = true);
      try {
        final retained = _draft;
        if (retained != null) {
          await store.save(retained, submissionUncertain: _submissionUncertain);
        }
        if (!_current(provider, lease)) return;
        final created = await catalog.createDraft(initial);
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
        initialDraft: initial ?? _draft,
        previousSubmissionUncertain: _submissionUncertain,
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

  Widget _localAccountsButton() => OutlinedButton.icon(
    key: const ValueKey('studio-mail-known-drafts'),
    onPressed: _blocked ? null : _openLocalAccounts,
    icon: const Icon(Icons.folder_open_outlined),
    label: Text(widget.strings.mailLocalAccounts),
  );

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(_title, overflow: TextOverflow.ellipsis),
        actions: [
          if (_connected) ...[
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
              onPressed: _dialogOpen ? null : _disconnect,
            ),
          IconButton(
            tooltip: widget.strings.close,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: _connected
          ? _inbox()
          : _cloud
          ? _cloudSetup()
          : _setup(),
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
      enabled: !_busy,
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
              onChanged: _busy
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
              onPressed: _busy ? null : _connect,
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
              onChanged: _busy
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
              onPressed: _busy ? null : _connect,
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
            child: Row(children: [Expanded(child: Text(_error ?? _notice!))]),
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

  Widget _messageList({required bool compact}) => Column(
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
          strings: widget.strings.mailMessageListStrings,
          items: [
            for (final header in _headers)
              MailMessageListItem(
                id: 'ews-message-${header.id.value}',
                subject: header.envelope.subject,
                sender: header.envelope.from
                    .map(
                      (address) =>
                          address.displayName == null ||
                              address.displayName!.isEmpty
                          ? address.address
                          : '${address.displayName} <${address.address}>',
                    )
                    .join(', '),
                dateLabel: header.envelope.sentAt?.toLocal().toString(),
                isRead: _isRead(header),
                isFlagged: _isFlagged(header),
              ),
          ],
          selectedId: _selected == null
              ? null
              : 'ews-message-${_selected!.id.value}',
          busy: _blocked,
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

  Widget _actions({required bool compact}) {
    final selected = _selected;
    final canChange = selected != null && !_blocked && !_needsRefresh;
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
          PopupMenuButton<MailMailbox>(
            tooltip: widget.strings.ewsMove,
            enabled: canChange && _capabilities.supports(MailCapability.move),
            icon: const Icon(Icons.drive_file_move_outline),
            itemBuilder: (context) => [
              for (final box in _mailboxes)
                if (box.id != _mailbox?.id)
                  PopupMenuItem(value: box, child: Text(box.displayName)),
            ],
            onSelected: (box) {
              if (selected != null) {
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
            onPressed: canChange ? _delete : null,
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
