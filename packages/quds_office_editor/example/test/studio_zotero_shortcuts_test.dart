import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_zotero.dart';
import 'package:quds_office_studio/suite_workspace.dart';

final class _Transport extends StudioZoteroTransport {
  _Transport(this.handle, this.onDispose);

  final ZoteroTransport handle;
  final VoidCallback onDispose;

  @override
  bool get supportsLocal => true;

  @override
  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) => handle(request);

  @override
  void dispose() {
    onDispose();
    super.dispose();
  }
}

final class _Desktop {
  _Desktop({this.inspectCurrentField = false});

  final bool inspectCurrentField;
  final commands = <String>[];
  final requests = <String>[];
  int connections = 0;
  int disposals = 0;
  String _documentId = '';
  String? currentFieldId;
  String? currentFieldText;
  Completer<void>? firstResponse;

  StudioZoteroTransport connect() {
    connections++;
    return _Transport(_send, () => disposals++);
  }

  Future<ZoteroHttpResponse> _send(ZoteroHttpRequest request) async {
    requests.add(request.uri.path);
    expect(request.method, 'POST');
    expect(request.uri.host, 'localhost');
    expect(request.uri.port, 23119);
    expect(request.headers['Zotero-API-Key'], isNull);
    final Object? message;
    if (request.uri.path.endsWith('/execCommand')) {
      final start = jsonDecode(request.body!) as Map<String, dynamic>;
      commands.add(start['command'] as String);
      _documentId = start['docId'] as String;
      await firstResponse?.future;
      message = {
        'command': 'Application.getActiveDocument',
        'arguments': <Object?>[],
      };
    } else {
      expect(request.uri.path, '/connector/document/respond');
      if (inspectCurrentField && requests.length == 2) {
        message = {
          'command': 'Document.cursorInField',
          'arguments': [_documentId, 'Http'],
        };
      } else if (inspectCurrentField && requests.length == 3) {
        final field = jsonDecode(request.body!);
        currentFieldId = field is Map ? field['id'] as String? : null;
        currentFieldText = field is Map ? field['text'] as String? : null;
        message = {
          'command': 'Document.complete',
          'arguments': [_documentId],
        };
      } else {
        message = {
          'command': 'Document.complete',
          'arguments': [_documentId],
        };
      }
    }
    return ZoteroHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(message),
    );
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<WordEditorController> _studio(
  WidgetTester tester,
  _Desktop desktop,
) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    if (desktop.firstResponse case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Liberation Sans'),
      home: SuiteWorkspace(zoteroTransportFactory: desktop.connect),
    ),
  );
  await tester.pump();
  final editor = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
  final controller = editor.controller;
  controller.proofing.enabled = false;
  controller.proofing.configure(OfficeProofingService(providers: []));
  controller.document = WmlDocument.empty(text: 'A citation belongs here.');
  controller.refresh();
  expect(find.byTooltip('Language'), findsOneWidget);
  await _frames(tester);
  editor.focusNode!.requestFocus();
  await _frames(tester);
  return controller;
}

Finder _command(String label, {bool skipOffstage = true}) =>
    find.byWidgetPredicate(
      (widget) => widget is StudioCmd && widget.label == label,
      skipOffstage: skipOffstage,
    );

Future<void> _tapCommand(WidgetTester tester, String label) async {
  final finder = _command(label);
  final ribbon = find.descendant(
    of: find.byType(StudioRibbonStrip),
    matching: find.byType(Scrollable),
  );
  if (finder.evaluate().isEmpty) {
    tester.state<ScrollableState>(ribbon).position.jumpTo(0);
    await tester.pump();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 240, scrollable: ribbon);
    }
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _frames(tester);
}

Future<void> _shortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
}) async {
  final modifier = meta
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  try {
    await tester.sendKeyEvent(key);
  } finally {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(modifier);
  }
  await _frames(tester);
}

VoidCallback _binding(WidgetTester tester, LogicalKeyboardKey key) {
  final activator = key == LogicalKeyboardKey.keyC
      ? const SingleActivator(LogicalKeyboardKey.keyC, control: true, alt: true)
      : const SingleActivator(
          LogicalKeyboardKey.keyR,
          control: true,
          alt: true,
        );
  final workspace = find.descendant(
    of: find.byType(SuiteWorkspace),
    matching: find.byType(CallbackShortcuts),
  );
  return tester.widget<CallbackShortcuts>(workspace.first).bindings[activator]!;
}

Future<void> _finishCommand(WidgetTester tester, _Desktop desktop) async {
  for (
    var tick = 0;
    tick < 60 && desktop.disposals < desktop.connections;
    tick++
  ) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await _frames(tester);
  expect(desktop.disposals, desktop.connections);
  expect(find.byType(Dialog), findsNothing);
}

void main() {
  for (final meta in [false, true]) {
    for (final action in [
      (key: LogicalKeyboardKey.keyC, command: 'addEditCitation'),
      (key: LogicalKeyboardKey.keyR, command: 'refresh'),
    ]) {
      testWidgets(
        '${meta ? 'Cmd' : 'Ctrl'} Alt ${action.key.keyLabel} dispatches ${action.command} from the Word caret',
        (tester) async {
          final desktop = _Desktop();
          final controller = await _studio(tester, desktop);
          final document = controller.document;
          final clipboardCalls = <MethodCall>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.getData' ||
                  call.method == 'Clipboard.setData') {
                clipboardCalls.add(call);
              }
              if (call.method == 'Clipboard.hasStrings') {
                return {'value': false};
              }
              return null;
            },
          );
          addTearDown(() {
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            );
          });
          await _shortcut(tester, action.key, meta: meta);
          expect(desktop.commands, [action.command]);
          expect(desktop.connections, 1);
          await _finishCommand(tester, desktop);
          expect(controller.document, same(document));
          expect(controller.canUndo, isFalse);
          expect(clipboardCalls, isEmpty);
          expect(
            tester
                .widget<QudsWordEditor>(find.byType(QudsWordEditor))
                .focusNode!
                .hasPrimaryFocus,
            isTrue,
          );
          expect(desktop.disposals, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('body composition blocks shortcuts and saved ribbon callbacks', (
    tester,
  ) async {
    final desktop = _Desktop();
    final controller = await _studio(tester, desktop);
    await tester.tap(find.text('Insert').first);
    await _frames(tester);
    final ribbon = tester
        .widget<StudioCmd>(_command('Add/Edit citation'))
        .onPressed!;
    final editor = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
    editor.focusNode!.requestFocus();
    await _frames(tester);
    const composition = TextRange(start: 0, end: 1);
    controller.input.setValue(
      TextEditingValue(
        text: controller.document.paragraphs.single.text,
        selection: const TextSelection.collapsed(offset: 1),
        composing: composition,
      ),
    );
    await _shortcut(tester, LogicalKeyboardKey.keyC);
    await _shortcut(tester, LogicalKeyboardKey.keyR);
    ribbon();
    await _frames(tester);
    expect(desktop.connections, 0);
    expect(desktop.requests, isEmpty);
    expect(find.byType(Dialog), findsNothing);
    expect(controller.input.composing, composition);
    expect(editor.focusNode!.hasPrimaryFocus, isTrue);
    expect(controller.canUndo, isFalse);
  });

  testWidgets('successive shortcuts return directly to the writing caret', (
    tester,
  ) async {
    final desktop = _Desktop();
    final controller = await _studio(tester, desktop);
    controller.caret.logicalIndex = 3;
    controller.caret.collapseSelection();
    for (final key in [LogicalKeyboardKey.keyC, LogicalKeyboardKey.keyR]) {
      await _shortcut(tester, key);
      await _finishCommand(tester, desktop);
      expect(controller.caret.logicalIndex, 3);
      expect(
        tester
            .widget<QudsWordEditor>(find.byType(QudsWordEditor))
            .focusNode!
            .hasPrimaryFocus,
        isTrue,
      );
    }
    expect(desktop.commands, ['addEditCitation', 'refresh']);
    expect(desktop.connections, 2);
    expect(desktop.disposals, 2);
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final action in [
    (label: 'Add Zotero note', command: 'addNote'),
    (label: 'Add Zotero annotation', command: 'addAnnotation'),
  ]) {
    testWidgets('${action.label} ribbon invokes its native picker', (
      tester,
    ) async {
      final desktop = _Desktop();
      final controller = await _studio(tester, desktop);
      await tester.tap(find.text('Insert').first);
      await _frames(tester);
      await _tapCommand(tester, action.label);
      await _finishCommand(tester, desktop);
      expect(desktop.commands, [action.command]);
      expect(controller.canUndo, isFalse);
      expect(
        controller.document.paragraphs.single.text,
        'A citation belongs here.',
      );
      expect(
        tester
            .widget<QudsWordEditor>(find.byType(QudsWordEditor))
            .focusNode!
            .hasPrimaryFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Ctrl Alt C finds the citation in the focused Notes editor', (
    tester,
  ) async {
    final desktop = _Desktop(inspectCurrentField: true);
    final controller = await _studio(tester, desktop);
    final note = WordNotes.insert(
      controller.document,
      controller.document.paragraphs.single,
      endnote: false,
      text: 'Before ',
    );
    WordZotero.insertCitation(
      note.paragraphs.single,
      ZoteroCitation(
        citationId: 'note-source',
        plainCitation: '(Old)',
        items: [
          ZoteroCitationItem.fromCsl(
            itemData: {'id': 'source', 'type': 'book', 'title': 'Notes source'},
            uris: ['http://zotero.org/users/42/items/ABCD1234'],
          ),
        ],
      ),
    );
    controller.refresh();
    final body = controller.document.paragraphs.single.text;
    await _frames(tester);
    final noteEditor = find.byKey(ValueKey<String>('notes-edit-${note.id}'));
    await tester.ensureVisible(noteEditor);
    final field = tester.widget<TextField>(noteEditor);
    field.focusNode!.requestFocus();
    field.controller!.selection = TextSelection.collapsed(
      offset: field.controller!.text.indexOf('(Old)') + 2,
    );
    await _frames(tester);
    expect(field.focusNode!.hasPrimaryFocus, isTrue);
    expect(controller.noteEditingTarget?.note, same(note));
    await _shortcut(tester, LogicalKeyboardKey.keyC);
    expect(desktop.commands, ['addEditCitation']);
    await _finishCommand(tester, desktop);
    expect(desktop.currentFieldId, isNotEmpty);
    expect(desktop.currentFieldText, '(Old)');
    expect(controller.document.paragraphs.single.text, body);
    expect(controller.zoteroFields.single.cachedText, '(Old)');
    expect(controller.canUndo, isFalse);
    expect(field.focusNode!.hasPrimaryFocus, isTrue);
    expect(desktop.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'citation shortcuts and saved ribbon callbacks respect viewing mode',
    (tester) async {
      final desktop = _Desktop();
      final controller = await _studio(tester, desktop);
      await tester.tap(find.text('Insert').first);
      await _frames(tester);
      final addCitation = tester
          .widget<StudioCmd>(_command('Add/Edit citation'))
          .onPressed!;
      final refresh = _binding(tester, LogicalKeyboardKey.keyR);
      await tester.tap(find.text('File').first);
      await _frames(tester);
      await _tapCommand(tester, 'View');
      expect(controller.config.allowsMutation, isFalse);
      final editor = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
      editor.focusNode!.requestFocus();
      await _frames(tester);
      await _shortcut(tester, LogicalKeyboardKey.keyC);
      await _shortcut(tester, LogicalKeyboardKey.keyR, meta: true);
      addCitation();
      refresh();
      await _frames(tester);
      expect(desktop.connections, 0);
      expect(find.byType(Dialog), findsNothing);
      expect(controller.canUndo, isFalse);
      await tester.tap(find.text('Insert').first);
      await _frames(tester);
      expect(tester.widget<StudioCmd>(_command('Zotero')).onPressed, isNotNull);
      expect(
        tester.widget<StudioCmd>(_command('Add/Edit citation')).onPressed,
        isNull,
      );
      await _tapCommand(tester, 'Zotero');
      expect(find.text('Zotero references'), findsOneWidget);
      expect(
        find.text(
          'This document is read-only. You can browse and export reference data.',
        ),
        findsOneWidget,
      );
      expect(desktop.commands, isEmpty);
      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await _frames(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('citation commands stay inactive in other Studio applications', (
    tester,
  ) async {
    final desktop = _Desktop();
    final controller = await _studio(tester, desktop);
    final citation = _binding(tester, LogicalKeyboardKey.keyC);
    final refresh = _binding(tester, LogicalKeyboardKey.keyR);
    for (final app in ['Spreadsheets', 'Presentations', 'PDF']) {
      await tester.tap(find.text(app).first);
      await _frames(tester);
      await _shortcut(tester, LogicalKeyboardKey.keyR);
      citation();
      refresh();
      await _frames(tester);
      expect(desktop.connections, 0, reason: app);
      expect(find.byType(Dialog), findsNothing, reason: app);
    }
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a covering modal blocks Zotero even when Word retains focus', (
    tester,
  ) async {
    final desktop = _Desktop();
    final controller = await _studio(tester, desktop);
    final citation = _binding(tester, LogicalKeyboardKey.keyC);
    final refresh = _binding(tester, LogicalKeyboardKey.keyR);
    final editor = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
    final context = tester.element(find.byType(SuiteWorkspace));
    unawaited(
      showDialog<void>(
        context: context,
        requestFocus: false,
        builder: (_) => const AlertDialog(title: Text('Another task')),
      ),
    );
    await _frames(tester);
    expect(editor.focusNode!.hasPrimaryFocus, isTrue);
    await _shortcut(tester, LogicalKeyboardKey.keyC);
    await _shortcut(tester, LogicalKeyboardKey.keyR);
    citation();
    refresh();
    await _frames(tester);
    expect(desktop.connections, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Another task'), findsOneWidget);
    expect(controller.canUndo, isFalse);
    Navigator.of(context).pop();
    await _frames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rapid ribbon and shortcut activation opens one Zotero workspace',
    (tester) async {
      final desktop = _Desktop()..firstResponse = Completer<void>();
      await _studio(tester, desktop);
      await tester.tap(find.text('Insert').first);
      await _frames(tester);
      final button = tester
          .widget<StudioCmd>(_command('Add/Edit citation'))
          .onPressed!;
      final refresh = _binding(tester, LogicalKeyboardKey.keyR);
      button();
      button();
      refresh();
      await _frames(tester);
      expect(desktop.connections, 1);
      expect(desktop.commands, ['addEditCitation']);
      expect(find.byType(Dialog), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyR);
      button();
      refresh();
      await _frames(tester);
      expect(desktop.connections, 1);
      expect(desktop.commands, ['addEditCitation']);
      desktop.firstResponse!.complete();
      await _frames(tester);
      await _finishCommand(tester, desktop);
      expect(desktop.disposals, 1);
      refresh();
      await _frames(tester);
      expect(desktop.connections, 2);
      expect(desktop.commands, ['addEditCitation', 'refresh']);
      await _finishCommand(tester, desktop);
      expect(desktop.disposals, 2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [TargetPlatform.linux, TargetPlatform.macOS]) {
    testWidgets('citation ribbon shows shortcuts for ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _studio(tester, _Desktop());
        await tester.tap(find.text('Insert').first);
        await _frames(tester);
        final modifier = platform == TargetPlatform.macOS ? 'Cmd' : 'Ctrl';
        expect(
          find.byTooltip('Add/Edit citation ($modifier+Alt+C)'),
          findsOneWidget,
        );
        expect(
          find.byTooltip('Refresh citations ($modifier+Alt+R)'),
          findsOneWidget,
        );
        expect(_command('Add/Edit citation'), findsOneWidget);
        expect(_command('Refresh citations'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
