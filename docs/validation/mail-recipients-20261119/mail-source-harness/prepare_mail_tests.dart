import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crypto/crypto.dart';

final class TestCollector extends RecursiveAstVisitor<void> {
  final tests = <MethodInvocation>[];
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'test') tests.add(node);
    super.visitMethodInvocation(node);
  }
}

void main() {
  const repo = '/workspace/scratch/32e3793609d8/quds_office_suite';
  const out = '/workspace/scratch/32e3793609d8/validation/mail-source-harness';
  const lib = '$repo/packages/quds_office_editor/example/lib';
  final manifest = <String, Object?>{
    'runtime': 'Flutter 3.47.8 bundled Dart 3.13.7',
    'harness': '/workspace/scratch/32e3793609d8/runtime/core-validation',
    'qualification': 'Offline path dependency against actual production source. Separate cached graph, not repository locked workspace acceptance.',
    'transformations': [
      'Replace flutter_test import with package:test/test.dart.',
      'Resolve Studio production package imports to original absolute file URIs.',
      'Remove entire test declarations containing buildStudioMailMessage or QudsMimeCodec; no retained assertion body is altered.',
      'Remove now-unavailable submission and MIME imports.',
    ],
    'files': <Map<String, Object?>>[],
    'production': <Map<String, String>>[],
  };
  for (final name in ['studio_mail_recipients', 'studio_mail_reply', 'studio_mail_threading']) {
    final sourcePath = '$repo/packages/quds_office_editor/example/test/${name}_test.dart';
    final source = File(sourcePath).readAsStringSync();
    final ast = parseString(content: source, path: sourcePath, throwIfDiagnostics: true);
    final collector = TestCollector();
    ast.unit.accept(collector);
    final omitted = <Map<String, Object?>>[];
    final retained = <String>[];
    final removals = <({int start, int end})>[];
    for (final node in collector.tests) {
      final statement = node.parent;
      if (statement is! ExpressionStatement) throw StateError('Unexpected test parent');
      final text = source.substring(statement.offset, statement.end);
      final name = node.argumentList.arguments.first.toSource();
      if (text.contains('buildStudioMailMessage') || text.contains('QudsMimeCodec')) {
        removals.add((start: statement.offset, end: statement.end));
        omitted.add({
          'name_expression': name,
          'reason': 'Requires unavailable MIME/submission dependencies',
          'source_start_line': '\n'.allMatches(source.substring(0, statement.offset)).length + 1,
          'source_end_line': '\n'.allMatches(source.substring(0, statement.end)).length + 1,
        });
      } else {
        retained.add(name);
      }
    }
    var transformed = source;
    removals.sort((a, b) => b.start.compareTo(a.start));
    for (final removal in removals) {
      transformed = transformed.replaceRange(removal.start, removal.end, '');
    }
    transformed = transformed.replaceAll("import 'package:flutter_test/flutter_test.dart';", "import 'package:test/test.dart';");
    transformed = transformed.replaceAll("import 'package:quds_mail_mime/quds_mail_mime.dart';\n", '');
    transformed = transformed.replaceAll("import 'package:enough_mail/enough_mail.dart' as mail;\n", '');
    transformed = transformed.replaceAll("import 'package:quds_office_studio/studio_mail_submission.dart';\n", '');
    transformed = transformed.replaceAllMapped(RegExp(r"package:quds_office_studio/([a-z_]+\.dart)"), (m) => File('$lib/${m[1]}').uri.toString());
    final outputPath = '$out/${name}_offline_test.dart';
    File('$out/${name}_original.dart').writeAsStringSync(source);
    File(outputPath).writeAsStringSync(transformed);
    (manifest['files'] as List).add({
      'source_path': sourcePath,
      'source_sha256': sha256.convert(utf8.encode(source)).toString(),
      'source_git_blob_sha': sha1.convert([...utf8.encode('blob ${utf8.encode(source).length}\u0000'), ...utf8.encode(source)]).toString(),
      'transformed_path': outputPath,
      'transformed_sha256': sha256.convert(utf8.encode(transformed)).toString(),
      'retained_test_declarations': retained,
      'omitted_test_declarations': omitted,
    });
  }
  for (final name in ['studio_mail_recipients', 'studio_mail_draft', 'studio_mail_reply', 'studio_mail_threading']) {
    final path = '$lib/$name.dart';
    final bytes = File(path).readAsBytesSync();
    (manifest['production'] as List).add({'path': path, 'sha256': sha256.convert(bytes).toString()});
  }
  File('$out/provenance.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
  for (final file in manifest['files'] as List) {
    print('${file['source_path']}: retained ${(file['retained_test_declarations'] as List).length} declarations, omitted ${(file['omitted_test_declarations'] as List).length}.');
  }
}
