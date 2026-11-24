import 'dart:io';
import 'dart:typed_data';

import 'package:covfuzz/covfuzz.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

List<Uint8List> _seeds() {
  final out = <Uint8List>[];
  for (final root in <String>['test', 'packages/quds_office_engine/test']) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      final path = file.path.toLowerCase();
      if (!(path.endsWith('.docx') ||
          path.endsWith('.xlsx') ||
          path.endsWith('.pptx') ||
          path.endsWith('.odt'))) {
        continue;
      }
      if (file.lengthSync() > 64 * 1024) continue;
      out.add(file.readAsBytesSync());
      if (out.length >= 48) return out;
    }
  }
  return out;
}

void main(List<String> args) {
  final seeds = _seeds();
  if (seeds.isEmpty) {
    stderr.writeln('No OOXML/ODF seeds found.');
    exit(64);
  }
  final report = fuzz<Uint8List>(
    seeds: seeds,
    entry: (bytes) {
      final package = OfficeRepair.open(bytes);
      var read = 0;
      for (final part in package.parts) {
        if (read++ >= 32) break;
        part.readBytes();
      }
    },
    mutate: mutateBytes,
    isClean: (error) =>
        error is OfficeRepairException ||
        error is ZipException ||
        error is ZipDeflateException ||
        error is XmlParseException ||
        error is FormatException,
    iterations: 20000,
    budgetMs: int.tryParse(args.firstOrNull ?? '') ?? 30000,
  );
  exit(report.report());
}
