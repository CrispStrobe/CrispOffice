# Zotero research materials — 20 November 2026

Development continuation on `codex/zotero-research-materials-20261120`.
This initial checkpoint records incoming-work reconciliation and runtime setup;
feature implementation and final acceptance are in progress.

## Incoming work

The captured fork main is `a452efdadc9000c51a8e5e9ba2f16405d4979e2e`.
The previous Zotero PR #218, subsequent VBA PR #219, macOS spaCy PR #220 and
the latest native DOCX review changes are already included.

The initial audit covers 12 branch heads and all 220 PR heads, with no open PRs.
206 PR heads are ancestors; 14 historical equivalents were independently
rechecked using complete trees or original-delta path/mode/blob identity.
The actual upstream's four branches and four PR heads are also ancestors.
Exact identities and proof records are in [initial-reconciliation.json](initial-reconciliation.json)
and [upstream-reconciliation.json](upstream-reconciliation.json).

The one outstanding branch is `integrate/recent-pptx` at
`f007b24503eece6ea0316a3049a10243fcf2dd2c`. Its four commits add inherited
slide decorations, symbol fallback, block arrows, heading fitting and numeric
text ordering. The integration retains original ancestry and existing fixes
for imported rich text, background ownership and anchored text hit testing.

## Planned Zotero workflow

An explicit **Reference details → Notes and attachments** action will browse
child research notes and attachment metadata. Notes will have inert plain-text
inspection and copying. Parent selection, unfinished search input and document
history remain independent of this read-only workflow.

## Local runtime

The official Flutter 3.47.8 / Dart 3.13.7 archive and executable digests are
verified, with current locked dependency archives and enforced offline
resolution. No manifests or dependency versions are changed. [runtime.json](runtime.json)
and `runtime-setup.tar.gz` preserve setup receipts and diagnostics.
The existing 31-case formatting smoke suite passes; it is setup evidence,
not final product acceptance.

GitHub Actions, workflow, check and commit-status endpoints are neither
queried nor awaited. Incremental checkpoints use `[skip ci]`.
