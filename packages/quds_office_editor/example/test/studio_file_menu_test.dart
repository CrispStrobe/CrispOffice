import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_about.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_desktop_menu.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/studio_recent_files.dart';
import 'package:quds_office_studio/studio_settings.dart';
import 'package:quds_office_studio/studio_window.dart';
import 'package:quds_office_studio/suite_workspace.dart';

class _Picker extends FilePicker {
  int saves = 0;
  int opens = 0;
  FilePickerResult? picked;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saves++;
    return null;
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    opens++;
    return picked;
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<WordEditorController> _studio(
  WidgetTester tester, {
  StudioRecentFiles? recentFiles,
}) async {
  final preferences = StudioRibbonPreferences(persist: false);
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    preferences.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: SuiteWorkspace(
        ribbonPreferences: preferences,
        recentFiles: recentFiles,
      ),
    ),
  );
  await _frames(tester);
  final controller = tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller;
  controller.proofing.enabled = false;
  controller.proofing.configure(OfficeProofingService(providers: []));
  controller.document = WmlDocument.empty(text: 'Keep my document');
  controller.refresh();
  await _frames(tester);
  return controller;
}

Future<void> _fileAction(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(const ValueKey('desktop-file-menu')));
  await _frames(tester);
  await tester.tap(find.byKey(ValueKey('desktop-file-$id')));
  await _frames(tester);
}

void main() {
  tearDown(() {
    FilePicker.platform = FilePickerIO();
    StudioWindow.supported = false;
    StudioWindow.fullscreen = false;
  });

  test('recent files persist in order and de-duplicate opened paths', () async {
    final backend = MemoryStudioSettingsBackend();
    final history = StudioRecentFiles(backend);
    await Future.wait([
      history.remember('/Example/first.xlsx', 'first.xlsx'),
      history.remember('/Example/second.pdf', 'second.pdf'),
      history.remember('/Example/first.xlsx', 'first.xlsx'),
    ]);
    final reloaded = StudioRecentFiles(backend);
    expect((await reloaded.read()).map((file) => file.name), [
      'first.xlsx',
      'second.pdf',
    ]);
    await reloaded.clear();
    expect(await history.read(), isEmpty);
  });

  testWidgets('recent files persist and release macOS bookmark access', (
    tester,
  ) async {
    final channel = StudioRecentFiles.channel;
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'bookmark' => 'saved-bookmark',
        'begin' => {'path': '/Example/moved.xlsx', 'token': 'scope-token'},
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final backend = MemoryStudioSettingsBackend();
    final history = StudioRecentFiles(backend);
    await history.remember('/Example/original.xlsx', 'original.xlsx');
    final reopened = StudioRecentFiles(backend);
    final access = await reopened.begin((await reopened.read()).single);
    expect(access.path, '/Example/moved.xlsx');
    await access.close();
    expect(calls.map((call) => (call.method, call.arguments)), [
      ('bookmark', '/Example/original.xlsx'),
      ('begin', 'saved-bookmark'),
      ('end', 'scope-token'),
    ]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Open and Recent reopen a legacy workbook as an XLSX copy', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('crisp-recent-xls');
    addTearDown(() => dir.deleteSync(recursive: true));
    final legacy = File('${dir.path}/legacy.xls');
    final bytes = Uint8List.fromList(
      utf8.encode(
        '<html><table><tr><td>Legacy example</td><td>42</td></tr></table></html>',
      ),
    );
    legacy.writeAsBytesSync(bytes);
    final picker = _Picker()
      ..picked = FilePickerResult([
        PlatformFile(name: 'legacy.xls', path: legacy.path, size: bytes.length),
      ]);
    FilePicker.platform = picker;
    final recent = StudioRecentFiles(MemoryStudioSettingsBackend());
    await _studio(tester, recentFiles: recent);

    SheetEditorController? sheet() {
      final finder = find.byType(QudsSheetEditor);
      if (finder.evaluate().isEmpty) return null;
      return tester.widget<QudsSheetEditor>(finder).controller;
    }

    Future<void> waitForLegacy() async {
      for (
        var i = 0;
        i < 160 && sheet()?.sheet.cellA1('A1').asString != 'Legacy example';
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 24));
      }
      expect(sheet()?.sheet.cellA1('A1').asString, 'Legacy example');
      await _frames(tester);
    }

    await _fileAction(tester, 'open');
    await waitForLegacy();
    expect((await recent.read()).single.path, legacy.path);
    expect(find.textContaining('legacy.xlsx'), findsWidgets);
    await _fileAction(tester, 'save');
    expect(picker.saves, 1);
    expect(legacy.readAsBytesSync(), bytes);

    await _fileAction(tester, 'new');
    expect(sheet()?.sheet.cellA1('A1').asString, isNot('Legacy example'));
    await _fileAction(tester, 'recent-files');
    await tester.tap(find.widgetWithText(ListTile, 'legacy.xls'));
    await _frames(tester);
    await waitForLegacy();
    expect(picker.opens, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Save As cancellation keeps the document, dirty state and undo', (
    tester,
  ) async {
    final picker = _Picker();
    FilePicker.platform = picker;
    final word = await _studio(tester);
    word.insertText('Unsaved ');
    await _frames(tester);
    final document = word.document;
    final revision = word.contentRevision;
    await _fileAction(tester, 'save-as');
    expect(picker.saves, 1);
    expect(identical(word.document, document), isTrue);
    expect(word.contentRevision, revision);
    expect(word.isDirty, isTrue);
    expect(word.canUndo, isTrue);
    expect(
      find.textContaining('CrispOffice product brief.docx*'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'New confirms dirty work and clears the previous history only after discard',
    (tester) async {
      final word = await _studio(tester);
      word.insertText('Unsaved ');
      await _frames(tester);
      final previous = word.document;
      await _fileAction(tester, 'new');
      expect(find.text('Save changes?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _frames(tester);
      expect(identical(word.document, previous), isTrue);
      expect(word.isDirty, isTrue);
      await _fileAction(tester, 'new');
      await tester.tap(find.widgetWithText(TextButton, 'Don’t Save'));
      await _frames(tester);
      expect(identical(word.document, previous), isFalse);
      expect(word.isDirty, isFalse);
      expect(word.canUndo, isFalse);
      expect(find.text('Document1.docx'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'Open confirms the destination spreadsheet and cancellation keeps its draft',
    (tester) async {
      final picker = _Picker()
        ..picked = FilePickerResult(<PlatformFile>[
          PlatformFile(
            name: 'replacement.xlsx',
            size: 1,
            bytes: Uint8List.fromList(<int>[0]),
          ),
        ]);
      FilePicker.platform = picker;
      final word = await _studio(tester);
      final document = word.document;
      await tester.tap(find.byTooltip('Spreadsheets'));
      await _frames(tester);
      final sheet = tester
          .widget<QudsSheetEditor>(find.byType(QudsSheetEditor))
          .controller;
      sheet.beginCellEdit(initial: 'Unsaved cell', replace: true);
      await _frames(tester);
      expect(sheet.isDirty, isTrue);
      await tester.tap(find.byTooltip('Documents'));
      await _frames(tester);
      await _fileAction(tester, 'open');
      expect(picker.opens, 1);
      expect(
        find.text('Save changes to "Budget.xlsx" before closing it?'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _frames(tester);
      expect(identical(word.document, document), isTrue);
      expect(sheet.isDirty, isTrue);
      expect(sheet.cellEditor.formulaBar, 'Unsaved cell');
      expect(find.byType(QudsWordEditor), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'macOS opens native dialogs safely and disables modal File actions',
    (tester) async {
      StudioWindow.supported = true;
      final messenger = tester.binding.defaultBinaryMessenger;
      const windowChannel = MethodChannel('window_manager');
      final shown = Completer<void>();
      final windowCalls = <String>[];
      messenger.setMockMethodCallHandler(windowChannel, (call) async {
        windowCalls.add(call.method);
        if (call.method == 'isMinimized') {
          return false;
        }
        if (call.method == 'show') {
          await shown.future;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
        SystemChannels.menu,
        (call) async => null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(windowChannel, null);
        messenger.setMockMethodCallHandler(SystemChannels.menu, null);
      });
      final picker = _Picker();
      FilePicker.platform = picker;
      await _studio(tester);
      expect(
        find.byKey(const ValueKey('native-traffic-light-space')),
        findsOneWidget,
      );
      expect(find.byType(StudioCaptionButton), findsNothing);
      expect(find.byType(StudioFileMenu), findsNothing);
      expect(find.byType(PlatformMenuBar), findsOneWidget);
      final before = tester.widget<StudioNativeMenus>(
        find.byType(StudioNativeMenus),
      );
      expect(
        before.fileGroups
            .expand((group) => group)
            .every((action) => action.onSelected != null),
        isTrue,
      );
      before.onSettings();
      await _frames(tester);
      expect(windowCalls.where((method) => method == 'show'), hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
      before.onAbout();
      expect(windowCalls.where((method) => method == 'show'), hasLength(1));
      shown.complete();
      await _frames(tester);
      expect(windowCalls.where((method) => method == 'focus'), hasLength(1));
      expect(find.byType(AlertDialog), findsOneWidget);
      final during = tester.widget<StudioNativeMenus>(
        find.byType(StudioNativeMenus),
      );
      expect(
        during.fileGroups
            .expand((group) => group)
            .every((action) => action.onSelected == null),
        isTrue,
      );
      // Stale native/shortcut callbacks must also check the current route.
      before.fileGroups.first
          .singleWhere((action) => action.id == 'open')
          .onSelected!();
      await _frames(tester);
      expect(picker.opens, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await _frames(tester);
      before.onAbout();
      await _frames(tester);
      expect(find.byType(StudioAboutDialog), findsOneWidget);
      expect(windowCalls.where((method) => method == 'show'), hasLength(2));
      expect(windowCalls.where((method) => method == 'focus'), hasLength(2));
      final close = find.byKey(const ValueKey('studio-about-close'));
      expect(close.hitTestable(), findsOneWidget);
      await tester.tap(close);
      await _frames(tester);
      expect(find.byType(StudioAboutDialog), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
