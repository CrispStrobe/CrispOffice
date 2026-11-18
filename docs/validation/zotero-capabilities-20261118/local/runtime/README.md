# Genuine local runtime preparation

`runtime-ready.json` records the pinned Flutter 3.47.8 / Dart 3.13.7 identities, exact recorded workspace and Flutter-tool lock equality, unmodified current manifests, official dependency archive verification, and setup adjustments.

`setup-evidence.tar.gz` retains the exact scripts, environment file, package archive verification receipt, resolver/precache logs, and setup smoke logs; its index binds every member. No runtime binary or dependency cache is copied into Git. All runtime binaries were downloaded from official Flutter sources and matched the prior committed executable hashes. The framework checkout remained unchanged.

The external validation workspace copies production manifests verbatim and links current source files. The real repository's local `.dart_tool` link points at that generated package graph so the analyzer can resolve imports after following source links; this link must remain uncommitted. The separate pure-Dart engine wrapper uses copies of current manifests without workspace membership and the exact historical engine test lock. Product qualification uses the actual 109-package external workspace, not the separate smoke wrapper.

Two setup resolvers initially rejected missing artifacts/locked versions. Their logs are retained; after downloading the genuine artifacts and all exact pinned versions, offline resolution with `--enforce-lockfile` succeeded. The initial symlink-only analyzer attempt could not resolve imports. With the real-root graph link, analysis reached the actual source and reported one genuine null-aware-element lint to the implementation owner, who fixed it before product qualification.

The 18-test engine smoke and 31-test editor smoke establish runtime usability only. They overlap later full product validation and are excluded from final product totals. The complete engine cohort and its before/after guards are in `../engine/summary.json`.

No GitHub Actions/status endpoint was queried or awaited.
