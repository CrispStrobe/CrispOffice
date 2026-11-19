import 'dart:io';
import 'dart:convert';
import 'package:quds_office_engine/quds_office_engine.dart';
void main() {
 final input=File('/tmp/quds-docx-libreoffice-roundtrip-20261119/output/isolate-3.docx');
 var doc=WordDeserializer().readBytes(input.readAsBytesSync());
 final before=doc.revisions.length;
 if(before!=14) throw StateError('Expected 14 linked body/header/footer revisions, got $before');
 for(final r in doc.revisions) {
  if(r.author!='Native reviewer'||r.dateIso!='2026-10-01T12:30:00Z') throw StateError('Metadata changed');
 }
 final bytes=WordSerializer().writeBytes(doc);
 File('/tmp/quds-docx-libreoffice-roundtrip-20261119/quds-reexport.docx').writeAsBytesSync(bytes);
 doc=WordDeserializer().readBytes(bytes);
 if(doc.revisions.length!=before) throw StateError('Changes lost on re-export');
 final accepted=WordDeserializer().readBytes(bytes);
 WordRevisions.acceptAll(accepted);
 if(accepted.revisions.isNotEmpty) throw StateError('Accept failed');
 final rejected=WordDeserializer().readBytes(bytes);
 WordRevisions.rejectAll(rejected);
 if(rejected.revisions.isNotEmpty) throw StateError('Reject failed');
 print(jsonEncode({'passed':true,'externalApplication':'LibreOffice Writer','linkedStoryRevisions':before,'metadataPreserved':true,'qudsReexportPreserved':true,'acceptAll':true,'rejectAll':true,'scope':'body and six header/footer stories; fixture notes/comments are unreferenced and Writer omits them','microsoftWordTested':false}));
}
