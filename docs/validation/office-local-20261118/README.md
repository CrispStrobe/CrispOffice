# Quds Office local qualification — 18 November 2026

## Saved state

- Branch: `codex/office-local-qualification-20261118`.
- Corrected source candidate: `9a7c80be00258def2dcae3bb288c28558c83aa72`.
- Main reconciled at `482e08176dea6bd8f5fc80d1c0064d96b712db43`, including PRs #151/#152 and the later German grammar, complete-phrase formatting and spreadsheet icon work.
- Initial inventory: 190 branch heads / 152 PR heads. Follow-up review: 191 branches / 152 PR records; main remained unchanged.
- **Final qualification is not accepted.** The latest canonical attempt ended with a disk-full error. The execution workspace subsequently became unavailable.

The only production-library change relative to that main is the reviewed civil-date conditional-format repair from `2bfac9b2`: construct today and month offsets as UTC civil dates using the injected clock's calendar fields. Eight regressions cover timezone endpoints, DST and year boundaries. The other non-documentation changes are those tests, the changelog, and braces around an existing rendering-test statement required by strict analysis. The lint repair changes no condition, assertion or test behavior.

Historical recovery evidence omitted by the squash merge has been preserved from `6d97fedc` and `8ad80eb2`, keeping its original source attribution. The native spaCy branches and the concurrent Office continuation retain their distinct ownership and frame implementation; their outcomes are not counted as qualification of this source.

## Actual current-source results

| Gate | Result on 9a7c80be |
| --- | --- |
| Five strict analysis commands | Passed |
| Formatting | 145 files checked; passed |
| Python controls | 117 passed |
| Engine Zotero selection | 390 success events across 19 selected suites, followed by process exit 255 |
| Remaining five canonical cohorts | Not started |
| 17 Node suites / two example smoke tests | Not started |
| Calendar controls under UTC, Berlin and Los Angeles | Not started |
| Retained 33+7 / boundary five / focused frame five consumers | Not started |
| Serial native 1/2/4/8-thread sweep | Not started |

The engine test events do **not** make the cohort accepted. Its compiler could not create its cleanup/cache directory because the shared filesystem had no free space. The workspace integrity check also correctly rejected a changed package-config byte hash. The runner author observed only an equivalent `flutterRoot` symlink-versus-actual-path change after normalizing the 109 package records; that observation is not a waiver of the failed byte-integrity gate.

Source, dependency, runtime, system and harness maps remained unchanged. The exact run remains rejected. No product assertion failure was observed before the environmental exit.

## Evidence and independent review

The complete ended attempt is [canonical-attempt-9a7c80be.tar.xz](evidence/canonical-attempt-9a7c80be.tar.xz), with its [member index](evidence/canonical-attempt-9a7c80be.tar.index.json). It retains raw events, stdout/stderr, commands, all before/after maps, the failure receipt and helpers. Size: 638,988 bytes; SHA-256: `14a2e5d6d0ae73501eb6e240d67896a3936482188a3344c1eee44c877e161e42`.

The archive's `checkpoint_complete` flag means the ended attempt was completely packaged. Its run status is failed and qualification acceptance is false.

The native and Flutter recovery archives, rejected `401d0126` lint preflight, independent runtime reviews, latest remote source review and bounded qualification helpers are also preserved here. Native recovery reproduced the pinned library/model/pack hashes; independent review checked 3,504 consumer runtime files and eight fonts. Flutter recovery independently checked the retained SDK, all 162 Pub archive pins, runtime core hashes and source bindings. These setup results do not substitute for the missing current-source gates.

See [recovery-handoff.md](recovery-handoff.md) for exact commands, pins, remaining work and the package-config stabilization step. See [verification.json](verification.json) for machine-readable status.

## Publication policy

Source and completed evidence were saved incrementally through non-forced expected-head branch updates, with `[skip ci]` checkpoint messages. Evidence publication used a separate Git index and then direct verified Git blobs, keeping the qualification checkout and HEAD fixed. GitHub Actions, workflow, check and status endpoints were neither queried nor awaited.

Two unavailable private-PDF early returns remain explicitly excluded from substantive broad-run counts. Native DOCX rendering uses LibreOffice; no Microsoft Word result is claimed. No final broad, portable, consumer or native-sweep success is inferred from an earlier source.
