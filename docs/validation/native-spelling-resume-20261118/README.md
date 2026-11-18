# Native spelling resume — 18 November 2026

Work continues on `codex/native-spelling-resume-20261118` after reconciling
all captured incoming branches and pull requests. The integrated baseline is
`4dceb86e9fae51877bb5b7dc01e7a8bc721cb6ea`.

## Checkpoint status

This is an incremental implementation checkpoint; final qualification is in
progress. The native platform adapter now protects identifiers reported by the
system dictionary as whole spans, as well as fragments that contain a numeric
or connector character. Its existing adjacent-identifier protections remain.
The per-request grapheme index supports logarithmic lookup in arbitrary native
result order. Ordinary prose, explicit hyphen parts and CJK dictionary spans
remain reviewable.

The eight new native tests include Word review through Flutter's real default
spelling service with controlled method-channel responses. The unchanged
baseline reproduces seven behavioral nonpasses and one passing control. After
the repair, the initial four-file native selection passes 52 substantive tests,
zero failures or skips. These development results will be superseded by the
final source-bound qualification and archived raw evidence.

German dictionary normalization and projected-text protections are being
implemented separately. They are not claimed by this checkpoint.

## Incoming work

[Reconciliation](reconciliation.md) and [the complete reference inventory](refs.json)
account for all 372 captured incoming references, representing 241 distinct
heads. No incoming head remains unresolved. Main's merged spelling, Zotero and
spaCy changes are retained, together with document-review hardening and stable
golden host selection.

Checkpoints are saved through non-forced expected-head GitHub updates and use
`[skip ci]`. No GitHub Actions, workflow, check-run or CI-status endpoint is
queried, awaited, dispatched or rerun.
