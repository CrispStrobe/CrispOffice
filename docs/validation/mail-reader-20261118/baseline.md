# Mail reader source and toolchain receipt

The implementation branch is `codex/mail-reader-20261118` in
`CrispStrobe/quds_office_suite`. Work began from main
`4fbc8741f314af67592517595c760ba3036dedba`, the saved Mail scope and plan.
The fresh checkout had no user modifications and no competing Mail packages.

## Incoming work

Fetched all remote heads and PR head refs before implementation. The initial
inventory accounts for 207 pre-existing branches and 169 PR heads. The initial
document-review head (`eedf2aee`) includes the Zotero follow-ups; the completed
thesaurus head (`315beeb3`) adds two commits beyond their common baseline.
Both were merged with main on the implementation branch. Six overlapping
review/thesaurus files were reconciled, preserving both feature sets.

See `initial-reconciliation.md` and the three `baseline-*.json` inventories for
full SHA identities and proof of the 14 historical equivalent heads. They were
not blindly re-applied. The first two remote integration checkpoints are
`6db30ea1b290d7632110e881d404085648796d94` and
`0e07d24714e6261123fcb835c36a592d6827982d`.

A second full head/PR-ref fetch captured work published while the Mail reader
was being implemented. The external inventory increased to 209 branches and
170 PR heads. Updated review/thesaurus heads and new Zotero-note/spaCy heads
are all ancestors of `b9728ea1ec835cb589b266cfe9fc98507eb7acfa`. Its 26 additional
commits were merged into the already saved Mail branch at
`c473a25f27bbbce083ef8a5aa40eaa74e70d3146`. The merge had no source conflicts;
Git preserved both the Mail roadmap update and the incoming EOF cleanup.
`final-reconciliation.json` records the exact captured refs and ancestry proof.
The `checks/late-*` receipts identify the separate local regression cohort for
that later source; imported historical validation totals are not re-counted.

## Toolchain

- Repository `.fvmrc`: Flutter 3.47.8.
- Official framework revision: `737ba8f885dc774b53b442759999a312c9461e4e`.
- Engine revision: `cf636b1dfb818dd6a3ff16e390e93b1a036969c8`.
- Actual Dart runtime: 3.13.7 stable, Linux x64.
- Official archive: `https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz`.
- Archive SHA-256: `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.

The SDK, compiler and framework come from that checksum-verified archive. SDK
versions, manifests and locks were not fabricated or relaxed. The source
workspace resolved with the actual Flutter SDK and the root constraints.
Flutter tools required a separate ordinary pinned dependency bootstrap. A
workspace-owned temporary directory was necessary because this executor has no
`/tmp`. Native/JavaScript checks use the direct bundled Dart executable; Flutter
checks use the official tool snapshot and `--no-version-check` to avoid optional
version-network probing. A second extraction provided an independent cache
while the first startup lock was held; the existing lock was not bypassed.

## Source boundaries and intended targets

Read `.cursorrules`, `CONTRIBUTING.md`, `docs/MISSION.md` and all four Mail
specification documents before implementation. New core/MIME/UI source is MIT;
the complete reviewed enough_mail revision remains MPL with provenance and
separate notices. No CrispCloud implementation, tests, fixture mail, assets or
host imports were copied into these packages.

Targets: pure Dart on the VM and JavaScript; Flutter native reader; browser
reader compilation and subsequent browser runtime qualification. Apple signed
archives, real provider accounts, production credentials and CrispCloud parity
are outside this reader checkpoint's measured results.

GitHub Actions were never queried, awaited or rerun. Remote checkpoints use
`[skip ci]`. Authenticated writes use the GitHub plugin, with expected-head
leases and exact local/remote tree verification; unauthenticated CLI fetch is
used for local source retrieval.
