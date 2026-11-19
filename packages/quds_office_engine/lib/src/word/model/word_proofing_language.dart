import 'wml_document.dart';

final _complexScriptLetter = RegExp(
  r'(?=\p{L})[\u0590-\u05FF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]',
  unicode: true,
);

/// Whether [text] contains a letter of a right-to-left complex script
/// (Arabic or Hebrew, including presentation forms).
bool wordTextHasComplexScriptLetter(String text) =>
    _complexScriptLetter.hasMatch(text);

/// Whether the run's text or explicit formatting uses the complex-script
/// language slot. A missing complex-script language still falls back to the
/// Latin-language chain when resolving the effective language.
bool wordRunUsesComplexScriptLanguage(WmlRun run) =>
    run.properties.complexScript == true ||
    wordTextHasComplexScriptLetter(run.text);

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
      wordRunUsesComplexScriptLanguage(run)) {
    return complex;
  }
  return run.properties.proofingLanguage ??
      paragraph.properties.proofingLanguage ??
      documentLanguage;
}
