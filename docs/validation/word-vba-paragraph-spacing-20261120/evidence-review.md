# Independent final evidence review

**PASS for the qualified Word source and the reviewed evidence.**

Qualified commit: `0201b549d0dc3f601c50e36255d557034cb01699`. Qualified tree: `86531c002a6b1d6e748849f7370a87072a5fa768`.

This review independently read the actual source and runtime files, recomputed their hashes and Git identities, reconstructed raw reporter events, and reopened the packaged archives. It did not import producer audit helpers or execute the final test suite again. The final remote merge is a separate publication check.

## Accepted checks

| Check | Independently verified result |
| --- | --- |
| Word/Office regression | 2,799 successful cases, 75 original VM suites, eight accepted bounded invocations; zero failures, skips or reporter errors in this accepted set |
| Previous coverage | All 70 prior modules have exactly the same 2,569 `(file, name, occurrence)` identities and unchanged source content/modes/Git objects |
| New feature coverage, included above | 99 compiler, 96 native and 23 integration cases: 218 total |
| Additional existing line-layout coverage, included above | 12 cases in two modules |
| VBA selection | All 48 current `office_vba_*` modules included |
| Strict analysis | Entire engine package; fatal infos and warnings; no issues found |
| Formatting | All eight changed Dart files, nonmutating verification, zero changes |
| Exact BAS portability | Byte-identical 1,393-byte VM and compiled JavaScript output; exact canonical result equality |
| Independent source-review probes | 56 successful expectations, counted separately from regression |
| Later macOS correction checks | 61 producer checks and 36 separate independent expectations; excluded from Word totals |

The raw-event review verifies LF framing, unique protocol start/end events, complete and unique reporter IDs, valid suite/group ancestry, every declared group count, file/source-coordinate bindings, all outcomes, and exact stored case metadata. Global start/end IDs are namespaced by batch. Each of the 75 original files occurs exactly once within the eight accepted invocations; no aggregate shared test library was introduced.

## Source and runtime binding

All phases use the same 1,131 selected repository inputs. Actual filesystem bytes, modes, byte sizes, SHA-256 values and recomputed Git blob IDs match the immutable qualified tree. The scope includes engine libraries/tests/tools/examples, legacy parser libraries, configurations and the two font fixtures used by line-layout cases. The separate source review also binds the Word contract and exact BAS.

The bounded regression has 16 before/after snapshots plus a final audit snapshot. All 17 are identical. Its 3,489 recorded runtime inputs include the frozen runner/launcher, SDK binaries and libraries, configured hosted package sources/manifests, package configurations and coordinator executables. Portable execution separately binds 20 runtime inputs, and static checks bind 19. These are explicitly selected phase-specific inventories, not a claim that every shared operating-system dependency was fingerprinted.

Raw VM/JavaScript SHA-256: `2c5c1131842f09451d4334bbb7c3f97ae39f52db560c2847e8fbdd7c045e8f59`.

Canonical output SHA-256: `f0fe334a367c08018ed63936f0cd690371cd85f4e1ca90d1a60de85483791e51`.

The actual BAS bytes in both command-line defines and the stored snapshot match the committed example. The reviewed results include exact, minimum and multiple spacing, repeat save/reopen, DOCM opaque parts, replay, decimal conversions, policy refusals, transactional rollback, source guards and recording exclusion after failed native calls.

## Attempts kept outside acceptance

The original long invocation ended without a process-exit receipt, automatic after snapshot or terminal reporter event. Its 2,679 visible completions are retained as incomplete diagnostic evidence and add zero cases to the accepted total. The later observation of unchanged inputs is explicitly separate from normal completion.

- Diagnostic batch 2: 299 visible completions, including 2 timeout failures. Recorded tool exit: 130; normal execution receipt present: False. Contribution to accepted cases: zero.
- Diagnostic batch 3: 41 visible completions, including 1 timeout failures. Recorded tool exit: 1; normal execution receipt present: True. Contribution to accepted cases: zero.

All original failed-attempt bytes survived relocation. Exact timeout errors were independently recounted. Resource contention is an inference, supported by overlapping CLI-heavy invocations and separate successful retries; this review does not assert a proven root cause. The final accepted files are reconstructed only from their eight accepted batch directories. Earlier development failures and all 15 development reporter streams are also preserved and excluded.

## Archive verification

Every indexed member, byte size, SHA-256 value, permission class, normalized archive header and embedded/external index was checked against the actual archived payload. Frozen source/evidence payloads match their mapped source files; historical snapshots of evolving reviewer tools are explicitly identified when their current versions differ. Required phase files are complete. The final regression archive was also rebuilt independently in memory from normalized records and produced the same compressed bytes.

- **portable_static**: 60 members, 940,356 bytes; SHA-256 `d4d48a757e34ae1c3e3aa8c1c2113b6f52bf229e86dae40c3c50c3461742c41a`.
- **development_and_source_review**: 110 members, 933,452 bytes; SHA-256 `7fbfbd9b62133c114ce5ea402e61d502d8ade49608140b52545f3cdc6ed81df4`.
- **regression**: 158 members, 997,460 bytes; SHA-256 `bc691608884ad4e3a28c67dcf90acd1898352707d95fbea488b792668a6fa422`.
- **interrupted-regression-evidence**: 17 members, 598,024 bytes; SHA-256 `6cdd05e5f627041cfa076c3251a93700e727f8ec705c6b5cbcc491177a99a481`.
- **late-intake-evidence**: 249 members, 36,952 bytes; SHA-256 `d223283dae6098b89b4c0dce96ad036486fe993ddd687673ec7ae9abe8556b81`.
- **bounded-progress-evidence**: 67 members, 401,756 bytes; SHA-256 `c88bd97f9b7d74e4e995461b768323402fc16420d7129896a8706479fd341801`.

The late-intake archive preserves the initial findings, exact corrected candidate, Apple source provenance, isolated outputs and stopped optional interpreter-setup diagnostics. It explicitly claims neither an actual macOS build/signing run nor actual Bash 3 execution. The reviewed correction is approved for integration; its final Git ancestry, executable mode and publication are checked separately.

## Review boundaries

There are no outstanding findings in the qualified Word source/evidence scope. Final main/remote consistency, incorporation of the three selected original late heads, preservation of the Word inputs after integration, and the explicit later-head deferral inventory remain separate publication checks. A classified deferred reference is not represented as incorporated. No GitHub Actions were queried or awaited.

The JSON companion contains the complete audit details, per-module identity comparison, exact command receipts, every artifact digest, snapshot bindings, diagnostic classification, archive proofs and hashes of the independent verifier sources.
