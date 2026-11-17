import 'dart:convert';
import 'package:quds_office_engine/quds_office_engine.dart';

void main() {
  final book=SmlWorkbook(sheets:[SmlWorksheet(name:'Rules',sheetId:1)]);
  book.firstSheet.cellA1('A1').value=4;
  book.firstSheet.conditionalFormats.add(SmlConditionalRule(range:SmlRange.parse('A1:A5'),kind:SmlConditionalKind.top,rank:3,priority:7,stopIfTrue:true,fillRgb:'',fontRgb:'0000FF'));
  final original=SheetSerializer().write(book,recalculate:false);
  final imported=SheetDeserializer().read(original);
  final first=imported.firstSheet.conditionalFormats.single;
  final before={'fill':first.fillRgb,'font':first.fontRgb,'priority':first.priority,'stop':first.stopIfTrue,'rank':first.rank};
  first.rank=2;
  final saved=SheetSerializer().write(imported,recalculate:false);
  final reopened=SheetDeserializer().read(saved).firstSheet.conditionalFormats.single;
  print(jsonEncode({'original_styles':original.getPart('/xl/styles.xml')!.readText(),'imported_rule':before,'saved_styles':saved.getPart('/xl/styles.xml')!.readText(),'edited_rule':{'fill':reopened.fillRgb,'font':reopened.fontRgb,'priority':reopened.priority,'stop':reopened.stopIfTrue,'rank':reopened.rank}}));
}
