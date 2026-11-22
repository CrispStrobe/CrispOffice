# Incoming Word and directional-layout qualification

Fresh focused local tests passed **802 cases across nine suites**, with no failures,
skips, or incomplete test lifecycles. Strict analysis passed all 15 changed Dart
paths, and pinned formatting reported zero changes. No production code or tests
were changed by this qualification.

| Gate | Cases passed |
| --- | ---: |
| Directional paragraph DOCX I/O | 43 |
| VBA string intrinsics | 102 |
| VBA Variant substrings | 108 |
| VBA Word headers and footers | 94 |
| VBA named measurements | 160 |
| VBA named selectors | 132 |
| VBA page setup | 88 |
| VBA text-selector conformance | 65 |
| Directional editor ruler | 10 |
| **Total** | **802** |

## Source boundary

The requested integration source was `982ea168648c7b24be9dd61cac3e9cd5ab76d274`.
The first capture observed the subsequent documentation checkpoint
`a867f9e8edcd46665a2609043d189423fa5ed620`; final capture observed
`f8baf34fd121614ad3a9e72bf235c0a31d1329d4`. All **4,650 tracked inputs** in
engine/editor/reports/legacy-parser packages (excluding their example apps),
root manifests, analysis options and SDK pin match both captured Git sources
and are identical to the requested integration source. Every captured input and
the generated package configuration stayed unchanged through qualification.
Mail host work proceeded independently in the excluded Studio example.

[summary.json](summary.json) records this equivalence and points to compressed
before/interruption/after manifests. The static gate records exact path hashes
before and after. No historical tests are included in the 802-case count.

## Commands and runtime

The normal pinned Dart runner executed the eight engine files with concurrency 2
and JSON reporting. The normal pinned Flutter runner executed the ruler file
with `--no-pub`, concurrency 2 and JSON reporting. Gates ran sequentially.
[engine-result.json](engine-result.json), [editor-result.json](editor-result.json)
and [static-result.json](static-result.json) retain full commands, timestamps,
exit codes, individual cases and raw/gzip hashes. Raw reporters and stderr are
preserved alongside them; loader and fixture lifecycles are excluded from counts.

[runtime.json](runtime.json) identifies the complete, unmodified official
Flutter 3.47.8 / Dart 3.13.7 SDK and verified archive. The root lockfile stayed
unchanged. All accepted commands sourced the prepared environment with `CI=true`.

## Startup interruptions

The first Flutter attempt was interrupted during normal first-use SDK tooling
dependency resolution, before any reporter event. Its empty streams and exit 130
are retained in [editor-startup-interrupted.json](editor-startup-interrupted.json)
and receive no test credit. The verbose retry completed dependency setup and all
ten ruler cases normally, with exit 0. A subsequent stop signal arrived after its
complete result/reporters were saved and interrupted only final harness
bookkeeping; the final input capture was then completed without rerunning tests.
No manual dependency provisioning, lock deletion, SDK patch, or project-source
change was performed.

This is a focused local incoming-code gate. It does not establish full-engine,
full-editor, installed Office, live-provider, or visual-golden acceptance.
GitHub Actions were neither queried nor awaited.
