# Combined-main Zotero integration qualification

This record qualifies the combined published source after a concurrent main
update was detected during the separator PR's final read-back. It preserves
both changes and keeps their original execution evidence distinct.

## Published source and detected difference

| Identity | Meaning |
| --- | --- |
| `a1b555979b25c5586f27915cf219a95e886febd7` | Original separator qualification source. |
| `a70c0e7af251d737dc7639f44a48777bbea1bf51` | Separator PR head, adding only documentation and evidence after qualification. |
| `2f7f5ffc668d7f6452facb13e006e6704c93f439` | Concurrent main merge of host ownership and shortcut safeguards, PR #347. |
| `ad577ea82695231b5932d6b973f92b5156b1d2d6` | Published separator merge, PR #348; parents are the preceding two heads. |

The last prepublication fetch saw `cc797dc2`. The eventual merge correctly
retained newer main `2f7f5ffc`, so its tree differs from the separator branch.
The immediate read-back deliberately failed its expected-tree assertion and
triggered this follow-up. Neither change was reverted or overwritten.

Compared with the original 6,319-input capture, seven existing inputs changed
and one test was added. The three production changes are the shared Zotero
dialog and Studio's shortcut/workspace code. The other changes are editor
release notes and Studio tests. Every engine, parser, dependency, font and
package-configuration input remains identical. The
[source-continuity record](source-continuity.json) enumerates exact old/new
hashes and the unchanged input groups.

## Qualification and accounting

**Accepted: 3,794 distinct qualified cases, zero failures, errors or skips.**
The [qualification receipt](checks/qualification.json) and
[independent audit](checks/independent-audit.json) separate retained engine
execution from the fresh combined-source UI execution:

| Gate | Source / scope | Qualified cases |
| --- | --- | ---: |
| Retained engine | `a1b5559`; 122 suites; exact engine/dependency continuity to `ad577ea` | 2,677 |
| Fresh editor | `ad577ea`; original 55 suites in five disjoint batches | 1,022 |
| Fresh Studio | `ad577ea`; all eight relevant host/shortcut/ODT suites | 94 |
| Fresh continued-notes golden | `ad577ea`; three pages initially and after three DOCX exports | 1 |
| **Unique total** | **2,677 retained engine + 1,117 fresh UI cases** | **3,794** |

Strict analysis reports no issues across all 29 changed Dart files; formatting
reports zero changes. The audit excludes 18 successful fixture hooks and 186
successful loader completions. Fresh streams have complete lifecycles and
empty stderr. The golden makes 12 image comparisons against unchanged baseline
images. Earlier overlapping UI and development runs are not added to this total.

All fresh gates share this unchanged 6,320-input manifest:

```text
b88774ebf481f2e7710704f4363eb1ec8f670e1814ab294ad1a719a830124b65
```

All 6,319 tracked captured inputs match the combined Git source; the unchanged
generated package configuration is the sole additional input. The pinned Dart
and Flutter test executable hashes and the unchanged workspace lockfile were
rechecked. The [captured-intake replay](intake-replay.json) again accounts for
345 ancestor observations and 14 verified historical replacements.

Frozen audit SHA-256:
`bd1a467ca3b34183f47b05d9d2e387fecf8ebfb49340ec1c09866abced055e62`.
Frozen source-continuity SHA-256:
`fe7cf34ffc8373b77d733a7969206e3dd2ebed50fb742e58f022337776222007`.

The original 2,677 engine cases retain source attribution to `a1b5559` and
are applicable through the explicit continuity proof. Engine source, tests,
tools, local dependencies, runtime/dependency configuration and referenced
font assets have no changes. The new shared dialog and Studio implementation
is outside the engine's dependency direction.

Editor, Studio, the existing continued-notes golden, and strict static checks
run freshly against `ad577ea`. All 55 original editor suites are retained.
Studio adds five suites to the original three, reproducing the eight-suite
host-ownership scope: settings, shortcut catalog/dispatch, Mail isolation,
Zotero commands/transport, ODT opening and editable ODT export. Analysis and
formatting cover the union of all 29 changed Dart files.

The fresh 6,320-input manifest is checked before/after each execution and
against the exact combined Git source. Original editor, Studio and golden
runs are superseded for this aggregate, not added to the fresh results.
Earlier host-ownership totals also retain their separate original source
attribution. Successful hooks/loaders and repeated runs are excluded.

## Integration review

The incoming host predicate strengthens existing edit, protocol and final
publication guards. It does not replace the separator's immutable model or
transaction source guard. Leaving Word invalidates the navigation generation;
returning cannot revive an earlier operation. Zotero's own nested dialogs
remain within the originating host's lifetime.

Fresh checks cover the two delayed-publication regressions, focused authored
notes, reserved citation chords, hidden-document mutation prevention, native
text actions in Mail/dialogs and ODT open/save dispatch. No production fix was
needed to combine the changes.

The engine, model, file readers/writers, layout and converter acceptance tool
are unchanged, so the identified converter evidence retains its original
scope. Installed Word, supported-release LibreOffice and live Zotero plugin
acceptance remain separate work; the known custom-DOCX separator normalization
is not reclassified as passing.

## Publication safeguards

The follow-up branch is `codex/zotero-main-qualification-20261121`, created
from the actual published merge. It retains the original separator branch and
all earlier checkpoints. Publication adds evidence and documentation only.
The final merge uses the observed main commit as an explicit expected head
and a non-forced fast-forward ref update to a reviewable merge commit. An
intervening main update therefore requires inspection before retrying.
Remote read-back verifies ancestry, source hashes and a clean local main.

GitHub Actions, commit checks and workflow queues are neither queried nor
awaited. The actual command arguments and raw event receipts are retained
beside this record, with the original pinned runtime receipts one level up.
