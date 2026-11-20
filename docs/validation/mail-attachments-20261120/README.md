# Studio mail attachments: resumed completion and qualification

This continuation completes PR #221's bounded attachment increment and preserves
the recent Office work captured at intake. It uses local qualification on the
repository's locked dependencies. GitHub Actions, workflow status and commit
status endpoints were neither consulted nor awaited.

The fresh checks contain **2,049 distinct passing application cases**,
**zero failed cases**, and **one explicitly not-run optional native case**.
The [independent audit](independent-audit/README.md) recounts raw events and
checks selections, completion, source hashes, runtime hashes and artifact bytes.
Its [final-main add-on](independent-audit/FINAL_MAIN.md) binds the accepted set
to the last macOS refresh without counting the pin-test replacement twice.
The original frozen acceptance set contains 2,034 cases. The final main refresh
adds 15 passing comment-language widget cases in
[post-main-comment-draft](post-main-comment-draft/README.md). The original audit
remains immutable; a supplement verifies the new suite and combined total.

## Delivered mail behavior

- The shared native Studio composer accepts file attachments for SMTP, EWS,
  Gmail and Microsoft 365 submission paths: at most ten files and 10 MiB of
  combined original file bytes, with UTF-8 filenames limited to 255 bytes.
  Empty files and repeated filenames are supported.
- Selection is atomic. Names, declared sizes, aggregate bytes and count are
  checked before reading. Actual stream chunks are bounded, actual length must
  equal the declared length, and each file has a 30-second read deadline.
  Cancellation and late callbacks cannot add files to a closed composer.
- Attachment bytes are copied into owned snapshots. Editing or deleting the
  original file cannot alter an acknowledged retry. Uncertain submissions still
  require the user's explicit acknowledgement before retry; this remains a
  foreground, session-only flow.
- Canonical MIME is `multipart/mixed`, with the text/HTML alternative first and
  base64 file parts. RFC 2231 filename encoding retains Unicode names. Bcc stays
  out of the canonical message; all intended recipients remain in the separate
  submission envelope or existing private provider-request copy.
- The inherited quoted-printable encoder now protects trailing whitespace and
  maintains its 76-column boundary around Unicode data.
- The narrow Arabic composer keeps the message body visible at normal text size
  while retaining editing, IME and undo/redo state across a resize.

The [attachment guide](../../roadmaps/mail/attachments.md) specifies behavior,
limits and remaining work. The [Arabic screenshot](arabic-composer/arabic-composer.png)
was captured at 390 × 844 from the public production composer and visually
reviewed. Its exact harness, raw events and receipts accompany it. It is a
separate visual check, not an extra case in the 2,034 total.

## Fresh accepted checks

| Cohort | Passed | Complete suites | Evidence |
| --- | ---: | ---: | --- |
| Mail core, MIME, store and transport, Dart VM | 1,068 | 53 | [Mail receipt](mail-packages/receipt.json) |
| Mail store/transport portable boundaries, Node | 9 | 4 | [Selection](mail-packages/selection.json) |
| Vendored MIME builder and quoted-printable regressions | 83 | 3 | [Raw archive index](mail-packages/raw-evidence.index.json) |
| Studio mail hosts, composer, attachments, recipients and threading | 319 | 11 | [Receipt](flutter-cohorts/mail-host/receipt.json) |
| Editor slide/rendering regressions | 109 | 10 | [Receipt](flutter-cohorts/editor-rendering/receipt.json) |
| Editor Zotero research-material browsing | 48 | 3 | [Receipt](flutter-cohorts/editor-zotero-materials/receipt.json) |
| Studio spaCy setup and pinning | 20 | 2 | [Receipt](flutter-cohorts/studio-spacy/receipt.json) |
| Engine slide/PDF rendering | 224 | 12 | [Receipt](incoming-office/engine-rendering/receipt.json) |
| spaCy controlled package tests | 113 | 11 | [Controlled receipt](incoming-office/spacy-package/controlled-suite-receipt.json) |
| Macro CLI, language and runtime | 41 | 3 | [Receipt](incoming-office/macros/receipt.json) |
| **Original frozen acceptance subtotal** | **2,034** | **112** | [Independent raw-event audit](independent-audit/report.json) |
| Comment-language regression after main refresh | 15 | 1 | [Post-main receipt](post-main-comment-draft/receipt.json) |
| **Combined distinct fresh acceptance total** | **2,049** | **113** | [Independent audit and supplement](independent-audit/README.md) |

The only skipped case is **“the qualified macOS library has the recorded code
digest”**, because `QUDS_SPACY_MACOS_LIBRARY` was not supplied. The original
spaCy strict receipt remains unchanged and rejects its blanket no-skips guard.
A separate controlled receipt accepts only that exact predeclared native skip;
all 113 executed controlled cases passed. This is not native macOS or real-model
qualification.

Strict analyzer and formatter checks passed for all **62 changed Dart targets**
in the final product freeze ([receipt](static/receipt.json)). A separate strict
analysis passed on **16 selected file/directory targets**, including all spaCy
libraries/tests, its new tools and changed slide/PDF/German-facts sources
([receipt](incoming-office/analysis/receipt.json)). These are overlapping
analysis scopes, not counts of additional tests. The newly received comment
test also passed exact-file formatting and strict analysis. Nine pre-existing style
findings in the unrelated spaCy `tool/consume_distribution.dart` remain; no
whole-workspace analyzer-clean claim is made.

The independent [MIME probe](attachment-core/README.md) additionally passed
three synthetic scenarios through the production builder, production decoder
and Python's independent email parser. It checked exact file bytes and names,
canonical Bcc exclusion, body whitespace, threading, empty/duplicate files and
maximum configured attachment/body bounds. The maximum fixture produced
21,986,572 canonical bytes and 29,315,432 outer-base64 bytes. A recorded 1 KiB
HTTP-wrapper allowance is an estimate, not a captured provider request.

The probe, visual capture, 42-case background repair development run, preliminary
runs and inherited historical reports are **not added** to the 2,049 cases.
The final rendering cohort already contains the 42 background cases.

## Reconciliation and repaired Office behavior

The [captured reconciliation audit](resumed/reconciliation/README.md) accounts
for all **117 distinct heads** in two saved branch/latest-100-PR inventories:
106 ancestors and eleven proven historical equivalents. All **477** complete
changed-path identity comparisons matched, including six pairs with identical
entire trees. There are no unresolved captured heads.

The later intake snapshot spans **20 November 2026, 05:21:08–05:21:09 UTC**
(06:21 Berlin). The initial snapshot has no separately recorded precise time;
that limitation is retained. The audit establishes preservation of these exact
captured revisions, not all subsequent work on actively changing branches.

The combined source preserves the captured Zotero research browser, VBA
reconciliation/string work, native grammar-v2 and macOS signing/portability
changes. Integration review repaired PPTX background ownership and inheritance,
background preservation across repeated saves and slide copies, and PDF picture
borders after crop restoration. Earlier numeric-text, layout, animation-ID and
connector/flip corrections remain intact. See the [incoming Office report](incoming-office/README.md).

The first final main refresh incorporates `b0b79d90b0f4ca0036483d73095b4821efddcc8e`
(PR #226), which changes only seven lines in a comment-language test. The observed
Zotero reconciliation head `f3f98987824e021ed22a4d909e38d6307495267b` is also
retained; merging it after main changed no tree bytes. A subsequent refresh
incorporates main `3e5f44ae14926b8054b2e5c0558ce71477891a33` (PR #228),
preserving pinned spaCy bytes in ad hoc builds and updating the signing
cross-check. Relative to the qualified source it changes one build script,
release documentation and Dart comments; no executable Dart or package
configuration changes. Its [focused check](post-main-macos/README.md) and final
source-applicability proof are retained separately. The one pin-test replacement
and eight controlled shell scenarios do not add application cases. Newer unmerged Variant and shape-preset/theme
revisions observed after the intake cutoff remain separately identifiable on
their source branches. They are not claimed as qualified by this mail
acceptance set.

## Source and publication identities

| Local source checkpoint | Qualification / purpose | Published identical tree |
| --- | --- | --- |
| `75083ea738d08be3eb9a3d983ac80a7f05a6201b` | Mail package inputs and independent MIME probe | `2c3479838721632167933eb99b78beaac285e862` |
| `84eb237806a3110b36322382aa98a1897ebac204` | Incoming reconciliation checkpoint; background save repair still in progress | `e12910204ef77644c12bf06ef7030c11268ada86` |
| `b8686c05e055ca0395726fe528d585379597d628` | Completed product repair and 496 Flutter cases | `906843fbf2bfc20f8040543a122d88c93f20de83` |
| `58c6962ec3ea82811bfcafec42981385f216f892` | Engine/spaCy/macro acceptance and strict changed-target checks | Included in final publication; mapping recorded in PR #221 |
| `6184051c75d882cac53be3c1a9384e4556588ad1` | Main comment-test refresh plus observed Zotero ancestry | Included in final publication; mapping recorded in PR #221 |
| `f8f36eb87b051a0b26ee68747dfd24c4717eaec1` | Subsequent merged macOS build fix; executable Dart unchanged | Included in final publication; mapping recorded in PR #221 |

The [publication ledger](resumed/publication-checkpoints.json) records completed
remote checkpoints. GitHub's final PR body records the publication containing
the ledger itself and the merge verification. API-created publication commits
have different commit IDs from local commits; the entire Git tree is required
to match exactly before updating the remote branch. Updates use the expected
previous head and `force=false`, and preserve original incoming commits as
parents or ancestors.

The small [local source checkpoint bundle](resumed/local-source-checkpoints.bundle)
also preserves the exact local commit objects named by the validation runners.
Its prerequisite commits are all retained in the published branch's history.
After fetching the final branch into a clone, `git bundle verify` can check the
bundle; `git fetch path/to/local-source-checkpoints.bundle
HEAD:refs/heads/evidence-local-qualification` imports the original local source
history without moving the current branch. This permits source-bound audit
replay using the original local IDs as well as the published-tree mappings.

No executable Dart application code changed after `b8686c0`. The next two commits add
braces to a standalone grammar tool and correct newly added PDF test assertions
to recognize semantically equivalent numeric/whitespace formatting while
checking both crop-state restores. The [Flutter input proof](flutter-cohorts/final-input-audit/receipt.json)
verifies that neither file is selected or imported by the accepted Flutter
cohorts; application, dependency and runtime bytes remained unchanged through
that freeze. The later macOS refresh changes comments in the distribution
library and the separate build script, with its scope proved independently.
The independent audit separately binds the earlier mail/probe inputs to the final
freeze. The post-main supplement proves applicability after the unrelated test
change. Final evidence/documentation commits do not change qualified product,
test, package, asset or runtime inputs.

## Runtime and reproducibility

The recovered runtime is **Flutter 3.47.8 / Dart 3.13.7 / Node 24.22.3**.
The official Flutter archive SHA-256, 194 hosted-package archive hashes, locked
offline resolution and the normal SQLite/FTS5 native hook are retained in
[runtime receipts](runtime/README.md). No dependency versions were updated.

Each accepted cohort retains its exact command and selection, complete machine
events, stderr, input inventories, receipt and runner. The existing robust
[Zotero runner](../zotero-research-materials-20261120/run_validation.py) is reused
with explicit selection adapters; test declarations and timeouts were not
weakened. Hidden loading/lifecycle events are excluded from application totals
but any failure in them rejects acceptance.

The mail package archive and all diagnostic archives have per-file byte lengths
and SHA-256 indexes. Receipt paths referring to the original scratch workspace
describe where execution happened; adjacent scripts and retained repository
paths make the evidence inspectable without reconstructing that machine.

For the audit scripts' original flat directory layout, run
`python restore_evidence.py --output /path/to/new-final-validation` from this
report's directory. The helper verifies every indexed archive member while
restoring the evidence. It does not install the recorded SDK/dependency files
or source Git objects; those remain explicit prerequisites for a full input
recheck. Import the source checkpoint bundle described above when local commit
IDs are needed. The original pre-final static receipt used by the immutable
audit is also retained in the diagnostic archive; the final 62-target rerun is
available directly under `static/`.

## Diagnostic history and practical limits

The [diagnostics](diagnostics/README.md) retain the first mail run whose receipt
rejected a concurrently changed lockfile, the incoming PPTX failures and repair
stages, the two PDF test-assertion failures, the initial analyzer findings and
unsuitable visual-capture harness attempts. Those records are not relabeled as
passing. Accepted replacements and their exact source identities are separate.

This increment does not establish live-account delivery, recipient-facing Bcc
privacy on real services, native file-picker interoperability, installed Word/
Excel/PowerPoint compatibility, release signing or real native-model behavior.
No real message was submitted during qualification. Full Office/VBA parity,
durable composer drafts/outbox, automatic background resend, received-attachment
forwarding, document/PDF-to-mail commands and VBA mail methods remain future
work. The attachment representation and canonical send path supply a bounded
foundation for those later increments.
