import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_productivity_automation.dart';
import 'package:quds_office_engine/quds_productivity_live.dart';
import 'package:test/test.dart';

Map<String, Object?> _request(String method, [Map<String, Object?>? params]) =>
    {'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': ?params};

final _initialize = _request('initialize', {
  'protocolVersion': '2025-11-25',
  'capabilities': <String, Object?>{},
  'clientInfo': {'name': 'test', 'version': '1'},
});

Future<void> _start(ProductivityGrantRelay relay) async {
  expect(await relay.forward(_initialize), contains('result'));
  expect(
    await relay.forward({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    }),
    isNull,
  );
}

Map<String, Object?> _result(Map<String, Object?>? reply) =>
    (reply!['result']! as Map<String, Object?>)['structuredContent']
        as Map<String, Object?>;

void main() {
  for (final kind in ProductivityKind.values) {
    test(
      '${kind.name} grant returns current data and fences the scope',
      () async {
        var current = true;
        var text = 'First';
        var reads = 0;
        final grant = await ProductivityGrant.open(
          isCurrent: () => current,
          session: ProductivityMcp.live(
            kind: kind,
            read: () {
              reads++;
              return ProductivitySnapshot.capture(
                kind: kind,
                capturedAt: DateTime.utc(2026, 11, 26),
                rows: [
                  {kind.fields.first: text, 'secret': 'must never be shared'},
                ],
              );
            },
          ),
        );
        addTearDown(grant.revoke);
        final relay = ProductivityGrantRelay(
          ProductivityGrantTicket.parse(grant.ticket.relayCredential),
        );
        addTearDown(relay.close);
        await _start(relay);
        final call = _request('tools/call', {'name': kind.tool});
        expect(_result(await relay.forward(call))['rows'], [
          {kind.fields.first: 'First'},
        ]);
        text = 'Latest';
        expect(_result(await relay.forward(call))['rows'], [
          {kind.fields.first: 'Latest'},
        ]);
        expect(grant.successfulReads, 2);
        final rejected = await relay.forward(
          _request('tools/call', {
            'name': kind.tool,
            'arguments': {'account': 'different-account'},
          }),
        );
        expect(rejected, contains('error'));
        expect(
          await relay.forward(_request('tools/call', {'name': 'mail_send'})),
          contains('error'),
        );
        current = false;
        expect(await relay.forward(call), contains('error'));
        expect(reads, 2);
        await grant.revoke();
        expect(await relay.forward(call), contains('error'));
      },
    );
  }

  test(
    'the optional body tool is read-only and follows the pinned message',
    () async {
      var messageCurrent = true;
      final grant = await ProductivityGrant.open(
        isCurrent: () => true,
        session: ProductivityMcp.live(
          kind: ProductivityKind.mail,
          read: () => throw StateError('Headers not requested'),
          readOpenedMail: () => messageCurrent
              ? ProductivityMailText(subject: 'Open', text: 'Example text')
              : null,
        ),
      );
      addTearDown(grant.revoke);
      final relay = ProductivityGrantRelay(grant.ticket);
      addTearDown(relay.close);
      await _start(relay);
      final call = _request('tools/call', {'name': 'mail_read_opened_text'});
      expect(_result(await relay.forward(call))['text'], 'Example text');
      messageCurrent = false;
      expect(await relay.forward(call), contains('error'));
    },
  );

  test(
    'the private relay rejects invalid bearer, Host and browser Origin',
    () async {
      final grant = await ProductivityGrant.open(
        isCurrent: () => true,
        session: ProductivityMcp.live(
          kind: ProductivityKind.tasks,
          read: () => throw StateError('Unexpected data read'),
        ),
      );
      addTearDown(grant.revoke);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final parts = grant.ticket.relayCredential.split('.');
      final target = Uri.parse(
        'http://127.0.0.1:${parts.first}/productivity-grant',
      );
      Future<int> status({
        String? bearer,
        String? origin,
        String? host,
        String? body,
      }) async {
        final request = await client.postUrl(target);
        request.headers.contentType = ContentType.json;
        if (bearer != null) {
          request.headers.set('authorization', 'Bearer $bearer');
        }
        if (origin != null) request.headers.set('origin', origin);
        if (host != null) request.headers.set('host', host);
        final input = utf8.encode(body ?? jsonEncode(_initialize));
        request.contentLength = input.length;
        request.add(input);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await status(), HttpStatus.forbidden);
      expect(await status(bearer: 'wrong'), HttpStatus.forbidden);
      expect(
        await status(bearer: parts.last, origin: 'https://example.test'),
        HttpStatus.forbidden,
      );
      expect(
        await status(bearer: parts.last, host: 'example.test'),
        HttpStatus.forbidden,
      );
      expect(
        await status(bearer: parts.last, body: List.filled(34000, ' ').join()),
        HttpStatus.requestEntityTooLarge,
      );
      expect(await status(bearer: parts.last), HttpStatus.ok);
    },
  );

  test(
    'Dart stdio executable relays reads with only the granted credential',
    () async {
      final grant = await ProductivityGrant.open(
        isCurrent: () => true,
        session: ProductivityMcp.live(
          kind: ProductivityKind.tasks,
          read: () => ProductivitySnapshot.capture(
            kind: ProductivityKind.tasks,
            capturedAt: DateTime.utc(2026, 11, 26),
            rows: [
              {'title': 'Local task', 'status': 'completed'},
            ],
          ),
        ),
      );
      addTearDown(grant.revoke);
      final process = await Process.start(
        Platform.resolvedExecutable,
        [
          if (Platform.packageConfig case final config?) '--packages=$config',
          'tool/macros/productivity_live_mcp.dart',
        ],
        includeParentEnvironment: false,
        environment: {
          ProductivityGrantTicket.environmentKey: grant.ticket.relayCredential,
        },
      );
      addTearDown(process.kill);
      final stdout = utf8.decoder
          .bind(process.stdout)
          .transform(const LineSplitter())
          .map(jsonDecode)
          .toList();
      final stderr = utf8.decoder.bind(process.stderr).join();
      for (final request in [
        _initialize,
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        _request('tools/list'),
        _request('tools/call', {'name': 'tasks_list_items'}),
      ]) {
        process.stdin.writeln(jsonEncode(request));
      }
      await process.stdin.close();
      expect(await process.exitCode, 0);
      expect(await stderr, isEmpty);
      final replies = await stdout;
      expect(replies, hasLength(3));
      expect(_result(replies.last as Map<String, Object?>)['rows'], [
        {'title': 'Local task', 'status': 'completed'},
      ]);
    },
  );

  test('grants expire and bound request rates', () async {
    final session = ProductivityMcp.live(
      kind: ProductivityKind.calendar,
      read: () => throw StateError('Unexpected data read'),
    );
    final grant = await ProductivityGrant.open(
      session: session,
      isCurrent: () => true,
    );
    addTearDown(grant.revoke);
    final relay = ProductivityGrantRelay(grant.ticket);
    addTearDown(relay.close);
    for (var i = 0; i < 60; i++) {
      expect(await relay.forward(_request('ping')), contains('result'));
    }
    expect(await relay.forward(_request('ping')), contains('error'));
    final expiring = await ProductivityGrant.open(
      session: session,
      isCurrent: () => true,
      lifetime: const Duration(milliseconds: 30),
    );
    addTearDown(expiring.revoke);
    final shortRelay = ProductivityGrantRelay(expiring.ticket);
    addTearDown(shortRelay.close);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(expiring.isActive, isFalse);
    expect(await shortRelay.forward(_request('ping')), contains('error'));
  });
}
