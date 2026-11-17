# German proofing continuation — 17 November 2026

This continuation integrates the newer optional GECToR implementation into
PR #105, adds conservative genitive noun repairs, fixes manual coverage and
worker admission, and validates the combined source locally. The qualified
source checkpoint is **`65728d8da063b5e1cc9f8a76f2ff3d5a69b0753e`**.

The real compiled provider meets the provisional short-check latency and
process-memory budgets on this Linux host. Its guarded correction quality is
still limited: **5/18 frozen error cases corrected, 0/10 supported clean
controls changed**, with the two Swiss controls explicitly unsupported. This
is an experimental manual host opt-in, not default or release qualification.

## Integration and implementation

The supplied handoff ended at `b63d76a2`, where the GECToR provider/native work
was still pending. The relevant feature branch had since advanced to
`216d9a4ba11d87d27f861d84d26bf74ca1d4f298`, including the small native target's
qualification, verified Dart provider and manual/F7 editor lane. Merge
checkpoint `5e7fbad97c4d2d66bab7d8b4e27b20d2680e7509` preserves both histories.
Only the two changelog additions conflicted; both sides were retained.

The ODT comment/footnote fix, namespace-aware annotation exclusion, section
layouts and page breaks from the handoff are preserved. The relevant writer,
extraction/search files and regressions are byte-identical to that checkpoint.
Harper, the seven English/German hyphenation sources, lexical data and their
notices are also unchanged. Exact paths and Git/source identity checks are in
[source-binding.json](source-binding.json). This is a bounded refresh of the
relevant grammar feature, not a claim to have resnapshotted every remote branch.

### Explicit genitive noun endings

The deterministic analyzer now admits a noun repair when the existing complete
determiner table identifies genitive uniquely. It uses the unchanged article's
compatible gender, complete morphology slots, valid-analysis veto, unique
replacement and modern-spelling corroboration. It does not infer a governor
for variable-case prepositions such as `wegen`.

| Input | Suggested correction |
| --- | --- |
| `Das ist das Auto des Student.` | `Das ist das Auto des Studenten.` |
| `Das ist wegen des schlimmen Fehler.` | `Das ist wegen des schlimmen Fehlers.` |
| `Die Bedeutung des Name bleibt.` | `Die Bedeutung des Namens bleibt.` |

The regular adjective stem `schlimm` was added to the reviewed first-party
list so this phrase can reach the noun analyzer. Ambiguous articles such as
`dieses`, `jenes` and `der` do not establish genitive. Valid optional forms,
unknown nouns/adjectives, unresolved readings and nominalized adjectives retain
their safeguards. The existing `de.grammar.noun-case` rule remains independently
ignorable, with original UTF-16/grapheme boundaries and Swiss spelling behavior.

The new suite has 53 tests: 14 correction/recheck cases, 35 valid or deliberately
undecided controls, and four operational groups. The `des Student` regression
fails against the preceding implementation and passes after this change.

### Worker admission and manual coverage

Superseding a request previously removed its pending entry before the worker
acknowledged the old message. Rapid replacements could therefore accumulate
full snapshots in the isolate mailbox while synchronous native inference ran.
The sender now retains remote slots until acknowledgement and coalesces unsent
same-key requests. It bounds unacknowledged sends and local waiters separately,
allows independent keys to progress, and completes waiting requests on disposal
or unexpected worker exit. Oversized text is rejected before it can cancel
valid work. Controlled-isolate tests exercise a 200-snapshot burst and these
lifecycle paths. This queue bound follows inspected invariants and tests;
it is not a separate measured queue-memory benchmark.

An English-only background check also used to appear incomplete whenever a
de-DE-only manual model was installed. Omitted manual coverage now depends on
applicable captured languages. Mixed-language documents still indicate skipped
German model work until an explicit check. The regression fails on the incoming
source and passes with the fix; the mixed-language test checks a real nonzero
paragraph offset. Model suggestions keep the existing correction, undo,
protection and stale-result paths, and deterministic findings retain precedence
when manual proposals overlap.

The model remains explicitly loaded, de-DE-only and native-worker-only. No
model, native binary, download, automatic typing check or default provider is
introduced by the package. Existing deterministic German checking continues
on native and web, including its previously supported regional policies.

## Fresh validation

Flutter **3.47.8**, Dart **3.13.7**, and the pinned workspace dependencies were
prepared from authenticated archives. CI mode and analytics suppression prevent
the SDK's unrelated environment-detection network request. All checks below ran
locally; no Actions workflow was dispatched or awaited.

| Check | Result |
| --- | --- |
| Engine proofing, Dart VM | **558 passed** |
| Engine proofing, compiled JavaScript/Node | **558 passed** |
| Optional GECToR package, including real native fixture | **100 passed, zero skipped** |
| Focused Flutter proofing, correction and hyphenation | **176 passed** |
| ODT/ODP/ODS, extraction and search regressions | **279 passed** |
| Python qualification controls | **56 passed, 1 explicitly skipped** |
| Small native target contracts | **50 checks passed** |
| Strict engine, GECToR and changed editor proofing analysis | **No issues** |
| Native provider AOT compilation | **Passed** |

Groups overlap and must not be added together. The Python skip is the tiny
ONNX MatMulNBits converter check, which requires absent development-only
`onnxruntime`; no new ONNX inference run is claimed.

Strict analysis found two missing statement braces in the incoming read-only
lexicon query. The full 558-test Node run precedes those two equivalent
brace-only changes. Its preserved formatting-followup receipt proves that
the other 825 selected inputs are unchanged. Final strict analysis, VM tests,
both VM/Node corpus runs and the native execution use the repaired source.
No second full-suite Node run is implied.

### Frozen deterministic corpus comparison

| Measure | Previous qualified result | Current result |
| --- | ---: | ---: |
| Exact corrections, all 81 errors | 69/81 | **70/81** |
| Original targeted morphology subset | 68/73 | **68/73** |
| Broader challenge subset | 1/8 | **2/8** |
| Valid core controls flagged | 0/175 | **0/175** |
| Review-set exact corrections | 24/24 | **24/24** |
| Review controls flagged | 0/60 | **0/60** |

VM and Node produce exactly equal outcomes. Comparing all **1,700 records per
runtime** against the prior preserved output changes only `error-081` in its
four prose variants: base, nonzero offset, authored soft hyphen and locale alias.
They now suggest `Fehlers`; its protected-code variant remains untouched.
All 340 protected-code variants and all operational, rule-ignore and
correction-recheck controls pass. [corpus-comparison.json](corpus-comparison.json)
records every changed result and the original archive/member hashes.

These development panels establish bounded regression improvement, not broad
German accuracy. The original five morphology misses remain conservative
ambiguity/unknown-word or exact-expectation limits rather than newly forced fixes.

## Fresh compiled native-provider measurement

The same pinned source model was regenerated locally into both GGUF artifacts.
The F32 and mixed Q4_K files exactly match the previously recorded artifact
hashes. The mixed model contains 72 Q4_K encoder matrices, one Q8_0 token table,
three F16 position/head matrices and 125 F32 tensors, and occupies
**82,756,896 bytes**. The exact native source closure also matches the earlier
112-file inventory, while this newly compiled library has its own binary hash.

The compiled Dart executable runs the real persistent worker, native inference,
all iterative passes, guards, read-only German dictionary, source mapping and
`OfficeProofingService`. The run uses two native threads, one warmup and three
measured repetitions per input. All 30 cases have their expected operational
status, all eight extra controls pass, and all three longer probes are stable.

| Measurement | This compiled run |
| --- | ---: |
| Model verification and worker/dictionary startup | **3,477.616 ms** |
| Pooled warm median, inputs through 64 WordPieces | **22.418 ms** |
| Pooled warm p95, inputs through 64 WordPieces | **58.877 ms** |
| Maximum in that pool | **156.278 ms** |
| Peak whole-process RSS | **404,336,640 bytes / 385.61 MiB** |
| 61-WordPiece structural probe, p95 | **156.278 ms** |
| 126-WordPiece structural probe, p95 | **337.759 ms** |
| 256-WordPiece structural probe, p95 | **803.379 ms** |

The 87-sample short pool comprises 28 supported panel cases plus one 61-token
structural probe, each repeated three times. Its p95 is not a representative
distribution of every sentence length through 64 tokens. Startup excludes
earlier source/reference admission, and filesystem caches may already be warm.
The provisional 500 ms short-check and 768 MiB process budgets pass on this
host. The 256-token result exceeds 500 ms; longer inputs are not silently
truncated. Intended desktop/mobile devices and a browser model remain unqualified.

The retained JIT result of 819,101,696 bytes / 781.16 MiB remains in its original
report. This compiled measurement is additional evidence, not an attribution
of a cross-run difference to one code change. The runtime model's guarded
quality remains **5/18**, with **0/10** supported clean controls changed and
two Swiss cases unsupported. The earlier unguarded 9/18 reference and its Swiss
false correction also remain unchanged. No fresh unguarded raw-logit parity
qualification is claimed for the newly built binary.

Important identities:

- Quds source: `65728d8da063b5e1cc9f8a76f2ff3d5a69b0753e`.
- CrispEmbed checkout: `957ffa3bcf578daf6dda546d6f1af7c12607dc4a`; its measured
  native code matches the prior `853a1ce6` closure.
- ggml: `3a27b6c665b191cb230be367db5c52d81dd3e2ac`.
- Mixed GGUF SHA-256: `549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b`.
- New native library SHA-256: `71b32e67763164be7f79067dc712d1b21d405fd94b925074f880b221b738c856`.
- Dart AOT executable SHA-256: `dbc34bcd43709bde1d9ff1d9150a65082281752f9e435d058aae50cef728606c`.

[provider-aot.json](provider-aot.json) contains every case, sample, status,
source hash and budget result. The archived outer receipt binds executable,
library, model, reference and report hashes and captures host identity.

## Evidence and remaining gates

[source-binding.json](source-binding.json) verifies **2,188 tested inputs**:
2,187 tracked files match the qualified Git tree and the ignored root lockfile
matches its preserved [workspace-pubspec.lock](workspace-pubspec.lock). The
combined run's before/after manifests are identical. The exact manifest is
[tested-inputs.json.gz](tested-inputs.json.gz).

The archive preserves original successful logs, individual JSON results,
initial failures, source manifests, setup/build/conversion receipts and
reproduction commands. [evidence-index.json](evidence-index.json) lists every
member of [local-evidence.tar.xz](local-evidence.tar.xz) with size and SHA-256.
Generated executables/caches and duplicate temporary checkouts are excluded
explicitly; their identities or original source/reproduction commands remain.
No model weights, raw neural logits or native executable are committed.

The preliminary archived `final/deterministic-source-binding.json` refers to
`c7c92bb` and correctly records a spelling-file mismatch, but its explanatory
all-match prose is inaccurate for that intermediate checkpoint. The new final
binding above supersedes that statement without rewriting the original receipt.
Independent review verified the final input, log, model, library and executable
hashes and recomputed the native timing and quality totals.

The source/model notices remain MIT, Unicode-3.0 or Apache-2.0 as documented.
The newly built development library's GNU/Linux system/runtime dependencies
retain the previously identified strict-license distribution boundary. Successful
tests and top-level permissive licenses do not approve its packaging. No binary
distribution, model publication, release or main-branch merge is performed.

Next product work is broader held-out language evaluation and incremental value
over the deterministic checker, followed by the required intended-device and
native packaging qualification. Unrestricted sentence syntax, compounds,
de-AT/de-CH model support, browser inference and automatic background model
checking remain separate work.
