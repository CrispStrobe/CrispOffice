import 'dart:convert';
import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';
import '../../quds_office_suite/packages/quds_office_editor/example/lib/studio_zotero.dart';

const output = '/workspace/scratch/7b8555dd0115/zotero-native-acceptance/first-insertion';
const docId = 'quds-native-first-insertion-20261116';
String state(WmlDocument doc) => jsonEncode({
  'body':doc.paragraphs.map((p)=>p.text).toList(),
  'fields':WordZotero.fields(doc).map((f)=>{'code':f.instruction,'text':f.cachedText}).toList(),
  'footnotes':doc.footnotes.map((n)=>{'id':n.id,'text':n.text}).toList(),
  'endnotes':doc.endnotes.map((n)=>{'id':n.id,'text':n.text}).toList(),
  'data':WordZoteroDocumentData.read(doc),
});

Future<void> main() async {
  final trace=File('$output/protocol.jsonl').openWrite();
  final transport=StudioZoteroTransport(integrationTimeout:const Duration(seconds:120));
  var phase='catalog';
  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    trace.writeln(jsonEncode({'phase':phase,'send':request.uri.path,'body':request.body}));
    await trace.flush();
    final response=await transport.send(request);
    trace.writeln(jsonEncode({'phase':phase,'receive':response.statusCode,'body':response.body}));
    await trace.flush();
    return response;
  }
  try {
    final catalog=ZoteroClient.local(transport:send);
    await catalog.probeLocal();
    final sources=await catalog.items(ZoteroLibrary.localUser(),query:'Native Acceptance Alpha');
    final alpha=sources.items.single;
    if(alpha.citationUri==null || alpha.cslJson==null) throw StateError('Fixture source is not linked');
    final document=WmlDocument.empty(text:'Before After');
    final before=state(document);
    if(WordZoteroDocumentData.stylePreferences(WordZoteroDocumentData.read(document))!=null) throw StateError('Document already has native style');
    File('$output/before.docx').writeAsBytesSync(WordSerializer().writeBytes(document));
    final session=WordZoteroCitingSession(document:document, documentId:docId, insertionParagraph:document.paragraphs.single, insertionOffset:7);
    final completed=<String>[];
    Future<void> execute(ZoteroCitingCommand command) async {
      phase=command.name;
      await ZoteroCitingClient(transport:send,requestTimeout:const Duration(seconds:120)).execute(
        command:command, documentId:docId,guard:session.assertUnchanged,
        handler:(name,args){
          if(name=='Document.displayAlert') {
            final answer=args[3]==0 ? 1:0;
            trace.writeln(jsonEncode({'phase':phase,'alert':args,'response':answer}));
            return answer;
          }
          final result=session.handle(name,args);
          trace.writeln(jsonEncode({'phase':phase,'handled':name,'result':result}));
          return result;
        });
      completed.add(command.name);
      if(state(document)!=before) throw StateError('$phase changed original before application');
    }
    await execute(ZoteroCitingCommand.setDocPrefs);
    final prefs=WordZoteroDocumentData.stylePreferences(session.documentData);
    if(prefs==null || prefs.noteType!=1 || prefs.locale!='de-DE' || !prefs.id.endsWith('/chicago-notes-bibliography-subsequent-ibid')) throw StateError('Choose pinned German footnote style in the native preferences dialog');
    if(!session.isComplete || !session.hasChanges) throw StateError('Native preferences were not staged');
    final seed=ZoteroCitation(citationId:'quds-first-native-seed',plainCitation:'Before native picker',items:[
      ZoteroCitationItem.fromCsl(itemData:alpha.cslJson!,uris:[alpha.citationUri.toString()],locator:'12',label:'page')
    ]);
    session.continueWithCitation(seed);
    if(session.isComplete || session.hasAcceptedSeedCitation || state(document)!=before) throw StateError('Seed was not staged correctly');
    await execute(ZoteroCitingCommand.addEditCitation);
    if(!session.hasAcceptedSeedCitation || !session.isComplete) throw StateError('Native picker did not accept seeded citation');
    session.prepareReview();
    final warnings=session.formattingWarnings.toList();
    session.apply();
    final bytes=WordSerializer().writeBytes(document);
    File('$output/inserted.docx').writeAsBytesSync(bytes);
    final reopened=WordDeserializer().readBytes(bytes);
    final field=WordZotero.fields(reopened).single;
    final item=field.citation!.items.single;
    final finalPrefs=WordZoteroDocumentData.stylePreferences(WordZoteroDocumentData.read(reopened));
    if(reopened.footnotes.length!=1 || reopened.endnotes.isNotEmpty || item.locator!='34' || !field.cachedText.contains('Synthetic Native Acceptance Alpha') || !field.cachedText.contains('34') || !item.uris.contains(alpha.citationUri.toString()) || finalPrefs?.locale!='de-DE' || finalPrefs?.noteType!=1) throw StateError('Native insertion or DOCX persistence mismatch: ${field.cachedText}, locator=${item.locator}');
    File('$output/result.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'result':'passed','actual_studio_transport':true,'actual_citing_client':true,'same_word_session_for_both_commands':true,
      'commands_completed':completed,'initial_document_has_style':false,'source_unchanged_after_each_command':true,
      'seed_selected_from_actual_local_catalog':true,'initial_seed_locator':'12','native_picker_accepted_locator':item.locator,
      'accepted_seed_flag':session.hasAcceptedSeedCitation,'apply_count':1,'docx_saved_reopened':true,
      'footnotes':reopened.footnotes.length,'citation':field.cachedText,'citation_uri':alpha.citationUri.toString(),
      'native_preferences':WordZoteroDocumentData.read(reopened),'review_warnings':warnings
    }));
    stdout.writeln('PASS: real native first-use style selection, same-session catalog seed, picker locator edit, one application and DOCX reopen');
  } catch(e,st) {
    File('$output/failure.txt').writeAsStringSync('$e\n$st');rethrow;
  } finally {transport.dispose();await trace.close();}
}
