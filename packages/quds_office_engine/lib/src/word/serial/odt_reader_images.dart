import 'dart:convert';
import 'dart:typed_data';

import '../../odf/odf_text.dart';
import '../../opc/zip/zip_reader.dart';
import '../../visual/office_visual.dart';
import '../../xml/xml_node.dart';
import '../model/word_zotero_note_image.dart';
import 'odt_reader_styles.dart';

const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _svg = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';
const _xml = 'http://www.w3.org/XML/1998/namespace';

/// Shared bounded raster qualification for native ODT pictures.
///
/// Each instance owns the existing Zotero note raster budgets for a complete
/// document. The same bytes, dimensions, orientation and pixel validation apply
/// to native ODT input and the explicit editable Zotero copy export.
final class OdtInlineImageValidator {
  final _reader = WordZoteroNoteImageReader();

  OfficeVisual decode(
    Uint8List bytes, {
    required double width,
    required double height,
    String title = '',
    String description = '',
  }) {
    if (bytes.length > WordZoteroNoteImageReader.maxImageBytes) {
      throw const FormatException('ODT inline picture exceeds 4 MiB.');
    }
    if (!width.isFinite ||
        !height.isFinite ||
        width < 1 ||
        height < 1 ||
        width > 4000 ||
        height > 4000) {
      throw const FormatException(
        'ODT inline picture dimensions are out of bounds.',
      );
    }
    final mime = bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80
        ? 'image/png'
        : bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8
        ? 'image/jpeg'
        : throw UnsupportedError(
            'ODT inline pictures require PNG or JPEG data.',
          );
    // The reused decoder accepts CSS pixels, while ODF/native extents use
    // points. Retain exact admitted ODF extents after byte/raster validation.
    final visual = _reader.read({
      'src': 'data:$mime;base64,${base64.encode(bytes)}',
      'width': (width / 0.75).toString(),
      'height': (height / 0.75).toString(),
      'title': title,
      'alt': description,
    });
    visual.width = width;
    visual.height = height;
    return visual;
  }

  void validateVisual(OfficeVisual visual) {
    final picture = visual.picture;
    if (!visual.isPicture ||
        visual.imageBytes == null ||
        visual.offsetX != 0 ||
        visual.offsetY != 0 ||
        picture.wrap != PictureWrap.inline ||
        picture.cropLeft != 0 ||
        picture.cropTop != 0 ||
        picture.cropRight != 0 ||
        picture.cropBottom != 0 ||
        picture.rotationDeg != 0 ||
        picture.brightness != 0 ||
        picture.contrast != 1 ||
        picture.transparency != 0 ||
        picture.borderColor.isNotEmpty ||
        picture.borderWidth != 0 ||
        picture.flipH ||
        picture.flipV ||
        picture.shadow) {
      throw UnsupportedError(
        'Editable Zotero ODT requires unadjusted inline PNG or JPEG pictures.',
      );
    }
    decode(
      visual.imageBytes!,
      width: visual.width,
      height: visual.height,
      title: picture.altTitle,
      description: picture.altDescription,
    );
  }
}

/// Reads only complete, embedded, character-anchored raster picture frames.
/// Floating drawings, external URLs, transformations, image maps, OLE, SVG,
/// text boxes and multiple image alternatives remain explicit refusals.
final class OdtReaderImages {
  OdtReaderImages(this.zip, this.styles);

  final ZipReader zip;
  final OdtReaderStyles styles;
  final _rasters = OdtInlineImageValidator();

  OfficeVisual read(XmlElement frame) {
    _attributes(frame, {
      odfTextNamespace: {'anchor-type'},
      _draw: {'name', 'style-name'},
      _svg: {'width', 'height'},
      _xml: {'id'},
    });
    if (frame.getAttribute('anchor-type', namespaceUri: odfTextNamespace) !=
        'as-char') {
      throw UnsupportedError(
        'Only character-anchored ODT pictures are supported.',
      );
    }
    _graphicStyle(frame.getAttribute('style-name', namespaceUri: _draw));
    final width = _dimension(frame.getAttribute('width', namespaceUri: _svg));
    final height = _dimension(frame.getAttribute('height', namespaceUri: _svg));
    XmlElement? image;
    String? title;
    String? description;
    for (final child in frame.children) {
      if (child is XmlText || child is XmlCdata) {
        final value = child is XmlText ? child.text : (child as XmlCdata).text;
        if (value.trim().isNotEmpty) _unsupported();
      } else if (child is XmlElement) {
        if (child.namespaceUri == _draw && child.localName == 'image') {
          if (image != null) _unsupported();
          image = child;
        } else if (child.namespaceUri == _svg &&
            (child.localName == 'title' || child.localName == 'desc')) {
          _attributes(child, {});
          if (child.childElements.isNotEmpty) _unsupported();
          if (child.localName == 'title') {
            if (title != null) _unsupported();
            title = child.text;
          } else {
            if (description != null) _unsupported();
            description = child.text;
          }
        } else {
          _unsupported();
        }
      }
    }
    if (image == null) _unsupported();
    _attributes(image, {
      _xlink: {'href', 'type', 'show', 'actuate'},
      _draw: {'mime-type'},
    });
    if (image.childElements.isNotEmpty || image.text.trim().isNotEmpty) {
      _unsupported();
    }
    for (final entry in {
      'type': 'simple',
      'show': 'embed',
      'actuate': 'onLoad',
    }.entries) {
      final value = image.getAttribute(entry.key, namespaceUri: _xlink);
      if (value != null && value != entry.value) _unsupported();
    }
    final path = _packagePath(image.getAttribute('href', namespaceUri: _xlink));
    if (!zip.contains(path)) {
      throw const FormatException('Missing embedded ODT picture.');
    }
    final bytes = zip.read(
      path,
      maxBytes: WordZoteroNoteImageReader.maxImageBytes,
    );
    final visual = _rasters.decode(
      bytes,
      width: width,
      height: height,
      title: title ?? '',
      description: description ?? '',
    );
    final declaredMime = image.getAttribute('mime-type', namespaceUri: _draw);
    if (declaredMime != null &&
        declaredMime != (bytes[0] == 137 ? 'image/png' : 'image/jpeg')) {
      throw const FormatException(
        'ODT picture MIME type does not match its bytes.',
      );
    }
    visual.title =
        frame.getAttribute('name', namespaceUri: _draw) ?? title ?? '';
    return visual;
  }

  void _graphicStyle(String? name) {
    // Effective graphic values need explicit mappings before they can be
    // accepted. Empty inherited graphic styles carry no presentation changes.
    for (final definition in styles.styleChain('graphic', name)) {
      for (final properties in definition.childElements) {
        if (properties.namespaceUri != _style ||
            properties.localName != 'graphic-properties') {
          _unsupported();
        }
        _attributes(properties, {});
        if (properties.childElements.isNotEmpty ||
            properties.text.trim().isNotEmpty) {
          _unsupported();
        }
      }
    }
  }

  static String _packagePath(String? href) {
    if (href == null || href.isEmpty || href.length > 2048) _unsupported();
    final uri = Uri.tryParse(href);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        href.startsWith('/') ||
        href.contains('\\')) {
      _unsupported();
    }
    // Uri normalizes dot segments during parsing. Check the original decoded
    // segments before any normalization so an alias cannot traverse or escape
    // the explicit package picture namespace.
    final segments = href.split('/').map(Uri.decodeComponent).toList();
    if (segments.length < 2 ||
        segments.first != 'Pictures' ||
        segments.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains('\\') ||
              part.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f),
        )) {
      _unsupported();
    }
    return segments.join('/');
  }

  static double _dimension(String? value) {
    if (value == null || value.length > 32) _unsupported();
    final match = RegExp(
      r'^((?:\d+(?:\.\d*)?|\.\d+))(pt|in|cm|mm|pc)$',
    ).firstMatch(value);
    if (match == null) _unsupported();
    final factor = switch (match.group(2)) {
      'in' => 72.0,
      'cm' => 72 / 2.54,
      'mm' => 72 / 25.4,
      'pc' => 12.0,
      _ => 1.0,
    };
    final points = double.parse(match.group(1)!) * factor;
    if (!points.isFinite || points < 1 || points > 4000) _unsupported();
    return points;
  }
}

void _attributes(XmlElement element, Map<String, Set<String>> allowed) {
  for (final attribute in element.attributes) {
    if (attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns') {
      continue;
    }
    if (allowed[attribute.namespaceUri]?.contains(attribute.localName) !=
        true) {
      _unsupported();
    }
  }
}

Never _unsupported() => throw UnsupportedError(
  'Native ODT inline picture properties or package reference are unsupported.',
);
