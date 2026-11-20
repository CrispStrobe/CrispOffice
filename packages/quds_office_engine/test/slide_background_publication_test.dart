import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _ns =
    'xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}" '
    'xmlns:r="${OfficeNamespaces.r}"';
const _picture =
    '<p:bg><p:bgPr><a:blipFill><a:blip r:embed="rBackground"/>'
    '<a:stretch><a:fillRect/></a:stretch></a:blipFill></p:bgPr></p:bg>';

PmlPresentation _importPicture(String owner) {
  final package = OpcPackage.openBytes(
    (PptxDeckBuilder()..addTitleSlide(title: '')).build(),
  );
  final image = PngBytes.rgb(
    width: 1,
    height: 1,
    plot: (x, y, rgb) {
      rgb[0] = 255;
      rgb[1] = 0;
      rgb[2] = 0;
    },
  );
  package.createPart('/ppt/media/background.png', 'image/png', image);
  for (final (kind, root, uri) in [
    ('master', 'sldMaster', '/ppt/slideMasters/slideMaster1.xml'),
    ('layout', 'sldLayout', '/ppt/slideLayouts/slideLayout1.xml'),
    ('slide', 'sld', '/ppt/slides/slide1.xml'),
  ]) {
    final background = kind == 'master' || kind == owner ? _picture : '';
    package
        .getPart(uri)!
        .writeText(
          '<p:$root $_ns><p:cSld>$background<p:spTree/></p:cSld></p:$root>',
        );
    package
        .relationshipsFor(uri)
        .add(
          id: 'rBackground',
          type: RelationshipTypes.image,
          target: '../media/background.png',
        );
  }
  return SlideDeserializer().read(package);
}

Iterable<PmlShape> _pictures(PmlSlide slide) =>
    slide.backgroundShapes.where((shape) => shape.isBackgroundPicture);

PmlPresentation _reopen(PmlPresentation deck) =>
    SlideDeserializer().readBytes(SlideSerializer().writeBytes(deck));

void main() {
  test(
    'direct master solids affect PDF immediately, retaining local fills',
    () {
      for (final color in ['112233', 'FFFFFF']) {
        for (final owner in ['master', 'layout', 'slide']) {
          final deck = _importPicture(owner);
          final slide = deck.slides.single;
          expect(_pictures(slide), hasLength(1));
          final sourceXml = deck.package!
              .getPart('/ppt/slideMasters/slideMaster1.xml')!
              .readText();
          deck.master.background = color;
          for (final perPage in [1, 2]) {
            final ops = PdfFile.open(
              OfficePdfExport.presentation(deck, slidesPerPage: perPage),
            ).displayList(0).ops;
            expect(
              ops.whereType<PdfDrawImage>(),
              hasLength(owner == 'master' ? 0 : 1),
              reason: '$owner owner, $color paper, $perPage per page',
            );
            if (owner == 'master') {
              expect(
                ops.whereType<PdfFillPath>().map((op) => op.color),
                contains(0xFF000000 | int.parse(color, radix: 16)),
              );
            }
          }
          // Rendering resolves the authored master without rewriting the model
          // snapshot or its original package. Native save remains explicit.
          expect(_pictures(slide), hasLength(1));
          expect(
            deck.package!
                .getPart('/ppt/slideMasters/slideMaster1.xml')!
                .readText(),
            sourceXml,
          );
        }
      }
    },
  );

  test('fresh deck copies keep pictures unless a master solid is explicit', () {
    final source = _importPicture('master');
    final snapshot = _pictures(source.slides.single).single.visual!.imageBytes;
    final fresh = PmlPresentation(slides: [source.slides.single.copy(id: 300)]);
    expect(fresh.master.background, 'FFFFFF');
    expect(fresh.master.hasAuthoredBackground, isFalse);
    final saved = _reopen(fresh);
    expect(_pictures(saved.slides.single), hasLength(1));
    expect(_pictures(saved.slides.single).single.visual!.imageBytes, snapshot);
    expect(_pictures(source.slides.single), hasLength(1));

    for (final color in ['112233', 'FFFFFF']) {
      final explicit = _reopen(
        PmlPresentation(
          master: PmlMaster(name: 'Explicit master', background: color),
          slides: [source.slides.single.copy(id: 301)],
        ),
      );
      expect(_pictures(explicit.slides.single), isEmpty);
      expect(explicit.slides.single.background, color);
      expect(explicit.master.background, color);
    }
  });
}
