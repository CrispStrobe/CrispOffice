import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import '../quds_office_suite/packages/quds_office_editor/example/lib/studio_zotero.dart';

Future<void> main() async {
  final transport = StudioZoteroTransport();
  final client = ZoteroClient.local(transport: transport.send);
  try {
    await client.probeLocal();
    final library = ZoteroLibrary.localUser();
    final all = await client.items(library);
    final search = await client.items(library, query: 'Native Acceptance Alpha');
    final collections = await client.collections(library);
    if (all.items.length != 3 || search.items.length != 1) {
      throw StateError('Synthetic catalog or search did not match the fixture.');
    }
    final collection = collections.items.single;
    final members = await client.items(library, collectionKey: collection.key);
    if (members.items.length != 3 || all.items.any((i) => i.citationUri == null || i.cslJson == null)) {
      throw StateError('The native catalog did not supply linked CSL sources.');
    }
    final output = {
      'result': 'passed',
      'uses_actual_studio_transport': true,
      'uses_actual_zotero_client': true,
      'catalog_count': all.items.length,
      'search_count': search.items.length,
      'collection_count': collections.items.length,
      'collection_members': members.items.length,
      'items': [for (final item in all.items) {
        'key': item.key,
        'title': item.title,
        'uri': item.citationUri.toString(),
        'csl': item.cslJson,
      }],
    };
    File('/workspace/scratch/7b8555dd0115/zotero-native-acceptance/logs/catalog-client-result.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));
    stdout.writeln('PASS: real Zotero catalog browse, collection, search and linked CSL data');
  } finally {
    transport.dispose();
  }
}
