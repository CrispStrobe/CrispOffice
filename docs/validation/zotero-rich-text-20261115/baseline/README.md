# Executed baseline validation — 15 November 2026

Before the new rich-text changes, the existing Zotero branch at
`0d9b008720b01371bc9db498efd063e3077be279` was tested from a frozen Git archive.

- Engine/client/native-field cohort: **103 passed**, exit 0.
- Shared Flutter controller/formatter/dialog cohort: **68 passed**, exit 0.
- Total: **171 passed**, including the 39 cases previously committed but unexecuted.

The runtime is official Flutter 3.47.8 / Dart 3.13.7. The official Dart archive
SHA-256 matched its sidecar, and Flutter source is pinned to the official tag's
framework commit. Standard Flutter tooling fetched its normal artifacts.
Dependencies were genuinely resolved with Pub from standalone staging manifests;
the repository source/tests were unchanged, and repository dependency manifests
were not relaxed. The receipt includes exact source revision, commands,
manifests, lockfiles, source links, runtime identities, and log hashes.

This is focused baseline execution, not a full workspace or native application
build. New source changes require their own subsequent verification. No GitHub
Actions were polled, awaited, or rerun. Remote checkpoints use `[skip ci]`.
