# Preserved local attempts

The first canonical attempt passed all three strict analyses, then its broad
formatting preflight rejected four Zotero test files that are byte- and
mode-identical to the captured main. No application tests ran. Source and
runtime inputs were unchanged, and analyzer configuration was restored.
The failed receipt, raw logs, input maps and exact executed runner are retained
in `preflight-attempt-1.tar.gz`.

The second attempt retains all 123 strict-analysis targets and all 144 selected
test files. Formatting checks every one of the 77 changed existing Dart paths
plus four previously recovered production targets. Its scope amendment records
the inherited failures and exact baseline equality; it does not claim those four
unchanged test files pass formatting. No production or test bytes were changed.

`../runtime-setup.tar.gz` preserves the completed official runtime and locked
workspace setup. Setup contributes zero application-test passes. Archive and
member digests are recorded in `preflight-index.json`.

The second attempt passed all analysis and formatting commands and the Dart
runner completed all 390 engine Zotero cases successfully. Its qualification
wrapper then rejected relative suite paths because it had expected absolute
path suffixes. This is retained as an unsuccessful overall attempt in
`suite-path-attempt-2.tar.xz`; none of its test counts is added to the final
accepted total. `suite-path-index.json` verifies the archive and every member.

The corrected wrapper resolves both observed and selected suite paths against
the command working directory and requires exact equality, rejecting unexpected
suites as well as missing suites. The third attempt repeats the complete
canonical qualification with this correction. Source and test bytes, selected
test files, and analysis/format scopes are unchanged.
