import 'package:quds_office_engine/quds_office_engine.dart';

/// Set an explicit Word line rule and its point value as one native edit.
///
/// Word uses twelve points to express one line for multiple spacing. The
/// native model stores that rule as a multiplier, while exact/minimum spacing
/// remains in points. Owning both values avoids interpreting an old document
/// value according to a different rule.
void setWordLineSpacing(
  WmlDocument document,
  WmlParagraph paragraph, {
  required String rule,
  required double points,
}) {
  final nativeRule = switch (rule) {
    'atLeast' => WmlLineSpacingRule.atLeast,
    'exact' => WmlLineSpacingRule.exact,
    'multiple' => WmlLineSpacingRule.auto,
    _ => throw ArgumentError('rule must be atLeast, exact, or multiple'),
  };
  final twips = points * 20;
  if (!points.isFinite ||
      points <= 0 ||
      twips > 2147483647 ||
      twips.round() / 20 != points) {
    throw ArgumentError(
      'points must be positive exact twentieth-points with at most '
      '2147483647 twips',
    );
  }
  validateWordLineSpacingSource(document, paragraph);
  final properties = paragraph.properties.copy();
  // Preserve sparse ownership of before/after attributes and foreign source
  // metadata. Removing the granular snapshot also records a same-value write
  // as direct formatting, even when its effective value came from a style.
  properties.importedValues?.remove('spacing:line');
  properties.lineSpacingRule = nativeRule;
  properties.lineSpacing = rule == 'multiple' ? points / 12 : points;
  properties.explicitLineSpacing = true;
  paragraph.properties = properties;
}

/// Apply Word's OpenUp, CloseUp, or OpenOrCloseUp to one current paragraph.
///
/// The toggle deliberately runs against the detached native document, after
/// earlier plan operations. Compiling the source does not read document state.
/// Only the before-spacing attribute group becomes direct formatting.
void setWordParagraphSpaceBefore(
  WmlDocument document,
  WmlParagraph paragraph, {
  required String action,
}) {
  if (!const {'open', 'close', 'toggle'}.contains(action)) {
    throw ArgumentError('action must be open, close, or toggle');
  }
  _validateWordSpacingSource(document, paragraph, beforeControl: true);
  final before = paragraph.properties.spacingBefore;
  final twips = before * 20;
  if (!before.isFinite ||
      before < 0 ||
      twips > 2147483647 ||
      twips.round() / 20 != before) {
    throw UnsupportedError(
      'Paragraph spacing controls require nonnegative exact twentieth-points '
      'within signed Long twips.',
    );
  }
  final properties = paragraph.properties.copy();
  properties.importedValues?.remove('spacing:before');
  properties.spacingBefore = switch (action) {
    'open' => 12,
    'close' => 0,
    _ => before == 0 ? 12 : 0,
  };
  properties.explicitSpacingBefore = true;
  paragraph.properties = properties;
}

const _w = OfficeNamespaces.w;

bool _word(XmlElement node, String name) =>
    node.localName == name && node.namespaceUri == _w;

/// Validate source ownership and serialization boundaries before any native
/// line-spacing edit, including presets in the general paragraph operation.
void validateWordLineSpacingSource(
  WmlDocument document,
  WmlParagraph paragraph,
) => _validateWordSpacingSource(document, paragraph);

void _validateWordSpacingSource(
  WmlDocument document,
  WmlParagraph paragraph, {
  bool beforeControl = false,
}) {
  if (WordFieldSpans.unbalanced(document).isNotEmpty) {
    throw UnsupportedError(
      'Line-spacing edits cannot preserve unbalanced modeled field boundaries.',
    );
  }
  final source = paragraph.properties.sourcePropertiesXml;
  if (source != null && source.isNotEmpty) {
    final wrapper = XmlDocument.parse(
      '<w:context xmlns:w="$_w">$source</w:context>',
    ).root!;
    final roots = wrapper.childElements.toList(growable: false);
    if (roots.length != 1 || !_word(roots.single, 'pPr')) {
      throw UnsupportedError(
        'Line-spacing edits require unambiguous native paragraph properties.',
      );
    }
    _checkElement(roots.single, beforeControl: beforeControl);
  }
  for (final part in document.package?.parts ?? <PackagePart>[]) {
    if (!part.contentType.endsWith('+xml') ||
        (!part.contentType.contains('wordprocessingml') &&
            !part.contentType.contains('vnd.ms-word'))) {
      continue;
    }
    final source = part.readText();
    if (!beforeControl &&
        !source.contains('spacing') &&
        !source.contains('pPr')) {
      continue;
    }
    final root = XmlDocument.parse(source).root;
    if (root == null) {
      throw UnsupportedError('Missing native Word XML root.');
    }
    _checkElement(root, beforeControl: beforeControl);
  }
}

void _checkElement(
  XmlElement element, {
  bool alternative = false,
  bool paragraphProperties = false,
  bool beforeControl = false,
  bool unmodeledBefore = false,
}) {
  final isAlternative =
      element.localName == 'AlternateContent' &&
      element.namespaceUri == OfficeNamespaces.mc;
  final insideAlternative = alternative || isAlternative;
  final isParagraphProperties = _word(element, 'pPr');
  final insideProperties = paragraphProperties || isParagraphProperties;
  if (beforeControl && _word(element, 'styles')) {
    _checkBeforeStyleIdentities(element);
  }
  // The live cascade does not project paragraph spacing from numbering
  // levels or these conditional table regions. A toggle cannot infer it.
  final unsupportedRegion =
      unmodeledBefore ||
      _word(element, 'lvl') ||
      (_word(element, 'tblStylePr') &&
          !const {
            'wholeTable',
            'band1Horz',
            'band2Horz',
            'firstRow',
          }.contains(element.getAttribute('type', namespaceUri: _w)));
  if ((isAlternative && paragraphProperties) ||
      (insideAlternative && isParagraphProperties)) {
    throw UnsupportedError(
      'Line-spacing edits cannot preserve alternative paragraph-property packets.',
    );
  }
  if (element.localName == 'spacing' && insideAlternative) {
    // Even a foreign spacing lookalike may be discarded when the reader
    // selects an alternative. Refuse rather than claiming to preserve a
    // property packet whose opaque branch is not retained by this model.
    throw UnsupportedError(
      'Line-spacing edits do not resolve spacing-bearing '
      'markup-compatibility alternatives.',
    );
  }
  if (_word(element, 'spacing')) {
    for (final name in const ['line', 'lineRule']) {
      if (element.attributes
              .where((a) => a.localName == name && a.namespaceUri == _w)
              .length >
          1) {
        throw UnsupportedError('Ambiguous duplicate native spacing $name.');
      }
    }
    if (beforeControl) {
      _checkBeforeSpacing(element, unmodeled: unsupportedRegion);
    }
  }
  if (_word(element, 'pPr') &&
      element.childElements.where((child) => _word(child, 'spacing')).length >
          1) {
    throw UnsupportedError('Ambiguous duplicate native paragraph spacing.');
  }
  if (_word(element, 'p') &&
      element.childElements.where((child) => _word(child, 'pPr')).length > 1) {
    throw UnsupportedError('Ambiguous duplicate native paragraph properties.');
  }
  for (final child in element.childElements) {
    _checkElement(
      child,
      alternative: insideAlternative,
      paragraphProperties: insideProperties,
      beforeControl: beforeControl,
      unmodeledBefore: unsupportedRegion,
    );
  }
}

void _checkBeforeStyleIdentities(XmlElement root) {
  String? attribute(XmlElement element, String name) {
    final matches = element.attributes.where(
      (a) => a.localName == name && a.namespaceUri == _w,
    );
    if (matches.length > 1) {
      throw UnsupportedError('Ambiguous duplicate native style attribute.');
    }
    return matches.firstOrNull?.value;
  }

  final styles = <String, String?>{};
  var defaults = 0;
  for (final style in root.childElements.where(
    (node) => _word(node, 'style'),
  )) {
    final id = attribute(style, 'styleId');
    if (id == null || id.isEmpty || styles.containsKey(id)) {
      throw UnsupportedError(
        'Paragraph spacing controls require unique nonempty native style IDs.',
      );
    }
    final defaultValue = attribute(style, 'default');
    if (defaultValue != null &&
        !const {
          '0',
          '1',
          'false',
          'true',
          'off',
          'on',
        }.contains(defaultValue)) {
      throw UnsupportedError('Ambiguous native default-style flag.');
    }
    if (attribute(style, 'type') == 'paragraph' &&
        const {'1', 'true', 'on'}.contains(defaultValue)) {
      defaults++;
    }
    final parents = style.childElements.where((node) => _word(node, 'basedOn'));
    if (parents.length > 1) {
      throw UnsupportedError('Ambiguous duplicate native style inheritance.');
    }
    final parent = parents.firstOrNull;
    final parentId = parent == null ? null : attribute(parent, 'val');
    if (parent != null && (parentId == null || parentId.isEmpty)) {
      throw UnsupportedError('Missing native style inheritance reference.');
    }
    styles[id] = parentId;
  }
  if (defaults > 1) {
    throw UnsupportedError('Ambiguous multiple default paragraph styles.');
  }
  final resolved = <String>{};
  for (final id in styles.keys) {
    final chain = <String>{};
    String? current = id;
    while (current != null && !resolved.contains(current)) {
      if (!styles.containsKey(current) || !chain.add(current)) {
        throw UnsupportedError(
          'Paragraph spacing controls require complete acyclic style inheritance.',
        );
      }
      current = styles[current];
    }
    resolved.addAll(chain);
  }
}

void _checkBeforeSpacing(XmlElement element, {required bool unmodeled}) {
  final values = <String, String>{};
  for (final attribute in element.attributes) {
    if (attribute.namespaceUri != _w ||
        !const {
          'before',
          'beforeLines',
          'beforeAutospacing',
        }.contains(attribute.localName)) {
      continue;
    }
    if (values.containsKey(attribute.localName)) {
      throw UnsupportedError('Ambiguous duplicate native before spacing.');
    }
    values[attribute.localName] = attribute.value;
  }
  if (values.isEmpty) return;
  if (unmodeled || values.containsKey('beforeLines')) {
    throw UnsupportedError(
      'Paragraph spacing controls do not resolve line-based before spacing, '
      'numbering-level spacing, or unsupported conditional table regions.',
    );
  }
  final automatic = values['beforeAutospacing'];
  if (automatic != null && !const {'0', 'false', 'off'}.contains(automatic)) {
    throw UnsupportedError(
      'Paragraph spacing controls do not resolve automatic before spacing.',
    );
  }
  final raw = values['before'];
  if (raw == null) return;
  final twips = RegExp(r'^\+?[0-9]+$').hasMatch(raw) ? int.tryParse(raw) : null;
  if (twips == null || twips > 2147483647) {
    throw UnsupportedError(
      'Paragraph spacing controls require native before spacing in '
      'nonnegative integer twips within signed Long range.',
    );
  }
}
