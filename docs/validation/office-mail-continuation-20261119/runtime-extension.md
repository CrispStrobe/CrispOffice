# Runtime extension for the secure-storage lock

The Mail connectivity/keychain continuation changes the workspace lock from
`35d1ef372908f4ab278973355ec6a957cd3240bea115d615056c5b9e398df974` to
`72a5a52654a1484f4df646c631b4d1ea47e96025a671beff045eecf2b9e78e82`.
The original runtime restorer remains pinned to its original profile. Its SDK
archive, 176 hosted archives, omission policy, executable hashes and original
restore runs have not been relabeled as a restoration of the newer lock.

`extend_runtime.py` verifies that original ready runtime, preserves its receipts
and package mappings, and extends its hosted cache by the exact 18 additions in
`runtime-extension-locks.json`. The union of workspace and Flutter-tools hosted
archives becomes **194**, with no old archive removed or replaced. Only those
18 new archives are downloaded. Their full archive contents are retained;
the original cache omission record is left byte-identical.

Before touching the cache, the extension rehashes every original retained input
and every already-bound external input, including any prepared CLD3, native
fixture, Camel Morph and model files. It marks the current runtime `extending`
and removes its ready marker. After verified extraction, it performs real
`dart pub get --offline --enforce-lockfile` resolution and the original native
SQLite smoke through an entrypoint owned by `quds_mail_store`. It refreshes the
workspace graph and native bindings without changing an existing external
library hash. Only the generated native-assets mapping may be regenerated.
The original SDK identity and restore run records remain unchanged.

## Replay from a fresh checkout

Use a dedicated clean checkout and empty external runtime/evidence directories.
Keep the **same absolute checkout path** for both source revisions: package
configuration and native provenance are location-bound. Set `QUALIFIED_SOURCE`
to the frozen source commit named by the new aggregate receipt. Do not use the
old implementation commit as acceptance for the later integrated source.

```bash
REPLAY_REPO="/absolute/path/to/clean-checkout"
REPLAY_RUNTIME="/absolute/path/to/office-runtime"
REPLAY_EXTENSION="/absolute/path/to/runtime-extension"
QUALIFIED_SOURCE="<frozen source commit from the aggregate receipt>"

git -C "$REPLAY_REPO" switch --detach 4c25c0455cee867db4cfad0f737cb886f01c1936
python -B "$REPLAY_REPO/docs/validation/document-review-notes-20261118/runtime/restore_runtime.py" \
  --repo "$REPLAY_REPO" --runtime-root "$REPLAY_RUNTIME" --node-tests

git -C "$REPLAY_REPO" switch --detach "$QUALIFIED_SOURCE"
python -B "$REPLAY_REPO/docs/validation/office-mail-continuation-20261119/test_extend_runtime.py"
python -B "$REPLAY_REPO/docs/validation/office-mail-continuation-20261119/extend_runtime.py" \
  --repo "$REPLAY_REPO" --runtime "$REPLAY_RUNTIME" --output "$REPLAY_EXTENSION"
```

Then prepare the source-pinned CLD3 real backend and cleanup fixture,
Camel Morph backend and four-file local bundle, and separate web SDK using
`prepare_language_id.py`, `prepare_arabic_morph.py` and `prepare_web_sdk.py` from
the frozen source. Each native preparation adds its real artifact hashes to the
ready runtime receipt. An already-prepared original runtime can also be extended:
the extension preserves and verifies those native bindings, as in this recovery.
No regeneration of a native library is needed merely because hosted Dart
dependencies were added.

Use the complete gate and independent acceptance audit from the frozen source.
The outer gate now requires the exact ready extension profile, binds its receipt
and logs, and runs the extension integrity controls in addition to all existing
stages. The independent auditor reconstructs the original/new archive union,
compares all original retained entries, and checks every retained new package
file directly against its locked archive. The controls and preparation smoke
do not replace the aggregate tests or establish installed keychain behavior.

## Evidence and interrupted extensions

The external extension directory contains the untouched original runtime,
retained-input, package-cache and omission receipts; original package/native
mappings; the original workspace lock; the 18 exact downloaded archives;
extracted staging copies; two raw command logs; and `extension.json`.
The updated runtime binds the original evidence, downloaded archives and
extension receipt as additional inputs. The outer gate separately freezes both
raw extension logs. Extracted staging copies can be omitted from an evidence
archive when the exact package archives and verification records are preserved;
they are redundant package bytes, not an additional source of provenance.
Pub version/advisory cache JSON encountered during development is retained and
hashed separately. The auditor allows only version/advisory JSON in Pub's
metadata directory, verifies its structure and identity, and separately reports
cached package names absent from the lock. These entries do not add packages to
the enforced dependency graph. It counts metadata separately from package files;
it does not attribute their contents to the 18 verified package archives.

A failed extension remains `failed` and has no ready marker. The tool refuses
to overwrite a previous attempt or a partially installed addition. Preserve
that attempt for diagnosis and replay into a fresh runtime; copying an old
ready receipt over a changed cache does not restore the original runtime.
The original preserved receipt is historical evidence, not an acceptance claim
for the new dependency graph. This workflow does not query or wait for GitHub
Actions.
