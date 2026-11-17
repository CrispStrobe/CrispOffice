# GECToR and Office continuation — 17 November 2026

This continuation preserves `feat/german-gector-proofing` at
`34c70ece1e9c14954398826f93c1bb6aa61007a8` and reconciles the newer Office
continuation at `e9889e07c983ac15ff002771cf78854d1bc0d572` (PR #144).
The latter includes PR #143 and main `16e2477ff93f7a1ec5c6ed78491f2716ce4d1658`.
Work is saved on `codex/gector-office-resume-20261117`; other active branches
remain independently owned. Checkpoint messages use `[skip ci]`.

## Integration decisions

- Fetch every current branch and PR head before editing. The first API inventory
  captured 177 branch heads and 144 PR heads. Exact refs and subsequent
  observations are saved beside this report.
- Retain original historical followup/resume reports and archives. Their old
  results remain attributed to their original source; they do not qualify this
  newly merged source. The automatic merge would otherwise delete these files.
- Preserve current Office field planning, strict PAGE/NUMPAGES admission,
  mandatory cached display, bookmark endpoint pairing and column-boundary
  behavior from PR #144. Unsupported DATE/TIME/TITLE instructions retain
  their cached runs; missing caches do not invent a display.
- Restore original schema-ordered headers/footers, empty default stories,
  all six stories' comment references in section identity, and a paragraph
  anchor for every frame. Retain PAGE/NUMPAGES fallback for significant cached
  whitespace and independent original regressions.
- Preserve the latest generated German common-word and morphology data with
  their matching manifests. The common-word additions are Straßenpolizist and
  Straßenpolizisten. Keep the bounded verb-object and sein-participle rules.
- Preserve the deliberate AOT/RML product removal. Native spaCy Quds PR #139
  and CrispEmbed PR #236 remain separate work, with no dependency upgrade.

## Remaining qualification at this checkpoint

The first integration save is not a test-pass claim. Required next work is
the floating-frame common-style consumer repair, focused regressions, fresh
merged-source local qualification, and the pending serial native thread sweep
on distinct long passages. The official pinned runtime and the exact historical
native library/model are being restored from recorded sources and checksums.
No historical binary trust pin will be weakened. GitHub Actions are neither
polled nor awaited.

## Frame repair and restored prerequisites

The common-style repair now passes the original failed consumer control.
All five scoped consumer fixtures, all 20 official-schema checks and all
102 focused engine cases pass. The independent package comparison verifies
that the identical frame graphic style only changes placement, restoring the
DOCX bookmark with the exact authored box and unchanged surrounding text.
The observed internal glyph-position difference is recorded explicitly in
`office-consumer/README.md`, alongside raw before/after evidence.

The official Flutter 3.47.8 / Dart 3.13.7 archive, all 162 hosted package/version
pairs, the 23-file native development pack, the native library, both model
precisions and the quantizer match their recorded hashes. The isolated graph
resolves 109 packages with the original dependency lock unchanged. Runtime
recovery receipts and failed infrastructure attempts are retained under
`recovery/` without counting them as successful tests.

The previously lost 377-row quality baseline has been reproduced on its exact
590-file source snapshot and independently reconstructed. Its complete raw
outputs are saved under `quality/`. The current merged-source comparison,
broad VM/Node/example cohorts, retained consumers and serial thread timings
remain the next gates for this source checkpoint.
