# Office local qualification completed — 18 November 2026

**The planned local qualification is accepted.** All required canonical, portable, example, timezone, document-consumer and native gates passed, with independent evidence audits and unchanged source/runtime guards. The earlier disk-full attempt remains rejected and preserved in `../office-local-20261118`; it is not counted as a successful run.

This is qualification of implementation `9a7c80be00258def2dcae3bb288c28558c83aa72`, executed at documentation-equivalent source `9d060658ee6be8ec97d73f56b9aec10d346b7952`. The current branch is `codex/office-local-qualification-20261118`. Later commits preserve reports and evidence without changing product implementation or tests. [status.json](status.json) is the current machine-readable result.

## Reconciliation and product change

The final refresh fetched all 191 branch heads and 154 PR heads. Main remains `482e08176dea6bd8f5fc80d1c0064d96b712db43`, including merged #151/#152 and the later German grammar, phrase formatting and spreadsheet-icon work. Separate spaCy #139 remains `20026ff4`; W7 #153 advanced to `2df0e930`, with the last three commits containing documentation/evidence only. The earlier W7 developer-consumer changes remain separately owned. No new Office product source requires integration. Exact remote heads, PR metadata and delta assessment are in [reconciliation/remote-frontier.json](reconciliation/remote-frontier.json).

The Office production repair keeps spreadsheet time-period boundaries in UTC civil-date arithmetic while preserving the injected clock's local year, month and day. Eight regressions cover midnight endpoints, daylight-saving transitions and year changes. The accompanying rendering-test edit adds braces to an existing statement without changing its condition or assertions.

## Accepted gates

| Gate | Accepted result |
| --- | --- |
| Strict analysis | Five commands passed |
| Formatting | 145 files, zero changes |
| Python controls | 117 passed |
| Canonical selection | 224 files; 4,236 raw successes, 4,234 substantive successes; zero unexpected skips |
| Portable | 17 Node suites, 225 successes |
| Editor example | Two smoke tests passed |
| Calendar matrix | Eight tests in each of UTC, Europe/Berlin and America/Los_Angeles; 24 overlapping executions with timezone offsets verified |
| Document consumers | Retained 33 + current seven + boundary five + focused frame five fixtures; all 50 accepted; 220 XML schema parts accepted |
| Native preparation | 23 audit controls and source-bound AOT build passed |
| Native sweep | Serial 1/2/4/8 arms exited zero; cross-arm semantics, true two-thread historical comparison, complete-source coverage and final input guards passed |

The successful canonical and document runs are preserved in `../office-retry-20261118`. They were audited directly from Git commit `c9d86b3e`, not rerun merely because this workspace was new. Their complete source binding matches the execution source above. The remaining native gate was executed in this restored workspace.

## Independent evidence review

- [Saved-run audit](review/saved-evidence-audit.json): 8,381 checks, zero findings; 14 archives and all 1,145 indexed members verified; raw events and source Git blobs independently reconstructed.
- [Consumer replay](review/document-contract-replay.json): 257 checks, zero findings; all 50 archived fixtures reproduced their recorded measurements and all 220 schema parts passed the preserved oracles, without recompilation or document conversion.
- [Runtime restoration archive](evidence/flutter-runtime-restoration.tar.xz): 3,277 retained SDK files, 162 Pub archive pins and 5,099 consumed dependency files match the accepted prior maps; actual-root 109-package configuration stayed byte-identical through prewarm.
- [Final native audit](review/native-completion-review.json): 157,981 checks, zero findings; 568 complete-source decoder records and 20 additional controls audited, all four process exits and both guards verified. [Preparation linkage](review/preparation-runtime-linkage.json) completes the live runtime input rehash.
- [Reviewer provenance archive](evidence/native-independent-review.tar.xz): partial receipts, auditor controls and exact reviewer script versions corresponding to their recorded hashes.

## Native measurements

The same source-bound provider AOT, pinned native library/model, 64-token segmentation target and disabled inference reuse were used for every arm. Each admitted timed input had one warmup and three measured repetitions. These are exploratory measurements on this local host.

| Threads | Short-check median | Short-check p95 | Peak RSS |
| ---: | ---: | ---: | ---: |
| 1 | 35.013 ms | 156.511 ms | 275.898 MiB |
| 2 | 22.289 ms | 66.157 ms | 274.008 MiB |
| 4 | 17.179 ms | 52.068 ms | 274.996 MiB |
| 8 | 12.657 ms | 41.935 ms | 364.137 MiB |

All arms satisfy the recorded short-check p95 ≤500 ms, peak RSS ≤768 MiB and GGUF model size ≤160 MiB flags. These measured flags are reported separately from semantic acceptance. The unchanged native panel retains six exact fixes among 18 supported error cases and all ten supported clean controls unchanged; two corpus cases are explicitly unsupported. This is bounded nonregression evidence and does not establish broad German correction quality or intended-device performance.

## Complete native archives

| Archive | Members | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| [Preparation](evidence/native-prepare-9d060658.tar.xz) | 17 | 640,408 | `ecccb2c63a18b16ac9d6b4d719c86b5c4403a42e5375c4e2ca21e1ad50303171` |
| [Sweep](evidence/native-sweep-9d060658.tar.xz) | 20 | 689,748 | `61c750faabdc8b0badb45bab2f42b297aafee1ab6b7adbc08aba80bb7e60102e` |

The matching `.tar.index.json` files bind every archived member. The generated provider executable is reproducible from its source/dependency/SDK-bound build receipt and was independently rehashed live; it is omitted from the archives. Complete closed-arm snapshots and earlier remote checkpoints remain preserved.

## Scope and accounting

Two unavailable private-PDF early returns are excluded from the 4,234 substantive canonical successes. The 24 timezone executions overlap canonical coverage. The boundary cohort is four strict layouts and one bounded page-precedence control, with 15 PDF variants and ten DOCX reopens. Official Jing schema acceptance is retained where lxml produced documented diagnostic false negatives. Document rendering uses LibreOffice; no Microsoft Word rendering result is claimed.

First results, warmups, all timed decoder observations and all retained findings were independently checked. Every final corrected output from every timed repetition is not stored, so full timed-output stability remains the producer's claim. Local qualification acceptance is separate from deployment or release acceptance; `release_accepted` remains false.

## Durable publication

Checkpoints were saved incrementally through non-forced expected-head branch updates with `[skip ci]`. The tested checkout stayed frozen and clean. Remote blobs, archives and every member were fetched and verified against the prepared local trees. The final publication receipt is recorded in the closure checkpoint. No GitHub Actions, workflow, check or status endpoint was queried, awaited or rerun.
