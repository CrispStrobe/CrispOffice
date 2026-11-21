# Retained development diagnostics

These artifacts explain the changes and preserve failed routes. They do not
replace the final qualified-source receipts in `../final/`.

| Archive path | Meaning |
|---|---|
| `duplicate-name-failure/original`, `saved`, `verified-agent` | Original and actual LibreOffice-saved image fixtures before unique drawing names. The saved PNG comparison shows a missing second object. The earlier image-only visited-link style refusal was diagnosed on these same untouched saved files. |
| `attempt-02` | Fresh unique-name conversion. Native import matched both images; the initial verifier then incorrectly dereferenced raw `document.zoteroDocumentData` after DOCX reopening. The supported accessor lazily resolves that data, so the harness now uses `WordZoteroDocumentData.read`. The original failed receipt and subsequent cycle artifacts are retained unchanged. |
| `passing-before-story-fix` | Passing converter run before the broad gate exposed header comparison regressions. Source manifests identify the intermediate source; final acceptance was repeated after correction. |
| `first-broad-gate` | Frozen `81e478ca` run: 1,261 engine passes and three failures; 44 editor and 41 Studio passes; formatting/analysis passed. Two failures were real page-master regressions from allocated names. The third was a direct-parent assertion needing the styled inline-frame hierarchy. All input hashes stayed unchanged. |
| `baseline` | Immutable starting-production-source bibliography/table-note converter probes. Original native files reopened; returned files refused section/table defaults. No repair or normalization was applied. |
| `independent-review` | Source hashes and font/superscript/script-flag probe, including the known `complexScript` mapping boundary. |
| `focused-tests` | 101-case image review and final 133-case affected-story gate. They overlap the broader final suite and are not counted again. |

`archive-contents.json` records each member's byte length and SHA256 plus the
archive hash. Final source-bound converter evidence is in
`../final/execution.tar.gz` under `converter/`, including its original,
untouched returned and repeated-cycle files.
