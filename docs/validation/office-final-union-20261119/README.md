# Office continuation — final evidence union, 19 November 2026

This publication completes the remaining history and evidence reconciliation after [PR #191](https://github.com/CrispStrobe/quds_office_suite/pull/191) merged into main at `4c25c0455cee867db4cfad0f737cb886f01c1936`. It preserves that main tree's implementation, tests, plans, dependency inputs and runners without any product change, restores the missing accepted `0f16754c` evidence publication, and retains the later `f8248650` Mail-action checkpoint as source-bound historical work.

**There is no accepted runtime qualification for the final combined implementation.** The current source's aggregate failed during core/store; its exact Store failure could not be inspected after the environment became unwritable. Earlier accepted results remain valid for their own commits and are not a substitute for a new final-source run.

## What is merged

The current implementation comes from `de24bdfc2b2a1c6691d53d963c993fc236d1ffe5`. Its next commit, `1d762d4c369795175b55a4ecb9c44efd29f041b1`, changed exactly six documentation/observation files. The normal main merge at `4c25c045` has the same tree as that documentation commit: `15e1d979abdcacaf316b849e58dac4249e643424`.

The GitHub comparisons establish that `de24bdfc` already contains PR #192's `0601d279` and the previously qualified `0f16754c` source. It did not yet contain `ae5bb49c`, which publishes the completed `0f16754c` results. That missing evidence is restored here. The new union keeps `f8248650` and `4c25c045` as actual parents, so both histories remain explicit.

| Input | Disposition |
| --- | --- |
| Main `4c25c045` | Base tree; all implementation, test, plan and runner entries retained exactly |
| PR #191 / `de24bdfc` | Current implementation, already merged into main |
| PR #192 / `0601d279` | Preserved ancestor; overlapping Mail ownership safeguards reviewed semantically |
| `ae5bb49c` | All 24 evidence-publication entries restored; its overview also retained as an exact historical copy |
| `f8248650` | Original source retained through ancestry; all ten Mail-action evidence files retained |
| Earlier failed, interrupted and accepted checkpoints | Original attributions and archives retained |

[The lineage record](lineage.json), [source preservation review](preservation-review.json), [Mail review](mail-review.json) and [test disposition map](test-dispositions.json) document the finite reconciliation. The publication manifest records exact overlays and the unchanged non-documentation trees.

## Resulting application behavior

The retained implementation combines native account sessions and saved EML reading, with the browser import graph separated from native transports. Body reads and mark-read use the bounded mailbox/UIDVALIDITY/UID provider path; mark-read verifies the flag before local success and does not automatically retry writes.

Reply and text-only Forward use the authoritative decoded plain-text body, respect Unicode scalar boundaries and explicit quote limits, and protect a retained uncertain draft from implicit replacement. Confirmed SMTP acceptance remains final when later cleanup fails; an outcome from another client cannot confirm the current send. Unconfirmed submissions retain their draft and explicit retry acknowledgement. SMTP final-acceptance and pending-command-abort checks remain in the vendored transport.

The reviewed lifecycle differences from PR #192 do not establish a normal-workflow regression: generation guards, candidate cleanup, independent transport aborts, queued disconnects and transport generation checks retain ownership and shutdown behavior. Its extra repeated stale cleanup and synchronous factory-seam guards are not copied over the newer implementation without a demonstrated failure.

Word retains selected-script language defaults, an explicit two-slot mode, mixed-fragment inspection and selection split/coalescing safeguards. Arabic semantic marks, UTF-16 mappings and token boundaries remain; morphology numeric feature text stays portable across VM and JavaScript. Current footer, Settings/Notes/comment/Zotero, About-link, cancellation and publisher work is retained.

## Validation, with source boundaries

| Source | Recorded result | What it qualifies |
| --- | --- | --- |
| `0bd53e3e2b0d75ae48a4d7807dcddd123ab477f9` | **1,898 passing executions; 1,327 distinct cases; 68 suites** | Earlier full Office checkpoint; [report](../office-resume-main-20261119/final/README.md) |
| `0f16754c278aa83cc79d5777e5b45d3f739e5469` | **404 passing executions; 395 distinct cases; 28 suites**, zero failures/skips; 45 strict analysis/format targets | Later modular-Mail/main follow-up; [report](../office-resume-main-20261119/main-refresh/README.md) and [independent raw-event audit](../office-resume-main-20261119/main-refresh/review/qualification-audit-refresh.json) |
| `f824865001913e48b4b2551eb9f359476e6cbd56` action work | Three-path strict analysis passed; **zero runtime cases executed** | Superseded narrow action proposal; Flutter failed at suite startup with ENOSPC; [exact record](../office-resume-main-20261119/mail-actions/README.md) |
| `de24bdfc`, carried unchanged into current main | **No accepted aggregate**; observed exit 1 / FAIL during core-store | [Uploaded external failure notice](../office-mail-continuation-20261119/attempt-de24bdfc/environment-failure-notice.json); raw Store receipt/log and final fingerprints could not be inspected |
| This final evidence union | Git object/ref/tree and preservation checks | Documentation/history publication only; no new runtime execution is claimed |

The 1,642-execution result reported in the earlier PR #192 description is not accepted here: its stated final evidence commit was not available on GitHub. The later PR #191 closeout supersedes its earlier RUNNING description and explicitly records an unqualified failed attempt. [Captured PR observations](peer-observations.json) preserve that distinction.

The five prepared `f8248650` action regressions are superseded by the newer canonical loader/reply/session tests for their main behavioral intentions. Two precise sequence-coverage gaps remain: failure followed by a successful mark-read retry, and an old completion arriving while a replacement session already has a new mark-read request pending. Their prepared source remains archived; no execution or product failure is inferred.

The local host reported zero writable bytes. Removal of only verified untracked generated caches did not restore capacity. The reviewed source and raw startup evidence were uploaded through the Git data API with independently computed hashes. The current local checkout remains at the earlier `ae5bb49c` merge workspace; it is not claimed synchronized with the remote result.

## Replay and remaining acceptance

Use a separate clean checkout on a host with sufficient storage. Preserve existing failed-attempt files if they become available, and use a new empty output directory. The current [native plan](../office-mail-continuation-20261119/native-plan.json), [Node plan](../office-mail-continuation-20261119/node-plan.json), pinned [web SDK preparation](../office-mail-continuation-20261119/prepare_web_sdk.py), and [driver](../office-mail-continuation-20261119/run_validation.py) remain unchanged.

For a new qualification of the actual checked-out final commit, after restoring the pinned native/runtime and separate web SDK:

```bash
OFFICE_SOURCE=$(git rev-parse HEAD)
python3 -B docs/validation/office-mail-continuation-20261119/run_validation.py \
  --head "$OFFICE_SOURCE" \
  --base b070e228a749e22cc8ce2098029a76ab5fb8eccb \
  --runtime "$OFFICE_RUNTIME" \
  --web-sdk "$OFFICE_WEB_SDK" \
  --output "$OFFICE_RESULTS" \
  --command-timeout 900
```

Complete and independently audit the passing gate before assigning accepted totals. The earlier source-bound commands remain in their own reports.

Actual browser sessions and persistence, installed application/OS/IME behavior, live Mail/Zotero accounts, external Word/LibreOffice interoperability, broader native/Wasm packaging, the real morphology library/language bundle and independent linguistic acceptance remain separate.

No GitHub Actions run, job, queue or status was queried, dispatched or awaited.
