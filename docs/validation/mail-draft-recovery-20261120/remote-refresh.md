# Final remote freshness review — 20 November 2026

## Capture and disposition

The latest repository GET capture was **2026-11-20 07:53:04 UTC**. All fork
heads and pull-request heads were fetched, together with upstream main. The
complete 16-branch capture and sole open PR metadata are retained in
`remote-refresh/remote-snapshot.json`. No GitHub Actions, checks, workflow runs,
commit-status endpoints or queue waits were used. Remote refs were not changed.

| Source | Captured SHA | Disposition |
| --- | --- | --- |
| Fork main | `e06eb3a7e21b71c1d5d4b1d2cc9abde24774eb26` | Unchanged since the qualified main refresh; included in local merge `233b506e341bc2e299e7e1021910a94858eb9e35` |
| `codex/zotero-parity-20261120` | `e06eb3a7e21b71c1d5d4b1d2cc9abde24774eb26` | Same commit as main, no separate delta |
| `integrate/recent-pptx` | `9bd16ff4d97f2a63f450f161fe10eb3bb2808857` | New installed-font checkpoint retained but deferred; concrete integration defect described below |
| `codex/vba-variant-conversions-20261120`, PR #227 | `656e7b96f15142942b00335e8b7eb894ce068565` | Active open draft; combined-source qualification still expressly incomplete |
| Mail work branch | `bbc114d4aee1d54564edb4c6f333830d5a8fdeea` | Concurrent Mail checkpoint owned by the main task; retain when combining this evidence |
| Upstream main | `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` | Unchanged and already incorporated |

Other surviving branch heads are unchanged from the original audit. Their
ancestor/patch-equivalence dispositions remain as recorded in `integration.md`.
The recent merged proofing/web/Arabic PRs are already in captured main. PR #227
is the only open PR in the final API capture; no new ready PR was found.

## New PPTX font checkpoint

Commit `236850d387a6588807d2d4f5809818d8113186a6` adds optional installed
Office/OS font discovery and Studio registration. The branch tip `9bd16ff4`
has that commit and main `e06eb3a7` as parents. Relative to refreshed main,
its genuine delta consists of six editor/Studio font files (152 added lines).
The earlier gradient, shadow and transparency work remains incorporated by
our qualified integration; only this subsequently discovered font work is
deferred.

The new Studio path first calls `OfficeHostFonts.ensureRegistered()`, which
owns Arial, Times New Roman and Courier New through bundled Liberation aliases.
It then calls the existing `registerFamily()` with those installed family
names. That method rejects an already owned alias before loading bytes.
The new caller catches and discards the error. Consequently these common
installed faces do not replace the fallback face or its metrics.

A bounded isolated probe reproduces the exact call for all three names. Each
call throws `StateError('Font alias is already registered to another family.')`,
leaves the fallback owner unchanged and does not advance font registration
revision. The probe uses bundled fixture bytes because rejection happens before
font-byte loading; it does not claim access to installed Microsoft font files.
The tested registration source is Git blob
`885d5a8873146a0c872b5c2df47104fccab9f904`, identical in the qualified local
source and the incoming PPTX branch. All **three defect-reproduction probes
passed**, with no errors or skips in the correctly launched run. Source,
commands, hashes, raw events and the initial asset-launch diagnostic are
retained under `remote-refresh/`.

Static review also found that the incoming discovery method trusts filenames
and uses synchronous unbounded file reads without validating actual format,
family, weight or italic metadata. Its comment describes skipping TTC,
variable and color fonts, but the reader performs no corresponding signature
or table checks. These are incomplete implementation details, not a reason to
change the established ownership contract indiscriminately.

## Active PR #227

[PR #227](https://github.com/CrispStrobe/quds_office_suite/pull/227) remains
open and draft at `656e7b96`; metadata was last updated at
`2026-11-20T07:49:58Z`. Its description explicitly records independent-review
findings and says fixes and combined-source qualification are in progress.
The repository evidence README at that exact head likewise labels development
runs as non-final and says the final accepted source, selections, static
checks and review resolutions are still to be recorded. The PR discussion
contained no comments announcing a completed acceptance gate.

That head incorporates the font commit and contains a new
`registerInstalledFamily()` path, bounded font-file reading and metadata
validation; its Studio caller is wired to the new method. This is active repair
work, so this Mail task does not duplicate or publish an unfinished slice of
that owner's branch. The draft/readiness evidence is sufficient to defer the
whole branch without claiming that every previously reported code defect
necessarily remains unfixed.

**Recommended publication:** combine the qualified `e06eb3a7` reconciliation
and Mail acceptance, retain both newer remote heads, and explicitly identify
the unfinished font/Variant changes as excluded pending their own completed
review and local qualification. No product source was changed by this final
freshness review. Recheck main once immediately before the final remote merge
because other contributors can continue publishing.
