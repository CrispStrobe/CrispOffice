import 'dart:async';
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

const _preferences =
    '{"style":{"styleID":"http://www.zotero.org/styles/apa",'
    '"locale":"de-DE"},"prefs":{"fieldType":"Field","noteType":0}}';

WmlDocument _document() {
  final document = WmlDocument.empty(text: 'Research ')
    ..zoteroDocumentData = _preferences;
  WordZotero.insertCitation(
    document.paragraphs.single,
    ZoteroCitation(
      citationId: 'studio-export',
      plainCitation: '(Source)',
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: <String, Object?>{
            'id': 1,
            'type': 'book',
            'title': 'Research source',
          },
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
          locator: '12–14',
          label: 'page',
        ),
      ],
    ),
  );
  return document;
}

WmlDocument _romanEndnotes({bool uppercase = false, bool restart = false}) {
  final cited = WmlParagraph(inlines: [WmlRun(text: 'Cited note ')]);
  WordZotero.insertCitation(
    cited,
    WordZotero.fields(_document()).single.citation!,
  );
  return WmlDocument(
    zoteroDocumentData: _preferences,
    sections: [
      WmlSection(
        sourceProperties: uppercase || restart
            ? WmlSectionSource(
                xml:
                    '<w:sectPr xmlns:w="${OfficeNamespaces.w}">'
                    '<w:endnotePr><w:numFmt w:val="${uppercase ? 'upperRoman' : 'lowerRoman'}"/>'
                    '${restart ? '<w:numRestart w:val="eachSect"/>' : ''}'
                    '</w:endnotePr></w:sectPr>',
                values: const {},
              )
            : null,
        blocks: [
          WmlParagraph(
            inlines: [
              WmlRun(text: 'Uncited '),
              WmlRun(text: '41', noteRefId: 41, noteRefEndnote: true),
              WmlRun(text: ' cited '),
              WmlRun(text: '72', noteRefId: 72, noteRefEndnote: true),
              WmlRun(text: ' tail'),
            ],
          ),
        ],
      ),
    ],
    endnotes: [
      WmlNote(
        id: 41,
        endnote: true,
        paragraphs: [
          WmlParagraph(inlines: [WmlRun(text: 'Uncited note')]),
        ],
      ),
      WmlNote(id: 72, endnote: true, paragraphs: [cited]),
    ],
  );
}

class _Picker extends FilePicker {
  String? savePath;
  Completer<String?>? pending;
  final names = <String?>[];
  final extensions = <List<String>?>[];

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
    names.add(fileName);
    extensions.add(allowedExtensions);
    return pending == null ? savePath : pending!.future;
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<WordEditorController> _studio(
  WidgetTester tester, {
  WmlDocument? document,
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
        initialWord: (name: 'Research.docx', document: document ?? _document()),
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

StudioMenuAction _action(WidgetTester tester, String id) => tester
    .widget<StudioFileMenu>(find.byType(StudioFileMenu))
    .groups
    .expand((group) => group)
    .singleWhere((action) => action.id == id);

Future<void> _waitFor(WidgetTester tester, bool Function() complete) async {
  final watch = Stopwatch()..start();
  while (!complete() && watch.elapsed < const Duration(seconds: 30)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(complete(), isTrue);
}

void main() {
  tearDown(() {
    FilePicker.platform = FilePickerIO();
    StudioWindow.supported = false;
    StudioWindow.fullscreen = false;
  });

  test('Zotero copy names select ODT without changing the source name', () {
    expect(StudioFiles.zoteroOdtExportName(' Research.docx '), 'Research.odt');
    expect(StudioFiles.zoteroOdtExportName('Research.DOCM'), 'Research.odt');
    expect(
      StudioFiles.zoteroOdtExportName('chapter.revised.odt'),
      'chapter.revised.odt',
    );
    expect(StudioFiles.zoteroOdtExportName('Research'), 'Research.odt');
    expect(StudioFiles.zoteroOdtExportName(''), 'Document1.odt');
  });

  testWidgets('exports an active Zotero copy and keeps normal save as DOCX', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('zotero-export-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final copy = File('${directory.path}/citation-copy.odt');
    final saved = File('${directory.path}/Research.docx');
    final picker = _Picker()..savePath = '${directory.path}/citation-copy';
    FilePicker.platform = picker;
    final word = await _studio(tester);
    word.caret.logicalIndex = 0;
    word.caret.collapseSelection();
    word.insertText('Edited ');
    await _frames(tester);
    final revision = word.contentRevision;
    final instructions = word.zoteroFields.single.instruction;
    _action(tester, 'export-zotero-odt').onSelected!();
    await _frames(tester);
    await _waitFor(tester, () => copy.existsSync());
    await _waitFor(tester, () => _action(tester, 'save').onSelected != null);

    expect(picker.names, ['Research.odt']);
    expect(picker.extensions, [
      <String>['odt'],
    ]);
    expect(word.isDirty, isTrue);
    expect(word.contentRevision, revision);
    expect(word.zoteroFields.single.instruction, instructions);
    expect(word.document.zoteroDocumentData, _preferences);
    final inventory = await tester.runAsync(
      () => OdfZotero.inspect(copy.readAsBytesSync()),
    );
    expect(inventory!.fields.single.isImportCandidate, isTrue);
    expect(inventory.fields.single.cachedText, '(Source)');
    expect(find.textContaining('Research.docx'), findsWidgets);

    picker.savePath = saved.path;
    _action(tester, 'save').onSelected!();
    await _frames(tester);
    await _waitFor(tester, () => !word.isDirty);
    await _waitFor(tester, () => _action(tester, 'save').onSelected != null);
    expect(picker.names, ['Research.odt', 'Research.docx']);
    expect(picker.extensions.last, ['docx']);
    final reopened = WordDeserializer().readBytes(saved.readAsBytesSync());
    expect(WordZotero.fields(reopened).single.instruction, instructions);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'picker cancellation preserves dirty edits and re-enables export',
    (tester) async {
      final picker = _Picker();
      FilePicker.platform = picker;
      final word = await _studio(tester);
      word.insertText('Pending ');
      await _frames(tester);
      final revision = word.contentRevision;
      final text = word.document.paragraphs.single.text;
      _action(tester, 'export-zotero-odt').onSelected!();
      await _frames(tester);
      await _waitFor(tester, () => picker.names.isNotEmpty);
      await _waitFor(
        tester,
        () => _action(tester, 'export-zotero-odt').onSelected != null,
      );
      expect(word.isDirty, isTrue);
      expect(word.contentRevision, revision);
      expect(word.document.paragraphs.single.text, text);
      expect(word.zoteroFields.single.citation!.citationId, 'studio-export');
      expect(find.text('Exported ODT with Zotero fields.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('edits during picking do not change the detached exported copy', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('zotero-snapshot-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final copy = File('${directory.path}/snapshot.odt');
    final gate = Completer<String?>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete(null);
    });
    final picker = _Picker()..pending = gate;
    FilePicker.platform = picker;
    final word = await _studio(tester);
    _action(tester, 'export-zotero-odt').onSelected!();
    await _frames(tester);
    await _waitFor(tester, () => picker.names.isNotEmpty);
    expect(_action(tester, 'export-zotero-odt').onSelected, isNull);
    word.caret.logicalIndex = 0;
    word.caret.collapseSelection();
    word.insertText('Later edit ');
    final revision = word.contentRevision;
    gate.complete(copy.path);
    await _waitFor(tester, () => copy.existsSync());
    await _waitFor(tester, () => _action(tester, 'save').onSelected != null);
    expect(word.isDirty, isTrue);
    expect(word.contentRevision, revision);
    expect(word.document.paragraphs.single.text, startsWith('Later edit '));
    final exported = OfficeTextExtractor.extract(
      copy.readAsBytesSync(),
      name: 'snapshot.odt',
    );
    expect(exported.paragraphs.join('\n'), isNot(contains('Later edit ')));
    expect(exported.paragraphs.join('\n'), contains('Research (Source)'));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'invalid active Zotero data refuses before choosing a destination',
    (tester) async {
      final picker = _Picker();
      FilePicker.platform = picker;
      final document = _document()..zoteroDocumentData = 'broken preferences';
      final word = await _studio(tester, document: document);
      final revision = word.contentRevision;
      final text = document.paragraphs.single.text;
      _action(tester, 'export-zotero-odt').onSelected!();
      await _frames(tester);
      await _waitFor(
        tester,
        () => find
            .textContaining('Could not export Zotero ODT.')
            .evaluate()
            .isNotEmpty,
      );
      expect(picker.names, isEmpty);
      expect(word.contentRevision, revision);
      expect(word.document, same(document));
      expect(document.paragraphs.single.text, text);
      expect(document.zoteroDocumentData, 'broken preferences');
      expect(_action(tester, 'export-zotero-odt').onSelected, isNotNull);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final upper in [false, true]) {
    testWidgets(
      '${upper ? 'upper' : 'default lower'} Roman endnotes export as an editable copy',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync('zotero-roman-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final copy = File('${directory.path}/roman.odt');
        final saved = File('${directory.path}/Research.docx');
        final picker = _Picker()..savePath = copy.path;
        FilePicker.platform = picker;
        final word = await _studio(
          tester,
          document: _romanEndnotes(uppercase: upper),
        );
        word.caret.logicalIndex = 0;
        word.caret.collapseSelection();
        word.insertText('Edited ');
        await _frames(tester);
        final original = word.document;
        final revision = word.contentRevision;
        final instruction = word.zoteroFields.single.instruction;
        final labels = upper ? ['I', 'II'] : ['i', 'ii'];

        _action(tester, 'export-zotero-odt').onSelected!();
        await _frames(tester);
        await _waitFor(tester, () => copy.existsSync());
        await _waitFor(
          tester,
          () => _action(tester, 'save').onSelected != null,
        );
        expect(word.document, same(original));
        expect(word.contentRevision, revision);
        expect(word.isDirty, isTrue);
        expect(word.canUndo, isTrue);
        expect(word.zoteroFields.single.instruction, instruction);
        final imported = await tester.runAsync(
          () => OdtDocumentReader.readBytes(copy.readAsBytesSync()),
        );
        final numbering = WordNoteNumbering(imported!);
        expect(imported.endnotes.map(numbering.labelFor), labels);
        expect(
          WordZotero.fields(imported).single.paragraph,
          same(imported.endnotes[1].paragraphs.single),
        );
        expect(WordZotero.fields(imported).single.instruction, instruction);
        expect(picker.names, ['Research.odt']);

        picker.savePath = saved.path;
        _action(tester, 'save').onSelected!();
        await _frames(tester);
        await _waitFor(tester, () => !word.isDirty);
        await _waitFor(tester, () => _action(tester, 'save').onSelected != null);
        final reopened = WordDeserializer().readBytes(saved.readAsBytesSync());
        final reopenedNumbering = WordNoteNumbering(reopened);
        expect(reopened.endnotes.map(reopenedNumbering.labelFor), labels);
        expect(WordZotero.fields(reopened).single.instruction, instruction);
        expect(picker.names, ['Research.odt', 'Research.docx']);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets('restarting Roman notes refuse before destination selection', (
    tester,
  ) async {
    final picker = _Picker();
    FilePicker.platform = picker;
    final document = _romanEndnotes(restart: true);
    final word = await _studio(tester, document: document);
    word.insertText('Unsaved ');
    await _frames(tester);
    final revision = word.contentRevision;
    final originalText = document.paragraphs.single.text;
    _action(tester, 'export-zotero-odt').onSelected!();
    await _frames(tester);
    await _waitFor(
      tester,
      () => find
          .textContaining('Could not export Zotero ODT.')
          .evaluate()
          .isNotEmpty,
    );
    expect(picker.names, isEmpty);
    expect(word.document, same(document));
    expect(word.contentRevision, revision);
    expect(document.paragraphs.single.text, originalText);
    expect(word.isDirty, isTrue);
    expect(word.canUndo, isTrue);
    expect(_action(tester, 'export-zotero-odt').onSelected, isNotNull);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
