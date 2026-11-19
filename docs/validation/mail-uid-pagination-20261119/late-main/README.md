# Later main integration and bounded follow-up

While the `162f53c0` attempt ran unchanged, remote main advanced to
`b559f6c764fbfac143f593e89ddc1096ad8b5c4e`. It adds the Arabic T1 rule set,
CrispOffice Studio branding/localized modules, an account-free saved-message Mail
reader, and attributed incoming evidence. The source was first merged in an
isolated checkout and then fast-forwarded into the primary checkout after the
attempt ended. Existing Mail, protocol-fork, Hunspell and AyaSpell inputs were
preserved during the merge.

The incoming sample replacement intentionally removes 35 legacy Al Tahreer
images (6,643,916 bytes) and its sample Dart source, replacing the demo with a
neutral CrispOffice document. All removed content remains reachable in parent
history. The [inventory](merge-inventory.json) records the reviewed delta.
The replacement gallery description was also corrected to describe its English
paragraph sample rather than the removed bilingual/table/image document.

Review found and repaired two concrete integration defects. Studio Mail checks
`mounted` after both asynchronous file-selection/read boundaries; a new test
closes the dialog before a deferred picker completes. Arabic T1 raw phrase,
date and future checks now use the existing Unicode continuation boundaries and
comparison-mark handling; 17 new controls protect mixed-script tokens,
combining hamza/maddah and original UTF-16 offsets. All incoming positive rule
fixtures remain. Existing Studio tests now use the intended localized labels.
The [independent review](compatibility-repair-review.json) binds the four repair
files to their committed hashes; the [scope review](product-review.md) preserves
limits and test requirements.

The next committed plans cover 37 native suites (Arabic engine/editor, all 19
Studio suites, and actual Hunspell/lifecycle tests) plus 14 Node suites. The
Node selection includes the ten deferred Mail/MIME/fork suites and four Arabic/
Hunspell suites. Screenshot output is explicitly enabled and Poppler inputs
are hash-bound. The 953 previously accepted Mail executions are separate and
require exact product/dependency continuity. No result from an unexecuted suite
is represented as a pass, and no GitHub Actions status is used.

## Exact isolated review history

The [Git bundle](local-review.bundle) preserves the exact isolated merge, label,
compatibility and runner-repair commits through `9f517f36`, including the local
`5293c141` identity referenced by the independent review. Its prerequisites are
the already published `162f53c0` and incoming main `b559f6c7`. The bundle was
verified against this repository; [its identity](local-review-bundle.json) records
its size and SHA-256. After obtaining the prerequisites, `git bundle unbundle`
can restore these review objects without rewriting any branch. Subsequent Dart
formatting and the gallery-description correction are recorded in the final
source rather than retroactively attributed to that local review commit.
