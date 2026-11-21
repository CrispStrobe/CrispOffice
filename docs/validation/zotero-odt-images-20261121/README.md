# Zotero images through editable ODT — 21 November 2026

Status: implementation in progress. No new runtime or interoperability result
is claimed by this initial checkpoint.

Starting main: `4970f71f983535d045ce263e86835b499db4fda9`.
Remote checkpoint branch: `codex/zotero-roundtrip-20261121`.

## Reconciled baseline

Before implementation, all advertised fork branches and PR heads, upstream
branches and upstream PR heads were fetched. The immutable intake contains
378 refs: 364 actual ancestors, ten independently reverified patch equivalents
and four API-confirmed squash integrations whose complete trees or aggregate
blob deltas were checked. No captured work remains unaccounted for.

See [intake accounting](intake/intake-accounting.json),
[review](intake/review.md) and [fresh squash metadata](intake/pr-squash-metadata.json).
This includes completed Word VBA, Mail, performance and earlier Zotero ODT
work. Later remote changes will be checked again before publication.

## Selected next capability

Native Zotero note/annotation insertion already supports embedded pictures,
but native ODT reopening refuses every drawing frame. The ordinary writer also
emits a canonical inline-picture placeholder as text before its image frame,
and omits the picture's alternative description.

This continuation will qualify bounded inline embedded PNG and upright RGB
JPEG pictures through editable ODT import/export and subsequent DOCX saves.
It will retain picture bytes, dimensions, links and alternative text while
preserving exact citation ownership and offsets. Unsupported field caches,
floating or transformed graphics, ambiguous packages and resource exhaustion
must refuse before an editable document is published.

The gates are focused engine regressions, independent citation/image lifecycle
checks, asynchronous editor loading and undo, formatting/analysis, and an actual
LibreOffice conversion probe with retained input/output artifacts. Installed
Zotero plugin and release-host acceptance remain separate from converter and
controlled protocol evidence. GitHub Actions are not queried or awaited.
