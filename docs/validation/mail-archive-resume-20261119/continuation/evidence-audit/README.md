# Independent continuation audit

**Result: the published acceptance baseline passed the independent replay.**

The baseline is commit `b2c05a0afa0ae606b061b13d5e50937c2a8eb1df`, tree
`93fdf5a60b0db71a77c58dbff5b23f5cb3f8dfef`. It preserves the accepted source at
`71053bf61521e093903d55cba890ef4beee039e1` without product or test changes.

## Checks performed in this continuation

The original `verify-publication.py` passed before the working tree was changed.
It rehashed all 4,493 recorded source inputs and checked the accepted inventory,
Git blobs, executable modes, ancestry, receipt hashes, and documentation-only
publication changes. Its result is retained in
`baseline-publication-verification.json`.

The independent `replay_published_acceptance.py` reads immutable baseline Git
objects. It does not depend on the current checkout contents. The completed
`published-acceptance-replay.json` confirms:

| Evidence | Independently verified result |
| --- | --- |
| Raw test lifecycle events | 2,243 passed, zero failed, zero skipped |
| Unique test identities | 2,243, across 121 files and 11 cohorts |
| Required command records | 42 successful commands; every saved stdout/stderr hash matches |
| Reporter integrity | Successful terminal events, matching starts/finishes, no explicit errors, hidden failures, malformed JSON or duplicate case identities |
| JavaScript | Six retained compiled programs match their recorded hashes and successful assertion output |
| Mail source inventory | 4,493 immutable baseline Git blobs match accepted SHA-256 values |
| Incoming source inventory | 4,494 immutable baseline Git blobs match accepted SHA-256 values |
| Executed harnesses | All 13 preserved harness/selection inputs match recorded hashes |
| UI captures | All 24 final image hashes match retained reviewed captures and the prior independent audit |
| Receipt links | Acceptance, executed auditor, raw audit, mail receipt and incoming inventory hashes agree; incoming group receipts and counts match their inventory |

The retained dependency and runtime before/after inventories also agree with
their accepted digests and counts: 9,298 dependency inputs; 1,108 mail runtime
files; and 1,118 incoming runtime files. Those original external files are not
present in this workspace and were **not rehashed in this continuation**.

This is a replay of preserved evidence, not a new execution of the historical
product commands. Image identity was checked; the original visual judgment was
not repeated. Superseded, interrupted and development attempts do not contribute
accepted counts. GitHub Actions were not used.

## Initial PR #214 resolution review

Main `9ceb994d8edce3989228f1244cda90ecc9884931` includes PR #214 after the accepted
baseline. Its native NER helper is behaviorally equivalent to the already
accepted `_nerStatus()` implementation. The reviewed continuation preserves the
accepted native host and all five existing download-size/NER regression cases,
then incorporates main's model-only label and two additional NER assertions.
At that initial continuation checkpoint, the observed product/test difference
from the acceptance baseline was exactly three paths:

- `packages/quds_office_editor/example/lib/studio_downloads_manager.dart`
- `packages/quds_office_editor/example/test/studio_downloads_manager_test.dart`
- `packages/quds_office_editor/example/test/studio_spacy_setup_test.dart`

The subsequent PR #215 integration additionally changes the native host and is
covered by the separate focused qualification and independent audit at final
source `9b8853667b68c7bebff050e52445b47ea0bbd188`. That final audit passed 50
executions across three complete test files and four commands, with all 4,493
source, 9,298 dependency and 695 declared runtime input hashes stable and
reverified. It supersedes the initial three-path review as the final integration
scope while preserving this historical acceptance replay unchanged.

No historical acceptance blocker was found. The final report should distinguish
the 2,243 historical accepted executions from the 50 fresh scoped executions;
adding them does not establish a new count of unique cases. Confirm the
published candidate's ancestry and verify the fetched merged tree against it.
