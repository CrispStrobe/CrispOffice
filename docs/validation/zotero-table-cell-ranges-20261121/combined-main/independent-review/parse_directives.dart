import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:pub_semver/pub_semver.dart';

Future<void> main() async {
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final item = jsonDecode(line) as Map<String, dynamic>;
    final parsed = parseString(content: item['content'] as String,
        path: item['path'] as String, throwIfDiagnostics: false,
        featureSet: FeatureSet.fromEnableFlags2(
          sdkLanguageVersion: Version.parse(item['languageVersion'] as String), flags: []));
    final uris = <Map<String, dynamic>>[];
    void add(StringLiteral uri, String kind) {
      uris.add({'value': uri.stringValue, 'literal': uri.toSource(),
        'offset': uri.offset, 'kind': kind});
    }
    for (final directive in parsed.unit.directives) {
      if (directive is UriBasedDirective) {
        add(directive.uri, directive.runtimeType.toString());
        if (directive is ImportDirective) {
          for (final config in directive.configurations) {
            add(config.uri, 'conditional-import');
          }
        } else if (directive is ExportDirective) {
          for (final config in directive.configurations) {
            add(config.uri, 'conditional-export');
          }
        }
      } else if (directive is PartOfDirective && directive.uri != null) {
        add(directive.uri!, 'part-of');
      }
    }
    stdout.writeln(jsonEncode({'key': item['key'], 'path': item['path'],
      'uris': uris, 'diagnostics': parsed.errors.map((e) => e.toString()).toList()}));
  }
}
