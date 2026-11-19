import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_mail.dart';
import 'package:quds_office_studio/studio_strings.dart';

class _DeferredPicker extends FilePicker {
  late final result = Completer<FilePickerResult?>();
  int calls = 0;

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
  }) {
    calls++;
    expect(type, FileType.custom);
    expect(allowedExtensions, <String>['eml']);
    expect(allowMultiple, isFalse);
    expect(withData, isTrue);
    return result.future;
  }
}

class _DeferredFile extends Fake implements File {
  @override
  final String path = '/deferred-studio-message.eml';
  final result = Completer<Uint8List>();
  int reads = 0;

  @override
  Future<Uint8List> readAsBytes() {
    reads++;
    return result.future;
  }
}

final class _DeferredReadOverrides extends IOOverrides {
  _DeferredReadOverrides(this.file);

  final _DeferredFile file;

  @override
  File createFile(String path) =>
      path == file.path ? file : super.createFile(path);
}

Uint8List _message() => Uint8List.fromList(
  utf8.encode(
    'From: Writer <writer@example.invalid>\r\n'
    'To: Reader <reader@example.invalid>\r\n'
    'Subject: A saved message\r\n'
    'Content-Type: text/plain; charset=utf-8\r\n'
    '\r\n'
    'Saved message body.\r\n',
  ),
);

FilePickerResult _pickedMessage() {
  final bytes = _message();
  return FilePickerResult(<PlatformFile>[
    PlatformFile(name: 'Saved.eml', size: bytes.length, bytes: bytes),
  ]);
}

MailReaderController _reader(WidgetTester tester) =>
    tester.widget<MailMessageView>(find.byType(MailMessageView)).controller;

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const StudioMailDialog(
                strings: StudioStrings(StudioLanguage.en),
              ),
            ),
            child: const Text('Launch Mail'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Launch Mail'));
  await _pump(tester);
  expect(find.byType(StudioMailDialog), findsOneWidget);
}

void main() {
  late _DeferredPicker picker;

  setUp(() {
    picker = _DeferredPicker();
    FilePicker.platform = picker;
  });

  testWidgets('Mail opens saved bytes and disposes replaced controllers', (
    tester,
  ) async {
    await _openDialog(tester);
    final initial = _reader(tester);
    expect(initial.mode, MailReaderMode.full);
    await tester.tap(find.text('Compact'));
    await _pump(tester);
    final compact = _reader(tester);
    expect(compact.mode, MailReaderMode.preview);
    expect(initial.isDisposed, isTrue);

    await tester.tap(find.text('Open message'));
    expect(picker.calls, 1);
    picker.result.complete(_pickedMessage());
    await _pump(tester);
    final opened = _reader(tester);
    expect(opened.mode, MailReaderMode.preview);
    expect(opened.decodedText, contains('Saved message body.'));
    expect(compact.isDisposed, isTrue);
    expect(opened.isDisposed, isFalse);
    expect(find.text('CrispOffice Mail · Saved.eml'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await _pump(tester);
    expect(opened.isDisposed, isTrue);
    expect(find.byType(StudioMailDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final emptyResult in <bool>[false, true]) {
    testWidgets(
      emptyResult
          ? 'an empty picker result preserves the current Mail message'
          : 'cancelling the picker preserves the current Mail message',
      (tester) async {
        await _openDialog(tester);
        final initial = _reader(tester);
        await tester.tap(find.text('Open message'));
        expect(picker.calls, 1);
        picker.result.complete(
          emptyResult ? FilePickerResult(<PlatformFile>[]) : null,
        );
        await _pump(tester);
        expect(_reader(tester), same(initial));
        expect(initial.isDisposed, isFalse);
        expect(find.text('CrispOffice Mail · Welcome.eml'), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await _pump(tester);
        expect(initial.isDisposed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a picker result after closing Mail is discarded', (
    tester,
  ) async {
    await _openDialog(tester);
    final initial = _reader(tester);
    await tester.tap(find.text('Open message'));
    expect(picker.calls, 1);
    await tester.tap(find.byTooltip('Close'));
    await _pump(tester);
    expect(initial.isDisposed, isTrue);
    picker.result.complete(_pickedMessage());
    await _pump(tester);
    expect(find.byType(StudioMailDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a file read finishing after closing Mail is discarded', (
    tester,
  ) async {
    await _openDialog(tester);
    final initial = _reader(tester);
    final file = _DeferredFile();
    IOOverrides.runWithIOOverrides(() {
      // Invoke the actual button callback in the IO zone. Test pointer dispatch
      // runs in the binding's zone and would bypass this controlled file read.
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Open message'))
          .onPressed!();
    }, _DeferredReadOverrides(file));
    picker.result.complete(
      FilePickerResult(<PlatformFile>[
        PlatformFile(name: 'Deferred.eml', size: 1, path: file.path),
      ]),
    );
    await _pump(tester);
    expect(file.reads, 1);
    await tester.tap(find.byTooltip('Close'));
    await _pump(tester);
    expect(initial.isDisposed, isTrue);
    file.result.complete(_message());
    await _pump(tester);
    expect(find.byType(StudioMailDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Studio cycles languages and Mail preserves its active sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const QudsOfficeStudioApp());
    await _pump(tester);

    void expectModules(List<String> labels) {
      expect(
        tester
            .widgetList<StudioAppSwitcher>(find.byType(StudioAppSwitcher))
            .map((widget) => widget.label),
        labels,
      );
    }

    expectModules(<String>[
      'Documents',
      'Spreadsheets',
      'Presentations',
      'PDF',
      'Mail',
    ]);
    await tester.tap(find.byTooltip('Language'));
    await _pump(tester);
    expectModules(<String>[
      'Dokumente',
      'Tabellen',
      'Präsentationen',
      'PDF',
      'E-Mail',
    ]);
    await tester.tap(find.text('Tabellen'));
    await _pump(tester);
    final sheet = tester.widget<QudsSheetEditor>(find.byType(QudsSheetEditor));
    await tester.tap(find.text('E-Mail'));
    await _pump(tester);
    expect(find.byType(StudioMailDialog), findsOneWidget);
    expect(find.text('Nachricht öffnen'), findsOneWidget);
    expect(find.text('Vollständig'), findsOneWidget);
    expect(find.text('Kompakt'), findsOneWidget);
    await tester.tap(find.byTooltip('Schließen').last);
    await _pump(tester);
    expect(find.byType(StudioMailDialog), findsNothing);
    expect(
      tester.widget<QudsSheetEditor>(find.byType(QudsSheetEditor)).controller,
      same(sheet.controller),
    );
    await tester.tap(find.byTooltip('Sprache'));
    await _pump(tester);
    expectModules(<String>[
      'المستندات',
      'جداول البيانات',
      'العروض التقديمية',
      'PDF',
      'البريد',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
