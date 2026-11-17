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
