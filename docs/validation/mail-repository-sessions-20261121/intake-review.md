# Incoming work before repository-backed Mail sessions

The work branch starts from `2cd11ced136a30354169fd0043e002079bcabfa3`,
which preserves remote main `84046975f286407e3c62e5e5352bc16bc89c0d26`
and all three incoming `perf/keystroke-trace-20261121` commits.

The complete live ref advertisement is retained in `intake.json`:

| Captured refs | Count |
| --- | ---: |
| Fork branches, including this work branch | 44 |
| Fork pull-request heads | 283 |
| Upstream branches | 4 |
| Upstream pull-request heads | 4 |
| Total | 335 |
| Ancestors of the integrated starting point | 311 |
| Independently verified historical equivalents | 24 |
| Uncovered work | 0 |

The GitHub open-PR search returned no open pull requests. Recent PRs #281
(Word PageSetup), #282 (Mail uncertain-action recovery), and #283 (Zotero
paragraph ranges) are already included in main. The upstream repository is
`MohammedAsaadAsaad/quds_office_suite`; its advertised refs are unchanged
from the previous intake and are included in the proof.

Historical equivalents were checked again against Git objects, rather than
accepted from an earlier report: each replacement is an ancestor, and either
its complete tree or all paths changed by the source exactly match. The
335-row receipt identifies every disposition and retains those proofs. The
10 divergent current branches fall within this historically equivalent set;
their obsolete deltas are not reapplied over newer implementations.

The incoming performance branch adds keystroke attribution, a profile-mode
benchmark and a document-replacement layout correction. It has no Mail
source overlap. Review identified a retry-state defect: a failed replacement
layout could cause a subsequent read to return the previous document's
layout. This work restores the stale flag after failure and adds regressions
for lazy and explicit layout failures, repeated failure, fresh full-layout
recovery and stable caching after success. The timed-listener bookkeeping is
also released on disposal. Local validation results are recorded separately.

To replay the inventory from a clone containing the fork's branch and PR
objects, run the retained verifier against the desired final head:

```sh
python3 docs/validation/zotero-multiparagraph-20261121/publication-intake/audit_intake.py \
  --head HEAD \
  --snapshot docs/validation/mail-repository-sessions-20261121/intake.json \
  --output /tmp/mail-repository-sessions-intake-replay.json
```

GitHub Actions, workflow queues, check runs and statuses were neither queried
nor awaited. No repository protection or workflow policy was changed by this
intake; the performance branch's existing workflow is preserved with its
source history.
