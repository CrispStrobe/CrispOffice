// Compile-only check of the browser transport:
//   dart compile js tool/web_compile_check.dart -o /tmp/out.js
import 'dart:typed_data';

import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

void main() {
  final provider = HunspellProofingProvider(
    bundle: ayaspellArabic,
    dictionary: HunspellDictionaryBytes(aff: Uint8List(0), dic: Uint8List(0)),
  );
  provider.dispose();
}
