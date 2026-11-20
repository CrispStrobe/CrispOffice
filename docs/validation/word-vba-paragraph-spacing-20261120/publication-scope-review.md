# Independent publication-scope review

Status: **PASS_WITH_EXPLICIT_DEFERRALS** against `ed750f1f6b8acab88406fd506e0dd511adcc4485`.

Every reference from the original intake is included or historically equivalent. The three selected original late heads are tracked separately from their newer continuations. Later moving work is explicitly deferred; all captured entries are classified.

| Captured source | Total | Incorporated or equivalent | Selected pending | Deferred | Unclassified |
| --- | ---: | ---: | ---: | ---: | ---: |
| fork_branches | 33 | 25 | 0 | 8 | 0 |
| fork_pull_requests | 270 | 264 | 0 | 6 | 0 |
| upstream_branches | 4 | 4 | 0 | 0 | 0 |
| upstream_pull_requests | 4 | 4 | 0 | 0 | 0 |

## Explicitly deferred captured heads

- `90ecd41c8a3ef2a6f35967f1219223022e2b0d32` — Later paragraph-controls implementation; draft PR268 qualification in progress. Captured refs: `refs/heads/codex/word-vba-paragraph-controls-20261120`, `refs/pull/268/head`.
- `b08e0a55b629ac22b33c54146b56438862965022` — Later App Store submission documentation. Captured refs: `refs/heads/docs/app-store-submission-20261120`, `refs/pull/266/head`.
- `3c6637b6e5585de5fb4b8d27a0ceda6f96edb95f` — Later App Store screenshot feature. Captured refs: `refs/heads/feat/app-store-screenshots-20261120`.
- `be47bed22a88382f016d823e526bae49590bd0eb` — Later Arabic web context feature. Captured refs: `refs/heads/feat/arabic-web-context-20261120`, `refs/pull/267/head`.
- `864292e8896f925bae461731993f343b1b929d7d` — Later Arabic web settings feature. Captured refs: `refs/heads/feat/settings-arweb-20261120`, `refs/pull/269/head`.
- `81691cde9606302cd8dee7ebe28d7532c858393d` — Later bookmark typing fix. Captured refs: `refs/heads/fix/bookmark-typing-20261120`.
- `15cd2ff4188ec811cb8f41d7480a0480d888136e` — Later main-green continuation; distinct from selected original PR264 head. Captured refs: `refs/heads/fix/main-green-20261120`, `refs/pull/264/head`.
- `f4f0da7379822d030e3549292696e76a6fd05526` — Later Mail parity continuation. Captured refs: `refs/heads/work/mail-parity-20261120`, `refs/pull/270/head`.

The raw inclusion audit intentionally retains all uncovered references and exit code 1. A fully classified publication scope does not turn deferred work into incorporated work. This review uses immutable captured SHAs and retains the 13 full-tree proofs plus the exact 37-path continuation proof. No GitHub Actions were queried or awaited.

The current report is an ancestry/source-inclusion review, not new runtime qualification of the deferred features.
