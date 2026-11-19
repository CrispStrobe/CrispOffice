# Incoming reconciliation before UID pagination

The bounded origin advertisement completed at **2026-11-19 07:40:04 UTC**
(08:40:04 CET), followed by the upstream advertisement at 07:40:08 UTC.
The original bytes and SHA-256 digests are retained in `origin-refs.txt`,
`upstream-refs.txt`, and `capture.json`.

The published integrated baseline is
`c1dc63f934f81e22a41bafd98df1abf22ee6a053`, tree
`4f52dbcc23c917a592eea69d44a369e19c26e490`.

| Captured reference kind | Count |
| --- | ---: |
| Fork branches | 215 |
| Pull-request heads | 175 |
| Tags | 17 |
| Upstream branches | 4 |
| **Actual references** | **411** |

Four additional rows are peeled annotated-tag advertisements, not additional
references. The post-integration audit accounts for all 411 actual references:
383 are ancestors and 28 are historical equivalents supported by 14 freshly
recomputed proofs. The historical equivalents remain non-ancestors. No captured
reference is missing or unaccounted for.

## Incoming changes preserved

- Mail `700e5a35` adds the final M06 report and retained evidence.
- Office integration `ac1e4c8c` includes that Mail checkpoint and preserves
  Socket-compatible TLS, strict FETCH handling, failure-path connection abort,
  the additional TLS assertions, and distinct-object flag equality coverage.
- Zotero `ca61a188`, followed by publication audit `b0a9bd3f`, reconciles the
  previously qualified Office source and evidence. Remote main advanced to
  `55e262ef` during capture by merging PR #173; that merge is included.
- Arabic `dd953dcc` adds the roadmap and reproducible AyaSpell download-bundle
  utility. It does not enable Arabic proofing in the product.

The initial audit of the earlier `d4100033` main is retained as
`initial-audit.json`. It intentionally reports unaccounted heads and the two
concurrent commit objects that had not yet been fetched. The passing
`post-integration-audit.json` follows the fetch and local merges at `4a3953dd`.
The identical tree was published as `c1dc63f9`;
`published-baseline-audit.json` rechecks ancestry on that actual remote checkpoint.
These are ancestry
and immutable-source checks, not new runtime acceptance results.

## Replay

From the repository root:

```sh
python3 docs/validation/mail-uid-pagination-20261119/incoming/replay_audit.py \
  --head c1dc63f934f81e22a41bafd98df1abf22ee6a053 \
  --output /tmp/mail-incoming-audit.json
```

The replay wrapper invokes the committed independent ancestry checker, verifies
its recorded digest, and treats a false report result as a nonzero exit. It
does not query the network, mutate refs, or query GitHub Actions. A later remote
refresh must have its own capture and attribution; this report does not imply
that branches cannot advance after the recorded cutoff.
