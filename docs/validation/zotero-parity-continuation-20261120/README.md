# Zotero parity continuation — 20 November 2026

## In progress

This continuation preserves the saved image-note work at `3100725d` and advances
the existing Word/LibreOffice parity roadmap with nested and multiparagraph
research lists. The remote checkpoint branch is
`codex/zotero-parity-continuation-20261120`. Main has not yet been published by
this continuation. No GitHub Actions, checks, statuses or workflow runs are
queried or awaited.

## Intake and preserved work

Captured main was `5e38de19ab5af8d6811d601c7317cba7f69d516b`. All 235 pull-request
heads, all 19 captured fork branches, and four upstream branches were fetched.
Unique current heads were integrated with original ancestry, with five separate
verified remote checkpoints:

| Incoming work | Original head | Remote integration checkpoint |
| --- | --- | --- |
| Current main | `5e38de19` | `d6ec077b` |
| VBA Variants/Word, Arabic lifecycle, font and background work | `1fe093a2` | `ef09cc41` |
| CrispOffice app identities | `afc3524e` | `6c6413b3` |
| Android spaCy grammar | `fa8b71b0` | `6adf829a` |
| PPTX normal autofit and metrics | `0e1d6d8c` | `a27df5d1` |

Each remote tree was checked against the exact local tree before the branch
advanced through a non-forced, expected-head update. Original incoming commits
remain parents in the published graph. The previous Zotero branch is retained.
VBA merge conflicts retained the image increment and complete existing test
sets without duplicating reordered test names. The PDF merge retains the
current background/visual ownership implementation and incoming text metrics.

Older ODS, ODT and union branches were already incorporated. Their changed
paths were checked by Git mode/type/blob identity against accepted main
ancestors, rather than replayed over later changes:

| Old head | Accepted ancestor | Matching changed paths |
| --- | --- | ---: |
| `c3494576` | `2c47165d` | 37 |
| `3abf8f43` | `4b2b4e78` | 221 |
| `58fdddfb` | `4eaca83b` | 1 |
| `69d14f84` | `52c73ae4` | 1 |
| `74ce9ffb` | `4584d5f3` | 7 |
| `0a53b8a7` | `b3f41eb4` | 8 |
| `68a0db23` | `d754bf15` | 4 |
| `005c708e` | `c84d5e16` | 7 |
| `7ef09f24` | `34dc6b68` | 7 |

The research-material, Mail recovery/attachments, and Android workflow heads
are already ancestors of captured main. Incoming native qualification remains
attributed to its original platform and source; it is not fresh execution here.

## Selected behavior and review findings

- Complete bounded PNG/JPEG note and image/ink annotation support already saved
  on the prior Zotero branch.
- Preserve mixed nested lists through nine levels, independent list starts,
  multiparagraph items and parent-item continuation after nested lists.
- Keep native citation fields and image positions, document preferences,
  surrounding text, and one undo/redo operation.
- Repair image-only DOCX paragraph normalization that can detach a picture from
  its list item, continuation paragraph or ordinary hyperlink.
- Repair incoming presentation autofit handling for fresh/modified model
  values, percentage syntax, bounds and consistent line-spacing behavior.
  Unchanged imported text-source XML already retained its original autofit.

## Development validation

The pinned official Flutter 3.47.8 / Dart 3.13.7 SDK archive was SHA-256 verified.
All 128 hosted archives from the existing workspace lock were hash-verified and
resolved offline with the lock enforced and unchanged. SDK tool dependencies
were resolved from their own exact lock. Only native Dart/Flutter test runtime
components are installed; no browser/mobile/native release build is implied.

At this checkpoint, the editor Add Note controller selection passes all 56
cases, including ten new structured-list transaction cases. Seven engine
selections report 164 passes and the expected newly exposed image-only list
round-trip failure; that failure remains open until the focused deserializer
repair is applied and retested. An earlier development run hit a temporary
mid-edit PDF compile error, now fixed. These development runs are not the final
combined-source acceptance.

The subsequent image-ownership repair passes 54 distinct cases in the focused
legacy-picture, image-note integration and structured-list selections, with no
failure or skip and unchanged recorded inputs. The previous image-only
round-trip failure is fixed. Bare legacy picture paragraphs keep their established
block representation; authored inline picture paragraphs retain their metadata,
list position and caret offset.

## Remaining publication gate

Finish the focused repairs, run complete Zotero engine/editor and relevant
incoming Office regressions locally, retain commands/results/source identities,
refresh remote main, publish the final checkpoint, and merge consistently.
Live Zotero, installed Word/LibreOffice, native application builds and active
ODT transfer remain separately unqualified. See the
[parity roadmap](../../roadmaps/zotero/word-processor-parity.md) for the remaining
feature work and acceptance boundaries.
