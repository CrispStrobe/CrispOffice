# Proofing geometry and platform spelling checks

All **19 local tests passed** on Flutter 3.47.8 / Dart 3.13.7, and focused
analysis completed without issues. `receipt.json` records commands, results,
source SHA-256 values captured before the checks, unchanged-source verification,
and log hashes. GitHub Actions were not used or waited for.

The ten geometry/rendering tests cover disjoint bidi ranges, wrapping, repeated
header labels, generated note markers, actual squiggle pixels on body and table
paragraphs, clearing findings on refresh, exclusion of generated fields and
page labels, source hits from secondary pointer clicks, measured header glyphs,
and visible zero-length findings at the end of body/header text.

The nine platform adapter tests distinguish successful empty checks from
unavailable, unsupported and failed checks; verify UTF-16 offsets and locale
mapping; bound suggestions; and check serialized requests, timeout retirement
and disposal. Two tests exercise Flutter's real `DefaultSpellCheckService`
against a mocked platform channel. These validate the adapter protocol; they
are not Android or iOS device tests.
