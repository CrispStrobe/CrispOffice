// Compile-only check of the browser transport:
//   dart compile js tool/web_compile_check.dart -o /tmp/out.js
import 'dart:typed_data';

import 'package:quds_language_id/quds_language_id.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

Future<void> main() async {
  final identifier = Cld3LanguageIdentifier(model: Uint8List(0));
  final detector = ParagraphLanguageDetector(identifier);
  await detector.detect('Bonjour le monde, comment allez-vous aujourd’hui ?');
  await identifier.dispose();
}
