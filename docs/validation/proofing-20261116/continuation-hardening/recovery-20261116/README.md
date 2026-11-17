# Recovered completion of the interrupted proofing turn

The interrupted conversation had already saved the completed implementation
and final local qualification to `codex/proofing-20261116-resume` at
`95185d2f803215d768d440cbbc2ee74789574005`. The final tests and release web
build finished on **16 November 2026 at 17:08:26 CET**; the final evidence
commit was saved at **17:16:28 CET**. See the [original completed report](../README.md).

This recovery verifies that saved result and its evidence. It adds no product
code and does not rerun Dart, Flutter, or the web build. The original results
remain bound to tested source `8b93e866b4661d19f4bbad4e1069c0a609441ebb`
and tree `834585ef6d66d995a633d6adf8e45a05628fe039`.

## What was recovered

| Original local qualification | Retained result |
| --- | --- |
| Engine, selected editor, and example-host analysis | Passed with `--fatal-infos` |
| Combined editor suite | 347 passed; no failures or skips |
| Separate canvas IME reattachment regression | 1 passed |
| Hyphenation, layout, export, and shaping | 295 passed; no failures or skips |
| Incoming ODS, Zotero, and comment/proofing styles | 503 passed; no failures or skips |
| Harper provider contracts | 8 passed |
| Harper native lifecycle guards | 3 passed; 1 real-library test skipped |
| Example release web build | Succeeded; output manifest records 117 files and 59,826,750 bytes |

These selected groups overlap. They are not a repository-wide test total.
The [editor receipt](../editor/receipt.json) and [engine receipt](../engine/receipt.json)
retain the exact commands, runtime identity, source hashes, and complete logs.

## Recovery checks

The [checkpoint integrity check](checkpoint-integrity.json) compares all
**5,206 tracked blobs** in the downloaded recovered checkout with its Git
tree. Every blob matches. It also confirms that all **228 original handoff
evidence files** remain unchanged from `9d9051859f0aa0fdf43dec938d31642ea3c67133`.

All **188 checks** in the [independent evidence review](evidence-review.json)
passed. The review recomputes log and
manifest digests, parses raw test event counts and success markers, checks
analysis flags, and decodes all **19 compressed evidence files**, including the runtime setup
archive. It binds the recorded
2,049 editor inputs and 4,291 engine inputs to the frozen source. The editor
input set includes the generated workspace lock, checked against its retained
copy. The original web output files are not present in this checkout; the
saved build log and output manifest are what this recovery verifies.

Only documentation, evidence, and package changelogs changed between the
tested source and recovered final commit. All referenced report targets are
present. Failed and interrupted development attempts remain explicitly
separate from the final passing run.

## Integration already completed

At the recovery audit cutoff, `main` was
`be9eeec9ea3455018de26fff5874c558dbc66798`. Git ancestry and the GitHub
comparison both show that it contains the recovered proofing checkpoint
and is 31 commits ahead, with none missing from the checkpoint.
Merge `3196e49bea45de49fb7a4ab85163e953cca58d11` included the proofing
checkpoint as an actual parent. The entire original proofing validation
subtree is byte-identical between the recovered checkpoint and that main
commit (tree `4204ba9d205be50c56c5cb4a71fdc3bc42213932`).

The [remote recovery audit](remote-proofing-recovery.json) retains the fresh
79-branch/79-PR inventory and empty second pages. The original implementation
audit remains bounded to its recorded 64 branches and 68 PRs at
16:39:54 CET. Later repository activity does not turn this recovered result
into a new qualification of current main.

No GitHub Actions, workflow, check-run, or commit-status endpoints were
queried or waited for during recovery.

## Reproduce the evidence audit

Use a checkout containing the recovered evidence and the referenced Git
history. The verifier uses only the Python standard library and local Git:

```sh
python3 verify_evidence.py \
  --repo /path/to/quds_office_suite \
  --output /path/to/new-evidence-review.json
```

The [verifier](verify_evidence.py) records its own SHA-256 in the output.
The original report retains separate instructions for rerunning the actual
Dart/Flutter qualification against `8b93e86`.

## Remaining boundaries

The original web build established compilation. Real-browser interaction,
HTTP/CSP delivery, mobile dictionary acceptance, and non-Linux native Harper
loading remain outside that qualification. The existing nonfatal
CupertinoIcons font warning is retained in the build log. The optional Harper
binaries and experimental German model were not rebuilt or rerun during
this continuation or recovery.
