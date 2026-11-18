import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

@JS('qudsSmokeState')
external set _browserState(JSString value);

SemanticsHandle? _semantics;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _semantics = SemanticsBinding.instance.ensureSemantics();
  await OfficeHostFonts.ensureRegistered();
  runApp(const _Fixture());
}

class _Fixture extends StatefulWidget {
  const _Fixture();

  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  final session = DateTime.now().microsecondsSinceEpoch.toString();
  late WordEditorController controller;
  final focus = FocusNode();
  String language = 'en-US';
  String sample = 'bank';
  int sampleRevision = 0;
  bool querying = false;
  Map<String, Object?>? panel;
  String? failure;

  @override
  void initState() {
    super.initState();
    controller = _create('bank', 'en-US');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focus.requestFocus();
      _publish();
    });
  }

  WordEditorController _create(String text, String locale) {
    final document = WmlDocument.empty(text: text)..proofingLanguage = locale;
    final result = WordEditorController(
      document: document,
      config: const OfficeSurfaceConfig(autofocus: true),
    );
    result.selectAll();
    result.addListener(_publish);
    return result;
  }

  void _publish() {
    _browserState = jsonEncode(<String, Object?>{
      'ready': true,
      'session': session,
      'sampleRevision': sampleRevision,
      'language': language,
      'sample': sample,
      'document': controller.document.paragraphs.first.text,
      'canUndo': controller.canUndo,
      'canRedo': controller.canRedo,
      'selection': <String, Object?>{
        'anchor': controller.caret.selectionAnchor,
        'end': controller.caret.logicalIndex,
      },
      'querying': querying,
      'panel': panel,
      'failure': failure,
      'semanticsEnabled': _semantics != null,
      'sharedCache': <String, int>{
        'shards': BundledOfficeThesaurus.shared.cachedShardCount,
        'results': BundledOfficeThesaurus.shared.cachedResultCount,
      },
    }).toJS;
  }

  void _select(String text, String locale) {
    final old = controller;
    old.removeListener(_publish);
    setState(() {
      sampleRevision++;
      language = locale;
      sample = text;
      controller = _create(text, locale);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
      focus.requestFocus();
      _publish();
    });
  }

  Future<void> _queryPanel() async {
    setState(() {
      querying = true;
      panel = null;
      failure = null;
    });
    _publish();
    try {
      final service = BundledOfficeThesaurus.create();
      final queries = <(String, String)>[
        ('bank', 'en-US'),
        ('run', 'en-US'),
        ('happy', 'en-GB'),
        ('ice cream', 'en-US'),
        ('children', 'en-US'),
        ('dogs', 'en-US'),
        ('Bank', 'de-DE'),
        ('Häusern', 'de-DE'),
        ('Maße', 'de-DE'),
        ('Masse', 'de-DE'),
        ('sich freuen', 'de-DE'),
        ('Straße', 'de-CH'),
        ('qudsxyzzynotaword', 'en-US'),
        ('qudsxyzzynotaword', 'de-DE'),
        ('banque', 'fr-FR'),
      ];
      final results = <Map<String, Object?>>[];
      final noticeRecords = <Map<String, Object?>>[];
      for (final (word, locale) in queries) {
        final clock = Stopwatch()..start();
        final result = await service.lookup(
          OfficeThesaurusQuery(text: word, language: locale),
        );
        clock.stop();
        results.add(<String, Object?>{
          'text': word,
          'language': locale,
          'status': result.status.name,
          'message': result.message,
          'elapsed_ms': clock.elapsedMicroseconds / 1000,
          'pack': result.packIdentity,
          'matches': <Map<String, Object?>>[
            for (final match in result.matchedTerms)
              {'text': match.text, 'reason': match.reason, 'pos': match.pos},
          ],
          'senses': <Map<String, Object?>>[
            for (final sense in result.senses)
              {
                'id': sense.id,
                'source': sense.source,
                'pos': sense.pos,
                'gloss': sense.gloss,
                'labels': sense.labels,
                'examples': sense.examples,
                'terms': <Map<String, Object?>>[
                  for (final term in sense.terms)
                    {'id': term.id, 'text': term.text, 'labels': term.labels},
                ],
                'relations': <Map<String, Object?>>[
                  for (final relation in sense.relations)
                    {'type': relation.type, 'target': relation.target},
                ],
              },
          ],
        });
        if (word == 'bank' || word == 'Bank') {
          final notices = await service.notices(result);
          noticeRecords.add(<String, Object?>{
            'locale': result.pack?.locale,
            'pack': result.packIdentity,
            'notices': <Map<String, String>>[
              for (final notice in notices)
                {'path': notice.path, 'text': notice.text},
            ],
          });
        }
      }
      final warmMs = <double>[];
      for (var iteration = 0; iteration < 5; iteration++) {
        for (final (word, locale) in queries) {
          final clock = Stopwatch()..start();
          await service.lookup(
            OfficeThesaurusQuery(text: word, language: locale),
          );
          clock.stop();
          warmMs.add(clock.elapsedMicroseconds / 1000);
        }
      }
      final sorted = List<double>.of(warmMs)..sort();
      panel = <String, Object?>{
        'queries': results,
        'notices': noticeRecords,
        'warm_mode': 'result-cache',
        'warm_ms': warmMs,
        'warm_p50_ms': sorted[(sorted.length * .5).floor()],
        'warm_p95_ms': sorted[(sorted.length * .95).floor()],
        'cached_shards': service.cachedShardCount,
        'cached_results': service.cachedResultCount,
        'cache_limits': <String, int>{
          'shards': service.maxCachedShards,
          'results': service.maxCachedResults,
        },
      };
    } catch (error, stack) {
      failure = '$error\n$stack';
    } finally {
      setState(() => querying = false);
      _publish();
    }
  }

  @override
  void dispose() {
    controller.removeListener(_publish);
    controller.dispose();
    focus.dispose();
    _semantics?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Quds thesaurus acceptance fixture',
    theme: ThemeData(
      fontFamily: 'Liberation Sans',
      colorSchemeSeed: Colors.teal,
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('Quds offline thesaurus')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                FilledButton(
                  onPressed: () => _select('bank', 'en-US'),
                  child: const Text('English sample'),
                ),
                FilledButton(
                  onPressed: () => _select('Bank', 'de-DE'),
                  child: const Text('German sample'),
                ),
                TextButton(
                  onPressed: controller.undo,
                  child: const Text('Undo'),
                ),
                TextButton(
                  onPressed: controller.redo,
                  child: const Text('Redo'),
                ),
                OutlinedButton(
                  onPressed: querying ? null : _queryPanel,
                  child: Text(querying ? 'Querying…' : 'Run query panel'),
                ),
              ],
            ),
          ),
          Expanded(
            child: QudsWordEditor(
              key: ValueKey(controller),
              controller: controller,
              focusNode: focus,
              enableLiveProofing: false,
            ),
          ),
        ],
      ),
    ),
  );
}
