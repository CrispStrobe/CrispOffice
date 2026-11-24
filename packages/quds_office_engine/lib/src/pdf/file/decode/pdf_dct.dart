import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../cos/pdf_cos.dart';
import '../cos/pdf_open_error.dart';

/// DeviceGray/DeviceRGB JPEG samples normalized to RGB888.
final class PdfDctImage {
  const PdfDctImage(this.pixels, {required this.isGray});

  final Uint8List pixels;
  final bool isGray;
}

/// Bounded PDF JPEG adapter. Four-component and non-device color spaces
/// deliberately retain the legacy host path; PDF CMYK Decode must be applied
/// before conversion to RGB, which the standalone JPEG API cannot guarantee.
abstract final class PdfDct {
  static const int maxPixels = 16 * 1024 * 1024;
  static const int maxDimension = 8192;
  static const int _maxBytes = 32 * 1024 * 1024;

  static Never _unsupported() =>
      throw const PdfFilterUnsupported('DCTDecode');

  static PdfDctImage? decode(
    Uint8List data,
    PdfCosDict dict,
    PdfCosDict parms, {
    required PdfCos? Function(PdfCos?) resolve,
  }) {
    final header = _read(data);
    final width = resolve(dict['Width']);
    final height = resolve(dict['Height']);
    final bits = resolve(dict['BitsPerComponent']);
    final mask = resolve(dict['ImageMask']);
    if (width is! PdfCosInt || width.value != header.width ||
        height is! PdfCosInt || height.value != header.height ||
        (bits != null && (bits is! PdfCosInt || bits.value != 8)) ||
        (mask is PdfCosBool && mask.value)) {
      _unsupported();
    }
    final rawTransform = resolve(parms['ColorTransform']);
    if (rawTransform != null && rawTransform is! PdfCosNull &&
        (rawTransform is! PdfCosInt ||
            (rawTransform.value != 0 && rawTransform.value != 1))) {
      _unsupported();
    }
    final cs = resolve(dict['ColorSpace']);
    final expected = switch (pdfCosName(cs)) {
      'DeviceGray' || 'G' => 1,
      'DeviceRGB' || 'RGB' => 3,
      'DeviceCMYK' || 'CMYK' => 4,
      _ => null,
    };
    if (expected != null && expected != header.components) {
      _unsupported();
    }
    if (header.components == 4 || (cs != null && expected == null)) {
      return null;
    }
    final gray = header.components == 1;
    // PDF ColorTransform defaults to 1 for three components. An Adobe
    // marker overrides DecodeParms. Give the codec exactly that transform.
    final transform = header.adobe ??
        (rawTransform is PdfCosInt ? rawTransform.value : 1);
    if (!gray && transform != 0 && transform != 1) {
      _unsupported();
    }
    final decode = resolve(dict['Decode']);
    final ranges = <double>[];
    if (decode != null && decode is! PdfCosNull) {
      if (decode is! PdfCosArray ||
          decode.items.length != header.components * 2) {
        _unsupported();
      }
      for (final item in decode.items) {
        final value = pdfCosNumber(resolve(item));
        if (value == null || !value.isFinite) {
          _unsupported();
        }
        ranges.add(value);
      }
    }
    final normalized = BytesBuilder(copy: false)..add(const [0xff, 0xd8]);
    if (!gray) {
      normalized.add([
        0xff, 0xee, 0, 14, 65, 100, 111, 98, 101, 0,
        100, 0, 0, 0, 0, transform,
      ]);
    }
    normalized.add(header.body);
    try {
      final image = img.decodeJpg(normalized.takeBytes(), maxPixels: maxPixels);
      if (image == null || image.width != header.width ||
          image.height != header.height) {
        _unsupported();
      }
      final pixels = image.getBytes(order: img.ChannelOrder.rgb);
      if (pixels.length != header.width * header.height * 3) {
        _unsupported();
      }
      if (ranges.isNotEmpty) {
        for (var i = 0; i < pixels.length; i++) {
          final pair = gray ? 0 : (i % 3) * 2;
          final t = pixels[i] / 255;
          final value = (ranges[pair] * (1 - t) + ranges[pair + 1] * t)
              .clamp(0.0, 1.0);
          pixels[i] = (value * 255).round();
        }
      }
      return PdfDctImage(pixels, isGray: gray);
    } on PdfFilterUnsupported {
      rethrow;
    } catch (_) {
      _unsupported();
    }
  }

  /// Inspect markers before allocating decoder pixels; strip application
  /// metadata so EXIF orientation cannot override the PDF CTM. Entropy
  /// decoding is delegated to image, not implemented by this marker walker.
  static ({
    int width, int height, int components, int? adobe, Uint8List body,
  }) _read(Uint8List data) {
    if (data.length < 4 || data.length > _maxBytes ||
        data[0] != 0xff || data[1] != 0xd8) {
      _unsupported();
    }
    final body = BytesBuilder(copy: false);
    var width = 0, height = 0, components = 0, scans = 0, markers = 0;
    int? adobe;
    var p = 2;
    var inScan = false;
    while (p < data.length) {
      if (++markers > 4096) {
        _unsupported();
      }
      if (inScan) {
        final start = p;
        var found = false;
        while (p < data.length) {
          if (data[p++] != 0xff) {
            continue;
          }
          final markerStart = p - 1;
          while (p < data.length && data[p] == 0xff) {
            p++;
          }
          if (p == data.length) {
            _unsupported();
          }
          final marker = data[p];
          if (marker == 0 || (marker >= 0xd0 && marker <= 0xd7)) {
            p++;
            continue;
          }
          body.add(Uint8List.sublistView(data, start, markerStart));
          p = markerStart;
          found = true;
          break;
        }
        if (!found) {
          _unsupported();
        }
        inScan = false;
      }
      final start = p;
      if (data[p++] != 0xff) {
        _unsupported();
      }
      while (p < data.length && data[p] == 0xff) {
        p++;
      }
      if (p == data.length) {
        _unsupported();
      }
      final marker = data[p++];
      if (marker == 0xd9) {
        if (components == 0 || scans == 0) {
          _unsupported();
        }
        body.add(const [0xff, 0xd9]);
        return (width: width, height: height, components: components,
            adobe: adobe, body: body.takeBytes());
      }
      if (marker == 0 || marker == 1 ||
          (marker >= 0xd0 && marker <= 0xd8) || p + 2 > data.length) {
        _unsupported();
      }
      final length = (data[p] << 8) | data[p + 1];
      final end = p + length;
      if (length < 2 || end > data.length) {
        _unsupported();
      }
      final payload = p + 2;
      final sof = marker >= 0xc0 && marker <= 0xcf &&
          marker != 0xc4 && marker != 0xc8 && marker != 0xcc;
      if (sof) {
        if (components != 0 || scans != 0 ||
            (marker != 0xc0 && marker != 0xc1 && marker != 0xc2) ||
            length < 8 || data[payload] != 8) {
          _unsupported();
        }
        height = (data[payload + 1] << 8) | data[payload + 2];
        width = (data[payload + 3] << 8) | data[payload + 4];
        components = data[payload + 5];
        if (width < 1 || height < 1 ||
            width > maxDimension || height > maxDimension ||
            width * height > maxPixels ||
            (components != 1 && components != 3 && components != 4) ||
            length != 8 + 3 * components) {
          _unsupported();
        }
        var blocks = 0;
        final ids = <int>{};
        for (var i = 0; i < components; i++) {
          final index = payload + 6 + i * 3;
          final sample = data[index + 1];
          final h = sample >> 4, v = sample & 15;
          if (!ids.add(data[index]) || h < 1 || h > 4 ||
              v < 1 || v > 4 || data[index + 2] > 3) {
            _unsupported();
          }
          blocks += h * v;
        }
        if (blocks > 10) {
          _unsupported();
        }
      }
      if (marker == 0xee && length >= 14 &&
          data[payload] == 65 && data[payload + 1] == 100 &&
          data[payload + 2] == 111 && data[payload + 3] == 98 &&
          data[payload + 4] == 101) {
        final transform = data[payload + 11];
        if (transform > 2 || (adobe != null && adobe != transform)) {
          _unsupported();
        }
        adobe = transform;
      }
      if (!(marker >= 0xe0 && marker <= 0xef) && marker != 0xfe) {
        body.add(Uint8List.sublistView(data, start, end));
      }
      if (marker == 0xda) {
        if (components == 0 || ++scans > 128 || length < 6 ||
            data[payload] < 1 || data[payload] > components ||
            length != 6 + 2 * data[payload]) {
          _unsupported();
        }
        inScan = true;
      }
      p = end;
    }
    _unsupported();
  }
}
