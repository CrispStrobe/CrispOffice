# Zotero recovery — 16 November 2026

This continuation preserves the merged Zotero improvements, integrates the distinct incoming text-rendering work and a bounded later sheet update, and publishes a fresh local qualification for the resulting source. The qualified implementation is [`b87f9d6c3a2532c9695024adf48ca9fbd3c0927a`](https://github.com/CrispStrobe/quds_office_suite/commit/b87f9d6c3a2532c9695024adf48ca9fbd3c0927a), with exact tree `acb1d1060879dc4a8168df8abf3105dc828af360`. Later evidence-only commits must retain this implementation identity and its measured inputs.

**Fresh canonical qualification: 1,104 tests; 0 skips; overall result passed.** The [receipt](canonical/receipt.json) is authoritative for final counts, exit codes and input-integrity gates. The [host receipt](host/receipt.json) records actual host, vendor/sync and license checks separately; the [CrispCloud companion report](https://github.com/CrispStrobe/CrispCloud/blob/codex/zotero-recovery-20261116/docs/validation/zotero-recovery-20261116/README.md) explains the host integration.

The completed companion host qualification passed **41 host tests and 28 Python tests**, plus strict analysis/formatting of 24 targets and the 2,509-file vendor guards. The combined fresh total is **1,173 tests**, with earlier attempts excluded. Its 3,732 selected source inputs and 5,837 dependency/runtime inputs stayed unchanged and its analyzer configuration was restored. The complete [host receipt and logs](host/README.md) are included here as well as in CrispCloud.

The host's managed content hashes match their declared sources. An auxiliary Git-mode comparison remains false for eight inherited executable bits; all are unchanged from the incoming host baseline. The [original diagnostic](audit/delivery-verification.json) and [inherited-difference disposition](audit/host-inherited-differences.md) preserve that distinction. This report does not claim that the full host package tree is identical to canonical Quds.

## Preserved implementation

Quds PR #63 and CrispCloud PR #176 had already merged when recovery began. The four Zotero production files retain the previously qualified implementation: embedded-source identity selection in `word_zotero.dart`, online backoff handling in `zotero_client.dart`, bibliography selection in `word_zotero_format.dart`, and dialog/session behavior in `word_zotero_dialog.dart`. The [source-preservation comparison](audit/zotero-preservation.json) records their historical and integrated blob identities.

Complete URI alias components still produce one bibliography source across late and transitive bridges, including bridges without embedded CSL. Selection keeps the first available snapshot and preserves unrelated library/profile identities and citation metadata. The document tab still reuses its field scan within a build. The historical 1,000-citation control measured one scan instead of four; this is a traversal-count result, not a new latency benchmark. Online sessions still preserve the maximum server pause deadline through client replacement and dialog reopening, while local desktop clients remain independent. Prior refresh batching, rich fields, saved searches, undo and stale-document guards remain in the selected regression suites.

The rendering integration adds the frozen PR #72 head `6bf486ee0bbcd2025c3a42cae7d7003b8c9324a4`. Its five engine production changes separate PDF character identifiers from glyph identifiers, retain Unicode aliases that share a glyph, and strengthen TrueType subset structure and font metadata. Its FontTools MIT notice remains in `packages/quds_office_engine/third_party/fonttools/LICENSE`; the companion host update retains this notice in guarded vendoring and bundled licenses. Existing direct PDF callers retain the identity-encoding API.

## Incoming work accounted for

The [frozen inventory](audit/incoming-refs.json) records **166 refs at 113 distinct heads**, observed through **2026-11-16 19:39:07 UTC**: 79 fork branch heads, 79 fork PR heads, four original-upstream branch heads and four upstream PR heads. PR merge refs and this outgoing recovery branch are excluded. Fork main was `be9eeec9ea3455018de26fff5874c558dbc66798`; original upstream main was `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`.

The final implementation accounts for every frozen ref:

| Disposition at `b87f9d6` | Refs |
| --- | ---: |
| Actual ancestors | 151 |
| Exact whole-tree squash aliases | 12 |
| Vendor aliases with identical changed source/test blobs and modes | 2 |
| Superseded vendor head with the same production change and retained test assertions | 1 |
| **Total** | **166** |

The [actual ancestry receipt](audit/final-ancestry.json), [dispositions](audit/final-dispositions.json) and [exact comparisons](audit/squash-comparison.json) support this accounting. The superseded head `928f854` differs from its corrected successor only by removal of an unused test local; no assertion or production behavior was omitted. These vendor dispositions do not claim whole-branch equivalence. Earlier projected receipts remain labeled as projections.

One later main observation, `63194d8e482892f284eaccb95ce48a8a8132376d`, was exposed while creating recovery PR #85 before qualification. It was reviewed and merged once. Its five commits through PR #84 add worksheet page setup and ODS header/footer round-trips, changing four sheet implementation files, two tests and two documentation files. It does not overlap the Zotero/font/PDF implementation or dependency manifests. The [bounded late-main review](audit/late-main-review.json) records this additional observation; it does not extend the original inventory to unobserved later branches or PR heads.

## Fresh local qualification

The fresh run passed **1,104 tests across 70 disjoint test files** in nine cohorts, with zero skips: 576 Zotero cases and 528 integration cases. The runner deduplicates explicit additions against existing cohorts. Every count below comes solely from the completed fresh receipt.

| Disjoint canonical cohort | Files | Passed |
| --- | ---: | ---: |
| Engine Zotero | 19 | 390 |
| Editor Zotero | 13 | 186 |
| Engine proofing and hyphenation | 4 | 74 |
| ODS reader integration | 1 | 102 |
| Word layout and styles | 2 | 31 |
| Editor proofing and platform spelling | 6 | 107 |
| Editor hyphenation, painting and caret behavior | 4 | 30 |
| Engine rendering, ODS writer/page setup and comment-style regressions | 19 | 180 |
| Editor rendering and hidden-sheet navigation | 2 | 4 |
| **Total** | **70** | **1,104** |

Strict analysis uses `--fatal-infos` on **37 selected source, test and support-fixture targets**. Formatting uses the existing Dart 3.12 language-version gate with zero changes required. The support fixture is analyzed without being enrolled as a standalone test suite. Analyzer result: **passed with no issues**. Format result: **passed with zero changes**.

The runtime is genuine **Flutter 3.47.8 / Dart 3.13.7**, framework `737ba8f885dc774b53b442759999a312c9461e4e`, engine `cf636b1dfb818dd6a3ff16e390e93b1a036969c8`. The locked engine/editor harnesses were reconstructed and resolved with lockfile enforcement, then copied into isolated retry harnesses. Their source links point to the detached `b87f9d6` checkout. Shared SDK/cache binaries are fingerprinted; production dependency constraints are preserved. The [setup report](setup/README.md) records the input checks and path rebasing.

The final receipt binds **1,568 selected canonical inputs** to their immutable Git blobs and fingerprints **3,857 external dependency/runtime inputs** before and after execution. The selection includes package source/tests, fonts/assets/third-party notices, the three imported PDF widget examples and their verified relative closure, Studio source/tests and non-documentation dependency/analysis manifests. The final gate requires unchanged source, external dependency/runtime inputs and locked harness inputs; it also requires restoring the temporary analyzer configuration. Final source/dependency/harness integrity result: **all passed; temporary analyzer configuration restored**. Four optional system-font paths actually probed by these PDF tests and examples are observed separately for presence and byte hashes before and after execution. They are excluded from both the canonical-source count and the resolved dependency/runtime count. Their separate unchanged-fixture gate **passed; all four paths were present and unchanged**. The [example closure](audit/example-input-closure.json) records the exact three source inputs and four fixture paths; no fonts were installed or substituted. Before/after maps and command logs are listed in the [artifact inventory](canonical/artifact-inventory.json).

The [runner](canonical/run-qualification.py), [exact recorded invocation](retry-invocation.json) and [launcher](run-retry-canonical.sh) retain the full selections and environment. The runner hash is `198271764369f36955d7fe8455e1b74db8a9f32bc0147f14019387c5c3dbf2d9`. For reproduction, place the runner under `zotero-toolchain/retry-canonical-complete`, retain the pinned SDK/cache, and point `--source-dir` and `--harness-root` at the source checkout and reconstructed harnesses. Adapt workspace paths in the invocation without changing source pins, dependency locks, cohorts or success gates. The published `retry-invocation.json` and `run-retry-canonical.sh` retain the final invocation and launcher; their original local names are `complete-invocation.json` and `run-complete-canonical.sh`, recorded in the publication metadata. Earlier versions remain under excluded attempts. The recorded final launch is:

```bash
bash /workspace/scratch/79aea0ff70bc/recovery-audit/quds/run-complete-canonical.sh
```

Each command journals its start, 15-second heartbeat and terminal result. A 600-second command timeout terminates the subprocess group and fails the run. A test result is accepted only with a zero exit code and terminal success marker. The [runner mechanics controls](attempts/runner-mechanics/mechanics-report.json) verify these controls with synthetic subprocesses; they are excluded from all qualification totals.

The current Unicode-alias PDFs from `retry-canonical-complete/render` also **passed the independent Poppler raster/text verifier**. The encoded PDF and identity-glyph reference rendered to exactly matching 320 × 112 RGB images at 72 dpi: zero differing pixels, with 2,109 nonwhite ink pixels in each. Both the directly encoded PDF and the Word-exported PDF extracted the authored sequence `U+0041 U+1F600 U+20000 U+0041 U+005A` exactly, after removing only trailing newline/form-feed characters. This fixture maps the supplementary code points onto existing Latin outlines; it does not establish emoji/CJK glyph coverage, shaping parity or broader platform conformance.

The verifier's checks are unchanged. Its source-binding wrapper selects the isolated checkout and requires the completed successful producer receipt; [the binding record](canonical/poppler-binding.json) preserves that explicit path override and provenance. The [PDF verification receipt](canonical/poppler/receipt.json) records seven successful external commands, both successful comparison checks, unchanged source/producer inputs, executable metadata and artifact hashes. The original verifier and the wrapper both returned success. These independent rendering checks do not add Dart/Flutter test cases to the table.

## Historical evidence and excluded attempts

Two historical figures describe different source pins and evidence scopes:

| Historical record | Scope and attribution |
| --- | --- |
| [Committed canonical archive](../zotero-capabilities-20261116/final-canonical/README.md) | **825 canonical tests**, zero skips, at Quds `8e017e8c148517fea61f8d55eaafc7f070b82bba`, tree `17eecf8b8c8558c78dbbefe9ffc9b1249e2455cf`; raw evidence survives. |
| [Later final checkpoint](../zotero-capabilities-20261116/final-qualification-checkpoint.md) | **923 combined tests**: 854 canonical, 41 actual host and 28 Python checks, at Quds `9de43669088c3719d541c9fe1c7dcb3ffbf86df3` and CrispCloud `24486b7df6a523cbfa4e5f2680efd3e1c188067e`. This is the preserved observed summary; its final `post-pr-canonical/` and `post-pr-host/` raw archives were not published before disk exhaustion. |

The fresh run produces new source-bound evidence. It neither reconstructs missing historical logs nor reattributes the 825-test archive to the later source. All historical results and rendering checkpoints remain outside the fresh totals.

The first recovery setup attempt stopped before tests because two tracked report-studio manifests were absent from the sparse checkout. Their exact published Git blobs were materialized; the [setup receipt](attempts/sparse-setup-missing.json) records the correction. This attempt contributes zero tests.

The next attempt completed an engine cohort of 390 tests, then lost its managed execution session while the editor log was at a progress counter of `+121`. There was no terminal editor result, process exit code or traceback, so the cause remains unknown. The [interruption record](attempts/interruption/interruption-record.json) and raw partial logs are preserved. Recovery also found that Flutter had added only `flutterRoot` and `flutterVersion` metadata to the engine package configuration. The package graph and lock were unchanged, but the original byte-for-byte harness gate was no longer satisfied; [the exact metadata comparison](attempts/interruption/harness-metadata-adjustment.json) records this.

The isolated retry then completed seven cohorts totaling **920 tests**, but its engine recovery cohort failed to load `pdf_widgets_test.dart` because the invoice, proposal and report example files were missing from the harness. That cohort's `+162` progress counter is not an accepted completed result. Its [full failure archive](attempts/missing-example-fixtures/attempt.json) preserves all 22 original files, with matching bytes, including the failed receipt, raw logs, producer outputs and runner. Source, external dependency/runtime and harness inputs remained unchanged, and the analyzer configuration was restored; later qualification gates had not all run.

The correction links only the three published example files into the harness and adds them to the measured source scope. Their relative import closure contains no further files. Four actually probed system-font paths receive a separate presence/byte-integrity gate. Neither the source/test implementation nor the cohort selections, analysis/format gates or production dependency constraints changed. The final complete run uses the same detached `b87f9d6` source and isolated harness, with warmed metadata included before its baseline fingerprint and a new output directory.

**The interrupted attempt's 390 engine passes and incomplete editor progress, and the missing-example attempt's 920 passes and partial `+162` progress, are excluded from every final total.** Their incremental checkpoints remain historical. Only the complete final run contributes the canonical table above.

## Scope and practical limits

This qualification covers the selected local engine, widget, rendering, integration and companion host behavior under the recorded runtime. It does not establish a new full application build, live Zotero account/private-key acceptance, native keychain interaction or Microsoft Word/LibreOffice acceptance. Historical live and platform-specific evidence keeps its original source and platform scope. The incoming inventory is a recorded cutoff; concurrent work may continue after it.

No GitHub Actions jobs, workflow runs, CI status/check endpoints, logs or artifacts were queried, awaited or rerun. Recovery checkpoints use `[skip ci]`.
