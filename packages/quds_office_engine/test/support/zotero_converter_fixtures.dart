import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const zoteroConverterFixtureRoot = 'test/fixtures/zotero/converter';

List<WmlParagraph> converterStory(WmlDocument document, String kind) {
  if (kind == 'footnote') {
    return document.footnotes.single.allParagraphs.toList();
  }
  if (kind == 'cell') {
    final table = document.sections.single.blocks.whereType<WmlTable>().single;
    return WordTree.paragraphs(table.rows.single.cells.first.blocks).toList();
  }
  return document.paragraphs.toList();
}

/// The original converter increment's semantic snapshot, including editability.
/// Its expected JSON is copied byte-for-byte from the original evidence archive.
Map<String, Object?> converterSnapshot(WmlDocument document, String kind) {
  final paragraphs = converterStory(document, kind);
  final selected = <String, Object?>{};
  for (final key in ['HEADING', 'RTL_COLOUR', 'LTR_COLOUR', 'TAIL']) {
    final p = paragraphs.singleWhere((p) => p.text.contains(key));
    selected[key] = {
      'text': p.text.trim(),
      'rtl': p.properties.rightToLeft,
      'alignment': p.properties.justification.name,
      'left': p.properties.indent.left,
      'right': p.properties.indent.right,
      'heading': p.properties.headingLevel,
    };
  }
  final colors = <String, Object?>{};
  for (final key in ['HEADING', 'RTL_COLOUR', 'LTR_COLOUR']) {
    final r = paragraphs
        .expand((p) => p.inlines)
        .whereType<WmlRun>()
        .singleWhere((r) => r.text.contains(key));
    colors[key] = {
      'color': r.properties.color,
      'highlight': r.properties.highlight,
    };
  }
  return {
    'kind': kind,
    'paragraphs': selected,
    'text': paragraphs.map((p) => p.text.trim()).toList(),
    'empty': paragraphs
        .where((p) => p.text.isEmpty)
        .map(
          (p) => {
            'rtl': p.properties.rightToLeft,
            'alignment': p.properties.justification.name,
            'left': p.properties.indent.left,
            'right': p.properties.indent.right,
          },
        )
        .toList(),
    'colors': colors,
    'fields': WordZotero.fields(document)
        .map(
          (f) => {
            'metadata': f.citation!.toJson(),
            'text': f.cachedText,
            'editable': f.canEdit,
            'in_target_story': paragraphs.contains(f.paragraph),
          },
        )
        .toList(),
    'preferences': jsonDecode(WordZoteroDocumentData.read(document)),
    'balanced': WordFieldSpans.unbalanced(document).isEmpty,
  };
}

void expectConverterSnapshot(
  WmlDocument document,
  String kind, {
  Map<String, String> refreshedCitationText = const {},
}) {
  final expected =
      jsonDecode(
            File(
              '$zoteroConverterFixtureRoot/original/$kind.expected.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  // A Refresh intentionally changes citation text and its two cache metadata
  // values. Derive only those expected changes from the unchanged fixture;
  // all paragraph geometry, colors, story ownership and other metadata still
  // use the independently recorded converter snapshot.
  final fields = (expected['fields']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final replaced = <String>{};
  for (final field in fields) {
    final metadata = field['metadata']! as Map<String, Object?>;
    final id = metadata['citationID']! as String;
    final replacement = refreshedCitationText[id];
    if (replacement == null) continue;
    replaced.add(id);
    final previous = field['text']! as String;
    field['text'] = replacement;
    final properties = metadata['properties']! as Map<String, Object?>;
    properties['plainCitation'] = replacement;
    properties['formattedCitation'] = replacement;
    final paragraphs = expected['paragraphs']! as Map<String, Object?>;
    for (final raw in paragraphs.values) {
      final paragraph = raw! as Map<String, Object?>;
      paragraph['text'] = (paragraph['text']! as String).replaceAll(
        previous,
        replacement,
      );
    }
    expected['text'] = [
      for (final text in expected['text']! as List<Object?>)
        (text! as String).replaceAll(previous, replacement),
    ];
  }
  expect(replaced, refreshedCitationText.keys.toSet());
  _expectSnapshot(expected, converterSnapshot(document, kind), kind);
}

void _expectSnapshot(Object? expected, Object? actual, String path) {
  if (expected is Map<String, Object?> && actual is Map<String, Object?>) {
    expect(actual.keys.toSet(), expected.keys.toSet(), reason: path);
    for (final key in expected.keys) {
      _expectSnapshot(expected[key], actual[key], '$path/$key');
    }
  } else if (expected is List<Object?> && actual is List<Object?>) {
    expect(actual.length, expected.length, reason: path);
    for (var i = 0; i < expected.length; i++) {
      _expectSnapshot(expected[i], actual[i], '$path/$i');
    }
  } else if (expected is num && actual is num) {
    expect(actual, closeTo(expected, 0.02), reason: path);
  } else {
    expect(actual, expected, reason: path);
  }
}
