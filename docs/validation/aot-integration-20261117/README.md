# AOT integration — 17 November 2026

Work branch: `codex/aot-proofing-analysis-20261117`.

## Incoming source

The initial integration starts from main `7cf48a2f` and includes every captured
fork branch, PR head and upstream branch by ancestry. `incoming.json` records the
exact fixed snapshot; concurrent updates after that snapshot are separate work.
The latest captured German continuation is PR #114 at `62eafbe4`; Office #113 is
`104b239c`, fidelity #111 is `d1738017`, and the GECToR branch is `78cd772c`.
All prior source and validation archives remain in history.

Merge decisions:

- Retain the current ODP hyperlink assertion once, with transition assertions.
- Combine section-anchored ODT frame/table extraction with linked drawing frames,
  ruby-base handling and hidden note/annotation/soft-page-break exclusions.
- Preserve authored empty frame-anchor paragraphs. Update the older empty-box
  regression to that explicit policy; retain the newer empty-frame regression.
- Keep current page fields, paragraph shading and model-tool documentation.
- Preserve the prior `readOdfParagraphs` entry point as a forwarding alias.

## Feature and validation progress

A separate optional `quds_proofing_aot` package is being added for the upstream
AOT/RML SynanDaemon. It will expose syntax/morphology analysis and conservative
German diagnostics, with explicit host configuration and manual proofing.
No AOT engine binary or dictionaries are bundled. Existing proofing remains
available independently. Local source and fixture tests are the validation gate;
GitHub Actions jobs, checks and commit-status endpoints are not queried or awaited.

This is an incremental integration checkpoint. Final local test results and the
precise supported rule scope will be recorded here after implementation.
