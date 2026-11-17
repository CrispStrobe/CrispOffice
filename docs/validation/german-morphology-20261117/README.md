# German morphology continuation — 17 November 2026

## Starting point and incoming work

This continuation starts at `8a778f1884b15065ef74f4c20f828d34b2374e06`,
the combined fork `main` after the previous proofing PR #91 was merged.
The initial fetch includes every advertised fork/upstream branch and pull-request
head: **206 references and 138 distinct commits**. Every captured commit is an
ancestor of the starting point. Exact references and observation time are in
[`incoming.json`](incoming.json).

Work is preserved incrementally on `codex/german-morphology-20261117`.
GitHub Actions is not queried, awaited, or used as the validation gate.

## Objective

Replace the main German coverage bottleneck — a small handwritten morphology
vocabulary — with reusable, separately licensed lexical analysis while keeping
the engine pure Dart and usable offline on native and web. Preserve English
Harper support, shared language handling, source offsets, protected text,
personal vocabulary, and English/German hyphenation.

External engines, model weights, lexical data, and rules require separate
license review. Existing no-GPL/AGPL/LGPL-only requirements apply. Unknown or
ambiguous linguistic analyses must not be converted into confident corrections.

## Checkpoint status

Initial reconciliation is complete. Implementation, license selection, and new
local qualification are in progress; no new runtime acceptance is claimed by
this initial checkpoint. The earlier qualification reports retain their original
source attribution.
