import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlDocument _document({
  String text = 'الفكرة جميلة',
  String flags = '<w:rtl/><w:cs w:val="0"/>',
  bool characterStyle = true,
  bool paragraphStyle = true,
  String? directBidi = 'ar-SA',
}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>
${paragraphStyle ? '<w:pPr><w:pStyle w:val="ParagraphChild"/></w:pPr>' : ''}
<w:r><w:rPr>
${characterStyle ? '<w:rStyle w:val="CharacterChild"/>' : ''}
<w:lang w:val="en-GB" w:eastAsia="ja-JP" ${directBidi == null ? '' : 'w:bidi="$directBidi"'}/>
$flags<w:spacing w:val="23"/>
</w:rPr><w:t>$text</w:t></w:r></w:p><w:sectPr/></w:body></w:document>''');
  package
      .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
      .writeText('''
<w:styles xmlns:w="${OfficeNamespaces.w}">
<w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val="de-DE" w:bidi="ar-AE"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:styleId="ParagraphBase"><w:rPr><w:lang w:bidi="ar-EG"/><w:b/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ParagraphChild"><w:basedOn w:val="ParagraphBase"/></w:style>
<w:style w:type="character" w:styleId="CharacterBase"><w:rPr><w:lang w:bidi="ar-MA"/><w:i/></w:rPr></w:style>
<w:style w:type="character" w:styleId="CharacterChild"><w:basedOn w:val="CharacterBase"/></w:style>
</w:styles>''');
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  return WordDeserializer().read(package);
}

WordEditorController _controller(WmlDocument document) {
  final controller = WordEditorController(document: document);
  addTearDown(controller.dispose);
  return controller;
}

List<WmlRun> _runs(WordEditorController controller) =>
    controller.document.paragraphs.single.inlines.whereType<WmlRun>().toList();

WmlDocument _reload(WordEditorController controller) =>
    WordDeserializer().readBytes(controller.saveBytes());

void _expectMetadata(
  WmlDocument document, {
  required String? directBidi,
  required String? directLatin,
}) {
  final xml = XmlDocument.parse(
    document.package!.getPart('/word/document.xml')!.readText(),
  );
  final run = xml.root!.firstChild('body')!.firstChild('p')!.firstChild('r')!;
  final props = run.firstChild('rPr')!;
  final language = props.firstChild('lang')!;
  expect(language.getAttribute('val'), directLatin);
  expect(language.getAttribute('eastAsia'), 'ja-JP');
  expect(language.getAttribute('bidi'), directBidi);
  expect(props.firstChild('rtl'), isNotNull);
  expect(props.firstChild('cs')!.getAttribute('val'), '0');
  expect(props.firstChild('spacing')!.getAttribute('val'), '23');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in ['ar-DZ', 'en-GB']) {
    test(
      'choosing $language updates the routed language and survives history',
      () {
        final controller = _controller(_document());
        expect(controller.textProofingTarget!.language, 'ar-SA');
        expect(
          controller.setTextProofingLanguage(
            language,
            target: controller.textProofingTarget!,
          ),
          isTrue,
        );
        expect(controller.textProofingTarget!.language, language);
        expect(_runs(controller).single.properties.proofingLanguage, language);
        expect(
          _runs(controller).single.properties.complexScriptLanguage,
          language,
        );
        expect(_runs(controller).single.properties.complexScript, isTrue);
        controller.undo();
        expect(controller.textProofingTarget!.language, 'ar-SA');
        expect(controller.canUndo, isFalse);
        controller.redo();
        expect(controller.textProofingTarget!.language, language);
        final loaded = _reload(controller);
        _expectMetadata(loaded, directBidi: language, directLatin: language);
        expect(_controller(loaded).textProofingTarget!.language, language);
      },
    );
  }

  for (final (name, characterStyle, paragraphStyle, inherited) in [
    ('character style', true, true, 'ar-MA'),
    ('paragraph style', false, true, 'ar-EG'),
    ('document default', false, false, 'ar-AE'),
  ]) {
    test(
      'reset inherits $name through undo and DOCX without a direct bidi tag',
      () {
        final controller = _controller(
          _document(
            characterStyle: characterStyle,
            paragraphStyle: paragraphStyle,
          ),
        );
        expect(
          controller.setTextProofingLanguage(
            null,
            target: controller.textProofingTarget!,
          ),
          isTrue,
        );
        expect(controller.textProofingTarget!.language, inherited);
        expect(_runs(controller).single.properties.proofingLanguage, isNull);
        expect(_runs(controller).single.properties.complexScript, isTrue);
        final revision = controller.contentRevision;
        expect(
          controller.setTextProofingLanguage(
            null,
            target: controller.textProofingTarget!,
          ),
          isTrue,
        );
        expect(controller.contentRevision, revision);
        controller.undo();
        expect(controller.textProofingTarget!.language, 'ar-SA');
        expect(controller.canUndo, isFalse);
        controller.redo();
        expect(controller.textProofingTarget!.language, inherited);
        final loaded = _reload(controller);
        _expectMetadata(loaded, directBidi: null, directLatin: null);
        final reopened = _controller(loaded);
        expect(reopened.textProofingTarget!.language, inherited);
        if (!paragraphStyle) {
          expect(
            _runs(reopened).single.properties.complexScriptLanguage,
            isNull,
          );
          loaded.complexScriptLanguage = 'ar-QA';
          expect(reopened.textProofingTarget!.language, 'ar-QA');
        }
      },
    );
  }

  test('partial Arabic selection keeps its chosen language separate', () {
    final controller = _controller(_document(flags: ''));
    controller.caret
      ..selectionAnchor = 0
      ..logicalIndex = 'الفكرة'.length;
    expect(
      controller.setTextProofingLanguage(
        'ar-DZ',
        target: controller.textProofingTarget!,
      ),
      isTrue,
    );
    expect(
      _runs(
        controller,
      ).map((run) => (run.text, run.properties.complexScriptLanguage)),
      [('الفكرة', 'ar-DZ'), (' جميلة', 'ar-SA')],
    );
    expect(controller.textProofingTarget!.language, 'ar-DZ');
    final loaded = _reload(controller);
    expect(
      loaded.paragraphs.single.inlines.whereType<WmlRun>().map(
        (run) => (run.text, run.properties.complexScriptLanguage),
      ),
      [('الفكرة', 'ar-DZ'), (' جميلة', 'ar-SA')],
    );
    controller.undo();
    expect(_runs(controller).single.text, 'الفكرة جميلة');
    expect(controller.textProofingTarget!.language, 'ar-SA');
  });

  test(
    'a Latin-only selection changes both overrides without changing the Arabic tail',
    () {
      final controller = _controller(_document(text: 'Text فكرة', flags: ''));
      controller.caret
        ..selectionAnchor = 0
        ..logicalIndex = 4;
      expect(
        controller.setTextProofingLanguage(
          'de-DE',
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(
        _runs(controller).map(
          (run) => (
            run.text,
            run.properties.proofingLanguage,
            run.properties.complexScriptLanguage,
          ),
        ),
        [('Text', 'de-DE', 'de-DE'), (' فكرة', 'en-GB', 'ar-SA')],
      );
      expect(controller.textProofingTarget!.language, 'de-DE');
    },
  );

  test('a changed document bidi default makes a displayed target stale', () {
    final controller = _controller(
      _document(characterStyle: false, paragraphStyle: false, directBidi: null),
    );
    final target = controller.textProofingTarget!;
    expect(target.language, 'ar-AE');
    controller.document.complexScriptLanguage = 'ar-QA';
    expect(
      controller.setTextProofingLanguage('ar-DZ', target: target),
      isFalse,
    );
    expect(controller.canUndo, isFalse);
  });
}
