# Remote reconciliation snapshot

Source checkpoint: `ca294cf8668706b45f40031ed9a2db52e5737cd2` on
`codex/proofing-20261116-resume`.

The [read-only audit](remote-audit.json) records **53 branches and 62 pull
requests**, with no open pull requests, at **2026-11-16 13:40:49 UTC**.
Concurrent writers continued working during recovery, so this is an explicit
cutoff. The [resolution record](resolution.json) describes how overlapping
implementations were reconciled.

| Incoming history | Exact integrated head | Result |
| --- | --- | --- |
| Fork main | `7edb096d3328263c75dc0229ff43bb77183e1ad3` | Clean merge of PRs #59–62: ODS hyperlinks, outline groups, metadata/progress documentation and filter predicates. |
| Original proofing branch | `93c13aa1315298c0f85a5a8b757042eb9ac435e1` | Adapted comment style inheritance, generated page-number exclusions, caret history, dialog switching, hit boundaries and strict analyzer fixes to the continuation implementation. |
| Zotero capabilities | `b6a6b4c42ad03eb8d0f8567e7800bb9e4e038fdb` | Integrated transitive source aliases, shared server pauses, cached dialog scans, five regression suites, and the standalone hyphenation license/generator notice cleanup. |

All three heads are actual parents of the source checkpoint, alongside the
previous continuation `54155845dfda909981e73f274a2550b265e2498b`. Local Git
ancestry checks verified this after fetching the saved commit. The initial
original-proofing checkpoint `976d05a` was already preserved as a parent of
`d3b37a9`.

New feature/docs/vendor ODS branch heads were patch-equivalent to the merged
main changes. The older vendor hyperlink adaptation had the same added and
removed production lines despite a different patch identity. Existing older
branches and upstream main were accounted for in the initial audit and the
fresh snapshot. Redundant implementations were not layered onto one another.

The continuation retains its standalone session/controller API and additional
grapheme, protected-content, pending-revision, stale-document and actual
renderer coverage. Follow-up regressions also fixed explicit `noProof`
overrides, wholly empty complex fields, and caret restoration after switching
between comments or header/footer stories. Superseded source and historical
receipts remain available through the preserved merge ancestry.

The continuation branch received incremental checkpoints with lease-protected
updates. No force push, GitHub Actions query, or CI queue wait was used.
