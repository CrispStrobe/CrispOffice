// Downloads the pinned database (camelMorphMsaProofingBin) and context model
// (camelMorphMsaDisambig) with the package's own verifying installer (every
// file against its pinned SHA-256 and size) and prints their directories:
//   dart run tool/fetch_bundles.dart <root>
// Output: one JSON object {"bundle": <dir>, "model": <dir>}.
import 'dart:convert';
import 'dart:io';

import 'package:quds_arabic_morph/installer_io.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/fetch_bundles.dart <root>');
    exit(2);
  }
  final root = Directory(args.single)..createSync(recursive: true);
  final installer = MorphInstaller(root);
  final bundle = await installer.install(camelMorphMsaProofingBin);
  final model = await installer.install(camelMorphMsaDisambig);
  stdout.writeln(
    jsonEncode({
      'bundle': File(bundle.manifestPath).parent.path,
      'model': File(model.manifestPath).parent.path,
    }),
  );
}
