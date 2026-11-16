# Changelog

## Unreleased

- Check complete English words across discretionary soft hyphens while retaining
  exact Word UTF-16 source ranges. Index scalar offsets once per request and
  protect source/checker grapheme boundaries, including emoji and accents.
- Accept a shared host-owned personal vocabulary. Suppress only spelling
  findings in the matching dialect and reject results after in-flight vocabulary
  changes. Native/Wasm backend code and dependencies are unchanged.
- Add source-projection and provider-contract regressions. The accompanying
  JavaScript semantic reference is explicitly separate from Dart/native/Wasm
  acceptance; see the dated validation report for execution limits.
