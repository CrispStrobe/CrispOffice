import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crypto/crypto.dart';

const repo = '/workspace/scratch/32e3793609d8/quds_office_suite';
const tip = '8356fb0ad4630824a39453ea9a5923d9fb2a2101';
const head = '3279d1ffb0d80c0133fc6edaa2c3854512ac8481';
const output = '/workspace/scratch/32e3793609d8/validation/final-reconciliation-audit';
final class Collector extends RecursiveAstVisitor<void> {
  final tests = <String, List<MethodInvocation>>{};
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'testWidgets' || node.methodName.name == 'test') {
      tests.putIfAbsent(node.argumentList.arguments.first.toSource(), () => []).add(node);
    }
    super.visitMethodInvocation(node);
  }
}
String readGit(String ref, String path) {
  final result = Process.runSync('git', ['show', '$ref:$path'], workingDirectory: repo, environment: {'GIT_NO_LAZY_FETCH':'1'});
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  return result.stdout.toString();
}
({CompilationUnit unit, Collector collector}) collect(String source, String path) {
  final unit = parseString(content: source, path: path, throwIfDiagnostics: true).unit;
  final collector = Collector();
  unit.accept(collector);
  return (unit: unit, collector: collector);
}
String tokenHash(AstNode node) {
  final lexemes = <String>[];
  var token = node.beginToken;
  while (true) {
    final next = token.next;
    if (!(token.lexeme == ',' && next != null && {')',']','}'}.contains(next.lexeme))) lexemes.add(token.lexeme);
    if (identical(token, node.endToken)) break;
    if (next == null) throw StateError('Unexpected end');
    token = next;
  }
  return sha256.convert(utf8.encode(jsonEncode(lexemes))).toString();
}
List<String> imports(CompilationUnit unit) => unit.directives.whereType<ImportDirective>().map((d) => d.toSource()).toList();
void main() {
  final wanted = {
    'studio_mail_cloud_test.dart': 'host keeps hidden recipients out of canonical MIME',
    'studio_mail_ews_test.dart': 'EWS host preserves visible groups and hides Bcc from canonical MIME',
    'studio_mail_test.dart': 'SMTP recipient groups stay in the envelope and survive acknowledged retry',
  };
  final results = <Map<String,Object?>>[];
  for (final entry in wanted.entries) {
    final path = 'packages/quds_office_editor/example/test/${entry.key}';
    final before = collect(readGit(head,path), path);
    final incomingSource = readGit(tip,path);
    final incoming = collect(incomingSource,path);
    final currentSource = File('$repo/$path').readAsStringSync();
    final current = collect(currentSource,path);
    final name = incoming.collector.tests.keys.singleWhere((n) => n.contains(entry.value));
    final incomingNode = incoming.collector.tests[name]!.single;
    final currentNodes = current.collector.tests[name] ?? [];
    final oldNamesMissing = before.collector.tests.keys.where((n) => !current.collector.tests.containsKey(n)).toList();
    final oldBodiesChanged = <String>[];
    for (final e in before.collector.tests.entries) {
      final now = current.collector.tests[e.key];
      if (e.value.length == 1 && now?.length == 1 && tokenHash(e.value.single) != tokenHash(now!.single)) oldBodiesChanged.add(e.key);
    }
    results.add({
      'path': path,
      'new_name_expression': name,
      'same_name_count_in_reference_head': before.collector.tests[name]?.length ?? 0,
      'same_name_count_in_current': currentNodes.length,
      'incoming_assertion_tokens_retained': currentNodes.length == 1 && tokenHash(incomingNode) == tokenHash(currentNodes.single),
      'normalized_incoming_test_token_sha256': tokenHash(incomingNode),
      'current_exact_name_duplicates': current.collector.tests.entries.where((e)=>e.value.length>1).map((e)=>{'name':e.key,'count':e.value.length}).toList(),
      'original_test_names_missing': oldNamesMissing,
      'original_test_bodies_changed_beyond_formatting': oldBodiesChanged,
      'imports_unchanged_from_reference_head': jsonEncode(imports(before.unit)) == jsonEncode(imports(current.unit)),
      'imports_unchanged_from_incoming': jsonEncode(imports(incoming.unit)) == jsonEncode(imports(current.unit)),
      'current_sha256': sha256.convert(utf8.encode(currentSource)).toString(),
      'incoming_sha256': sha256.convert(utf8.encode(incomingSource)).toString(),
    });
  }
  final result={'incoming_tip':tip,'reference_head':head,'method':'Read-only Dart AST parsing and token comparison; ignore whitespace/comments and optional trailing commas. No tests executed.','tests_executed':0,'new_test_declarations':3,'new_widget_cases':4,'files':results};
  File('$output/incoming-8356-host-test-checks.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(result)}\n');
  print(const JsonEncoder.withIndent('  ').convert(result));
}
