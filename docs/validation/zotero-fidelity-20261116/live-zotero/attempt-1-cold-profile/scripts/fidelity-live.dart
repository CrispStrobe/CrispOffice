import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_studio/studio_zotero.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Map<String, Object?> paragraphState(WmlParagraph paragraph) => {
  'text': paragraph.text,
  'left': paragraph.properties.indent.left,
  'hanging': paragraph.properties.indent.hanging,
  'firstLine': paragraph.properties.indent.firstLine,
  'spacingBefore': paragraph.properties.spacingBefore,
  'spacingAfter': paragraph.properties.spacingAfter,
  'lineSpacing': paragraph.properties.lineSpacing,
  'lineSpacingRule': paragraph.properties.lineSpacingRule.name,
  'tabs': [for (final tab in paragraph.properties.tabs) tab.position],
  'runs': [
    for (final run in paragraph.inlines.whereType<WmlRun>())
      {
        'text': run.text,
        'italic': run.properties.italic,
        'bold': run.properties.bold,
        'smallCaps': run.properties.smallCaps,
      },
  ],
};

Map<String, Object?> documentState(WmlDocument document) => {
  'preferences': WordZoteroDocumentData.read(document),
  'body': [for (final p in document.paragraphs) paragraphState(p)],
  'notes': [
    for (final note in document.footnotes)
      [for (final p in note.paragraphs) paragraphState(p)],
  ],
  'fields': [
    for (final field in WordZotero.fields(document))
      {'code': field.instruction, 'text': field.cachedText},
  ],
};

WmlDocument fixture(List<ZoteroItem> items, String style, String sessionId) {
  final alpha = items.singleWhere((item) => item.title.endsWith('Alpha'));
  final beta = items.singleWhere((item) => item.title.endsWith('Beta'));
  final document = WmlDocument.empty(text: 'Synthetic fidelity source ');
  final anchor = document.paragraphs.single;
  for (var i = 0; i < 4; i++) {
    final source = i == 3 ? beta : alpha;
    final note = WordNotes.insert(document, anchor, endnote: false, text: '');
    WordZotero.insertCitation(
      note.paragraphs.single,
      ZoteroCitation(
        citationId: '$sessionId-${i + 1}',
        noteIndex: i + 1,
        plainCitation: 'Before native refresh ${i + 1}',
        items: [
          ZoteroCitationItem.fromCsl(
            itemData: source.cslJson!,
            uris: [source.citationUri.toString()],
            locator: i == 2 ? '34' : '12',
            label: 'page',
          ),
        ],
      ),
    );
  }
  document.sections.single.blocks.add(
    WordZotero.bibliography(text: 'Before native bibliography refresh'),
  );
  document.sections.single.blocks.add(
    WmlParagraph(inlines: [WmlRun(text: 'After bibliography.')]),
  );
  // This is the exact native XML vocabulary returned by Zotero 10.0.8 in the
  // previous acceptance, with a fresh synthetic session and style layout unset.
  document.zoteroDocumentData =
      '<data data-version="3" zotero-version="10.0.8">'
      '<session id="$sessionId"/>'
      '<style id="http://www.zotero.org/styles/$style" locale="de-DE" '
      'hasBibliography="1" bibliographyStyleHasBeenSet="0"/>'
      '<prefs><pref name="fieldType" value="Field"/>'
      '<pref name="automaticJournalAbbreviations" value="true"/>'
      '<pref name="noteType" value="1"/></prefs></data>';
  return document;
}

Future<WmlDocument> refresh({
  required Directory base,
  required StudioZoteroTransport transport,
  required WmlDocument document,
  required String label,
  required double expectedLines,
  required bool smallCaps,
  required bool expectLayoutCallback,
}) async {
  final trace = File('${base.path}/logs/$label-protocol.jsonl').openWrite();
  final id = 'quds-fidelity-$label-20261116';
  final before = jsonEncode(documentState(document));
  final beforeBytes = WordSerializer().writeBytes(document);
  File('${base.path}/$label-before.docx').writeAsBytesSync(beforeBytes);
  final anchor = document.paragraphs.first;
  final session = WordZoteroCitingSession(
    document: document,
    documentId: id,
    insertionParagraph: anchor,
    insertionOffset: anchor.text.length,
  );
  final layoutCallbacks = <List<dynamic>>[];
  final client = ZoteroCitingClient(
    requestTimeout: const Duration(seconds: 45),
    transport: (request) async {
      trace.writeln(
        jsonEncode({'send': request.uri.path, 'body': request.body}),
      );
      await trace.flush();
      final response = await transport.send(request);
      trace.writeln(
        jsonEncode({'receive': response.statusCode, 'body': response.body}),
      );
      await trace.flush();
      return response;
    },
  );
  try {
    await client.execute(
      command: ZoteroCitingCommand.refresh,
      documentId: id,
      guard: session.assertUnchanged,
      handler: (name, args) {
        if (name == 'Document.displayAlert') {
          throw StateError(
            'Unexpected native alert in unattended fixture: $args',
          );
        }
        if (name == 'Document.setBibliographyStyle') {
          layoutCallbacks.add(List<dynamic>.from(args));
        }
        final result = session.handle(name, args);
        trace.writeln(jsonEncode({'handled': name, 'result': result}));
        return result;
      },
    );
    require(
      jsonEncode(documentState(document)) == before,
      'Native processing changed the source before staged apply',
    );
    session.prepareReview();
    require(
      session.formattingWarnings.isEmpty,
      'Supported style still needs formatting simplification: '
      '${session.formattingWarnings}',
    );
    require(
      expectLayoutCallback
          ? layoutCallbacks.length == 1
          : layoutCallbacks.isEmpty,
      'Unexpected bibliography callback count: ${layoutCallbacks.length}',
    );
    session.apply();
    final bytes = WordSerializer().writeBytes(document);
    File('${base.path}/$label-refreshed.docx').writeAsBytesSync(bytes);
    final reopened = WordDeserializer().readBytes(bytes);
    final fields = WordZotero.fields(reopened).toList();
    final citations = fields
        .where((f) => f.kind == ZoteroFieldKind.citation)
        .toList();
    final bibliography = fields.singleWhere(
      (f) => f.kind == ZoteroFieldKind.bibliography,
    );
    final text = citations.map((citation) => citation.cachedText).toList();
    require(
      text.length == 4,
      'Native refresh did not retain all four citations',
    );
    require(
      text[1] == 'Ebd.' && text[2] == 'Ebd., 34.',
      'Unexpected German repeated citations: $text',
    );
    require(
      bibliography.paragraphs.length == 2,
      'Expected two actual bibliography entry paragraphs',
    );
    require(
      WordZotero.canReplaceNativeBibliography(reopened, bibliography),
      'Reopened bibliography is not safely refreshable',
    );
    for (final paragraph in bibliography.paragraphs) {
      final props = paragraph.properties;
      require(
        !paragraph.text.contains('\n'),
        'Entry break remained an inline newline',
      );
      require(
        props.indent.left == 36 &&
            props.indent.hanging == 36 &&
            props.indent.firstLine == 0,
        'Native hanging indent did not survive DOCX: ${paragraphState(paragraph)}',
      );
      require(
        props.lineSpacing == expectedLines &&
            props.lineSpacingRule == WmlLineSpacingRule.auto,
        'Native line spacing did not survive DOCX: ${paragraphState(paragraph)}',
      );
      require(
        props.spacingBefore == 0 && props.spacingAfter == 12,
        'Native entry spacing did not survive DOCX: ${paragraphState(paragraph)}',
      );
    }
    require(
      reopened.paragraphs.last.text == 'After bibliography.',
      'Bibliography replacement changed following text',
    );
    final firstRuns = citations.first.paragraphs
        .expand((p) => p.inlines.whereType<WmlRun>())
        .toList();
    require(
      firstRuns.any(
        (r) =>
            r.text.contains('Synthetic Native Fidelity Alpha') &&
            r.properties.italic,
      ),
      'Native italic title did not survive DOCX',
    );
    if (smallCaps) {
      require(
        firstRuns.any(
          (r) => r.text.contains('Beispiel') && r.properties.smallCaps,
        ),
        'Native citation small caps did not survive DOCX',
      );
      require(
        bibliography.paragraphs.every(
          (p) =>
              p.inlines.whereType<WmlRun>().any((r) => r.properties.smallCaps),
        ),
        'Native bibliography small caps did not survive DOCX',
      );
      require(
        firstRuns.any(
          (r) =>
              r.text.contains('Synthetic Native Fidelity Alpha') &&
              !r.properties.smallCaps,
        ),
        'Small caps leaked into the ordinary italic title',
      );
    }
    require(
      WordZoteroDocumentData.stylePreferences(
            WordZoteroDocumentData.read(reopened),
          )?.locale ==
          'de-DE',
      'Native German document preferences did not survive DOCX',
    );
    File('${base.path}/logs/$label-result.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'result': 'passed',
        'real_native_processor': true,
        'actual_studio_transport': true,
        'actual_word_adapter': true,
        'staged_until_apply': true,
        'docx_saved_reopened': true,
        'native_layout_callbacks': layoutCallbacks,
        'layout_callback_expected': expectLayoutCallback,
        'expected_lines': expectedLines,
        'small_caps_expected': smallCaps,
        'warnings': session.formattingWarnings.toList(),
        'citations': text,
        'bibliography_entries': bibliography.paragraphs
            .map(paragraphState)
            .toList(),
        'first_citation_runs': firstRuns
            .map(
              (r) => {
                'text': r.text,
                'italic': r.properties.italic,
                'smallCaps': r.properties.smallCaps,
              },
            )
            .toList(),
        'native_preferences': WordZoteroDocumentData.read(reopened),
      }),
    );
    stdout.writeln(
      'PASS: $label native refresh, Ebd., entry paragraphs/layout, rich runs, DOCX reopen',
    );
    return reopened;
  } finally {
    await trace.close();
  }
}

Future<void> main(List<String> args) async {
  final base = Directory(args.single).absolute;
  final transport = StudioZoteroTransport(
    integrationTimeout: const Duration(seconds: 45),
  );
  final catalogTrace = File('${base.path}/logs/catalog-protocol.jsonl')
      .openWrite();
  final catalog = ZoteroClient.local(
    transport: (request) async {
      final response = await transport.send(request);
      catalogTrace.writeln(
        jsonEncode({
          'uri': request.uri.toString(),
          'status': response.statusCode,
          'body': response.body,
        }),
      );
      await catalogTrace.flush();
      return response;
    },
  );
  try {
    await catalog.probeLocal();
    final library = ZoteroLibrary.localUser();
    final items = await catalog.items(library);
    require(
      items.items.length == 3,
      'Expected exactly three synthetic sources',
    );
    require(
      items.items.every((i) => i.citationUri != null && i.cslJson != null),
      'Missing durable citation identities',
    );
    final searches = await catalog.savedSearches(library);
    final search = searches.items.single;
    require(
      search.key == 'QUDSABCD' && search.name == 'Synthetic Alpha saved search',
      'Unexpected saved search',
    );
    final matches = await catalog.savedSearchItems(
      library,
      search.key,
      limit: 1,
    );
    require(
      matches.items.length == 1 && matches.items.single.title.endsWith('Alpha'),
      'Native saved-search execution did not match its condition',
    );
    final excluded = await catalog.savedSearchItems(
      library,
      search.key,
      query: 'Beta',
    );
    require(
      excluded.items.isEmpty,
      'Additional query escaped the saved-search condition',
    );
    File('${base.path}/logs/catalog-result.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'result': 'passed',
        'actual_zotero_client': true,
        'actual_studio_transport': true,
        'catalog_count': items.items.length,
        'saved_search': {'key': search.key, 'name': search.name},
        'saved_search_matches': matches.items.map((i) => i.title).toList(),
        'additional_query_matches': excluded.items.length,
        'items': [
          for (final item in items.items)
            {
              'key': item.key,
              'title': item.title,
              'uri': item.citationUri.toString(),
              'csl': item.cslJson,
            },
        ],
      }),
    );
    stdout.writeln(
      'PASS: live local catalog and saved-search listing, condition execution and filtered query',
    );
    for (final (style, prefix, lines, caps, sessionId) in [
      (
        'chicago-notes-bibliography-subsequent-ibid',
        'chicago',
        1.0,
        false,
        'QDSCHIC1',
      ),
      ('quds-synthetic-smallcaps', 'smallcaps', 2.0, true, 'QDSCAPS1'),
    ]) {
      final first = await refresh(
        base: base,
        transport: transport,
        document: fixture(items.items, style, sessionId),
        label: '$prefix-first',
        expectedLines: lines,
        smallCaps: caps,
        expectLayoutCallback: true,
      );
      await refresh(
        base: base,
        transport: transport,
        document: first,
        label: '$prefix-repeat',
        expectedLines: lines,
        smallCaps: caps,
        expectLayoutCallback: false,
      );
    }
    File('${base.path}/logs/result.json').writeAsStringSync(
      jsonEncode({
        'result': 'passed',
        'live_catalog_saved_search': true,
        'native_style_scenarios': 2,
        'native_refresh_transactions': 4,
        'private_account_connected': false,
        'synthetic_sources_only': true,
        'full_native_application_build': false,
      }),
    );
  } catch (error, stack) {
    File('${base.path}/logs/failure.txt').writeAsStringSync('$error\n$stack');
    rethrow;
  } finally {
    await catalogTrace.close();
    transport.dispose();
  }
}
