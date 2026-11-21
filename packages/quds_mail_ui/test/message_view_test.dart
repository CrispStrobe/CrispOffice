import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'fixtures/mail_fixture.dart';
import 'support/runtime_network_guard.dart';

final class _Policy implements MailExternalResourcePolicy {
  int links = 0, resources = 0;
  MailResourceDecision decision = MailResourceDecision.deny;
  Completer<MailResourceDecision>? pending;
  @override
  Future<MailResourceDecision> openLink(Uri target) {
    links++;
    return pending?.future ?? Future.value(decision);
  }

  @override
  Future<MailResourceDecision> loadRemoteResource(Uri target) async {
    resources++;
    return MailResourceDecision.deny;
  }
}

Widget _app(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  testWidgets(
    'disposing the view invalidates a pending explicit link decision',
    (tester) async {
      final controller = MailReaderController(
        result: mailFixture(html: '<a href="https://a.invalid">A</a>'),
      );
      final policy = _Policy()..pending = Completer<MailResourceDecision>();
      var opens = 0;
      await tester.pumpWidget(
        _app(
          MailMessageView(
            controller: controller,
            externalResources: policy,
            onOpenApprovedLink: (uri) async {
              opens++;
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('mail-link-0')));
      await tester.pumpWidget(const SizedBox());
      policy.pending!.complete(MailResourceDecision.allow);
      await tester.pumpAndSettle();
      expect(opens, 0);
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );

  testWidgets(
    'find chrome accepts arbitrary query and finds attachment names',
    (tester) async {
      final controller = MailReaderController(
        result: mailFixture(
          plainText: 'Arbitrary query text',
          attachments: [byteAttachment()],
        ),
      );
      await tester.pumpWidget(_app(MailMessageView(controller: controller)));
      await tester.tap(find.byKey(const ValueKey('mail-find')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mail-find-input')),
        'original.bin',
      );
      await tester.pumpAndSettle();
      expect(controller.searchMatches, hasLength(1));
      expect(find.text('1 match'), findsOneWidget);
      await tester.tap(find.byTooltip('Next match (F3)'));
      await tester.pumpAndSettle();
      expect(controller.selectedText, 'original.bin');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'runtime network denial is active, independently of the injected policy',
    (tester) async {
      final guard = RuntimeNetworkGuard();
      await guard.run(() async {
        guard.probe();
      });
      expect(guard.attempts, 1);
    },
  );

  testWidgets(
    'hostile saved HTML causes zero policy and runtime outbound requests',
    (tester) async {
      // Bootstrap Flutter test assets before placing the independent runtime guard.
      await tester.pumpWidget(
        _app(
          const Column(
            children: [Text('Bootstrap complete'), Icon(Icons.copy)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller = MailReaderController(
        result: mailFixture(html: hostileHtml),
      );
      final policy = _Policy(), guard = RuntimeNetworkGuard();
      var opens = 0;
      await guard.run(() async {
        await tester.pumpWidget(
          _app(
            MailMessageView(
              controller: controller,
              externalResources: policy,
              onOpenApprovedLink: (uri) async {
                opens++;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MailSelectionSurface), findsOneWidget);
        expect(policy.links, 0);
        expect(policy.resources, 0);
        expect(opens, 0);
        expect(guard.attempts, 0);
      });
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'link activation is denied until host policy explicitly approves it',
    (tester) async {
      final controller = MailReaderController(
        result: mailFixture(
          html:
              '<a href="https://approved.invalid/start?redirect=https://next.invalid/">Link</a>',
        ),
      );
      final policy = _Policy();
      final opened = <Uri>[];
      await tester.pumpWidget(
        _app(
          MailMessageView(
            controller: controller,
            externalResources: policy,
            onOpenApprovedLink: (uri) async {
              opened.add(uri);
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('mail-link-0')));
      await tester.pumpAndSettle();
      expect(policy.links, 1);
      expect(opened, isEmpty);
      expect(find.text('The host did not approve this link.'), findsOneWidget);
      policy.decision = MailResourceDecision.allow;
      await tester.tap(find.byKey(const ValueKey('mail-link-0')));
      await tester.pumpAndSettle();
      expect(opened.single.host, 'approved.invalid');
      expect(opened.single.query, contains('next.invalid'));
      expect(policy.resources, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'late link approval cannot act on a replaced message or disposed view',
    (tester) async {
      final controller = MailReaderController(
        result: mailFixture(html: '<a href="https://a.invalid">A</a>'),
      );
      final policy = _Policy()..pending = Completer<MailResourceDecision>();
      var opens = 0;
      await tester.pumpWidget(
        _app(
          MailMessageView(
            controller: controller,
            externalResources: policy,
            onOpenApprovedLink: (uri) async {
              opens++;
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('mail-link-0')));
      controller.replaceResult(mailFixture(plainText: 'A new message'));
      policy.pending!.complete(MailResourceDecision.allow);
      await tester.pumpAndSettle();
      expect(opens, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'attachment and source/hex callbacks receive exact immutable snapshots',
    (tester) async {
      final attachment = byteAttachment();
      final result = mailFixture(attachments: [attachment]);
      final controller = MailReaderController(result: result);
      MailAttachment? opened;
      final sources = <(MailBytes, MailSourceView)>[];
      await tester.pumpWidget(
        _app(
          MailMessageView(
            controller: controller,
            onOpenAttachmentReadOnly: (value) async {
              opened = value;
            },
            onOpenSource: (bytes, view) async {
              sources.add((bytes, view));
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('mail-attachment-0')));
      await tester.tap(find.byKey(const ValueKey('mail-source')));
      await tester.tap(find.byKey(const ValueKey('mail-hex')));
      await tester.pumpAndSettle();
      expect(identical(opened, attachment), isTrue);
      expect(opened!.content.bytes, [0, 1, 128, 255]);
      expect(() => opened!.content.bytes[0] = 99, throwsUnsupportedError);
      expect(sources.map((value) => value.$2), MailSourceView.values);
      for (final (bytes, _) in sources) {
        expect(identical(bytes, result.original), isTrue);
        expect(bytes.bytes, [255, 0, 13, 10, 65]);
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'custom RenderBox supports keyboard select/copy and meaningful semantics',
    (tester) async {
      final controller = MailReaderController(
        result: mailFixture(plainText: 'Visible decoded text.'),
      );
      String? copied;
      await tester.pumpWidget(
        _app(
          MailMessageView(
            controller: controller,
            onCopy: (text) async {
              copied = text;
            },
          ),
        ),
      );
      final surface = find.byType(MailSelectionSurface);
      expect(tester.renderObject(surface), isA<RenderMailSelectionSurface>());
      await tester.tap(surface);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(copied, controller.decodedText);
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(surface).getSemanticsData().label,
        'Decoded message, read only',
      );
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('render rejection remains visible with exact source fallback', (
    tester,
  ) async {
    final controller = MailReaderController(
      result: mailFixture(plainText: 'x' * 200),
      budget: const MailReadBudget(maxRenderTextBytes: 100),
    );
    await tester.pumpWidget(
      _app(
        MailMessageView(
          controller: controller,
          onOpenSource: (bytes, view) async {},
        ),
      ),
    );
    expect(find.text('Message display unavailable'), findsOneWidget);
    expect(find.byType(MailSelectionSurface), findsNothing);
    expect(find.byKey(const ValueKey('mail-source')), findsOneWidget);
    expect(
      find.text('Decoded text exceeds the rendering limit.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('compact enlarged RTL view preserves actions without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MailReaderController(
      result: mailFixture(plainText: 'مرحبا بالعالم\nMixed text here.'),
      mode: MailReaderMode.preview,
    );
    await tester.pumpWidget(
      _app(
        MailMessageView(
          controller: controller,
          compact: true,
          onOpenSource: (bytes, view) async {},
        ),
        direction: TextDirection.rtl,
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // A completely decoded message has no status line, in any reader mode.
    expect(find.byKey(const ValueKey('mail-reader-status')), findsNothing);
    expect(find.byType(MailSelectionSurface), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('bounded CID PNG decodes locally under runtime network denial', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Column(children: [Text('Bootstrap complete'), Icon(Icons.copy)]),
      ),
    );
    await tester.pumpAndSettle();
    final controller = MailReaderController(
      result: mailFixture(
        html: '<img src="cid:pixel">',
        attachments: [
          byteAttachment(
            cid: 'pixel',
            mediaType: 'image/png',
            bytes: onePixelPng(),
          ),
        ],
      ),
    );
    final guard = RuntimeNetworkGuard();
    await guard.run(() async {
      await tester.pumpWidget(_app(MailMessageView(controller: controller)));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsOneWidget);
      expect(guard.attempts, 0);
      expect(tester.takeException(), isNull);
    });
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
