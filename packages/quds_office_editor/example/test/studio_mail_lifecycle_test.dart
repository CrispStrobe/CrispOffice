import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/studio_mail_fixture.dart';

void main() {
  // Network-reader lifecycle cases from #192 (d00bd397).
  for (final fail in [false, true]) {
    testWidgets(
      'closing Mail disposes its reader and ignores a pending message ${fail ? 'error' : 'success'}',
      (tester) async {
        final client = MailClientFixture();
        await openMail(tester, (_) => client);
        await connectMail(tester);
        await tester.tap(find.text('First message'));
        await pumpMail(tester);
        final reader = mailReader(tester);
        expect(reader.isDisposed, isFalse);
        expect(reader.decodedText, contains('Body of First message.'));

        final pending = Completer<mail.MimeMessage>();
        client.onContents = (_) => pending.future;
        await tester.tap(find.text('Second message'));
        await pumpMail(tester);
        expect(mailReader(tester), same(reader));
        expect(pending.isCompleted, isFalse);

        await closeMail(tester);
        expect(reader.isDisposed, isTrue);
        expect(client.disconnects, 1);
        if (fail) {
          pending.completeError(StateError('late contents failure'));
        } else {
          pending.complete(mailMessageFixture('Late message'));
        }
        await pumpMail(tester);
        expect(find.byType(StudioMailDialog), findsNothing);
        expect(find.byType(MailMessageView), findsNothing);
        expect(find.textContaining('late contents failure'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('closing Mail ignores a pending file picker result', (
    WidgetTester tester,
  ) async {
    final _DeferredFilePicker picker = _DeferredFilePicker();
    FilePicker.platform = picker;
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (BuildContext context) => const StudioMailDialog(
                  strings: StudioStrings(StudioLanguage.en),
                ),
              ),
              child: const Text('Show mail'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show mail'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Saved messages'));
    await tester.pumpAndSettle();
    final MailReaderController controller = tester
        .widget<MailMessageView>(find.byType(MailMessageView))
        .controller;
    await tester.tap(find.text('Open message'));
    await tester.pump();
    expect(picker.calls, 1);
    expect(picker.result.isCompleted, isFalse);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(StudioMailDialog), findsNothing);
    expect(controller.isDisposed, isTrue);

    final Uint8List message = Uint8List.fromList(
      utf8.encode('Subject: Late selection\r\n\r\nSaved message.\r\n'),
    );
    picker.result.complete(
      FilePickerResult(<PlatformFile>[
        PlatformFile(name: 'late.eml', size: message.length, bytes: message),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(StudioMailDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

final class _DeferredFilePicker extends FilePicker {
  final Completer<FilePickerResult?> result = Completer<FilePickerResult?>();
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
    return result.future;
  }
}
