# Final integrated local qualification — 19 November 2026

**Local qualification passed at `39843ed4874c7b56572c7aa8195716e5892aeca2`.**
The final affected-suite replay passed **2,018 distinct cases across 129 suites**.
The separate native thesaurus fixture passed **208 cases across 14 suites**, the
release web fixture compiled, and installation passed exact-file verification.
PR #174 remains a draft because actual offline-browser execution, installed
Studio/OS acceptance and independent human linguistic review remain open.

## What this continuation completed

The interrupted handoff had saved `7e4adc08`. All nine recovered archives and
215 indexed files were intact, but no complete 129-suite replay had been saved.
The first complete replay at `59f13897` passed 1,985 cases; its original logs,
source/runtime inventories and independent audit remain in
[`prior-union-summary.json`](prior-union-summary.json),
[`combined-before-annotations.tar.xz`](evidence/combined-before-annotations.tar.xz)
and [`review/before-annotations/`](review/before-annotations/).
Those passes are not added to the final replay.

A bounded final remote capture found three newer incoming heads:

| Work | Captured head | Integrated result |
| --- | --- | --- |
| Notes / PR #175 | `bb241a34` | Keep the stable Review layout and selection fixtures; add two stronger tracked-revision assertions. |
| Mail / PR #172 | `db7501ee` | Preserve the latest incoming ancestry, runtime and source-binding evidence. |
| Zotero / PR #173 | `ff06e554` | Add Annotation protocol, guarded Word transaction, workspace/direct dialogs and Studio ribbon, with the captured regressions. |
| Main | `690e6ac8` | Already included; unchanged in both captures. |

All **391 captured refs / 253 distinct heads** are accounted for: 363 refs by
ancestry and 28 refs through 14 independently reverified historical equivalents.
The latter remain non-ancestors. See the
[final published-head ancestry audit](incoming/final-integrated-audit-39843ed4.json)
and [merge-resolution review](incoming/final-merge-resolution-review.json).
No additional moving-head refresh is included in this frozen qualification.

The merge retains the stable Flex topology introduced by `3847d5f4`, preserving
Notes controller, focus, selection and composition through opening, closing and
resizing Review. Both tracked and untracked IME/undo regressions remain covered.
The new Add Annotation cases exercise controlled transport, cancellation,
guarded insertion, focus and document history. They do not establish a live
Zotero session or interoperability in Microsoft Word or LibreOffice.

The targeted runner now accepts a positive concurrency setting (default four),
saves atomic preflight/failure receipts, rejects malformed suite records and
layout/missed-tap diagnostics in either stream, and stops descendant processes
on timeout or interruption. **Fourteen runner controls passed**, including a
real child process that ignores SIGTERM. The final audit confirms their exact
five source files are unchanged; no additional control run is claimed.

## Final validation

| Final replay cohort | Suites | Distinct passed cases |
| --- | ---: | ---: |
| Engine / review / Zotero | 42 | 717 |
| Editor / Notes / headers / Zotero | 73 | 1,154 |
| Studio / review / navigation | 10 | 117 |
| Mail UI | 4 | 30 |
| **Complete affected-suite union** | **129** | **2,018** |

Strict static analysis with fatal infos/warnings and format checks passed for
**30 Dart paths**. This is targeted qualification, not a fresh whole-repository
run. [Summary](union-summary.json), [independent peer audit](review/final/peer-audit.md),
[exact case identities](review/final/peer-cases.json) and
[raw evidence archive](evidence/combined-final.tar.xz) are preserved.

The independent audit reconstructed counts from raw events and checked exact
planned suite/command coverage, start/completion integrity, terminal success,
lifecycle exclusions, stderr, diagnostics and compressed/original log hashes.
There were no failed, skipped, unfinished or repeated cases, duplicate case
identities, error events, overflows or missed-tap diagnostics. All **4,992 ordinary
source records** match the frozen Git commit; source, **11,948 environment
records**, six harness/plan inputs and effective package configuration remained
unchanged before and after execution.

The final native fixture separately passed **208 cases / 14 suites**. Its cases
overlap the union above and are not added to the 2,018. The saved Mail core,
store and MIME gate retains **152 distinct Dart cases** under its original
source/runtime receipts; unchanged Mail source was checked separately. The
historical 421- and 606-case reports are also not included in any new total.

## Native fixture, release compile and installation

The original committed fixture runner executed from a separate workspace with
verified live source links and locked dependencies. Application/fixture inputs
and all **11,953 captured native runtime files** remained unchanged.

| Build/installation result | Verified value |
| --- | ---: |
| Original compiled files | 1,155 |
| Original compiled bytes | 87,446,576 |
| Installed inventory files | 1,156 |
| Installed inventory bytes | 87,447,167 |
| Untouched original compiled files | 1,154 |
| Permitted installation changes | Exact `index.html` replacement and added `offline-install.js` |

Independent verification checked every installed file, the complete generated
worker, cache identity, successful compilation receipt, source inventory and
original logs. See [native/build summary](native-build-summary.json),
[independent native audit](review/native/summary.json) and
[native evidence archive](evidence/native-final-evidence.tar.xz).

The three [native screenshots](visuals/) were inspected, including German at
390 px with 1.5× text scaling. Dialog text, alternatives and action controls are
readable without visible modal clipping or overflow stripes. These are native
fixture renders; they are not browser screenshots or installed Studio evidence.

Both compiler warnings remain in the raw logs: the deprecated `--pwa-strategy`
flag and a wider-editor CupertinoIcons reference without that font bundled.
The thesaurus Material icon font is present. The generated application bytes
were verified locally but are **not included in the compact evidence archive**;
its receipts and original/installed inventories are included. Rebuild the frozen
source when preparing a fresh host replay.

## Linguistic review packet

The [fresh human-review packet](linguistic/linguistic-review.md) contains **15
observed native queries and 109 distinct meaning records**. An independent
review checked the full records against **92 hash-verified source shards** and
all **ten original notices** byte-for-byte. Reviewer identity, date, expertise,
judgments, notes and release recommendation remain blank. Its explicit status
is `not_reviewed`. This export makes no human linguistic acceptance claim.

## Remaining release acceptance

| Gate | Current status | Required completion |
| --- | --- | --- |
| Actual offline browser, CSP, lifecycle and performance | Unverified; this host still returns EPERM for the required AF_UNIX socket. No new browser execution was performed. | Run the bound fixture and existing Playwright harness on a supported browser host. |
| Installed Studio and real OS/IME workflows | Unverified; this host lacks the native compiler/GTK/display setup. Controlled tests do not establish live Zotero interoperability. | Execute the installed native Studio and OS/IME procedures on a suitable desktop. |
| Independent English/German linguistic review | Packet ready; human review incomplete. | Have an independent reviewer complete the supplied judgments and recommendation. |

Follow the [release acceptance guide](../../../roadmaps/thesaurus/release-acceptance.md)
and [Zotero workflow guide](../../../zotero-support.md). The test worker remains
acceptance infrastructure. No production deployment or release approval is
claimed. GitHub Actions were not queried, dispatched or awaited.

## Reproduce the local union

Use the verified Flutter **3.47.8 / Dart 3.13.7** runtime and its preserved
receipts. The complete official SDK archive and **176 hosted archives** were
hash-checked; both workspace and tooling resolution used
`--offline --enforce-lockfile`, preserving the committed lock.

```sh
python3 docs/validation/thesaurus-20261118/reconciled/run_targeted.py \
  --runtime /absolute/verified-runtime \
  --output /absolute/new-combined-evidence \
  --concurrency 4 --timeout 1800
```

The runner requires committed inputs and a fresh output directory. The
[native evidence index](evidence/native-final-evidence-index.json) identifies
its exact setup, invocation and independent installation-verification scripts.
All original failed/interrupted attempts in earlier checkpoints remain intact.

## Saved checkpoints

| Checkpoint | Purpose |
| --- | --- |
| `ff0775cb` | Initial Notes/Zotero reconciliation. |
| `59f13897` | First frozen source and hardened concurrent runner. |
| `c020fd7f` | Recovered-evidence, controls and coverage audit. |
| `15d51959` | Completed first engine cohort checkpoint. |
| `fa0cd40d` | Complete first 1,985-case replay and independent audit. |
| `39843ed4` | Final bounded annotation integration and 30-path analysis plan. |

Subsequent evidence/documentation commits retain the qualified application,
fixture, plan and runner bytes from `39843ed4`.
