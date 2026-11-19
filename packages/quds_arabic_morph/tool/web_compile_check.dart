// Compile-only check of the browser transport:
//   dart compile js tool/web_compile_check.dart -o /tmp/out.js
import 'package:quds_arabic_morph/quds_arabic_morph.dart';

void main() {
  final morphology = CamelArabicMorphology(
    database: MorphDatabaseBytes.verified(camelMorphMsaNoprob, const {}),
  );
  morphology.dispose();
}
