import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_cloud.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);

final class _Tokens extends Fake implements MailCloudTokenSource {
  int disposals = 0;
  @override
  void dispose() => disposals++;
}

final class _Provider extends Fake implements MailCloudProvider {
  _Provider(this.configuration);
  final MailCloudConfiguration configuration;
  int disposals = 0;
  int reads = 0;
  bool disposalThrows = false;
  MailOperationLease? lastLease;
  MailProblem? connectionProblem;
  Completer<MailResult<MailMessage>>? messageGate;
  MailSubmissionOutcome outcome = MailSubmissionOutcome.accepted;
  MailProblem? submissionProblem;
  final submissions = <MailPreparedMessage>[];
  final commands = <MailOperation>[];
  MailAccountId? accountOverride;

  @override
  MailAccountId get account => accountOverride ?? configuration.account;
  MailMailboxId box(String name) => MailMailboxId(name, account: account);
  MailOpaqueIdentity identity(String value) => MailOpaqueIdentity(
    account: account,
    provider: configuration.service == MailCloudService.gmail
        ? MailProviderKind.gmail
        : MailProviderKind.graph,
    value: value,
  );

  @override
  void dispose() {
    disposals++;
    if (disposalThrows) throw StateError('private-provider-cleanup');
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async {
    lastLease = lease;
    return connectionProblem == null
        ? MailSuccess(
            MailCapabilities(const [
              MailCapability.mail,
              MailCapability.folders,
              MailCapability.send,
              MailCapability.move,
            ]),
          )
        : MailFailure(connectionProblem!);
  }

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => MailSuccess([
    MailMailbox(id: box('inbox'), displayName: 'Inbox'),
    MailMailbox(id: box('archive'), displayName: 'Archive'),
  ]);

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    lastLease = lease;
    expect(limit, 50);
    return MailSuccess(
      MailHeaderPage(
        messages: [
          MailHeaderRecord(
            id: MailMessageId('cloud-message'),
            remote: identity('remote-message'),
            envelope: MailEnvelope(
              subject: 'Cloud message',
              from: [const MailAddress('writer@example.test')],
            ),
            flags: const MailMessageFlags(),
          ),
        ],
      ),
    );
  }

  MailMessage message() {
    final parsed = const QudsMimeCodec()
        .parse(
          utf8.encode(
            'From: Writer <writer@example.test>\r\n'
            'To: Reader <reader@example.test>\r\n'
            'Subject: Cloud message\r\n'
            'Content-Type: text/plain; charset=utf-8\r\n\r\n'
            'Body from cloud provider.\r\n',
          ),
        )
        .message!;
    return MailMessage(
      raw: parsed.raw,
      envelope: parsed.envelope,
      body: parsed.body,
      attachments: parsed.attachments,
      localId: MailMessageId('cloud-message'),
      remoteIdentity: identity('remote-message'),
    );
  }

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    reads++;
    lastLease = lease;
    return messageGate == null
        ? MailSuccess(message())
        : await messageGate!.future;
  }

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) async {
    commands.add(operation);
    lastLease = lease;
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailSubmissionResult> submit(
    MailPreparedMessage message, {
    required String attemptId,
    required MailOperationLease lease,
  }) async {
    submissions.add(message);
    lastLease = lease;
    return MailSubmissionResult(
      attemptId: attemptId,
      outcome: outcome,
      problem: submissionProblem,
    );
  }
}

final class _Harness {
  final tokens = _Tokens();
  int authorizations = 0;
  MailOAuthConfiguration? authorization;
  MailOperationLease? authLease;
  MailCloudLogSink? authLog;
  MailCloudLogSink? providerLog;
  Completer<MailResult<MailCloudTokenSource>>? authorizationGate;
  Object? authorizationError;
  MailProblem? authorizationProblem;
  MailProblem? connectionProblem;
  bool wrongAccount = false;
  bool factoryThrows = false;
  _Provider? provider;

  Future<MailResult<MailCloudTokenSource>> authorize({
    required MailOAuthConfiguration configuration,
    required MailAccountId account,
    required Future<bool> Function(Uri) openBrowser,
    required MailOperationLease lease,
    MailCloudLogSink? log,
  }) async {
    authorizations++;
    authorization = configuration;
    authLease = lease;
    authLog = log;
    expect(lease.account, account);
    if (authorizationError case final error?) throw error;
    if (authorizationProblem case final problem?) return MailFailure(problem);
    return authorizationGate == null
        ? MailSuccess(tokens)
        : await authorizationGate!.future;
  }

  MailCloudProvider create({
    required MailCloudConfiguration configuration,
    required MailCloudTokenSource tokenSource,
    MailCloudLogSink? log,
  }) {
    expect(tokenSource, same(tokens));
    if (factoryThrows) throw StateError('private-factory-credentials');
    providerLog = log;
    final result = _Provider(configuration)
      ..connectionProblem = connectionProblem;
    if (wrongAccount) {
      result.accountOverride = MailAccountId(
        'wrong-account',
        profile: configuration.account.profile,
      );
    }
    provider = result;
    return result;
  }
}

Finder _field(String key) => find.byKey(ValueKey(key));
Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _show(
  WidgetTester tester,
  _Harness harness, {
  MailCloudService service = MailCloudService.gmail,
  Size size = const Size(1280, 900),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => StudioMailCloudDialog(
                strings: _strings,
                service: service,
                authorizer: harness.authorize,
                providerFactory: harness.create,
                initialClientId: 'test-desktop-client',
                openBrowser: (_) async => true,
              ),
            ),
            child: const Text('Open cloud'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open cloud'));
  await _pump(tester);
}

Future<void> _connect(WidgetTester tester) async {
  await tester.enterText(_field('cloud-mailbox'), 'reader@example.test');
  await tester.ensureVisible(_field('cloud-connect'));
  await _pump(tester);
  await tester.tap(_field('cloud-connect'));
  await _pump(tester);
}

Finder _composeField(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _send(WidgetTester tester) async {
  await tester.tap(find.byTooltip(_strings.compose));
  await _pump(tester);
  await tester.enterText(_composeField(_strings.to), 'recipient@example.test');
  await tester.enterText(_composeField(_strings.subject), 'Cloud send');
  tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller
      .insertText('Sent from CrispOffice.');
  await tester.pump();
  final send = find.widgetWithText(FilledButton, _strings.send);
  await tester.ensureVisible(send);
  await tester.tap(send);
  await _pump(tester);
}

void main() {
  testWidgets('native setup offers Gmail, Microsoft 365 and Exchange', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: StudioMailDialog(strings: _strings)),
    );
    expect(_field('studio-mail-open-gmail'), findsOneWidget);
    expect(_field('studio-mail-open-microsoft365'), findsOneWidget);
    expect(_field('studio-mail-open-ews'), findsOneWidget);
    await tester.tap(_field('studio-mail-open-gmail'));
    await _pump(tester);
    expect(find.byType(StudioMailCloudDialog), findsOneWidget);
    expect(_field('cloud-mailbox'), findsOneWidget);
    expect(_field('ews-password'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final service in MailCloudService.values) {
    testWidgets(
      '${service.name} signs in and adopts the matching mailbox session',
      (tester) async {
        final harness = _Harness();
        await _show(tester, harness, service: service);
        if (service == MailCloudService.gmail) {
          await tester.enterText(
            _field('cloud-client-secret'),
            'desktop-metadata-secret',
          );
        } else {
          await tester.enterText(_field('cloud-tenant'), 'organizations');
        }
        final secret = service == MailCloudService.gmail
            ? tester.widget<TextField>(_field('cloud-client-secret')).controller
            : null;
        await _connect(tester);
        expect(harness.authorization!.service, service);
        expect(harness.authorization!.clientId, 'test-desktop-client');
        expect(
          harness.authorization!.tenant,
          service == MailCloudService.gmail ? 'common' : 'organizations',
        );
        expect(secret?.text ?? '', isEmpty);
        expect(
          harness.provider!.configuration.mailboxAddress,
          'reader@example.test',
        );
        expect(harness.authLog, isNull);
        expect(harness.providerLog, isNull);
        expect(find.text('Cloud message'), findsOneWidget);
        expect(harness.provider!.reads, 0);
        await tester.tap(find.text('Cloud message'));
        await _pump(tester);
        expect(find.byType(MailMessageView), findsOneWidget);
        expect(harness.provider!.commands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('invalid settings never authorize or construct a provider', (
    tester,
  ) async {
    final harness = _Harness();
    await _show(tester, harness);
    await tester.enterText(_field('cloud-client-id'), '');
    await _connect(tester);
    expect(harness.authorizations, 0);
    expect(harness.provider, isNull);
    expect(find.text(_strings.mailCloudInvalidSettings), findsOneWidget);
  });

  testWidgets(
    'authorization exceptions are redacted and leave retry available',
    (tester) async {
      final harness = _Harness()
        ..authorizationError = StateError(
          'secret-token private-address@example.test',
        );
      await _show(tester, harness);
      await _connect(tester);
      expect(find.text(_strings.mailCloudSignInFailed), findsOneWidget);
      expect(find.textContaining('secret-token'), findsNothing);
      expect(
        tester.widget<FilledButton>(_field('cloud-connect')).onPressed,
        isNotNull,
      );
      harness.authorizationError = null;
      await tester.tap(_field('cloud-connect'));
      await _pump(tester);
      expect(find.text('Cloud message'), findsOneWidget);
    },
  );

  testWidgets('denied OAuth permissions use localized actionable feedback', (
    tester,
  ) async {
    final harness = _Harness()
      ..authorizationProblem = const MailProblem(
        MailProblemCode.permissionDenied,
      );
    await _show(tester, harness);
    await _connect(tester);
    expect(find.text(_strings.mailCloudAccessFailed), findsOneWidget);
    expect(harness.provider, isNull);
  });

  testWidgets(
    'cancelled browser authorization rejects and disposes late tokens',
    (tester) async {
      final harness = _Harness()
        ..authorizationGate = Completer<MailResult<MailCloudTokenSource>>();
      await _show(tester, harness);
      await _connect(tester);
      expect(harness.authLease!.isCurrent, isTrue);
      await tester.ensureVisible(find.text(_strings.cancel));
      await tester.tap(find.text(_strings.cancel));
      await _pump(tester);
      expect(harness.authLease!.isCurrent, isFalse);
      harness.authorizationGate!.complete(MailSuccess(harness.tokens));
      await _pump(tester);
      expect(harness.tokens.disposals, 1);
      expect(harness.provider, isNull);
      expect(find.text('Cloud message'), findsNothing);
    },
  );

  testWidgets(
    'closing during authorization invalidates the lease and clears late tokens',
    (tester) async {
      final harness = _Harness()
        ..authorizationGate = Completer<MailResult<MailCloudTokenSource>>();
      await _show(tester, harness);
      await _connect(tester);
      await tester.tap(find.byTooltip(_strings.close));
      await _pump(tester);
      harness.authorizationGate!.complete(MailSuccess(harness.tokens));
      await _pump(tester);
      expect(harness.authLease!.isCurrent, isFalse);
      expect(harness.tokens.disposals, 1);
      expect(harness.provider, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mailbox rejection closes provider and tokens without exposing metadata secret',
    (tester) async {
      final harness = _Harness()
        ..connectionProblem = const MailProblem(
          MailProblemCode.authenticationRequired,
        );
      await _show(tester, harness);
      await tester.enterText(_field('cloud-client-secret'), 'secret-metadata');
      final secret = tester
          .widget<TextField>(_field('cloud-client-secret'))
          .controller!;
      await _connect(tester);
      expect(find.text(_strings.mailCloudAuthenticationFailed), findsOneWidget);
      expect(harness.provider!.disposals, 1);
      expect(harness.tokens.disposals, 1);
      expect(secret.text, isEmpty);
      expect(harness.authLease!.isCurrent, isFalse);
    },
  );

  testWidgets(
    'wrong-account provider is rejected and disposed before mailbox reads',
    (tester) async {
      final harness = _Harness()..wrongAccount = true;
      await _show(tester, harness);
      await _connect(tester);
      expect(find.text(_strings.mailCloudSignInFailed), findsOneWidget);
      expect(harness.provider!.disposals, 1);
      expect(harness.provider!.reads, 0);
      expect(harness.tokens.disposals, 1);
    },
  );

  testWidgets('provider construction errors retire the authorized tokens', (
    tester,
  ) async {
    final harness = _Harness()..factoryThrows = true;
    await _show(tester, harness);
    await _connect(tester);
    expect(harness.tokens.disposals, 1);
    expect(harness.authLease!.isCurrent, isFalse);
    expect(find.text(_strings.mailCloudSignInFailed), findsOneWidget);
    expect(find.textContaining('private-factory-credentials'), findsNothing);
  });

  testWidgets(
    'throttling displays the rounded delay without an automatic retry',
    (tester) async {
      final harness = _Harness()
        ..connectionProblem = const MailProblem(
          MailProblemCode.quotaExceeded,
          retryAfter: Duration(milliseconds: 12500),
        );
      await _show(tester, harness);
      await _connect(tester);
      expect(find.text(_strings.mailCloudRetryAfter(13)), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
      expect(harness.authorizations, 1);
      expect(harness.provider!.submissions, isEmpty);
    },
  );

  testWidgets(
    'provider cleanup failure cannot prevent token cleanup or disconnect',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness);
      await _connect(tester);
      harness.provider!.disposalThrows = true;
      await tester.tap(find.byTooltip(_strings.disconnect));
      await _pump(tester);
      expect(harness.tokens.disposals, 1);
      expect(_field('cloud-connect'), findsOneWidget);
      expect(find.textContaining('private-provider-cleanup'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disconnect ignores a pending message body and retires session resources',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness);
      await _connect(tester);
      final provider = harness.provider!
        ..messageGate = Completer<MailResult<MailMessage>>();
      await tester.tap(find.text('Cloud message'));
      await _pump(tester);
      await tester.tap(find.byTooltip(_strings.disconnect));
      await _pump(tester);
      provider.messageGate!.complete(MailSuccess(provider.message()));
      await _pump(tester);
      expect(provider.lastLease!.isCurrent, isFalse);
      expect(provider.disposals, 1);
      expect(harness.tokens.disposals, 1);
      expect(find.byType(MailMessageView), findsNothing);
      expect(_field('cloud-connect'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'verbose diagnostics opt in passes only structured safe events to the log',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness);
      await tester.ensureVisible(_field('cloud-diagnostics'));
      await tester.tap(_field('cloud-diagnostics'));
      await _pump(tester);
      await _connect(tester);
      expect(harness.authLog, isNotNull);
      expect(harness.providerLog, isNotNull);
      final captured = <String>[];
      final previous = debugPrint;
      debugPrint = (String? value, {int? wrapWidth}) {
        if (value != null) captured.add(value);
      };
      try {
        harness.providerLog!(
          const MailCloudLogEvent(
            service: MailCloudService.gmail,
            operation: MailCloudOperation.fetchHeaders,
            stage: MailCloudLogStage.completed,
            itemCount: 1,
            statusCode: 200,
          ),
        );
      } finally {
        debugPrint = previous;
      }
      expect(jsonDecode(captured.single), {
        'service': 'gmail',
        'operation': 'fetchHeaders',
        'stage': 'completed',
        'statusCode': 200,
        'itemCount': 1,
      });
    },
  );

  testWidgets(
    'cloud composition uses canonical MIME and does not overclaim delivery',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness, service: MailCloudService.microsoft365);
      await _connect(tester);
      await _send(tester);
      final submission = harness.provider!.submissions.single;
      expect(submission.envelope.sender, 'reader@example.test');
      expect(submission.envelope.recipients, ['recipient@example.test']);
      expect(
        utf8.decode(submission.wire.bytes),
        contains('Sent from CrispOffice.'),
      );
      expect(find.text(_strings.mailCloudSubmissionAccepted), findsOneWidget);
      expect(find.text(_strings.ewsSubmissionAccepted), findsNothing);
    },
  );

  testWidgets(
    'uncertain cloud send retains draft and never automatically resubmits',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness);
      await _connect(tester);
      harness.provider!.outcome = MailSubmissionOutcome.uncertain;
      await _send(tester);
      expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
      expect(harness.provider!.submissions, hasLength(1));
      await tester.tap(find.byTooltip(_strings.compose));
      await _pump(tester);
      expect(find.text(_strings.mailRetryAcknowledgement), findsOneWidget);
      final send = find.widgetWithText(FilledButton, _strings.send);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(harness.provider!.submissions, hasLength(1));
    },
  );

  testWidgets(
    'definite rejected sends retain drafts and show Retry-After without resending',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness);
      await _connect(tester);
      harness.provider!
        ..outcome = MailSubmissionOutcome.rejected
        ..submissionProblem = const MailProblem(
          MailProblemCode.quotaExceeded,
          retryAfter: Duration(seconds: 45),
        );
      await _send(tester);
      expect(
        find.textContaining(_strings.mailCloudRetryAfter(45)),
        findsOneWidget,
      );
      expect(
        find.textContaining(_strings.ewsSubmissionRejected),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 60));
      expect(harness.provider!.submissions, hasLength(1));
      await tester.tap(find.byTooltip(_strings.compose));
      await _pump(tester);
      expect(
        tester
            .widget<TextField>(_composeField(_strings.subject))
            .controller!
            .text,
        'Cloud send',
      );
      expect(find.text(_strings.mailRetryAcknowledgement), findsNothing);
    },
  );

  testWidgets('narrow cloud setup and mailbox remain usable without overflow', (
    tester,
  ) async {
    final harness = _Harness();
    await _show(tester, harness, size: const Size(400, 850));
    await _connect(tester);
    await tester.tap(find.text('Cloud message'));
    await _pump(tester);
    expect(find.byType(MailMessageView), findsOneWidget);
    expect(find.byTooltip(_strings.mailCloudDelete), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
