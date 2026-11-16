# Refreshed incoming Quds work accounting

Observed UTC: `2026-11-16T13:41:20.649412+00:00`. Ancestry is evaluated against exact
published continuation commit `8e017e8c148517fea61f8d55eaafc7f070b82bba`. This refresh reads only
already-fetched local `origin` and `upstream` refs; it performs no new fetch.

The observed refs and times above are unchanged. Ancestry was re-evaluated at
`2026-11-16T13:45:05.938340+00:00` against this published checkpoint, whose tree
is `17eecf8b8c8558c78dbbefe9ffc9b1249e2455cf`. That tree is identical to the local checkpoint originally
used for this inventory. Any local-only checkpoint hashes in the JSON are
explicit provenance and are not required to reproduce the graph results or
recover the preserved initial files.

## Cutoff and original evidence

The [machine-readable inventory](incoming-refs.json) records every local ref,
remote-ref mapping, SHA, ancestry result and disposition, plus the exact raw
ref snapshot and its SHA-256. These observed refs define the cutoff; the
inventory does not claim that remote branches stopped changing.

The initial inventory and narrative remain byte-for-byte copies:

| Preserved file | SHA-256 |
| --- | --- |
| [initial-incoming-refs.json](initial-incoming-refs.json) | `f135f3a919ca5be8813c6b2f047d4ad46b46a6950ed5f8bd5c9b6d9a259e4e02` |
| [initial-incoming-work.md](initial-incoming-work.md) | `2da282cd0aa254d16daf6da73619e1ed6dc4d5d28784fad37efcfbf3de3060a9` |

Compared with the initial 109 incoming refs, this snapshot adds the alternate
proofing resume branch, feature and vendor hyperlink branches, and PR #59's
head. Origin main advances from `e5e1e9af` to `14b13980`, and proofing advances
from `066e0797` to `52d6ae43`. No initially recorded incoming ref disappeared.

Origin ref reflogs record the heads-plus-PR-heads fetch update at
`2026-11-16T13:28:03+00:00`; the observed upstream-main entry records its
heads-plus-PR-heads fetch at `2026-11-16T13:07:45+00:00`. These are exact ref
update observations, not a claim about the completion time of every later
unchanged-ref fetch. The latest local `FETCH_HEAD` write,
`2026-11-16T13:31:52.421782+00:00`, contains only a subsequent
continuation-branch verification fetch at `b6a6b4c4`. It must not be treated
as the full incoming-ref cutoff.

## Exact integration and disposition

| Incoming work | Exact observed head | Result |
| --- | --- | --- |
| Origin main | `14b13980e0005f4a56e0d0790ed3a2c1fa4798e2` | Ancestor through combined merge `b6a6b4c4`; includes ODS hyperlink PR #59. |
| `codex/proofing-20261116` | `52d6ae43b659875e92b06cbabdd8f206aabbad6c` | Ancestor through the same merge; retains the integrated proofing session, review UI and source-mapping changes. |
| `feat/ods-hyperlinks` and PR #59 head | `e5daa20587e10971e8cb97d82a5495584b5c1553` | Retained as an explicit parent of published `8e017e8c`; source files already match main, while ancestry is explicitly preserved. |
| `codex/proofing-20261116-resume` | `4d395da7c1253dbebfce4a5065fdfd257939ce1c` | **Not an ancestor.** Selected caret/direction fixes are present in published `8e017e8c`; the alternate session and optional packaging changes remain on the retained remote branch. See [resume disposition](resume-disposition.md). |
| `vendor/ods-hyperlinks` | `95debbcce02c1e24d6e8159cd1f524bbf68afeba` | **Not an ancestor.** Its hyperlink behavior is superseded by feature/main, which retain newer validation and namespace behavior. This is behavioral supersession, not whole-branch patch equivalence. See [vendor disposition](ods-vendor-disposition.md). |
| Upstream main | `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` | Ancestor; all other observed upstream heads are ancestors as well. |

The exact combined merge has parents `039c1e29`, `14b13980` and `52d6ae43`.
The published checkpoint has parents `b6a6b4c4` and `e5daa205`. Its selected
caret fixes do not make the alternate resume head ancestral and do not imply
that all of that branch's changes were merged. The two retained
nonancestor branches have explicit source-review dispositions.

## Complete observed ref accounting

| Remote | Branch heads | PR heads | Ancestors of continuation | Nonancestor refs with explicit disposition |
| --- | ---: | ---: | ---: | ---: |
| `CrispStrobe/quds_office_suite` | 46 | 59 | 103 | 2 |
| `MohammedAsaadAsaad/quds_office_suite` | 4 | 4 | 8 | 0 |
| **Total** | **50** | **63** | **111** | **2** |

All **113 observed incoming refs are accounted for**: 111 are ancestors and
two have the explicit dispositions above. This is not a claim that every
incoming branch was merged. Fetched origin main alone contains 108 of the
113 ref heads; the proofing head and both feature/PR aliases have additional
retained ancestry on this continuation.

## Scope and exclusions

The current continuation branch `codex/zotero-capabilities-20261116` is excluded
from incoming counts, including its observed remote-tracking value. Symbolic
remote `HEAD`, tags, local-only branches and synthetic PR merge refs are also
excluded. Refs advertised after the recorded observation, or not present in
the existing local remote-tracking inventory, are outside this snapshot.
PR heads alone do not establish PR state or review approval.

This refresh modifies only these audit documents and preserves the initial
copies. It makes no merge, commit, push, fetch, GitHub Actions, workflow-job,
commit-status or check query. Runtime qualification is recorded separately.
