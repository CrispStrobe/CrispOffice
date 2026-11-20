# Local qualification evidence

The six archives retain original command receipts, source manifests, raw output,
small reproduction scripts, independent reviews, and explicitly superseded
attempts. `archive-index.json` records the SHA-256, byte size, exact file inventory,
and result/supersession notes for every bundle. Paths inside each archive are
relative to the original scratch workspace so the parent `rebind_sources.py`
can consume the extracted `qualification/`, `portable-final/`,
`pptx-validation/`, and `word-final/` directories directly.

Verify all archive and member hashes from this directory:

```sh
python3 rebuild_evidence.py --verify
```

Rebuild from the original workspace (or an equivalent directory containing the
selected evidence files):

```sh
python3 rebuild_evidence.py --workspace-root /path/to/workspace
```

For a later additional receipt in one existing bundle, pass `--only macro-local`
(or another bundle name). The builder refreshes that archive and its index entry
without discarding the others. Archive members, ownership, timestamps and gzip
headers are deterministic for identical selected file bytes and executable bits.
The builder performs no Git, network, SDK installation, or test operations.

The qualification scripts preserve their original absolute workspace paths.
Running them elsewhere requires mapping those paths and installing the pinned
runtime identified by the runtime receipts. The current source-level commands
for the portable corpus are also documented in `docs/VBA_CONFORMANCE.md`.

Bulk SDK/cache/download contents, all `artifacts/` directories, compiled JavaScript
and source maps are excluded. Their recorded hashes and the raw compiler
dependency graphs remain available. No new Office-host observations are claimed.
Development failures and superseded candidates remain labeled in the index and
their original receipts; overlapping selections must not be added into an
inflated total. In particular, the historical initial corpus generator does not
recreate the later revised 69-case fixture, and the surrogate probe source has no
separate persisted stdout receipt.

The parent milestone README and `source-bindings.json` explain how source-bound
results relate to the final reconciliation. These archives preserve the original
run evidence rather than rewriting it to imply that every gate ran on a later
commit.
