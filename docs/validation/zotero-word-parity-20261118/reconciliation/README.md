# Incoming work reconciliation

The bounded inventory was captured at **20:17:13 UTC (21:17:13 CET) on
18 November 2026**, before this Zotero increment. It covers **386 refs**:
210 fork branches, 172 pull-request heads, and four upstream branches.
The inventory contains the exact fetched SHA for every ref; it does not claim
to cover remote changes published after that observation.

## Result

At integration commit `aad56eb498aa4839ad5bb11fd35d9f734d2ca397`, all captured
refs are accounted for:

| Disposition | Refs | Verification |
| --- | ---: | --- |
| Included by ancestry | 358 | Fresh `git merge-base --is-ancestor` for each captured head |
| Historical equivalent | 28 | Fourteen distinct historical heads, independently rechecked below |
| Unaccounted | 0 | No recent captured work remains outside the integrated baseline |

The starting Mail head was `2fef06f5fe9aefb07a48c75c0e762eee3edf26e1`.
Its three missing recent heads were document review
`4600c0ebc9ac5e6acabd92935821d1c15315f2c1`, offline thesaurus
`0e84dc951e7a9e923107d7895fa457cf29a7af71`, and the prior Zotero evidence
head `c93fc23b388a053f0b4742b771adb511aaf3578a`.
The review head already contains the other two, so one real two-parent merge
integrated all three. The starting head already contains main, the Mail
reader foundation and its later fixes, the published English/French spaCy
follow-up, and all four captured upstream heads.

## Published baseline identity

The local merge above was published through the GitHub connector as
`aad56eb498aa4839ad5bb11fd35d9f734d2ca397`. Both commits have the exact Git tree
`3e819144230aedf16278a57cfaf56658c2cc325f`. A separate complete rerun against
the published commit is saved in `published-baseline-audit.json`; it again
reports 358 ancestors, 28 verified historical equivalent refs, and zero
unaccounted refs. The original audit is retained to preserve the local-to-remote
publication trail.

## Historical equivalence

Old rebased, squashed, or independently merged branch names are not merged
again solely to create ancestry. The local audit reruns the earlier evidence:

- Ten heads have only patch-equivalent non-ancestor commits according to
  `git cherry` against the new integration commit. Every returned line is
  negative; the exact lines are retained.
- Three heads have exactly the same Git tree as a landed ancestor. Both
  trees and the landed equivalent's ancestry are rechecked.
- The old PR #140 head has identical Git blobs for all 37 files changed
  from its comparison base at landed equivalent
  `2c47165d01d01cc883135a434ac9f6591ce6e770`. All 37 source and equivalent
  blob pairs, the comparison base, and the landed commit's ancestry are
  retained.

Each of these fourteen heads appears twice in the snapshot, as a branch and
a PR head. These proofs establish preserved history at the landed equivalent;
they do not undo later deliberate changes, including AOT removal.

## Merge decisions

The implementation owner resolved four overlapping files. An independent diff
review confirmed the resulting choices:

| File | Preserved behavior |
| --- | --- |
| `packages/quds_mail_ui/test/support/runtime_network_guard_web.dart` | Review's clearer `asyncValue` parameter name; the network-blocking callback behavior is unchanged. |
| `packages/quds_office_editor/example/lib/studio_chrome.dart` | Review's measured line heights and command sizing, with its app-switcher padding. |
| `packages/quds_office_editor/example/lib/suite_workspace.dart` | Review's measured title/ribbon height and scrollable title actions; Mail's compact navigation, separate PDF thumbnail controllers, scaled tab height, and draft-limit feedback; the review ribbon-tabs key remains available. |
| `packages/quds_office_editor/example/test/studio_comment_draft_proofing_test.dart` | Mail's stronger 390-pixel Arabic, 1.4-times text-scale scenario and modal navigation coverage, together with review's explicit over-limit feedback assertion. |

The cleanly applied editor context-menu selection change from review is also
retained. The MIME pubspec change removes one trailing blank line only.
This reconciliation review checks history and source choices. It does not
claim runtime acceptance of the merged widgets; the local qualification
report owns those results.

## Files and reproduction

- `captured-refs.json`: frozen incoming ref inventory.
- `pre-integration-audit.json`: starting Mail head, with five refs at three
  recent unique heads still missing before the real merge.
- `audit.json`: the completed integration audit and all equivalence evidence.
- `audit_refs.py`: reruns the local ancestry, patch, tree, and blob checks.

From the repository root:

```bash
python3 docs/validation/zotero-word-parity-20261118/reconciliation/audit_refs.py \
  --head aad56eb498aa4839ad5bb11fd35d9f734d2ca397
```

No GitHub Actions, checks, workflow, or status endpoint was queried or awaited
for this audit. The audit neither changes refs nor merges or stages files.
