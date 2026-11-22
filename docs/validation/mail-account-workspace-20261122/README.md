# Mail account workspace — integration and qualification

## Scope

Complete the outstanding connected-account navigation work in
`CrispStrobe/quds_office_suite`, preserve concurrent Office changes, and advance
the ordered desktop Mail roadmap. The implementation retains explicit sign-in
and one foreground account across IMAP/SMTP, Exchange EWS, Gmail and Microsoft
365. See [the feature guide](../../roadmaps/mail/connected-account-navigation.md)
for behavior and remaining product scope.

This record is maintained as work progresses. Final qualification and
publication receipts are added only after the combined source is checked.

## Initial reconciliation and remote checkpoints

The initial main was `659b81462224a40f50975cfbfca39f636538b836`.
The captured inventory contains 44 fork heads, the 100 latest updated pull
request heads, and four upstream heads; no PR was open. Two fork branches had
outstanding work: Word text selectors and connected Mail navigation. Both were
merged with their complete original ancestry. The resulting checkpoint
`77f8ede7e1bd3e08094a4bcc1a09aa911cce4b10` contains all 148 captured observations
(114 distinct commits).

Remote branch: `work/mail-account-workspace-20261122`.

| Checkpoint | Preserved increment |
| --- | --- |
| `77f8ede7e1bd3e08094a4bcc1a09aa911cce4b10` | Current main plus outstanding Word and Mail branch ancestry |
| `f4516c13937b9ce5cec771bf331dc91d9f37105d` | Atomic expected-record account refresh and optional host capability |
| `0c836fe7555e6fec4e2e2a0b05c43024bc054975` | Native account identity fencing, late-owner draining and regression coverage |

Checkpoint publication uses GitHub Git objects and a non-forced ref update
with the expected previous head. Every generated remote tree is compared with
the exact local tree before advancing the branch. No credentials are embedded
in Git configuration. No source branch is deleted or rewritten.

## Local qualification completed before late reconciliation

Repository-pinned Flutter 3.47.8 / Dart 3.13.7 is installed from the official
archive and verified against its published SHA-256. All 204 required hosted
package archives match their lockfile hashes. Ordinary enforced-lockfile
dependency restoration leaves the repository lockfile unchanged.

| Cohort | Passing cases | Source boundary |
| --- | ---: | --- |
| Mail core | 648 | Relevant inputs unchanged at `f4516c13` |
| Native Mail transport | 612 | Relevant inputs unchanged at `f4516c13` |
| Shared Mail UI | 294 | Relevant inputs unchanged at `f4516c13` |
| JavaScript transport boundaries | 6 | Node execution, not browser UI acceptance |
| Mail SQLite store | 1,159 | Includes 47 focused account cases and real interruption recovery |
| Store browser-error classification | 3 | Node execution |
| Incoming Word/VBA | 1,458 | 17 suites; all 1,382 captured inputs unchanged |

These cohorts each had zero failures and skips. Source manifests and raw
reporters will be retained with the final evidence bundle. Repeated development
runs and runtime bootstrap tests are not added to these totals. Studio host
acceptance is recorded separately after reconciliation; it is not inferred
from shared package results.

## Boundaries

GitHub Actions runs, statuses and queues are neither queried nor awaited.
All stated test results come from local normal runners with the unchanged
pinned SDK. No CI workflow or repository protection is changed.

No real account credentials, user mail, provider mutations or outbound messages
are used for qualification. Live-provider and installed-platform acceptance,
simultaneous background accounts, unified live folders and full Outlook,
Thunderbird or eM Client parity remain open. Node checks do not establish
browser UI acceptance. Failed native owner close can require a host restart;
only owners supporting a successful later close can recover in-process.
