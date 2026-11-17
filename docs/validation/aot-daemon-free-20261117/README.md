# Daemon-free AOT integration — 17 November 2026

Work branch: `codex/aot-daemon-free-20261117`.

## Initial incoming-source checkpoint

All 269 captured fork branch, fork PR, upstream branch, and upstream PR references
are ancestors of the integrated head recorded in `incoming.json`. This includes
AOT #117, Office #113/#116, German #114, GECToR continuation, latest main at
`388bd745`, and the separate original feature/vendor commits behind #115/#118
squash merges. No incoming branch or previous evidence was discarded.

Merge decisions retain the consolidated ODF frame/namespace/hidden-story
extraction contract and structured table ownership; preserve the previous
`readOdfParagraphTexts` entry point as an alias; keep hyperlink assertions once;
retain the empty-document invariant; and combine AOT, noun agreement and combined
German quality documentation. Repeated squash merge tab-stop bodies were
recognized as duplicates and retained exactly once.

This checkpoint precedes daemon-free implementation and local qualification.
GitHub Actions, checks and commit-status endpoints are not used as a gate.
