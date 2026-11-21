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
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_saved_mail.dart';
import 'package:quds_office_studio/studio_strings.dart';

final class _EmptyAccounts extends Fake
    implements StudioMailCredentialStore, StudioMailAccountCatalogStore {
  @override
  Future<StudioMailAccountCatalogResult> loadAccounts() async =>
      StudioMailAccountCatalogResult.success(
        StudioMailAccountCatalog(accounts: []),
      );
}

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

Future<void> _closeSavedMail(
  WidgetTester tester, {
  StudioStrings strings = const StudioStrings(StudioLanguage.en),
}) async {
  final close = find.descendant(
    of: find.byType(StudioSavedMailView),
    matching: find.byTooltip(strings.close),
  );
  expect(close, findsOneWidget);
  await tester.tap(close);
}

Future<void> _openDialog(
  WidgetTester tester, {
  StudioStrings strings = const StudioStrings(StudioLanguage.en),
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => StudioMailDialog(
                strings: strings,
                credentialStore: _EmptyAccounts(),
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
  expect(find.byType(MailMessageView), findsNothing);
  await tester.tap(find.byTooltip(strings.savedMessages));
  await _pump(tester);
}

void _openInFileZone(
  WidgetTester tester,
  _DeferredFile file, {
  StudioStrings strings = const StudioStrings(StudioLanguage.en),
}) {
  IOOverrides.runWithIOOverrides(() {
    // Invoke the real callback in this zone: pointer dispatch itself uses the
    // test binding's zone, which would bypass the controlled file read.
    tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, strings.openMessage),
        )
        .onPressed!();
  }, _DeferredReadOverrides(file));
}

FilePickerResult _pickedPath(_DeferredFile file) => FilePickerResult([
  PlatformFile(name: 'Deferred.eml', size: 1, path: file.path),
]);

void main() {
  late _DeferredPicker picker;

  setUp(() {
    picker = _DeferredPicker();
    FilePicker.platform = picker;
  });

  tearDown(() => FilePicker.platform = FilePickerIO());

  testWidgets('embedded native saved Mail closes through its host callback', (
    tester,
  ) async {
    const strings = StudioStrings(StudioLanguage.en);
    var closes = 0;
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: StudioMailDialog(
          strings: strings,
          credentialStore: _EmptyAccounts(),
          onClose: () => closes++,
        ),
      ),
    );
    await _pump(tester);
    await tester.tap(find.byTooltip(strings.savedMessages));
    await _pump(tester);
    final reader = _reader(tester);
    await _closeSavedMail(tester, strings: strings);
    await _pump(tester);
    expect(closes, 1);
    expect(find.byType(StudioMailDialog), findsOneWidget);
    expect(reader.isDisposed, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester);
    expect(reader.isDisposed, isTrue);
  });

  testWidgets('saved and account Mail views each expose one localized Close', (
    tester,
  ) async {
    const strings = StudioStrings(StudioLanguage.de);
    await _openDialog(tester, strings: strings);
    final reader = _reader(tester);
    final close = find.byTooltip(strings.close);

    // Search the whole dialog: limiting the finder to the saved-message view
    // would miss a duplicate Close command in the surrounding Mail ribbon.
    expect(close, findsOneWidget);
    await tester.tap(find.byTooltip(strings.mailAccounts));
    await _pump(tester);
    expect(find.byType(MailMessageView), findsNothing);
    expect(close, findsOneWidget);

    await tester.tap(find.byTooltip(strings.savedMessages));
    await _pump(tester);
    expect(_reader(tester), same(reader));
    expect(close, findsOneWidget);
    await tester.tap(close);
    await _pump(tester);
    expect(find.byType(StudioMailDialog), findsNothing);
    expect(reader.isDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mail opens saved bytes and disposes replaced controllers', (
    tester,
  ) async {
    await _openDialog(tester);
    final initial = _reader(tester);
    expect(initial.mode, MailReaderMode.full);
    expect(initial.decodedText, contains('local, read-only message.'));
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

    await _closeSavedMail(tester);
    await _pump(tester);
    expect(opened.isDisposed, isTrue);
    expect(find.byType(StudioMailDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved EML keeps exact octets across modes and account navigation',
    (tester) async {
      await _openDialog(tester);
      final bytes = Uint8List.fromList(<int>[
        ...ascii.encode(
          'Subject: Exact source\r\n'
          'Content-Type: text/plain; charset=iso-8859-1\r\n'
          'Content-Transfer-Encoding: 8bit\r\n\r\n',
        ),
        0x43,
        0x61,
        0x66,
        0xe9,
        0x0d,
        0x0a,
      ]);
      final expected = Uint8List.fromList(bytes);
      await tester.tap(find.text('Open message'));
      picker.result.complete(
        FilePickerResult(<PlatformFile>[
          PlatformFile(name: 'Exact.eml', size: bytes.length, bytes: bytes),
        ]),
      );
      await _pump(tester);
      final full = _reader(tester);
      expect(full.result.original!.bytes, orderedEquals(expected));
      expect(full.decodedText, contains('Café'));
      bytes.fillRange(0, bytes.length, 0);
      expect(full.result.original!.bytes, orderedEquals(expected));

      await tester.tap(find.text('Compact'));
      await _pump(tester);
      final compact = _reader(tester);
      expect(full.isDisposed, isTrue);
      expect(compact.result.original!.bytes, orderedEquals(expected));
      await tester.tap(find.byTooltip('Mail accounts'));
      await _pump(tester);
      expect(find.byType(MailMessageView), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
      await tester.tap(find.byTooltip('Saved messages'));
      await _pump(tester);
      expect(_reader(tester), same(compact));
      expect(compact.result.original!.bytes, orderedEquals(expected));
      await _closeSavedMail(tester);
      await _pump(tester);
      expect(compact.isDisposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fromRead in [false, true]) {
    final phase = fromRead ? 'file read' : 'picker';
    testWidgets('$phase failure preserves the reader with localized feedback', (
      tester,
    ) async {
      const strings = StudioStrings(StudioLanguage.de);
      await _openDialog(tester, strings: strings);
      final initial = _reader(tester);
      if (fromRead) {
        final file = _DeferredFile();
        _openInFileZone(tester, file, strings: strings);
        picker.result.complete(_pickedPath(file));
        await _pump(tester);
        expect(file.reads, 1);
        file.result.completeError(
          const FileSystemException('private path must not be shown'),
        );
      } else {
        await tester.tap(find.text(strings.openMessage));
        picker.result.completeError(
          StateError('private path must not be shown'),
        );
      }
      await _pump(tester);
      expect(_reader(tester), same(initial));
      expect(initial.isDisposed, isFalse);
      expect(find.text(strings.openMessageFailed), findsOneWidget);
      expect(find.textContaining('private path'), findsNothing);
      expect(tester.takeException(), isNull);
      await _closeSavedMail(tester, strings: strings);
      await _pump(tester);
    });

    testWidgets('$phase failure after closing saved Mail is ignored', (
      tester,
    ) async {
      await _openDialog(tester);
      final initial = _reader(tester);
      final file = fromRead ? _DeferredFile() : null;
      if (file != null) {
        _openInFileZone(tester, file);
        picker.result.complete(_pickedPath(file));
        await _pump(tester);
        expect(file.reads, 1);
      } else {
        await tester.tap(find.text('Open message'));
      }
      await _closeSavedMail(tester);
      await _pump(tester);
      expect(initial.isDisposed, isTrue);
      if (file != null) {
        file.result.completeError(
          const FileSystemException('late private read'),
        );
      } else {
        picker.result.completeError(StateError('late private picker'));
      }
      await _pump(tester);
      expect(find.byType(StudioMailDialog), findsNothing);
      expect(find.textContaining('late private'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a delayed saved-message path read replaces the chosen mode', (
    tester,
  ) async {
    await _openDialog(tester);
    await tester.tap(find.text('Compact'));
    await _pump(tester);
    final initial = _reader(tester);
    final file = _DeferredFile();
    _openInFileZone(tester, file);
    picker.result.complete(_pickedPath(file));
    await _pump(tester);
    expect(file.reads, 1);
    expect(_reader(tester), same(initial));
    expect(initial.isDisposed, isFalse);
    file.result.complete(_message());
    await _pump(tester);
    expect(initial.isDisposed, isTrue);
    expect(_reader(tester).mode, MailReaderMode.preview);
    expect(_reader(tester).decodedText, contains('Saved message body.'));
    expect(find.text('CrispOffice Mail · Deferred.eml'), findsOneWidget);
    await _closeSavedMail(tester);
    await _pump(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late picker path after closing saved Mail is never read', (
    tester,
  ) async {
    await _openDialog(tester);
    final file = _DeferredFile();
    _openInFileZone(tester, file);
    await _closeSavedMail(tester);
    await _pump(tester);
    picker.result.complete(_pickedPath(file));
    await _pump(tester);
    expect(file.reads, 0);
    expect(find.byType(StudioMailDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved reader toolbar fits a narrow enlarged-text window', (
    tester,
  ) async {
    await _openDialog(tester);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester);
    expect(find.text('Open message'), findsOneWidget);
    expect(find.text('Compact'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _closeSavedMail(tester);
    await _pump(tester);
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
        await _closeSavedMail(tester);
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
    await _closeSavedMail(tester);
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
    _openInFileZone(tester, file);
    picker.result.complete(_pickedPath(file));
    await _pump(tester);
    expect(file.reads, 1);
    await _closeSavedMail(tester);
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
    await tester.pump();
    final word = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
    word.controller.proofing.enabled = false;
    word.controller.proofing.configure(OfficeProofingService(providers: []));
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
    await tester.tap(find.byTooltip('Tabellen'));
    await _pump(tester);
    final sheet = tester.widget<QudsSheetEditor>(find.byType(QudsSheetEditor));
    await tester.tap(find.byTooltip('E-Mail'));
    await _pump(tester);
    expect(find.byType(StudioMailDialog), findsOneWidget);
    await tester.tap(find.byTooltip('Gespeicherte Nachrichten'));
    await _pump(tester);
    expect(find.text('Nachricht öffnen'), findsOneWidget);
    expect(find.text('Vollständig'), findsOneWidget);
    expect(find.text('Kompakt'), findsOneWidget);
    // Page-route dismissal can start asynchronously. Bound the wait by its
    // configured transition while retaining the removal/controller assertions.
    final mailCloseDuration = ModalRoute.of(
      tester.element(find.byType(StudioMailDialog)),
    )!.reverseTransitionDuration;
    await tester.tap(find.byTooltip('Schließen').last);
    await tester.pump();
    for (
      var frame = 0;
      frame < 3 && find.byType(StudioMailDialog).evaluate().isNotEmpty;
      frame++
    ) {
      await tester.pump(mailCloseDuration);
    }
    await tester.pump();
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
    await tester.tap(find.byTooltip('اللغة'));
    await _pump(tester);
    expectModules(<String>[
      'Documents',
      'Spreadsheets',
      'Presentations',
      'PDF',
      'Mail',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
