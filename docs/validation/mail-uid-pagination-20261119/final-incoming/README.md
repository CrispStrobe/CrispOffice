# Final bounded incoming reconciliation

The final live capture completed on 19 November 2026 at 08:03:00 UTC for
the fork and 08:03:04 UTC for upstream. It records 421 actual refs:
219 fork branches, 181 pull-request heads, 17 tags and four upstream branches.
Four peeled tag advertisements are retained separately in the raw 425 rows.
No GitHub Actions workflow, job or status was queried or awaited.

The previous 1,000-execution source `960fb72f` left 13 captured rows outside
its ancestry/equivalence accounting. `frontier.json` identifies the five
minimal tips merged to preserve all new work, including captured main
`dc267fb4957d5a6499ce8174fd4a2acc39a4acf8`, the v3 cursor freshness fix,
Arabic writing rule corrections and the optional Hunspell package.
`integration-requirements.json` records source and evidence path deltas.

The published combined checkpoint
`94b4f2bdc541cbd3821b3dfaeb40a6a1466f4eb2` accounts for every captured ref:
393 actual refs are ancestors and 28 are covered by 14 independently
recomputed historical-equivalence proofs. No ref is unaccounted for.
`published-merged-source-audit.json` binds that result to the published SHA;
this is incoming-history evidence, not a test receipt for the combined source.

Replay from repository root (replace HEAD only for a later integration audit):

```sh
python3 docs/validation/mail-uid-pagination-20261119/final-incoming/audit_capture_ancestry.py \
  --repo . --head 94b4f2bdc541cbd3821b3dfaeb40a6a1466f4eb2 \
  --refs docs/validation/mail-uid-pagination-20261119/final-incoming/origin-refs.txt \
  --upstream-refs docs/validation/mail-uid-pagination-20261119/final-incoming/upstream-refs.txt \
  --output /tmp/quds-final-incoming-audit.json
```

Inspect the output `passed` field, not only process exit status. The replay
uses captured immutable object IDs and does not refresh remote refs.
The earlier `incoming` and `preflight-incoming` captures remain unchanged.

## Later main update before the combined source freeze

Main advanced to `b655b8a3` after the capture, adding the Arabic rule specification
and a macOS Studio runner. That head was merged normally before the next local
qualification. [The separate review](late-main-review.json) records all 33 paths:
32 match incoming main exactly; the Arabic roadmap retains both new specification
links and the already reconciled implementation status. No Dart implementation
changed. Plist/XML/JSON assets parse; a macOS build or run was not performed on
this Linux host. This update does not relabel the earlier 421-ref capture.
