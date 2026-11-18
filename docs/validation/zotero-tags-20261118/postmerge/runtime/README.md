# Runtime after incorporating current main

The [refresh receipt](runtime-ready.json) records the workspace update for
qualified product `4e06d42d20521f56164303aa6c135d5580ea0948`.

All 11 manifests match current source. The graph has 110 packages: only the
incoming `quds_proofing_spacy` package was added, and all 109 earlier package
configuration entries remain unchanged. The exact hosted lock remains
`344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
No downloads or runtime changes were needed. Flutter 3.47.8 / Dart 3.13.7 and
their binary identities remain those in the original
[runtime provenance](../../local/runtime/README.md).

The preserved refresh script, offline dependency-resolution log and index are
included beside this receipt. Production, test and asset links point directly
to the current source, including the newly added spaCy package. No product
tests were run during this setup; only the final cohort directories contribute
to the acceptance totals.
