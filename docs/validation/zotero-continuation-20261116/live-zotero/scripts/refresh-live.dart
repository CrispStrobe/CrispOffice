import 'dart:convert';
import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';
import '../quds_office_suite/packages/quds_office_editor/example/lib/studio_zotero.dart';

const base = '/workspace/scratch/7b8555dd0115/zotero-native-acceptance';
Future<void> main() async {
  final trace = File('$base/logs/refresh-protocol.jsonl').openWrite();
  final transport = StudioZoteroTransport(integrationTimeout: const Duration(seconds: 90));
  final catalog = jsonDecode(File('$base/logs/catalog-client-result.json').readAsStringSync()) as Map<String, dynamic>;
  final alpha = (catalog['items'] as List).cast<Map<String, dynamic>>().singleWhere((v) => (v['title'] as String).endsWith('Alpha'));
  final document = WmlDocument.empty(text: 'Synthetic native acceptance ');
  final body = document.paragraphs.single;
  for (var i=0; i<3; i++) {
    final note = WordNotes.insert(document, body, endnote: false, text: '');
    WordZotero.insertCitation(note.paragraphs.single, ZoteroCitation(
      citationId: 'live-native-${i+1}', noteIndex: i+1, plainCitation: 'Before native refresh ${i+1}',
      items: [ZoteroCitationItem.fromCsl(itemData: alpha['csl'] as Map<String,dynamic>, uris: [alpha['uri'] as String], locator: i == 2 ? '34' : '12', label: 'page')],
    ));
  }
  document.sections.single.blocks.add(WordZotero.bibliography(text: 'Before native bibliography refresh'));
  document.zoteroDocumentData = jsonEncode({
    'dataVersion':4, 'sessionID':'quds-isolated-native-20261116',
    'style': {'styleID':'http://www.zotero.org/styles/chicago-notes-bibliography-subsequent-ibid','locale':'de-DE','hasBibliography':true},
    'prefs': {'fieldType':'Field','noteType':1,'automaticJournalAbbreviations':true}
  });
  const id='quds-isolated-native-refresh-20261116';
  final session=WordZoteroCitingSession(document:document, documentId:id, insertionParagraph:body, insertionOffset:body.text.length);
  final before = WordZotero.fields(document).map((f)=>f.cachedText).toList();
  File('$base/native-before.docx').writeAsBytesSync(WordSerializer().writeBytes(document));
  try {
    final client=ZoteroCitingClient(requestTimeout:const Duration(seconds:90), transport:(request) async {
      trace.writeln(jsonEncode({'send':request.uri.path,'body':request.body}));
      await trace.flush();
      final response=await transport.send(request);
      trace.writeln(jsonEncode({'receive':response.statusCode,'body':response.body}));
      await trace.flush();
      return response;
    });
    await client.execute(command:ZoteroCitingCommand.refresh, documentId:id, guard:session.assertUnchanged, handler:(name,args) {
      if(name == 'Document.displayAlert') {
        trace.writeln(jsonEncode({'alert':args,'response':args[3] == 0 ? 1 : 0}));
        return args[3] == 0 ? 1 : 0;
      }
      final result=session.handle(name,args);
      trace.writeln(jsonEncode({'handled':name,'result':result}));
      return result;
    });
    if (jsonEncode(WordZotero.fields(document).map((f)=>f.cachedText).toList()) != jsonEncode(before)) throw StateError('Staged processing changed source before apply');
    session.prepareReview();
    final warnings=session.formattingWarnings.toList();
    session.apply();
    final bytes=WordSerializer().writeBytes(document);
    File('$base/native-refreshed.docx').writeAsBytesSync(bytes);
    final reopened=WordDeserializer().readBytes(bytes);
    final citations=WordZotero.fields(reopened).where((f)=>f.kind == ZoteroFieldKind.citation).toList();
    final bibliography=WordZotero.fields(reopened).where((f)=>f.kind == ZoteroFieldKind.bibliography).single;
    final text=citations.map((f)=>f.cachedText).toList();
    if(text.length != 3 || text[1] != 'Ebd.' || text[2] != 'Ebd., 34.') throw StateError('Unexpected real processor German output: $text');
    if(!bibliography.cachedText.contains('Synthetic Native Acceptance Alpha')) throw StateError('Bibliography was not refreshed');
    if(WordZoteroDocumentData.stylePreferences(WordZoteroDocumentData.read(reopened))?.locale != 'de-DE') throw StateError('Document style did not survive DOCX');
    File('$base/logs/refresh-result.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'result':'passed','real_native_processor':true,'actual_studio_transport':true,'actual_word_adapter':true,
      'staged_until_apply':true,'docx_saved_reopened':true,'citations':text,'bibliography':bibliography.cachedText,'review_warnings':warnings,
      'native_preferences':WordZoteroDocumentData.read(reopened),'note_ids':reopened.footnotes.map((n)=>n.id).toList()
    }));
    stdout.writeln('PASS: native Zotero refresh, German Ebd./page locators, bibliography, staged application and DOCX reopen');
  } catch(e,st) {
    File('$base/logs/refresh-failure.txt').writeAsStringSync('$e\n$st');
    rethrow;
  } finally {transport.dispose(); await trace.close();}
}
