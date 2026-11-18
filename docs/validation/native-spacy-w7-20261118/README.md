# W7: verified Linux installation and worker consumption

Status: implementation and operational qualification in progress, 18 November
2026. The preceding [W6 qualification](../native-spacy-w6-20261117/README.md)
is complete and consumed. This step packages and consumes its unchanged
native/model bytes; it does not repeat or extend that language-quality claim.

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
