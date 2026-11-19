# AyaSpell publisher controls after the final main reconciliation

The publisher is retained byte-for-byte from main
`b655b8a37fddc874bd42a453c371eed6253e82d8`, Git blob
`9257d987fc3a4307a33bc82465fcd03f777f7e28`. Its upload allowlist contains only
verified manifest members plus `manifest.json`, so unrelated files in an
existing output directory remain local. This supersedes the earlier
fresh-output-directory guard; its historical seven checks remain attributed
to that earlier implementation.

The only publisher test change aligns one imported card-text assertion with
the current card, exactly as asserted in `test_build_bundle.py`. All existing
behavior controls remain intact. The three test files use synthetic fixture
bytes, stub downloads and in-memory publication APIs. The replay driver also
blocks `urllib.request.urlopen` and `socket.create_connection`.

- Accepted final run: 17 cases passed; zero failures, errors, skips or network
  attempts. Helper/test hashes match before and after the run.
- Excluded first run: 17 cases executed, 16 passed and one stale card-wording
  assertion failed. All 17 executions from that first run contribute zero to
  the accepted count. Original logs and receipt are preserved without edits.

These are separate publisher controls, not additions to the earlier 836 Mail
application executions, 78 Python controls, or 179 proofing executions. They
do not establish actual Hub publication, dictionary quality, external download
acceptance, or installed-app behavior.

## Replay

Use the resolved source containing the helper and three test hashes recorded
in `index.json`, with a new output directory outside the checkout:

```bash
python3 -B docs/validation/office-main-completion-20261119/release/publisher-main-controls/run_offline_publisher_tests.py \
  --repo "$QUDS_REPO" --output "$QUDS_RESULTS/publisher-controls"
```

The driver writes its raw unittest log and JSON receipt. It does not query CI,
perform real network requests, or publish resources. `index.json` contains
per-file hashes for this evidence and the selected source identities.
