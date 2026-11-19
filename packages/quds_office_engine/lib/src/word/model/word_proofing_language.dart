import 'wml_document.dart';

/// Whether [text] contains a letter of a right-to-left complex script
/// (Arabic or Hebrew, including presentation forms).
bool wordTextHasComplexScriptLetter(String text) {
  for (final unit in text.codeUnits) {
    if ((unit >= 0x0590 && unit <= 0x05FF) ||
        (unit >= 0x0600 && unit <= 0x06FF) ||
        (unit >= 0x0750 && unit <= 0x077F) ||
        (unit >= 0x08A0 && unit <= 0x08FF) ||
        (unit >= 0xFB1D && unit <= 0xFDFF) ||
        (unit >= 0xFE70 && unit <= 0xFEFF)) {
      return true;
    }
  }
  return false;
}

/// The proofing language Word would apply to [run].
///
/// Word keeps two languages per run: `w:lang/@w:val` for Latin-script text
/// and `w:lang/@w:bidi` for complex-script text (runs marked `w:rtl`/`w:cs`).
/// A run whose formatting is complex script, or whose text contains Arabic
/// or Hebrew letters, uses the complex-script language (the run's own, or
/// the document default) when one is set; otherwise the Latin-script chain
/// (run, paragraph, [documentLanguage]) applies. Returns null when nothing
/// is set.
String? wordRunProofingLanguage(
  WmlRun run,
  WmlParagraph paragraph, {
  String? documentLanguage,
  String? documentComplexScriptLanguage,
}) {
  final complex =
      run.properties.complexScriptLanguage ?? documentComplexScriptLanguage;
  if (complex != null &&
      complex.isNotEmpty &&
      (run.properties.complexScript == true ||
          wordTextHasComplexScriptLetter(run.text))) {
    return complex;
  }
  return run.properties.proofingLanguage ??
      paragraph.properties.proofingLanguage ??
      documentLanguage;
}
