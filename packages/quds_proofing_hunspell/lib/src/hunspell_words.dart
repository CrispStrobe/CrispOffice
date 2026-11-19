/// A word candidate with original UTF-16 offsets in the checked text.
typedef HunspellWord = ({int start, int end, String text});

/// Words are maximal runs of letters and combining marks. Arabic harakat
/// (Mn) and tatweel (Lm) stay inside the word with their original offsets;
/// the dictionary's IGNORE line makes Hunspell disregard them while checking.
/// Digits, punctuation, spaces and format controls (e.g. ZWNJ) end a word.
final _wordPattern = RegExp(r'[\p{L}\p{M}]+', unicode: true);

/// Arabic-script letters (Arabic, Supplement, Extended-A, presentation forms).
final arabicScriptLetter = RegExp(
  r'[ؠ-يٮ-ۓەۮۯۺ-ۼۿ'
  r'ݐ-ݿࢠ-ࣉﭐ-ﷻﹰ-ﻼ]',
);

/// Candidate words in [text]. With [script], words without any letter of that
/// script (e.g. Latin words inside Arabic prose) are not checked by this
/// dictionary; another language's provider owns them.
List<HunspellWord> hunspellWords(String text, {RegExp? script}) => [
  for (final match in _wordPattern.allMatches(text))
    if (script == null || script.hasMatch(match.group(0)!))
      (start: match.start, end: match.end, text: match.group(0)!),
];
