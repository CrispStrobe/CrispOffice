# Captured incoming-work reconciliation

This is a bounded inventory of `CrispStrobe/quds_office_suite`, captured through
the GitHub connector on **2026-11-18 at 20:15:31 UTC**. It records the remote
heads observed then, not a claim about later remote changes. No GitHub Actions
result was queried, dispatched, or awaited.

## Coverage

All **386 refs** were accounted for: 210 fork branches, 172 pull-request heads,
and four upstream branches, representing 251 unique commit heads.

| Classification against the handoff | Refs |
| --- | ---: |
| Already included in the handoff | 350 |
| Included by the captured review fast-forward | 6 |
| Included by the captured Mail merge | 2 |
| Historical equivalents freshly verified | 28 |
| **Total** | **386** |

There were no missing commit objects and no unaccounted heads. The 28 historical
refs correspond to 14 distinct heads. Their patch equivalence, identical trees,
or 37 exact changed-file identities in the recovered ODT continuation were
rechecked against the preserved history. They were not reapplied.

## Captured heads and completed integration

| Role | Captured commit |
| --- | --- |
| Thesaurus handoff | `0e84dc951e7a9e923107d7895fa457cf29a7af71` |
| Fork main, already included | `4fbc8741f314af67592517595c760ba3036dedba` |
| Document review | `4600c0ebc9ac5e6acabd92935821d1c15315f2c1` |
| Mail reader | `2fef06f5fe9aefb07a48c75c0e762eee3edf26e1` |

The review head is a descendant of the thesaurus handoff. It already includes
the captured Zotero Notes head `c93fc23b388a053f0b4742b771adb511aaf3578a` and
spaCy head `637b67c58482e40a3244c590ce77c08b9fc2740e`. The separate Mail head
adds seven commits absent from review, covering offline assets, reader
presentation, compact navigation, inline draft feedback, PDF thumbnail resize
handling, and evidence.

The local immutable merge commit
`813a7cdd7d55f2028e377393ae6bbc7388f5db73` has the captured review and Mail heads
as its two parents. Its tree is `35339d2a22adc3a4057bc42b623149a5e9dd9365`.
The separate [ancestry receipt](incoming_merged_ancestry.json) confirms that
handoff, main, review, and Mail are all ancestors. This ancestry check does
not establish runtime acceptance or the semantic correctness of conflict
resolution; those require their own source review and validation evidence.

## Scope of conflict resolution

The integration retained review's measured title/ribbon sizes, full-scale
actions, stable ribbon-scroll identity, and protected-document inspection.
It incorporated Mail's compact navigation sheet, navigation updates, separate
compact PDF thumbnail controller, flexible status text, and explicit over-limit
reply feedback. The combined Arabic draft test uses Mail's 390-pixel layout
and navigation exercise. The web network-guard parameter retains the clear
`asyncValue` spelling. These decisions do not themselves claim passing tests.

## Replay and source files

Keep these files together:

- [Captured fork branches and PR heads](incoming_audit_snapshot.json)
- [Captured upstream branches](incoming_upstream_snapshot.json)
- [Original classifications and equivalence checks](incoming_audit_result.json)
- [Read-only replay script](audit_incoming_current.py)
- [Integrated commit ancestry](incoming_merged_ancestry.json)

Run against a checkout containing the captured commit objects:

```sh
python audit_incoming_current.py --repo /path/to/quds_office_suite
```

When the script is stored beneath the checkout, `--repo` may be omitted. The
script reads sibling input JSON files, does not fetch or mutate Git refs, and
writes `incoming_audit_replay.json` beside itself by default. Use `--output` to
choose another replay destination. The original capture and decision files
remain unchanged. The portable replay was checked to reproduce the original
report exactly apart from its recording timestamp.
