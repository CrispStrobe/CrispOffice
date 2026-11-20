# Mail bulk branch reconciliation

## Captured source and qualification status

This integration uses the fixed incoming-source cutoff below. It does not chase
later feature pushes, query GitHub Actions, or wait for queued CI.

| Source | Captured commit |
| --- | --- |
| Frozen Word baseline | `cb5909fefe6dd41db0f9c38207db83166072dcaf` |
| Bulk actions | `9109fcc645d0d95fbe7a7568ddf1e0ebc07bc384` |
| Bulk flags | `fcc7bd27f7df6200ac7d3174f6e21097f931cca0` |
| Mail branch common ancestor | `b01cb23dc1b7bc94b691d68a2507b61dc6d48d7a` |

**The complete qualification of the resolved source is pending at this source
checkpoint.** Final command receipts must bind the durable integrated commit,
runtime and source hashes. Earlier core-only results for `69ab514b` do not
qualify the newly integrated provider, UI or Studio changes. Historical intake
files retain their original statuses and are not new acceptance runs.

## Resolution decisions

The flags branch contributes mutation-boundary evidence in `MailProblem` and
the native IMAP, EWS, cloud and unsupported providers, plus localized progress
and per-message outcomes. The actions branch contributes the retained strict
plan/provider validation, single-use coordinator, immutable record/action
adapter compatibility, and independent cancellation, reconnect, disposal,
keyboard and accessibility regressions.

There is one execution loop. The provider-result runner adapts into the same
typed-attempt coordinator, preserving original problem objects. Only explicit
no-mutation evidence is definite. Both entry points stop after uncertain
results, definite cancellation/stale-operation failures, retired scope or stop
requests. Progress observers cannot erase results, trigger replay, or permit
further work after retiring scope. The in-flight provider acknowledgment is
retained; the host separately guards view publication.

The shared UI uses `selectionRevision`, `bulkEnabled` and a host-owned
`bulkStatus`. Accepting an action consumes both the popup snapshot and checked
set. Original tests now capture the private immutable popup values and perform
a fresh selection before another action. Escape-to-clear, accessible stop while
busy, independent notice/error nodes, and mounted/disconnect guards are retained.

Native hosts accept either explicit bulk adapters or the earlier combination
of immutable remote records and action adapters. The latter preserves exact
frozen identities but conservatively reports every invoked failure as uncertain.
Adapters without immutable remote identity evidence remain read-only for bulk
operations. Current scope includes foreground behavior only; no durable command
journal, offline replay, persistent-cache update promise or live-account claim
is introduced.

## Retained independent coverage

- Core: `bulk_flags_test.dart` retains the actions coordinator suite;
  `bulk_flag_runner_test.dart` retains the flags provider-result suite.
  Stable operation IDs use the original `plan:index` form in both APIs.
- Mail UI: `bulk_message_list_test.dart` and `message_list_bulk_test.dart`
  retain both independently authored selection/callback suites. The first
  suite's expectations explicitly reflect consumed selection after dispatch.
- Studio: existing EWS and native workspace suites retain the actions cases;
  the native workspace also retains the separate evidence-aware fixture and
  flags cases. The flags provider/loader suites and both localized visual
  harnesses remain available. Cached-host assertions cover absent bulk status
  and mutation controls.

## Required local acceptance

Use the locked dependencies and recorded Flutter/Dart runtime without changing
tracked manifests or lockfiles. Run all Mail core and transport tests, all Mail
UI tests, the changed Studio provider/loader/native/EWS/cloud/cached/visual
suites, and strict analysis of affected packages and files. Capture localized
visual evidence outside the source tree before packaging it. Preserve failed
development logs separately from final passing receipts.

The Word production compiler, fixture families and documentation are retained
from the frozen Word baseline; the Mail merge must not change that accepted
source while its independent gate runs.
