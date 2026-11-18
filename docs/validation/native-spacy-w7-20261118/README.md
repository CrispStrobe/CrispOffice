# W7: verified Linux installation and worker consumption

Status: package controls passed; the saved Dart consumer is uncompiled and
execution is blocked by workspace exhaustion, 18 November 2026. The preceding [W6 qualification](../native-spacy-w6-20261117/README.md)
is complete and consumed. This step packages and consumes its unchanged
native/model bytes; it does not repeat or extend that language-quality claim.

## Saved status

| Work | Observed outcome |
| --- | --- |
| Source refresh and relevant main integration | Complete; all 342 sealed Quds source blobs preserved |
| Package controls | 25 passed on the saved packager source |
| Real package build and atomic installation | Passed; 20 payload files plus authenticated manifest |
| Second complete real-input build comparison | Pending |
| Corrected Python consumer | Source reviewed and saved; current 21 controls and first native run pending |
| Dart installed-package consumer | Source reviewed and saved; compilation, self-test and worker run pending |

Local execution is blocked by filesystem exhaustion during sandbox startup. Even task-owned cleanup commands could no longer launch. Approximately 440 MB of reproducible task files had already been removed before the later exhaustion. GitHub connector saves and readback remained available.

A later read-only workspace probe also failed before execution: the execution service returned `No such file or directory`. Current local mounting, contents and free capacity cannot be verified. This does not establish that files were deleted; use the independently verified remote branches as the recovery source.

Follow [CONTINUE.md](CONTINUE.md) and [checkpoint-status.json](checkpoint-status.json) from a workspace with capacity. The latest remote source can be newer than the local checkouts. Package/model binaries were not uploaded to ordinary Git, and some raw local preflight/SDK logs could not be reread after exhaustion; these preservation limits are explicit in the checkpoints.

The [source inventory](source-refresh.json) records all fetched branch and PR
heads. Main `482e0817` adds only the 72 retained morphology evidence files and
is merged at `13747281`. All 342 sealed source blobs still match the original
candidate, using the published W5 lock-file mapping. The final paired W6
completion was already saved in CrispEmbed at `93560df6`.

The paired CrispEmbed branch `feat/native-spacy-w7-20261118` implements a
deterministic package, external hash verification and atomic installation in
a private cache. The resulting bundle and SHA-named library paths fit the
existing `SpacyNativeBackendFactory` and explicit Studio configuration. The
accepted native binary has no RPATH; PCRE2 and the C/C++ runtime remain host
dependencies. The [restoration receipt](runtime-restoration.json) binds the
exact five model files, original native notices and six qualified dependency
hashes. glibc 2.38 is the binary's inferred minimum, not broad Linux coverage.

The [operational protocol](operational-protocol.json) freezes native package
loading and cleanup controls before execution. A separate local Dart worker
consumer will use the installed package without a Flutter SDK or workspace
dependency changes. Developer setup tools may use Python; the application
continues to execute C++ through Dart FFI without Python or a daemon.

The manual grammar provider stays disabled by default and Studio keeps its
explicit annotation view. Mobile/device packaging, immutable hosted artifact
publication and download readback remain unqualified until their actual
evidence exists. No Actions queue wait or linguistic qualification rerun is
part of this continuation.
