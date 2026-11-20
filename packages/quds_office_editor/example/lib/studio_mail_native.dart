import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart'
    show MailProblemCode, MailCursor;
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_archive_action.dart';
import 'studio_mail_archive_folder_action.dart';
import 'studio_mail_cloud.dart';
import 'studio_mail_compose.dart';
import 'studio_mail_credentials.dart';
import 'studio_credential_storage.dart';
import 'studio_credential_settings.dart';
import 'studio_mail_draft_store.dart';
import 'studio_mail_draft_store_native.dart';
import 'studio_mail_ews.dart';
import 'studio_mail_message_loader.dart';
import 'studio_mail_operation.dart';
import 'studio_mail_presets.dart';
import 'studio_mail_reply.dart';
import 'studio_mail_strings.dart';
import 'studio_mail_workspace_strings.dart';
import 'studio_mail_submission.dart';
import 'studio_saved_mail.dart';
import 'studio_strings.dart';

/// IMAP/SMTP client with optional platform-keychain account persistence.
///
/// Account setup is explicit; remembered credentials use the platform keychain.
/// Discovery and provider presets require verified encrypted transports. Every
/// network operation reports its own failure instead of presenting an empty
/// inbox.
class StudioMailDialog extends StatefulWidget {
  const StudioMailDialog({
    super.key,
    required this.strings,
    this.chromeBuilder,
    this.clientFactory,
    this.messageLoaderFactory,
    this.accountDiscovery,
    this.credentialStore,
    this.archiveWriter,
    this.archiveFolderWriter,
    this.draftStoreFactory,
  });

  final StudioStrings strings;
  final WidgetBuilder? chromeBuilder;

  /// Tests supply the keychain boundary without reading a platform credential.
  final StudioMailCredentialStore? credentialStore;
  final StudioMailArchiveWriter? archiveWriter;
  final StudioMailArchiveFolderWriter? archiveFolderWriter;
  final StudioMailDraftStoreFactory? draftStoreFactory;

  /// Creates a fresh client for each connection attempt. Tests use this seam
  /// to control network completions without contacting an external account.
  final mail.MailClient Function(mail.MailAccount account)? clientFactory;

  /// Resolves endpoint settings only; credentials are supplied after the
  /// discovery origin and IMAP/SMTP server types have been checked.
  final Future<mail.ClientConfig?> Function(String email)? accountDiscovery;

  /// Owns exact, bounded UID reads for this foreground account session.
  final StudioMailMessageLoader Function(mail.MailAccount account)?
  messageLoaderFactory;

  @override
  State<StudioMailDialog> createState() => _StudioMailDialogState();
}

class _StudioMailDialogState extends State<StudioMailDialog> {
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
  MailCursor? _nextHeaders;
  bool _needsRefresh = false;
  final _primaryLogin = TextEditingController();
  StudioMailImapPreset? _preset;
  bool _icloudFullAddressLogin = false;
  late final StudioMailCredentialStore _credentials;
  bool _remember = true;
  List<StudioMailCredentials> _savedAccounts = [];
  StudioMailCredentials? _lastCredentialSnapshot;
  bool _startTls = false;
  bool _hasSavedCredentials = false;
  bool _credentialPending = false;
  int _settingsRevision = 0;
  int _credentialGeneration = 0;

  mail.MailClient? _client;
  mail.MailClient? _pendingClient;
  StudioMailMessageLoader? _messageLoader;
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
  String? _credentialError;

  @override
  void initState() {
    super.initState();
    _credentials = widget.credentialStore ?? StudioMailCredentialStore();
    for (final controller in [
      _email,
      _password,
      _imapHost,
      _smtpHost,
      _primaryLogin,
    ]) {
      controller.addListener(_settingsEdited);
    }
    unawaited(_loadCredentials());
  }

  void _settingsEdited() => _settingsRevision++;

  Future<void> _loadCredentials() async {
    final generation = _sessionGeneration;
    final settings = _settingsRevision;
    final credentialGeneration = _credentialGeneration;
    final StudioMailCredentials? saved;
    try {
      saved = await _credentials.load();
      if (_credentials case final StudioMailAccountsStore store) {
        final accounts = await store.accounts();
        if (mounted) _savedAccounts = accounts;
      }
    } on Object {
      // Missing or locked keychains do not prevent explicit account setup.
      return;
    }
    if (!_currentAttempt(generation) ||
        credentialGeneration != _credentialGeneration) {
      return;
    }
    setState(() {
      _hasSavedCredentials = saved != null;
      if (saved == null ||
          _connecting ||
          _client != null ||
          settings != _settingsRevision) {
        return;
      }
      _email.text = saved.email;
      _password.text = saved.password;
      _imapHost.text = saved.imapHost;
      _smtpHost.text = saved.smtpHost;
      _manual = saved.manual;
      _startTls = saved.startTls;
      _preset = saved.preset;
      _primaryLogin.text = saved.primaryLogin;
      _icloudFullAddressLogin = saved.icloudFullAddressLogin;
    });
  }

  Future<void> _persistCredentials(
    mail.MailClient client,
    int sessionGeneration,
    StudioMailCredentials credentials,
    bool remember,
  ) async {
    if (!_currentSession(client, sessionGeneration)) return;
    _lastCredentialSnapshot = remember ? credentials : null;
    final generation = ++_credentialGeneration;
    setState(() => _credentialPending = true);
    bool success;
    try {
      success = remember
          ? await _credentials.save(credentials)
          : await _credentials.clear();
    } on Object {
      success = false;
    }
    if (success) {
      if (_credentials case final StudioMailAccountsStore store) {
        try {
          final accounts = await store.accounts();
          if (mounted && generation == _credentialGeneration)
            _savedAccounts = accounts;
        } on Object {
          /* A list refresh cannot invalidate the connected session. */
        }
      }
    }
    if (!mounted || generation != _credentialGeneration) return;
    setState(() {
      _credentialPending = false;
      if (success) _hasSavedCredentials = remember;
      if (_currentSession(client, sessionGeneration)) {
        // Credential feedback must not replace a confirmed SMTP receipt or
        // another mailbox operation's status while the keychain is pending.
        _credentialError = success
            ? null
            : remember
            ? widget.strings.mailKeychainSaveFailed
            : widget.strings.mailKeychainClearFailed;
      }
    });
  }

  Future<void> _forgetCredentials() async {
    if (_connecting) return;
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

  @override
  void dispose() {
    _sessionGeneration++;
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
    try {
      await store?.close();
    } on Object {
      // Closing releases ownership; it never discards the persisted draft.
    }
  }

  Future<bool> _restoreDraftStore(
    mail.MailClient client,
    mail.MailAccount account,
    int generation,
  ) async {
    if (!_currentSession(client, generation)) return false;
    if (_draftStore != null) return true;
    setState(() => _busy = true);
    StudioMailDraftStore? candidate;
    try {
      final incoming = account.incoming.serverConfig;
      final authentication = account.incoming.authentication;
      final identity = StudioMailDraftAccount(
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
      candidate = await (widget.draftStoreFactory ?? openStudioMailDraftStore)(
        identity,
      );
      final restored = await candidate.load();
      if (!_currentSession(client, generation)) {
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
      return true;
    } on Object {
      await _closeDraftStore(candidate);
      if (_currentSession(client, generation)) {
        setState(() => _error = widget.strings.mailDraftStorageFailed);
      }
      return false;
    } finally {
      if (_currentSession(client, generation)) setState(() => _busy = false);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => reader.dispose());
  }

  Future<void> _connect() => runStudioMailOperation(() async {
    if (_connecting || _client != null) return;
    final generation = ++_sessionGeneration;
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
    mail.MailClient? candidate;
    StudioMailMessageLoader? candidateLoader;
    bool adopted = false;
    try {
      mail.MailAccount account;
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
      final client =
          widget.clientFactory?.call(account) ??
          mail.MailClient(account, isLogEnabled: false);
      candidate = client;
      _pendingClient = client;
      final loader =
          widget.messageLoaderFactory?.call(account) ??
          NativeStudioMailMessageLoader(account);
      candidateLoader = loader;
      _pendingLoader = loader;
      await client.connect();
      if (!_currentAttempt(generation)) return;
      final boxes = await client.listMailboxes();
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
      _validateHeaderPage(page, observedMailbox, limit: _pageSize);
      final previous = _reader;
      setState(() {
        _client = client;
        _pendingClient = null;
        _messageLoader = loader;
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
        _selected = null;
        _reader = null;
        _connecting = false;
        _notice = null;
      });
      adopted = true;
      _retireReader(previous);
      await _restoreDraftStore(client, account, generation);
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
      );
    } on Object {
      if (!_currentAttempt(generation)) return;
      setState(() {
        _connecting = false;
        _error = widget.strings.mailConnectionFailed;
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

  Future<void> _selectMailbox(mail.Mailbox mailbox, {bool more = false}) =>
      runStudioMailOperation(() async {
        final client = _client;
        final loader = _messageLoader;
        if (client == null ||
            loader == null ||
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
        setState(() {
          _busy = true;
          _error = null;
          _notice = null;
          if (!more) {
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
          final messages = <String, mail.MimeMessage>{
            if (more)
              for (final message in _messages) _messageKey(message): message,
            for (final message in page.messages)
              _messageKey(message, mailbox: observedMailbox): message,
          };
          setState(() {
            if (cursor != null) _usedHeaderCursors.add(cursor.value);
            _messages = messages.values.toList();
            final retained = Set<mail.MimeMessage>.identity()
              ..addAll(_messages);
            _confirmedFlags.removeWhere(
              (message, _) => !retained.contains(message),
            );
            if (more && _selected != null) {
              _selected = messages[_messageKey(_selected!)];
            }
            _messageMailbox = observedMailbox;
            _nextHeaders = page.next;
            _needsRefresh = false;
            _busy = false;
          });
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
          final raw = await loader.fetch(mailbox, message);
          if (!_currentSession(client, generation)) return;
          final reader = MailReaderController.fromBytes(
            raw,
            codec: const QudsMimeCodec(),
          );
          final previous = _reader;
          setState(() {
            _selected = message;
            _reader = reader;
            _busy = false;
            _showCompactMessage = true;
          });
          _retireReader(previous);
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
    if (initial != null && _draft != null) {
      setState(() {
        _error = widget.strings.mailRetainedDraft;
        _notice = null;
      });
      return;
    }
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
          initialDraft: initial ?? _draft,
          previousSubmissionUncertain: _submissionUncertain,
          onSaveDraft: (snapshot) async {
            if (!_currentSession(client, generation) ||
                !identical(store, _draftStore)) {
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
    if (draft == null || !_currentSession(client, generation)) return;
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

  Future<void> _reply() => _composeFromMessage(forward: false);

  Future<void> _replyAll() =>
      _composeFromMessage(forward: false, replyAll: true);

  Future<void> _forward() => _composeFromMessage(forward: true);

  Future<void> _composeFromMessage({
    required bool forward,
    bool replyAll = false,
  }) => runStudioMailOperation(() async {
    final account = _account;
    if (_busy || _dialogOpen || _client == null || account == null) return;
    if (_draft != null) {
      setState(() {
        _error = widget.strings.mailRetainedDraft;
        _notice = null;
      });
      return;
    }
    // The list item contains only an envelope. Quote the authoritative
    // bounded raw-message parse, never the reader's header presentation.
    final message = _reader?.result.message;
    if (message == null) return;
    try {
      final draft = replyAll
          ? buildStudioMailReplyAllDraft(
              message,
              sender: account.email,
              truncationNotice: widget.strings.mailQuotedTextTruncated,
            )
          : buildStudioMailReplyDraft(
              message,
              forward: forward,
              truncationNotice: widget.strings.mailQuotedTextTruncated,
              forwardNotice: widget.strings.mailTextOnlyForward,
            );
      await _openComposer(draft);
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

  Future<void> _changeMessageFlags({bool? read, bool? flagged}) =>
      runStudioMailOperation(() async {
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
            throw const StudioMailMessageLoadException(
              MailProblemCode.conflict,
            );
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

  void _disconnect() {
    _sessionGeneration++;
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
      _selected = null;
      _showCompactMessage = false;
      _error = null;
      _notice = null;
    });
    _retireReader(previous);
    loader?.dispose();
    pendingLoader?.dispose();
    unawaited(_disconnectQuietly(client));
    unawaited(_disconnectQuietly(pending));
    unawaited(_closeDraftStore(draftStore));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: Column(
      children: [
        if (widget.chromeBuilder != null)
          widget.chromeBuilder!(context)
        else if (Theme.of(context).platform == TargetPlatform.macOS)
          const SizedBox(height: 32),
        _mailMenus(context),
        Expanded(
          child: RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, constraints) => IndexedStack(
                index: _showSavedMessages ? 1 : 0,
                children: <Widget>[
                  _accountView(context, compact: constraints.maxWidth < 800),
                  if (_savedMessagesVisited)
                    StudioSavedMailView(
                      strings: widget.strings,
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
  );

  Future<void> _openCredentialStorage() async {
    if (await showStudioCredentialSettings(context) && mounted) {
      _credentialGeneration++;
      setState(() {
        _credentialPending = false;
        _credentialError = _client != null && _lastCredentialSnapshot != null
            ? 'Save this connected account to the selected credential store.'
            : null;
        _savedAccounts = [];
      });
      await _loadCredentials();
    }
  }

  void _chooseSavedAccount(int? index) {
    if (index == null || _connecting || _client != null) return;
    final c = index < 0 ? null : _savedAccounts[index];
    if (c != null) {
      if (_credentials case final StudioMailAccountsStore store)
        store.selectAccount(c);
    }
    setState(() {
      _settingsEdited();
      _credentialError = null;
      _error = null;
      _email.text = c?.email ?? '';
      _password.text = c?.password ?? '';
      _imapHost.text = c?.imapHost ?? '';
      _smtpHost.text = c?.smtpHost ?? '';
      _manual = c?.manual ?? false;
      _startTls = c?.startTls ?? false;
      _preset = c?.preset;
      _primaryLogin.text = c?.primaryLogin ?? '';
      _icloudFullAddressLogin = c?.icloudFullAddressLogin ?? false;
      _hasSavedCredentials = c != null;
    });
  }

  Widget _mailMenus(BuildContext context) => MenuBar(
    style: MenuStyle(
      backgroundColor: WidgetStatePropertyAll(
        Theme.of(context).colorScheme.surface,
      ),
    ),
    children: [
      SubmenuButton(
        menuChildren: [
          MenuItemButton(
            onPressed: _openCredentialStorage,
            child: const Text('Credential storage…'),
          ),
          MenuItemButton(
            onPressed: () => setState(() {
              _savedMessagesVisited = true;
              _showSavedMessages = true;
            }),
            child: Text(widget.strings.savedMessages),
          ),
          MenuItemButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.strings.close),
          ),
        ],
        child: const Text('File'),
      ),
      SubmenuButton(
        menuChildren: [
          MenuItemButton(
            onPressed: _client == null || _busy ? null : _compose,
            child: Text(widget.strings.compose),
          ),
          MenuItemButton(
            onPressed: _busy || _mailbox == null
                ? null
                : () => _selectMailbox(_mailbox!),
            child: Text(widget.strings.refresh),
          ),
          MenuItemButton(
            onPressed: _client == null ? null : _disconnect,
            child: Text(widget.strings.disconnect),
          ),
        ],
        child: Text(widget.strings.mail),
      ),
      SubmenuButton(
        menuChildren: [
          MenuItemButton(
            onPressed: () => setState(() => _showSavedMessages = false),
            child: const Text('Accounts'),
          ),
          MenuItemButton(
            onPressed: () => setState(() {
              _savedMessagesVisited = true;
              _showSavedMessages = true;
            }),
            child: Text(widget.strings.savedMessages),
          ),
        ],
        child: const Text('View'),
      ),
    ],
  );

  Widget _accountView(
    BuildContext context, {
    required bool compact,
  }) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    appBar: AppBar(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      title: Text(widget.strings.mailTitle, overflow: TextOverflow.ellipsis),
      actions: <Widget>[
        IconButton(
          tooltip: 'Credential storage',
          icon: const Icon(Icons.key),
          onPressed: _credentialPending ? null : _openCredentialStorage,
        ),
        IconButton(
          onPressed: _busy || _connecting
              ? null
              : () => setState(() {
                  _savedMessagesVisited = true;
                  _showSavedMessages = true;
                }),
          tooltip: widget.strings.savedMessages,
          icon: const Icon(Icons.folder_open_outlined),
        ),
        if (_client != null) ...<Widget>[
          if (compact)
            IconButton(
              onPressed: _busy ? null : _compose,
              tooltip: widget.strings.compose,
              icon: const Icon(Icons.edit_outlined),
            )
          else
            TextButton.icon(
              onPressed: _busy ? null : _compose,
              icon: const Icon(Icons.edit_outlined),
              label: Text(widget.strings.compose),
            ),
          IconButton(
            onPressed: _busy || _mailbox == null
                ? null
                : () => _selectMailbox(_mailbox!),
            tooltip: widget.strings.refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (_draft != null)
            IconButton(
              onPressed: _busy || _dialogOpen ? null : _discardDraft,
              tooltip: widget.strings.mailDiscardDraft,
              icon: const Icon(Icons.delete_outline),
            ),
          IconButton(
            onPressed: _disconnect,
            tooltip: widget.strings.disconnect,
            icon: const Icon(Icons.logout),
          ),
        ],
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: widget.strings.close,
          icon: const Icon(Icons.close),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: _client == null
        ? _accountSetup(context)
        : _inbox(context, compact: compact),
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
                if (_savedAccounts.isNotEmpty)
                  DropdownButtonFormField<int>(
                    key: const ValueKey('mail-saved-accounts'),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Accounts'),
                    hint: const Text('Choose a saved account or add another'),
                    items: [
                      for (var i = 0; i < _savedAccounts.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            '${_savedAccounts[i].email} · ${_savedAccounts[i].imapHost}',
                          ),
                        ),
                      const DropdownMenuItem(
                        value: -1,
                        child: Text('Add account…'),
                      ),
                    ],
                    onChanged: _connecting ? null : _chooseSavedAccount,
                  ),
                TextButton.icon(
                  onPressed: _credentialPending ? null : _openCredentialStorage,
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
                      onPressed: _connecting
                          ? null
                          : () => showDialog<void>(
                              context: context,
                              builder: (_) => StudioMailCloudDialog(
                                strings: widget.strings,
                                service: service,
                              ),
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
                  onPressed: _connecting
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (_) =>
                              StudioMailEwsDialog(strings: widget.strings),
                        ),
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
                TextButton.icon(
                  key: const ValueKey('studio-mail-forget'),
                  onPressed: _connecting ? null : _forgetCredentials,
                  icon: Icon(
                    _credentialPending
                        ? Icons.hourglass_empty
                        : _hasSavedCredentials
                        ? Icons.key_off_outlined
                        : Icons.delete_outline,
                    size: 18,
                  ),
                  label: Text(widget.strings.forgetAccount),
                ),
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
                  onPressed: _connecting ? null : _connect,
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
              onPressed: _credentialPending
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
                    child: SelectableText(_error ?? _notice ?? '', maxLines: 2),
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
        const SizedBox(width: 8),
      ],
    ),
  );

  bool? _observedRead(mail.MimeMessage message) {
    final confirmed = _confirmedFlags[message];
    return confirmed != null
        ? confirmed.read
        : message.flags == null
        ? null
        : message.isSeen;
  }

  bool? _observedFlagged(mail.MimeMessage message) {
    final confirmed = _confirmedFlags[message];
    return confirmed != null
        ? confirmed.flagged
        : message.flags == null
        ? null
        : message.isFlagged;
  }

  String _messageKey(mail.MimeMessage message, {mail.Mailbox? mailbox}) {
    final observed = mailbox ?? _messageMailbox;
    // Production browser rows always have a validated UID. Legacy injected
    // readers may omit it; their row stays local to this in-memory snapshot.
    return 'imap-message-${observed?.uidValidity}:${message.uid ?? identityHashCode(message)}';
  }

  Widget _messageList() => MailMessageList(
    key: _messageListKey,
    scopeId: '$_sessionGeneration:${_mailbox?.path}',
    strings: widget.strings.mailMessageListStrings,
    items: [
      for (final message in _messages)
        MailMessageListItem(
          id: _messageKey(message),
          subject: message.decodeSubject() ?? '(no subject)',
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
          dateLabel: message.decodeDate()?.toLocal().toString(),
          isRead: _observedRead(message),
          isFlagged: _observedFlagged(message),
        ),
    ],
    selectedId: _selected == null ? null : _messageKey(_selected!),
    busy: _busy || _dialogOpen,
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
