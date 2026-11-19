// From #194 (4b8b9e2e). The union keeps #191's StudioSavedMailView as the
// single saved-message reader; these cases now drive it inside a dialog.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_saved_mail.dart';
import 'package:quds_office_studio/studio_strings.dart';

final class _Picker extends FilePicker {
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
    expect(allowedExtensions, ['eml']);
    expect(allowMultiple, isFalse);
    expect(withData, isTrue);
    return result.future;
  }
}

final class _PendingFile implements File {
  final result = Completer<Uint8List>();
  int reads = 0;

  @override
  String get path => '/studio-mail-controlled-message.eml';

  @override
  Future<Uint8List> readAsBytes() {
    reads++;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FileOverride extends IOOverrides {
  _FileOverride(this.file);

  final _PendingFile file;

  @override
  File createFile(String path) =>
      path == file.path ? file : super.createFile(path);
}

const _english = StudioStrings(StudioLanguage.en);
const _german = StudioStrings(StudioLanguage.de);
const _germanOpenFailure = 'Die Nachricht konnte nicht geöffnet werden.';

Uint8List _message() => Uint8List.fromList(
  utf8.encode(
    'From: sender@example.invalid\r\n'
    'To: reader@example.invalid\r\n'
    'Subject: Selected message\r\n'
    'MIME-Version: 1.0\r\n'
    'Content-Type: text/plain; charset=utf-8\r\n'
    '\r\n'
    'Selected body.\r\n',
  ),
);

FilePickerResult _selection({String? path, Uint8List? bytes}) =>
    FilePickerResult([
      PlatformFile(
        name: 'Selected.eml',
        size: bytes?.length ?? 0,
        bytes: bytes,
        path: path,
      ),
    ]);

MailReaderController _reader(WidgetTester tester) =>
    tester.widget<MailMessageView>(find.byType(MailMessageView)).controller;

Future<void> _show(
  WidgetTester tester, {
  StudioStrings strings = _english,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              unawaited(
                showDialog<void>(
                  context: context,
                  builder: (_) => Dialog.fullscreen(
                    child: StudioSavedMailView(strings: strings),
                  ),
                ),
              );
            },
            child: const Text('Launch Mail'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Launch Mail'));
  await tester.pumpAndSettle();
  expect(
    _reader(tester).result.message!.envelope.subject,
    'Welcome to CrispOffice Mail',
  );
}

Future<void> _open(
  WidgetTester tester,
  _Picker picker, {
  StudioStrings strings = _english,
}) async {
  await tester.tap(find.text(strings.openMessage));
  await tester.pump();
  expect(picker.calls, 1);
}

Future<void> _dismiss(
  WidgetTester tester, {
  StudioStrings strings = _english,
}) async {
  final controller = _reader(tester);
  await tester.tap(find.byTooltip(strings.close));
  await tester.pumpAndSettle();
  expect(find.byType(StudioSavedMailView), findsNothing);
  expect(controller.isDisposed, isTrue);
}

_PendingFile _deferRead() {
  final file = _PendingFile();
  final previous = IOOverrides.current;
  IOOverrides.global = _FileOverride(file);
  addTearDown(() => IOOverrides.global = previous);
  return file;
}

void main() {
  late _Picker picker;

  setUp(() {
    picker = _Picker();
    FilePicker.platform = picker;
  });

  tearDown(() {
    FilePicker.platform = FilePickerIO();
  });

  testWidgets('selected bytes replace the welcome message in the chosen mode', (
    tester,
  ) async {
    await _show(tester);
    final welcome = _reader(tester);
    await tester.tap(find.text(_english.compactView));
    await tester.pumpAndSettle();
    expect(welcome.isDisposed, isTrue);
    final preview = _reader(tester);
    expect(preview.mode, MailReaderMode.preview);
    await _open(tester, picker);
    picker.result.complete(_selection(bytes: _message()));
    await tester.pumpAndSettle();
    expect(preview.isDisposed, isTrue);
    expect(_reader(tester).mode, MailReaderMode.preview);
    expect(
      _reader(tester).result.message!.envelope.subject,
      'Selected message',
    );
    expect(find.text('CrispOffice Mail · Selected.eml'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('path fallback replaces the message after a delayed read', (
    tester,
  ) async {
    final file = _deferRead();
    await _show(tester);
    final welcome = _reader(tester);
    await _open(tester, picker);
    picker.result.complete(_selection(path: file.path));
    await tester.pump();
    expect(file.reads, 1);
    expect(_reader(tester), same(welcome));
    file.result.complete(_message());
    await tester.pumpAndSettle();
    expect(welcome.isDisposed, isTrue);
    expect(
      _reader(tester).result.message!.envelope.subject,
      'Selected message',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled selection leaves the current message intact', (
    tester,
  ) async {
    await _show(tester);
    final welcome = _reader(tester);
    await _open(tester, picker);
    picker.result.complete(null);
    await tester.pumpAndSettle();
    expect(_reader(tester), same(welcome));
    expect(welcome.isDisposed, isFalse);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissal ignores a later picker completion without reading', (
    tester,
  ) async {
    final file = _deferRead();
    await _show(tester);
    await _open(tester, picker);
    await _dismiss(tester);
    picker.result.complete(_selection(path: file.path));
    await tester.pumpAndSettle();
    expect(file.reads, 0);
    expect(find.byType(StudioSavedMailView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissal ignores a later file read completion', (tester) async {
    final file = _deferRead();
    await _show(tester);
    await _open(tester, picker);
    picker.result.complete(_selection(path: file.path));
    await tester.pump();
    expect(file.reads, 1);
    await _dismiss(tester);
    file.result.complete(_message());
    await tester.pumpAndSettle();
    expect(find.byType(StudioSavedMailView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final fromRead in [false, true]) {
    final phase = fromRead ? 'file read' : 'picker';
    testWidgets('$phase failure keeps the current message and shows feedback', (
      tester,
    ) async {
      final file = fromRead ? _deferRead() : null;
      await _show(tester, strings: _german);
      final welcome = _reader(tester);
      await _open(tester, picker, strings: _german);
      if (file == null) {
        picker.result.completeError(StateError('Controlled picker failure'));
      } else {
        picker.result.complete(_selection(path: file.path));
        await tester.pump();
        expect(file.reads, 1);
        file.result.completeError(const FileSystemException('Controlled read'));
      }
      await tester.pumpAndSettle();
      expect(_reader(tester), same(welcome));
      expect(welcome.isDisposed, isFalse);
      expect(
        find.descendant(
          of: find.byType(StudioSavedMailView),
          matching: find.text(_germanOpenFailure),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$phase failure after dismissal is safely ignored', (
      tester,
    ) async {
      final file = fromRead ? _deferRead() : null;
      await _show(tester);
      await _open(tester, picker);
      if (file != null) {
        picker.result.complete(_selection(path: file.path));
        await tester.pump();
        expect(file.reads, 1);
      }
      await _dismiss(tester);
      if (file == null) {
        picker.result.completeError(
          StateError('Controlled late picker failure'),
        );
      } else {
        file.result.completeError(
          const FileSystemException('Controlled late read'),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(StudioSavedMailView), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
