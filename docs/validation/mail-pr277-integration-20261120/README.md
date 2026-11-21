# PR277 Mail integration — 20 November 2026

**Accepted source:** `5c7b76a6137bc9373276ce2e7fccc6ed48903998`  
**Accepted tree:** `c3ac8ba4f302e6d4057e49d989ce3b81cd1dcd3c`

The accepted union contains **1,536 unique cases across 73 files**, with zero accepted failures or skips. **230 additional Node executions** recheck canonical identities and are not added to that count. The merge preserves previous completed publication `0e4e999a08996a6b8696ca3adba11e303331b73e` and captured main `383c0c0c5d3b4b1a6edccc8d09ffd1ca64029537` as actual parents.

| Accepted cohort | Cases | Files | Execution attribution |
| --- | ---: | ---: | --- |
| Unchanged prior cases | 1,125 | 50 | 606 at `c62338c6…`, 423 at `4163368b…`, 96 at `58cc4283…` |
| Fresh core compatibility | 28 | 1 | `5c7b76a6…`; all 28 also pass on Node |
| Fresh shared Mail UI | 190 | 12 | `5c7b76a6…` |
| Fresh Studio integration | 193 | 10 | `5c7b76a6…` |
| **Canonical union** | **1,536** | **73** | Accepted at `5c7b76a6…` |

All 346 identities from the replaced prior files remain present; 65 identities are added. The Node union retains 202 earlier rechecks and replaces the old 26-case compatibility run with 28 current cases. `accepted-test-cases.json` preserves each actual execution source. The shared Studio layout suite contains eight Word-only cases also represented in Word evidence; compare identities before combining project totals.

## Reconciled behavior

Core, transport and EWS production remain byte-identical to the prior qualified implementation. Both bulk API families, canonical runner tests, stop-problem evidence, conservative mutation certainty and captured identity guards remain. Exact duplicate incoming core test files retain their established canonical names. The compatibility suite adds certified-quota coverage to both entry points without duplicating the runner population.

Saved-account autoconnect now uses a queued ownership ticket. It captures settings, credential, store, session and account revisions and retires on edits, manual connection or disposal. It schedules only after adopting remembered credentials; injected client factories remain manual unless the host explicitly opts in. Fourteen incoming autoconnect regressions exercise these boundaries.

The public reader-owning `StudioMailRemoteImageLoader` and existing client-owning function share one bounded loading loop. They refuse redirects, limit candidates, streamed bytes and decoded image dimensions, and cancel stalled or late response bodies. Native publication also checks reader revision and host/session identity. Reader admission accounts for both body alternatives, original attachment bytes and previously admitted remote bytes. Fetching has its own batch limit; an acquired image may still be refused by final cumulative reader admission.

`addImages` returns the number actually admitted while preserving incremental, one-pass append semantics. Mixed valid/invalid input retains valid images; previously loaded images remain available in plain mode, subject to combined CID/external count and pixel re-admission on every rebuild. Only admitted URI placeholders disappear. Invalid, failed and unrequested alternatives keep their text, and preformatted whitespace is retained. Actual PNG/JPEG dimensions determine pixel admission.

The incoming atomic-batch and plain-mode-clearing expectations conflicted with the established append contract. Their meaningful assertions remain: invalid single items leave state unchanged, cumulative limits reject excess images, source messages stay immutable, and explicit projection rejects unrelated sources. The compatible loader regression accepts one safe image from a budget-limited pair and checks the combined byte bound. The original seven function-loader cases remain alongside eighteen new compatibility-loader cases.

Selection/enabled aliases reject contradictions. `remoteImageUris` and `remoteImageUrls` expose one immutable list, accept equal lists, and reject conflicting values or order. Incoming provider-callback, cached-host and working-status visual checks are preserved.

## Qualification, retention and visual evidence

The frozen run passed all 411 canonical cases and 28 Node rechecks, changed-file formatting and strict core, UI and scoped Studio analysis. Before/after seals match for 5,854 source files, 6,188 dependency files, SDK/runtime inputs, HEAD and tree; final Git status was clean. No corrective source change was required after this publication.

The verifier independently recounts raw JSON events, terminal status, loaded suites and case identities. It binds prior accepted exports to their published Git blobs and prior manifests, then verifies the old and current source manifests against Git. All 50 retained test files match. Core, transport, MIME, store, enough_mail, EWS and native loader inputs are unchanged. External dependencies, package configuration, native SQLite and shared runtime bytes match exactly; only the qualification script changes.

For the retained host cases, native bytes outside saved-credential autoconnect and explicit remote loading are identical. Retained tests do not invoke the new override or remote-image APIs. The fresh account/race, cached Mail, workspace and reader suites cover those changed paths. Message-list bytes outside constructor alias validation are identical; the five retained UI visual-tool cases use unchanged rendering and non-conflicting aliases. Separate Word evidence covers incoming table/Zotero changes.

All **36 current Studio PNGs** are accounted for: **31 match previously reviewed bytes**, including ten new selected/action filenames, and **five new working-status images** received independent review. English, German and Arabic counts and Stop controls remain readable; RTL shaping and compact scrolling are coherent. No concrete visual blocker was found. The five UI-tool images remain in the prior accepted package and were not regenerated here.

Incoming `zotero-vertical-tables-20261120/mail-final-*` evidence remains historical. The audit verified all 34 archive members, recounted 219 core and 375 host cases at `e8edb90a…`, and verified 530 of 531 relevant source bindings; the old native-host blob was unavailable locally. Later incoming totals remain tied to their own sources. None of those overlapping totals is added to this union, and no missing blob was fetched speculatively.

These are local Dart VM, headless Flutter and selected compiled-JavaScript checks using Flutter 3.47.8, Dart 3.13.7, package:test 1.31.1, Node 24.22.3 and sqlite3 package 3.9.1 with native SQLite 3.54.1. No live mailbox, native credential store, provider deployment or OS end-to-end claim is made. GitHub Actions was not queried or awaited. Earlier failed aggregates and their corrective diagnostics remain unchanged in the preceding evidence packages.

## Reproduce or inspect

Run these commands **from `docs/validation/mail-pr277-integration-20261120`**. The read-only verifier requires Python with PyYAML and a repository containing the named commits; it does not run tests or access the network.

```sh
sha256sum -c SHA256SUMS
mkdir /tmp/quds-mail-pr277-evidence
tar -xJf mail-pr277-qualification.tar.xz -C /tmp/quds-mail-pr277-evidence
python3 verify_mail_pr277_retention.py \
  --repo /absolute/path/to/quds_office_suite \
  --baseline-accepted /tmp/quds-mail-pr277-evidence/baseline/accepted \
  --baseline-sealed /tmp/quds-mail-pr277-evidence/baseline/sealed \
  --focused /tmp/quds-mail-pr277-evidence/focused \
  --out /tmp/quds-mail-pr277-recount
```

For fresh execution, use a separate clean checkout at the accepted source, Node 24.22.3, and fresh runtime/output directories. Runtime setup needs access to the pinned dependency archives.

```sh
python3 reproduce_flutter_runtime.py --repo /absolute/path/to/clean-checkout --runtime /absolute/path/to/new-runtime
python3 qualify_mail_pr277.py \
  --repo /absolute/path/to/clean-checkout \
  --runtime /absolute/path/to/new-runtime \
  --out /absolute/path/to/new-results \
  --expected-head 5c7b76a6137bc9373276ce2e7fccc6ed48903998 \
  --format-base 0e4e999a08996a6b8696ca3adba11e303331b73e \
  --command-timeout 180
```

The default reruns 411 cases and 28 Node rechecks. Historical raw results supporting the retained 1,125 cases remain in `../mail-latest-main-integration-20261120` and its prior source-bound packages. This archive includes their accepted identities, required seals and hashed package provenance. SDK binaries, caches, kernels, native libraries and JavaScript build outputs are excluded. The archive is deterministic and every member and readable export is hashed.
