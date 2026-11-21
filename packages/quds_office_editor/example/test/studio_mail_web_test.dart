import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_web.dart' as browser;
import 'package:quds_office_studio/studio_strings.dart';

final class _Picker extends FilePicker {
  final result = Completer<FilePickerResult?>();

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
    expect(type, FileType.custom);
    expect(allowedExtensions, <String>['eml']);
    expect(withData, isTrue);
    expect(allowMultiple, isFalse);
    return result.future;
  }
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

void main() {
  testWidgets('embedded browser Mail closes through its workspace callback', (
    tester,
  ) async {
    const strings = StudioStrings(StudioLanguage.en);
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: browser.StudioMailDialog(
          strings: strings,
          onClose: () => closed++,
        ),
      ),
    );
    await _pump(tester);
    await tester.tap(find.byTooltip(strings.close));
    await _pump(tester);
    expect(closed, 1);
    expect(find.byType(MailMessageView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester);
  });

  testWidgets(
    'browser Mail explains account availability and opens saved bytes',
    (tester) async {
      const strings = StudioStrings(StudioLanguage.en);
      final picker = _Picker();
      FilePicker.platform = picker;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(home: browser.StudioMailDialog(strings: strings)),
      );
      await _pump(tester);
      expect(find.text(strings.mailAccountsUnavailable), findsOneWidget);
      expect(find.widgetWithText(FilledButton, strings.connect), findsNothing);
      final original = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      final bytes = Uint8List.fromList(
        ascii.encode(
          'Subject: Browser saved message\r\n\r\nExact local bytes.\r\n',
        ),
      );
      await tester.tap(find.text(strings.openMessage));
      picker.result.complete(
        FilePickerResult(<PlatformFile>[
          PlatformFile(name: 'Browser.eml', size: bytes.length, bytes: bytes),
        ]),
      );
      await _pump(tester);
      final opened = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      expect(original.isDisposed, isTrue);
      expect(opened.result.original!.bytes, orderedEquals(bytes));
      expect(opened.decodedText, contains('Exact local bytes.'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester);
      expect(opened.isDisposed, isTrue);
    },
  );
}
