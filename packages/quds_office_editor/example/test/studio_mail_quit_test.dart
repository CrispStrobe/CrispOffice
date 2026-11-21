import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/studio_strings.dart';
import 'package:quds_office_studio/studio_window.dart';
import 'package:quds_office_studio/suite_workspace.dart';

const _strings = StudioStrings(StudioLanguage.en);

void main() {
  tearDown(() {
    StudioWindow.supported = false;
    StudioWindow.fullscreen = false;
    StudioWindow.maximized = false;
  });

  testWidgets(
    'native Quit flushes edits before autosave and disposes Mail after saving',
    (tester) async {
      final owner = _DraftOwner();
      await _openMail(tester, owner);
      await _compose(tester);
      await _edit(tester, 'Unfinished subject', 'Last instant edit مرحبا');
      expect(owner.saved, isEmpty);

      final quit = _nativeQuit(tester);
      await _finishRoutes(tester);

      expect(await quit, isTrue);
      expect(owner.saved, hasLength(1));
      expect(owner.saved.single.subject, 'Unfinished subject');
      expect(owner.saved.single.body, 'Last instant edit مرحبا');
      expect(owner.events, [
        'save started',
        'save completed',
        'owner disposed',
      ]);
      expect(find.byType(StudioMailComposeDialog), findsNothing);
      expect(find.byType(_MailPage), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(owner.saved, hasLength(1));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'pending draft save and repeated native Quit keep the account alive',
    (tester) async {
      final gate = Completer<void>();
      final owner = _DraftOwner()..gate = gate;
      await _openMail(tester, owner);
      await _compose(tester);
      await _edit(tester, 'Pending draft', 'Do not close its account yet');

      final firstQuit = _nativeQuit(tester);
      final repeatedQuit = _nativeQuit(tester);
      await tester.pump();
      await tester.pump();
      expect(await firstQuit, isFalse);
      expect(await repeatedQuit, isFalse);
      expect(owner.events, ['save started']);
      expect(owner.saved, isEmpty);
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      expect(find.byType(_MailPage), findsOneWidget);

      final stillSaving = _nativeQuit(tester);
      await tester.pump();
      await tester.pump();
      expect(await stillSaving, isFalse);
      expect(owner.events, ['save started']);

      gate.complete();
      await _finishRoutes(tester);
      expect(owner.saved.single.body, 'Do not close its account yet');
      expect(find.byType(StudioMailComposeDialog), findsNothing);
      expect(owner.disposed, isFalse);

      final completedQuit = _nativeQuit(tester);
      await _finishRoutes(tester);
      expect(await completedQuit, isTrue);
      expect(owner.events, [
        'save started',
        'save completed',
        'owner disposed',
      ]);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('failed draft save blocks native Quit and remains retryable', (
    tester,
  ) async {
    final owner = _DraftOwner()..fail = true;
    await _openMail(tester, owner);
    await _compose(tester);
    await _edit(tester, 'Keep this draft', 'The store is temporarily full');

    final failedQuit = _nativeQuit(tester);
    await tester.pump();
    await tester.pump();
    expect(await failedQuit, isFalse);
    expect(owner.saved, isEmpty);
    expect(owner.disposed, isFalse);
    expect(find.byType(StudioMailComposeDialog), findsOneWidget);
    expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);

    owner.fail = false;
    final retryQuit = _nativeQuit(tester);
    await _finishRoutes(tester);
    expect(await retryQuit, isTrue);
    expect(owner.saved.single.body, 'The store is temporarily full');
    expect(owner.events, [
      'save started',
      'save failed',
      'save started',
      'save completed',
      'owner disposed',
    ]);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'native Quit drains an ordinary dialog and Mail before approving close',
    (tester) async {
      final owner = _DraftOwner();
      await _openMail(tester, owner);
      await tester.tap(find.text('Open ordinary dialog'));
      await _finishRoutes(tester);
      expect(find.text('Ordinary dialog'), findsOneWidget);

      final quit = _nativeQuit(tester);
      await _finishRoutes(tester);
      expect(await quit, isTrue);
      expect(find.text('Ordinary dialog'), findsNothing);
      expect(find.byType(_MailPage), findsNothing);
      expect(owner.events, ['owner disposed']);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

final class _DraftOwner {
  final saved = <StudioMailDraft>[];
  final events = <String>[];
  Completer<void>? gate;
  bool fail = false;
  bool disposed = false;

  Future<void> save(StudioMailDraft draft) async {
    events.add('save started');
    if (disposed) throw StateError('Draft owner is already closed');
    await gate?.future;
    if (disposed) throw StateError('Draft owner closed during a write');
    if (fail) {
      events.add('save failed');
      throw StateError('Draft store unavailable');
    }
    saved.add(draft);
    events.add('save completed');
  }

  void dispose() {
    disposed = true;
    events.add('owner disposed');
  }
}

class _MailPage extends StatefulWidget {
  const _MailPage({required this.owner, required this.chrome});

  final _DraftOwner owner;
  final WidgetBuilder chrome;

  @override
  State<_MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<_MailPage> {
  @override
  void dispose() {
    widget.owner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        widget.chrome(context),
        TextButton(
          onPressed: () => showDialog<StudioMailDraft>(
            context: context,
            barrierDismissible: false,
            builder: (_) => StudioMailComposeDialog(
              strings: _strings,
              from: 'writer@example.test',
              onSaveDraft: widget.owner.save,
            ),
          ),
          child: const Text('Compose fixture draft'),
        ),
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(title: Text('Ordinary dialog')),
          ),
          child: const Text('Open ordinary dialog'),
        ),
      ],
    ),
  );
}

Future<void> _openMail(WidgetTester tester, _DraftOwner owner) async {
  StudioWindow.supported = false;
  final preferences = StudioRibbonPreferences(persist: false);
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.menu, (_) async => null);
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    preferences.dispose();
    messenger.setMockMethodCallHandler(SystemChannels.menu, null);
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: SuiteWorkspace(
        initialWord: (name: 'Untouched.docx', document: WmlDocument.empty()),
        ribbonPreferences: preferences,
        mailBuilder: (_, chrome) => _MailPage(owner: owner, chrome: chrome),
      ),
    ),
  );
  await _finishRoutes(tester);
  final word = tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller;
  word.proofing.enabled = false;
  word.proofing.configure(OfficeProofingService(providers: []));
  await tester.tap(
    find.byWidgetPredicate(
      (widget) => widget is StudioAppSwitcher && widget.label == _strings.mail,
    ),
  );
  await _finishRoutes(tester);
  expect(find.byType(_MailPage), findsOneWidget);
}

Future<void> _compose(WidgetTester tester) async {
  await tester.tap(find.text('Compose fixture draft'));
  await _finishRoutes(tester);
  expect(find.byType(StudioMailComposeDialog), findsOneWidget);
}

Future<void> _edit(WidgetTester tester, String subject, String body) async {
  await tester.enterText(
    find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == _strings.subject,
    ),
    subject,
  );
  tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller
      .insertText(body);
  await tester.pump();
}

Future<bool> _nativeQuit(WidgetTester tester) async {
  const codec = StandardMethodCodec();
  final result = Completer<ByteData?>();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'crispoffice/window',
    codec.encodeMethodCall(const MethodCall('confirmQuit')),
    result.complete,
  );
  final response = await result.future;
  return response != null && codec.decodeEnvelope(response) == true;
}

Future<void> _finishRoutes(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }
}
