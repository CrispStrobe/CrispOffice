import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _drawNs = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _tableNs = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

XmlElement _page(PmlShape shape) =>
    XmlDocument.parse(
          OpcPackage.openBytes(
            OdpPresentationWriter.writeBytes(
              PmlPresentation(
                slides: [
                  PmlSlide(id: 1, shapes: [shape]),
                ],
              ),
            ),
          ).getPart('/content.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _officeNs)!
        .firstChild('presentation', namespaceUri: _officeNs)!
        .firstChild('page', namespaceUri: _drawNs)!;

Iterable<XmlElement> _elements(
  XmlElement root,
  String name,
  String namespace,
) sync* {
  if (root.localName == name && root.namespaceUri == namespace) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name, namespace);
  }
}

PmlShape _chart({
  OfficeVisualKind kind = OfficeVisualKind.chartColumn,
  int rotation = 0,
}) => PmlShape(
  id: 1,
  name: 'Chart fallback',
  transform: PmlTransform(
    x: 762000,
    y: 1016000,
    cx: 1524000,
    cy: 762000,
    rot: rotation,
  ),
  visual: OfficeVisual(
    kind: kind,
    title: 'Data',
    points: [
      ChartPoint(label: 'Q<&1', value: 10.5),
      ChartPoint(label: 'Q2', value: -20.25),
    ],
  ),
);

List<List<String>> _cells(XmlElement table) => [
  for (final row in table.childrenNamed('table-row', namespaceUri: _tableNs))
    [
      for (final cell in row.childrenNamed(
        'table-cell',
        namespaceUri: _tableNs,
      ))
        cell.text,
    ],
];

void main() {
  for (final kind in [
    OfficeVisualKind.chartColumn,
    OfficeVisualKind.chartBar,
    OfficeVisualKind.chartPie,
    OfficeVisualKind.chartLine,
  ]) {
    test('$kind falls back to the exact ordered label/value table', () {
      final shape = _chart(kind: kind);
      final points = shape.visual!.points;
      final page = _page(shape);
      final frame = page.childrenNamed('frame', namespaceUri: _drawNs).single;
      final table = frame.childrenNamed('table', namespaceUri: _tableNs).single;
      expect(_cells(table), [
        ['Label', 'Value'],
        ['Q<&1', '10.5'],
        ['Q2', '-20.25'],
      ]);
      expect(shape.table, isNull);
      expect(shape.visual!.points, same(points));
      expect(points.map((point) => (point.label, point.value)), [
        ('Q<&1', 10.5),
        ('Q2', -20.25),
      ]);
      expect(shape.transform.rot, 0);
    });
  }

  test('an existing image stays preferred over chart fallback data', () {
    final shape = _chart(rotation: 90 * 60000);
    shape.visual!.imageBytes = _png;
    final page = _page(shape);
    expect(_elements(page, 'table', _tableNs), isEmpty);
    expect(_elements(page, 'g', _drawNs), isEmpty);
    expect(_elements(page, 'image', _drawNs), hasLength(1));
    expect(shape.visual!.imageBytes, same(_png));
    expect(shape.table, isNull);
  });

  test(
    'an explicit modeled table stays preferred over chart fallback data',
    () {
      final shape = _chart();
      final table = PmlTable(
        rows: [
          [PmlTableCell(text: 'Authored table')],
        ],
      );
      shape.table = table;
      final page = _page(shape);
      expect(_cells(_elements(page, 'table', _tableNs).single), [
        ['Authored table'],
      ]);
      expect(shape.table, same(table));
      expect(shape.visual!.points, hasLength(2));
    },
  );

  test('a chart without points retains the existing text fallback', () {
    final shape = _chart();
    shape.visual!.points.clear();
    shape.text = 'Visible fallback text';
    final page = _page(shape);
    expect(_elements(page, 'table', _tableNs), isEmpty);
    expect(
      _elements(page, 'text-box', _drawNs).single.text,
      'Visible fallback text',
    );
    expect(shape.text, 'Visible fallback text');
    expect(shape.table, isNull);
  });

  for (final rotation in [90 * 60000, -30 * 60000]) {
    test(
      'rotated chart $rotation retains data in rotated table fallback frames',
      () {
        final shape = _chart(rotation: rotation);
        final transform = shape.transform;
        final points = shape.visual!.points;
        final page = _page(shape);
        // Native ODP table rotation is ignored by the target consumer. The
        // existing rotated-table path preserves the cell geometry in text frames.
        expect(_elements(page, 'table', _tableNs), isEmpty);
        final group = page.childrenNamed('g', namespaceUri: _drawNs).single;
        expect(group.getAttribute('name', namespaceUri: _drawNs), shape.name);
        final cells = group
            .childrenNamed('frame', namespaceUri: _drawNs)
            .where(
              (frame) => frame
                  .getAttribute('name', namespaceUri: _drawNs)!
                  .contains(' cell '),
            )
            .toList();
        expect(cells, hasLength(6));
        expect(
          cells.map(
            (frame) => frame
                .firstChild('text-box', namespaceUri: _drawNs)!
                .firstChild('p', namespaceUri: _textNs)!
                .text,
          ),
          ['Label', 'Value', 'Q<&1', '10.5', 'Q2', '-20.25'],
        );
        for (final frame in cells) {
          expect(
            frame.getAttribute('transform', namespaceUri: _drawNs),
            startsWith('matrix('),
          );
        }
        expect(shape.table, isNull);
        expect(shape.transform, same(transform));
        expect(shape.transform.rot, rotation);
        expect(shape.visual!.points, same(points));
      },
    );
  }
}
