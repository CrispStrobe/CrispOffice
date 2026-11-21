import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_desktop_menu.dart';
import 'package:quds_office_studio/studio_files.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/studio_window.dart';
import 'package:quds_office_studio/suite_workspace.dart';

Uint8List _odt() {
  final name = encodeXmlAttribute(
    'ZOTERO_ITEM CSL_CITATION {"citationID":"studio-odt",'
    '"citationItems":[{"id":1}],"properties":{"plainCitation":"(Source)"}}'
    ' RND0123456789',
  );
  return (ZipWriter()
        ..addFile(
          'mimetype',
          utf8.encode('application/vnd.oasis.opendocument.text'),
          store: true,
        )
        ..addFile(
          'content.xml',
          utf8.encode(
            '<office:document-content '
            'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
            'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">'
            '<office:body><office:text><text:p>Research '
            '<text:reference-mark-start text:name="$name"/>(Source)'
            '<text:reference-mark-end text:name="$name"/>'
            '</text:p></office:text></office:body></office:document-content>',
          ),
        ))
      .close();
}

class _Picker extends FilePicker {
  FilePickerResult? picked;
  String? savePath;
  final saveNames = <String?>[];
  final saveExtensions = <List<String>?>[];
  List<String>? openExtensions;

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
    saveNames.add(fileName);
    saveExtensions.add(allowedExtensions);
    return savePath;
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
    openExtensions = allowedExtensions;
    return picked;
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<WordEditorController> _studio(WidgetTester tester) async {
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
        initialWord: (
          name: 'Existing.docx',
          document: WmlDocument.empty(text: 'Keep work'),
        ),
      ),
    ),
  );
  await _frames(tester);
  final word = tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller;
  word.proofing.enabled = false;
  word.proofing.configure(OfficeProofingService(providers: []));
  return word;
}

Future<void> _action(WidgetTester tester, String id) async {
  final menu = tester.widget<StudioFileMenu>(find.byType(StudioFileMenu));
  menu.groups
      .expand((group) => group)
      .singleWhere((action) => action.id == id)
      .onSelected!();
  await _frames(tester);
}

Future<void> _waitFor(WidgetTester tester, bool Function() complete) async {
  final watch = Stopwatch()..start();
  while (!complete() && watch.elapsed < const Duration(seconds: 20)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    complete(),
    isTrue,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .join('\n'),
  );
}

void main() {
  tearDown(() {
    FilePicker.platform = FilePickerIO();
    StudioWindow.supported = false;
    StudioWindow.fullscreen = false;
  });

  test('file classification and converted names include native ODT', () {
    expect(StudioFiles.extensions, contains('odt'));
    expect(
      StudioFiles.kindOf('research.ODT', Uint8List(0)),
      OpcPackageKind.word,
    );
    expect(StudioFiles.kindOf('misnamed.docx', _odt()), OpcPackageKind.word);
    expect(StudioFiles.kindOf('unknown.data', _odt()), OpcPackageKind.word);
    expect(
      StudioFiles.importedOdtSaveName('  research.ODT  '),
      'research.docx',
    );
    expect(
      StudioFiles.importedOdtSaveName('chapter.revised.docx'),
      'chapter.revised.docx',
    );
    expect(StudioFiles.importedOdtSaveName('untitled'), 'untitled.docx');
    expect(StudioFiles.importedOdtSaveName(''), 'Document1.docx');
  });

  for (final sourceName in ['research.odt', 'misnamed.docx']) {
    testWidgets('imported $sourceName saves separately with active citations', (
      tester,
    ) async {
      final directory = Directory.systemTemp.createTempSync('studio-odt-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final source = File('${directory.path}/$sourceName');
      final bytes = _odt();
      source.writeAsBytesSync(bytes);
      final destination = File('${directory.path}/saved.docx');
      final picker = _Picker()
        ..savePath = destination.path
        ..picked = FilePickerResult([
          PlatformFile(
            name: sourceName,
            path: source.path,
            bytes: bytes,
            size: bytes.length,
          ),
        ]);
      FilePicker.platform = picker;
      final word = await _studio(tester);
      final imported = Completer<void>();
      word.addListener(() {
        if (!imported.isCompleted && word.zoteroFields.isNotEmpty) {
          imported.complete();
        }
      });
      await _action(tester, 'open');
      await _waitFor(tester, () => imported.isCompleted);
      await _frames(tester);
      expect(picker.openExtensions, contains('odt'));
      expect(word.zoteroFields.single.citation!.citationId, 'studio-odt');
      expect(source.readAsBytesSync(), orderedEquals(bytes));
      final suggested = StudioFiles.importedOdtSaveName(sourceName);
      expect(find.text(suggested), findsWidgets);

      word.insertText('Edited ');
      final saved = Completer<void>();
      word.addListener(() {
        if (!saved.isCompleted && !word.isDirty) saved.complete();
      });
      await _frames(tester);
      await _action(tester, 'save');
      await _waitFor(tester, () => saved.isCompleted);
      await _frames(tester);
      expect(picker.saveNames, [suggested]);
      expect(picker.saveExtensions.single, ['docx']);
      expect(source.readAsBytesSync(), orderedEquals(bytes));
      final reopened = WordDeserializer().read(
        OpcPackage.openBytes(destination.readAsBytesSync()),
      );
      expect(
        WordZotero.fields(reopened).single.citation!.citationId,
        'studio-odt',
      );
      expect(reopened.paragraphs.single.text, startsWith('Edited '));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
}
