import 'dart:convert';
import 'dart:typed_data';

import 'package:jbig2/jbig2.dart' as jb;
import 'package:quds_office_engine/pdf_file.dart';
import 'package:quds_office_engine/src/pdf/file/decode/pdf_filters.dart';
import 'package:quds_office_engine/src/pdf/pdf_stream.dart';
import 'package:test/test.dart';

// Independent lossless OpenJPEG 2.5.4 fixtures, generated with Pillow from
// synthetic pixels. No third-party PDF or restricted ITU test data is copied.
const _rgbJp2 =
    'AAAADGpQICANCocKAAAAFGZ0eXBqcDIgAAAAAGpwMiAAAAAtanAyaAAAABZpaGRyAAAAAgAAAAIAAwcHAAAAAAAPY29scgEAAAAAABAAAACZanAyY/9P/1EALwAAAAAAAgAAAAIAAAAAAAAAAAAAAAIAAAACAAAAAAAAAAAAAwcBAQcBAQcBAf9SAAwAAAABAAEEBAAB/1wAB0BASEhQ/2QAJQABQ3JlYXRlZCBieSBPcGVuSlBFRyB2ZXJzaW9uIDIuNS40/5AACgAAAAAAHgAB/5OAgICT8wIA38/ABACn4AIA/9k=';
const _rgbJ2k =
    '/0//UQAvAAAAAAACAAAAAgAAAAAAAAAAAAAAAgAAAAIAAAAAAAAAAAADBwEBBwEBBwEB/1IADAAAAAEAAQQEAAH/XAAHQEBISFD/ZAAlAAFDcmVhdGVkIGJ5IE9wZW5KUEVHIHZlcnNpb24gMi41LjT/kAAKAAAAAAAeAAH/k4CAgJPzAgDfz8AEAKfgAgD/2Q==';
const _grayJp2 =
    'AAAADGpQICANCocKAAAAFGZ0eXBqcDIgAAAAAGpwMiAAAAAtanAyaAAAABZpaGRyAAAAAgAAAAMAAQcHAAAAAAAPY29scgEAAAAAABEAAACZanAyY/9P/1EAKQAAAAAAAwAAAAIAAAAAAAAAAAAAAAMAAAACAAAAAAAAAAAAAQcBAf9SAAwAAAABAAEEBAAB/1wAB0BASEhQ/2QAJQABQ3JlYXRlZCBieSBPcGVuSlBFRyB2ZXJzaW9uIDIuNS40/5AACgAAAAAAJAAB/5PD5wYMIX/H2gV+YHH4AQAEFwRjDwQ//9k=';
const _rgbaJp2 =
    'AAAADGpQICANCocKAAAAFGZ0eXBqcDIgAAAAAGpwMiAAAABPanAyaAAAABZpaGRyAAAAAgAAAAIABAcHAAAAAAAPY29scgEAAAAAABAAAAAiY2RlZgAEAAAAAAABAAEAAAACAAIAAAADAAMAAQAAAAAArmpwMmP/T/9RADIAAAAAAAIAAAACAAAAAAAAAAAAAAACAAAAAgAAAAAAAAAAAAQHAQEHAQEHAQEHAQH/UgAMAAAAAQABBAQAAf9cAAdAQEhIUP9kACUAAUNyZWF0ZWQgYnkgT3BlbkpQRUcgdmVyc2lvbiAyLjUuNP+QAAoAAAAAADAAAf+TgICAw+cCB5PzAgDfz8AEAKfgAgDH2gU/ACg+oBACfwLXAP/Z';

const _rgb = <int>[255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255];

PdfCosDict _jpx(int width, int height, {int alpha = 0}) =>
    PdfCosDict(<String, PdfCos>{
      'Filter': const PdfCosName('JPXDecode'),
      'Width': PdfCosInt(width),
      'Height': PdfCosInt(height),
      'SMaskInData': PdfCosInt(alpha),
    });

Uint8List _hex(Uint8List data) => Uint8List.fromList(ascii.encode(
  '${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}>',
));

PdfCosDict _predictor(int columns, int colors, int bits, {int predictor = 2}) =>
    PdfCosDict(<String, PdfCos>{
      'Filter': const PdfCosName('FlateDecode'),
      'DecodeParms': PdfCosDict(<String, PdfCos>{
        'Predictor': PdfCosInt(predictor),
        'Columns': PdfCosInt(columns),
        'Colors': PdfCosInt(colors),
        'BitsPerComponent': PdfCosInt(bits),
      }),
    });

void main() {
  test('JP2 and raw J2K reconstruct independent RGB reference', () {
    for (final fixture in [_rgbJp2, _rgbJ2k]) {
      final decoded = PdfFilters.decodeResult(
        base64Decode(fixture), _jpx(2, 2),
      );
      expect(decoded.unsupported, isNull);
      expect(decoded.bytes, _rgb);
      expect(decoded.jpxImage?.hasAlpha, isFalse);
    }
  });

  test('gray JPX with omitted ColorSpace uses codestream channels', () {
    final decoded = PdfFilters.decodeResult(base64Decode(_grayJp2), _jpx(3, 2));
    expect(decoded.jpxImage?.isGray, isTrue);
    expect(decoded.bytes, [
      for (final tone in [0, 64, 128, 192, 255, 17]) ...[tone, tone, tone],
    ]);
  });

  test('JPX honors SMaskInData and omits unused alpha', () {
    final data = base64Decode(_rgbaJp2);
    final decoded = PdfFilters.decodeResult(data, _jpx(2, 2, alpha: 1));
    expect(decoded.jpxImage?.hasAlpha, isTrue);
    expect(decoded.bytes, [255, 0, 0, 0, 0, 255, 0, 64,
      0, 0, 255, 128, 255, 255, 255, 255]);
    expect(PdfFilters.decode(data, _jpx(2, 2)), _rgb);
  });

  test('ASCIIHex then JPX preserves terminal image metadata', () {
    final dict = _jpx(2, 2)
      ..['Filter'] = PdfCosArray(<PdfCos>[
        const PdfCosName('ASCIIHexDecode'), const PdfCosName('JPXDecode'),
      ])
      ..['DecodeParms'] = PdfCosArray(<PdfCos>[
        const PdfCosNull(), PdfCosDict(),
      ]);
    final decoded = PdfFilters.decodeResult(_hex(base64Decode(_rgbJp2)), dict);
    expect(decoded.bytes, _rgb);
    expect(decoded.jpxImage, isNotNull);
  });

  test('bad JPX and mismatched dimensions remain typed unsupported', () {
    expect(PdfFilters.decodeResult(Uint8List(3), _jpx(2, 2)).unsupported,
        'JPXDecode');
    expect(PdfFilters.decodeResult(base64Decode(_rgbJp2), _jpx(1, 2)).unsupported,
        'JPXDecode');
  });

  test('JPX XObject reaches the display list without a JPEG host codec', () {
    final pdf = PdfFile.open(_imagePdf(
      base64Decode(_rgbJp2), '/Width 2 /Height 2 /Filter /JPXDecode',
    ));
    final image = pdf.displayList(0).ops.whereType<PdfDrawImage>().single;
    expect(image.placeholder, isFalse);
    expect(image.jpeg, isFalse);
    expect(image.pixelWidth, 2);
    expect(image.pixelHeight, 2);
    expect(image.bytes, _rgb);
  });

  test('JBIG2 generic region and symbol dictionary preserve polarity', () {
    final packed = Uint8List.fromList([0x81, 0x42, 0x24, 0x18,
      0x81, 0x42, 0x24, 0x18]);
    final expected = [
      for (final row in packed)
        for (int x = 7; x >= 0; x--) (row & (1 << x)) != 0 ? 0 : 255,
    ];
    for (final mode in [jb.Jbig2EncodeMode.genericRegion,
      jb.Jbig2EncodeMode.symbolDictionary]) {
      final data = jb.encodeJbig2Packed(packed, width: 8, height: 8,
        options: jb.Jbig2EncodeOptions(mode: mode));
      final dict = PdfCosDict(<String, PdfCos>{
        'Filter': const PdfCosName('JBIG2Decode'),
        'Width': const PdfCosInt(8),
        'Height': const PdfCosInt(8),
      });
      expect(PdfFilters.decode(data, dict), expected);
    }
  });

  test('indirect Flate-wrapped JBIG2Globals resolves through PdfCosStore', () {
    final packed = Uint8List.fromList(List<int>.generate(16,
        (i) => i.isEven ? 0x44 : 0x22));
    final single = jb.decodeJbig2Embedded(jb.encodeJbig2Packed(
      packed, width: 16, height: 8,
    ));
    final shared = jb.encodeJbig2EmbeddedPages([single, single],
      options: const jb.Jbig2EncodeOptions(
        mode: jb.Jbig2EncodeMode.symbolDictionary,
      ),
    );
    expect(shared.globals, isNotEmpty);
    final pdf = PdfFile.open(_imagePdf(shared.pages.first,
      '/Width 16 /Height 8 /BitsPerComponent 1 /ColorSpace /DeviceGray '
      '/Filter /JBIG2Decode /DecodeParms 6 0 R',
      extras: [
        ascii.encode('<< /JBIG2Globals 7 0 R >>'),
        _stream(PdfFlate.compress(shared.globals), '/Filter /FlateDecode'),
      ],
    ));
    final image = pdf.displayList(0).ops.whereType<PdfDrawImage>().single;
    expect(image.placeholder, isFalse);
    expect(image.bytes, [
      for (final tone in single.toGrayscale()) ...[tone, tone, tone],
    ]);
  });

  test('unresolved JBIG2Globals never silently falls back to a blank image', () {
    final dict = PdfCosDict(<String, PdfCos>{
      'Filter': const PdfCosName('JBIG2Decode'),
      'DecodeParms': PdfCosDict(<String, PdfCos>{
        'JBIG2Globals': const PdfCosRef(99),
      }),
    });
    expect(PdfFilters.decodeResult(Uint8List(12), dict).unsupported,
        'JBIG2Decode');
  });

  test('TIFF predictor undoes packed and 16-bit sample deltas by component', () {
    // 4-bit samples [1, 4, 15], padding nibble zero.
    expect(PdfFilters.decode(PdfFlate.compress([0x13, 0xb0]),
      _predictor(3, 1, 4)), [0x14, 0xf0]);
    // 2-bit samples [3, 0, 1, 3] (mod 4 wrap).
    expect(PdfFilters.decode(PdfFlate.compress([0xd6]),
      _predictor(4, 1, 2)), [0xc7]);
    // Two 16-bit RGB-like two-channel pixels:
    // [0x12ff,0xfffe] + [0x0002,0x0003] -> [0x1301,0x0001].
    expect(PdfFilters.decode(PdfFlate.compress(
      [0x12, 0xff, 0xff, 0xfe, 0, 2, 0, 3]),
      _predictor(2, 2, 16)),
      [0x12, 0xff, 0xff, 0xfe, 0x13, 1, 0, 1]);
  });

  test('predictor rejects incomplete rows and unknown PNG row tags', () {
    expect(PdfFilters.decodeResult(PdfFlate.compress([1]),
      _predictor(2, 1, 8)).unsupported, 'FlateDecode');
    expect(PdfFilters.decodeResult(PdfFlate.compress([5, 1, 2]),
      _predictor(2, 1, 8, predictor: 15)).unsupported, 'FlateDecode');
  });

  test('DCT remains encoded for existing JPEG host paths', () {
    final raw = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
    final result = PdfFilters.decodeResult(raw, PdfCosDict(<String, PdfCos>{
      'Filter': const PdfCosName('DCTDecode'),
    }));
    expect(result.bytes, raw);
    expect(result.jpxImage, isNull);
  });
}

Uint8List _stream(Uint8List data, String entries) => Uint8List.fromList([
  ...ascii.encode('<< $entries /Length ${data.length} >>\nstream\n'),
  ...data,
  ...ascii.encode('\nendstream'),
]);

Uint8List _imagePdf(Uint8List data, String entries,
    {List<List<int>> extras = const []}) {
  final objects = <List<int>>[
    ascii.encode('<< /Type /Catalog /Pages 2 0 R >>'),
    ascii.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    ascii.encode('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] '
        '/Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>'),
    _stream(Uint8List.fromList(ascii.encode('q 40 0 0 40 10 10 cm /Im0 Do Q')), ''),
    _stream(data, '/Type /XObject /Subtype /Image $entries'),
    ...extras,
  ];
  final out = BytesBuilder()..add(ascii.encode('%PDF-1.7\n'));
  final offsets = <int>[];
  for (int i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.add(ascii.encode('${i + 1} 0 obj\n'));
    out.add(objects[i]);
    out.add(ascii.encode('\nendobj\n'));
  }
  final xref = out.length;
  out.add(ascii.encode('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n'));
  for (final offset in offsets) {
    out.add(ascii.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'));
  }
  out.add(ascii.encode('trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n'));
  return out.takeBytes();
}
