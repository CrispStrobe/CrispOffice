import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/imap.dart' as imap;
import 'package:enough_mail/src/private/util/client_connection.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_transport/src/native/provider.dart';

Uint8List fixtureBytes(String value) => Uint8List.fromList(utf8.encode(value));

final class FixtureMessage {
  FixtureMessage({required this.raw, Uint8List? headers, this.flags = const []})
    : headers =
          headers ??
          fixtureBytes(
            'From: Sender <sender@example.test>\r\n'
            'To: Recipient <recipient@example.test>\r\n'
            'Subject: Fixture\r\n\r\n',
          );
  final Uint8List raw;
  final Uint8List headers;
  final List<String>? flags;
}

final class FixtureCredentials implements MailCredentialStore {
  FixtureCredentials(this.account);
  final MailAccountId account;
  bool revoked = false;
  int loads = 0;
  Future<void> Function()? beforeLoad;
  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference reference,
  ) async {
    loads++;
    await beforeLoad?.call();
    return MailSuccess(
      revoked
          ? null
          : MailCredentialRecord(
              reference: reference,
              opaqueData: MailBytes(fixtureBytes('fixture-only-password')),
            ),
    );
  }

  @override
  Future<MailResult<MailUnit>> delete(MailCredentialReference reference) async {
    revoked = true;
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account) async {
    revoked = true;
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> store(MailCredentialRecord record) async {
    revoked = false;
    return const MailSuccess(MailUnit.value);
  }
}

/// An original controlled server feeding real enough_mail command/read parsers.
/// No network binding or fake successful provider results are involved.
final class ImapFixture {
  ImapFixture({
    this.uidValidity = 41,
    this.uidNext = 4,
    Map<int, FixtureMessage>? messages,
    this.supportsMove = true,
    this.supportsStartTls = false,
    this.rejectLogin = false,
  }) : messages = messages ?? <int, FixtureMessage>{};

  final MailAccountId account = MailAccountId(
    'fixture-account',
    profile: MailProfileId('fixture-profile', hostId: 'fixture-host'),
  );
  late final MailMailboxId mailbox = MailMailboxId('INBOX', account: account);
  late final FixtureCredentials credentials = FixtureCredentials(account);
  int uidValidity;
  int uidNext;
  final Map<int, FixtureMessage> messages;
  bool supportsMove;
  bool supportsStartTls;
  bool rejectLogin;
  bool challengeAuth = false;
  bool supportsSaslIr = true;
  bool readOnly = false;
  bool omitValidity = false;
  bool wrongFetchedUid = false;
  bool partialBody = false;
  bool duplicateFetch = false;
  bool dropFetch = false;
  bool oversizeLiteral = false;
  bool malformedLiteral = false;
  bool fragmentedGreeting = false;
  bool longProtocolLine = false;
  String greeting = '* OK controlled fixture\r\n';
  bool lowerCaseFetch = false;
  bool malformedFetchPrefix = false;
  bool acknowledgeWithoutChange = false;
  bool closeAfterMutation = false;
  final List<String> commands = [];
  final List<FixtureImapClient> clients = [];
  Future<void> Function(String command)? beforeReply;
  Future<void> Function()? beforeConnect;
  Future<void> Function()? beforeTlsUpgrade;

  NativeMailImapProvider provider({
    MailAccountId? account,
    MailCredentialStore? credentialStore,
    MailTransportLimits limits = const MailTransportLimits(),
    MailTlsMode tls = MailTlsMode.implicitTls,
    MailImapAuthentication authentication = MailImapAuthentication.password,
  }) {
    final selected = account ?? this.account;
    return NativeMailImapProvider(
      configuration: MailImapConfiguration(
        account: selected,
        endpoint: MailServerEndpoint(
          host: 'mail.example.test',
          port: 993,
          tls: tls,
        ),
        username: 'reader@example.test',
        credential: MailCredentialReference(
          account: selected,
          key: 'imap-password',
        ),
        authentication: authentication,
      ),
      credentialStore: credentialStore ?? credentials,
      codec: const QudsMimeCodec(),
      limits: limits,
      clientFactory:
          ({
            required maxLiteralBytes,
            required maxResponseBytes,
            required limits,
          }) {
            final client = FixtureImapClient(
              this,
              maxLiteralBytes: maxLiteralBytes,
              maxResponseBytes: maxResponseBytes,
              limits: limits,
            );
            clients.add(client);
            return client;
          },
    );
  }

  Uint8List _envelopeHeaders(Uint8List input) {
    final allowed = <String>{
      'date',
      'from',
      'to',
      'cc',
      'bcc',
      'reply-to',
      'subject',
      'message-id',
      'in-reply-to',
      'references',
    };
    final output = <String>[];
    var keep = false;
    for (final line in utf8.decode(input).split('\r\n')) {
      if (line.isEmpty) break;
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        final colon = line.indexOf(':');
        keep =
            colon > 0 &&
            allowed.contains(line.substring(0, colon).toLowerCase());
      }
      if (keep) output.add(line);
    }
    return fixtureBytes('${output.join('\r\n')}\r\n\r\n');
  }

  Future<void> reply(FixtureSocket socket, String line) async {
    if (socket.pendingAuthTag != null) {
      commands.add(line.trim());
      socket.text('${socket.pendingAuthTag} NO authentication rejected\r\n');
      socket.pendingAuthTag = null;
      return;
    }
    final space = line.indexOf(' ');
    if (space < 1) throw StateError('Expected a tagged command');
    final tag = line.substring(0, space);
    final command = line
        .substring(space + 1)
        .replaceFirst(RegExp(r'\r\n$'), '');
    commands.add(command);
    await beforeReply?.call(command);
    if (socket.closed) return;
    if (command == 'CAPABILITY') {
      if (longProtocolLine) {
        socket.text('* ${'X' * 512}\r\n');
        return;
      }
      socket.text(
        '* CAPABILITY IMAP4rev1 AUTH=XOAUTH2 AUTH=OAUTHBEARER'
        '${supportsSaslIr ? ' SASL-IR' : ''}'
        '${supportsMove ? ' MOVE' : ''}${supportsStartTls ? ' STARTTLS' : ''}\r\n'
        '$tag OK capabilities\r\n',
      );
    } else if (command == 'STARTTLS') {
      socket.text('$tag OK begin TLS\r\n');
    } else if (command.startsWith('LOGIN ') ||
        command.startsWith('AUTHENTICATE ')) {
      if (challengeAuth && command.startsWith('AUTHENTICATE ')) {
        socket.pendingAuthTag = tag;
        socket.text('+ eyJzdGF0dXMiOiI0MDEifQ==\r\n');
      } else {
        socket.text('$tag ${rejectLogin ? 'NO' : 'OK'} authentication\r\n');
      }
    } else if (command.startsWith('LIST ')) {
      socket.text(
        '* LIST () "/" "INBOX"\r\n'
        '* LIST (\\Noselect) "/" "Container"\r\n'
        '* LIST () "/" "Archive"\r\n$tag OK mailboxes\r\n',
      );
    } else if (command.startsWith('SELECT ')) {
      socket.text(
        '* FLAGS (\\Seen \\Flagged \\Answered \\Draft \\Deleted)\r\n'
        '* ${messages.length} EXISTS\r\n'
        '${omitValidity ? '' : '* OK [UIDVALIDITY $uidValidity] validity\r\n'}'
        '* OK [UIDNEXT $uidNext] next\r\n'
        '* OK [PERMANENTFLAGS (\\Seen \\Flagged \\Answered \\Draft \\Deleted)] flags\r\n'
        '$tag OK [${readOnly ? 'READ-ONLY' : 'READ-WRITE'}] selected\r\n',
      );
    } else if (command.startsWith('UID FETCH ')) {
      if (dropFetch) {
        await socket.drop();
        return;
      }
      if (oversizeLiteral) {
        socket.text('* 1 FETCH (UID 1 BODY[] {999999999}\r\n');
        return;
      }
      final range = RegExp(r'^UID FETCH (\d+):(\d+) ').firstMatch(command);
      if (range == null) throw StateError('Expected a bounded UID range');
      final first = int.parse(range[1]!);
      final last = int.parse(range[2]!);
      final headers = command.contains('BODY.PEEK[HEADER.FIELDS ');
      var sequence = 0;
      for (final entry in messages.entries) {
        sequence++;
        if (entry.key < first || entry.key > last) continue;
        final literal = headers
            ? _envelopeHeaders(entry.value.headers)
            : entry.value.raw;
        final uid = wrongFetchedUid ? last + 1 : entry.key;
        final flags = entry.value.flags;
        final flagText = flags == null ? '' : ' FLAGS (${flags.join(' ')})';
        final body = headers
            ? imap.rawImapHeaderItem
            : partialBody
            ? 'BODY[]<0>'
            : 'BODY[]';
        for (var copy = 0; copy < (duplicateFetch ? 2 : 1); copy++) {
          var prefix =
              '* $sequence FETCH (UID $uid$flagText $body {${literal.length}}\r\n';
          if (lowerCaseFetch) prefix = prefix.toLowerCase();
          if (malformedFetchPrefix) {
            prefix = prefix.replaceFirst('* $sequence ', '* x ');
          }
          socket.text(prefix);
          socket.bytes(literal);
          socket.text(malformedLiteral ? '\r\n' : ')\r\n');
        }
      }
      socket.text('$tag OK fetched\r\n');
    } else if (command.startsWith('UID STORE ')) {
      final match = RegExp(
        r'^UID STORE (\d+) ([+-])FLAGS \(([^)]+)\)',
      ).firstMatch(command);
      if (match == null) throw StateError('Expected UID STORE');
      final uid = int.parse(match[1]!);
      final current = messages[uid];
      if (current != null && !acknowledgeWithoutChange) {
        final flags = <String>{...?current.flags};
        if (match[2] == '+') {
          flags.add(match[3]!);
        } else {
          flags.remove(match[3]!);
        }
        messages[uid] = FixtureMessage(
          raw: current.raw,
          headers: current.headers,
          flags: flags.toList(),
        );
      }
      if (closeAfterMutation) {
        await socket.drop();
        return;
      }
      socket.text('$tag OK applied\r\n');
    } else if (command.startsWith('UID MOVE ')) {
      final match = RegExp(r'^UID MOVE (\d+) ').firstMatch(command);
      if (match == null) throw StateError('Expected UID MOVE');
      if (!acknowledgeWithoutChange) messages.remove(int.parse(match[1]!));
      if (closeAfterMutation) {
        await socket.drop();
        return;
      }
      socket.text('$tag OK applied\r\n');
    } else {
      throw StateError('Unexpected fixture command: $command');
    }
  }
}

final class FixtureImapClient extends imap.ImapClient {
  FixtureImapClient(
    this.fixture, {
    required int maxLiteralBytes,
    required int maxResponseBytes,
    required MailTransportLimits limits,
  }) : super(
         defaultResponseTimeout: limits.operationTimeout,
         defaultWriteTimeout: limits.operationTimeout,
         maxLiteralSize: maxLiteralBytes,
         maxResponseBytes: maxResponseBytes,
         maxProtocolLineBytes: limits.maxProtocolLineBytes,
       );
  final ImapFixture fixture;
  late FixtureSocket socket;
  final List<FixtureSocket> sockets = [];
  bool? requestedSecure;
  @override
  Future<ClientConnection> createSecureConnectionSocket(
    ClientConnection original, {
    required String host,
  }) async {
    await fixture.beforeTlsUpgrade?.call();
    final secure = FixtureSocket(fixture.reply);
    sockets.add(secure);
    socket = secure;
    return SocketClientConnection(secure);
  }

  @override
  Future<ClientConnection> createConnectionSocket(
    String host,
    int port, {
    required bool isSecure,
  }) async {
    requestedSecure = isSecure;
    socket = FixtureSocket(fixture.reply);
    sockets.add(socket);
    await fixture.beforeConnect?.call();
    if (fixture.fragmentedGreeting) {
      socket.text('* O');
      scheduleMicrotask(() => socket.text('K controlled fixture\r\n'));
    } else {
      socket.text(fixture.greeting);
    }
    return SocketClientConnection(socket);
  }
}

final class FixtureSocket extends Stream<Uint8List> implements Socket {
  FixtureSocket(this.onCommand);
  final Future<void> Function(FixtureSocket socket, String command) onCommand;
  final StreamController<Uint8List> _input = StreamController<Uint8List>();
  bool closed = false;
  String? pendingAuthTag;
  final List<Object> errors = [];
  @override
  Encoding encoding = utf8;
  void text(String value) => bytes(utf8.encode(value));
  void bytes(List<int> value) {
    if (!closed) _input.add(Uint8List.fromList(value));
  }

  Future<void> drop() async {
    closed = true;
    await _input.close();
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _input.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  void write(Object? object) {
    if (closed) throw const SocketException('Fixture closed');
    unawaited(
      onCommand(this, object.toString()).catchError((Object error) {
        errors.add(error);
        if (!closed) _input.addError(error);
      }),
    );
  }

  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {
    closed = true;
    unawaited(_input.close());
  }

  @override
  void destroy() {
    unawaited(close());
  }

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Fixture socket operation is outside its protocol',
  );
}
