# Studio recipient groups and Reply all — 2026-11-19

## Outcome and qualification

This continuation adds multiple To recipients, Cc, Bcc and Reply all to the foreground Studio mail hosts. It also preserves the captured recent PPTX, VBA dynamic-array and Zotero histories, their regression tests, and their validation records. The starting main was `2170791c9250d72c9df31a065408365f9b50abaa`.

**Local execution is partial.** The pinned Flutter 3.47.8 / Dart 3.13.7 runtime was installed, but the complete workspace dependencies could not be resolved. The executed subsets use actual production source with a separate, normally resolved cached Dart dependency graph. They are not full-workspace or final Flutter/MIME/provider acceptance. GitHub Actions were neither queried nor awaited as a gate for this continuation.

| Executed check in this continuation | Result | Scope |
| --- | --- | --- |
| Studio mail recipient/reply/thread subset | 57 passed, 0 failed | 8 recipient, 33 reply and 16 threading cases; 46 retained declarations; 18 complete MIME-dependent declarations omitted |
| Unchanged `quds_mail_core` suite | 54 passed, 0 failed | Actual core source at tree `2860c22f05dacc4cdeb18552e419c01e9d9b6862`, under the separate cached graph |
| Independent recipient-parser checks | 49 passed, 0 failed | Direct import of the actual helper; boundary, invalid-input and deduplication checks |
| Slide import/model and explicit-style serialization | 15 passed, 0 failed | 14 import/model cases and one incoming explicit-style case, against the recorded 45-file production graph |
| Incoming Zotero tag-catalog suite | 27 passed, 0 failed | Original client/models and all original test assertions; existing transport fixtures, no live service |
| Pinned formatter on changed package Dart files | 52 files, 0 changes | Successful final format check; unavailable lint-include warnings do not constitute analyzer acceptance |
| Product whitespace and independent source review | Passed / no concrete blocker found | Mail envelope/privacy/retry logic, source preservation and the reconciled slide contracts |

The product whitespace check passed. Raw validation diffs retain their context spaces, and AST-adapted test copies retain the exact whitespace used during execution; an evidence-wide whitespace check therefore emits warnings. Those artifacts are preserved byte for byte.

Counts are separate cohorts, not an aggregate acceptance claim. `source-binding.json` links the executed source hashes to product checkpoint `7ac278d13f14ffed93f1685e42b4d2a8992d04f2` (tree `7f89fef47a470399287f3f5bb62c785350847f2b`). Evidence-only commits may follow without changing product code.

## Mail behavior

- To, Cc and Bcc accept comma- or semicolon-separated bare ASCII mailboxes. At least one recipient is required across the three fields, including Cc-only and Bcc-only messages.
- Manual input is bounded to 100 entries before deduplication and 25,600 total characters before splitting/trimming. Each mailbox is at most 254 characters; its local part is at most 64 and each DNS label at most 63.
- Stable deduplication gives To precedence over Cc and Cc over Bcc. The first spelling is retained; local parts compare exactly and domains ignore case. Controls, non-ASCII input, empty list entries and unsupported mailbox grammar reject the draft instead of silently selecting a subset.
- Canonical MIME contains visible To/Cc and no Bcc header. The complete validated envelope is passed separately to native SMTP, EWS and the cloud adapters. SMTP still disables concurrent Sent-folder append. Existing EWS SOAP and Gmail/Microsoft 365 service-request handling remains responsible for hidden recipient delivery; canonical prepared bytes are unchanged by that handling.
- Reply all uses every decoded Reply-To mailbox, or From when Reply-To is absent, then original To and Cc. It removes the connected account identity, preserves To/Cc roles, never inspects source Bcc, and reuses the existing quote and thread metadata. Source scanning is bounded to 1,024 entries and output to 100 distinct recipients. Unsupported decoded source participants fail explicitly. Self-only/empty sources leave an editable unaddressed draft.
- Ordinary Reply validates its selected decoded mailbox before copying it to a list-capable field. A malformed source mailbox cannot introduce extra recipients through a comma or semicolon. Forwarding inherits no recipients or reply-thread metadata.
- Composer edits and uncertain-send retries retain To, Cc, Bcc and thread metadata. The existing explicit delivery-check acknowledgement is still required before an uncertain attempt can be retried.

The address guarantees apply to the normalized `MailEnvelope`. They do not validate the complete raw address-header grammar or recover fragments that an upstream parser may already have omitted. The supported scope remains session-only plain-text composition: durable drafts/outbox, attachments, HTML-only quotation, SMTPUTF8, display-name input, alias discovery and live provider interoperability are outside this increment.

See the [behavior guide](../../roadmaps/mail/recipients-and-reply-all.md).

## Reconciliation

The initial read-only inventory captured 16 branches and the latest 100 updated PR records, with no open PR. The previously unseen `integrate/recent-pptx` commit `5c3f9d7fd4531dfac7c0e49fba1827c39e17caf6` was incorporated before mail implementation. Its later tab-positioning commit `a5ae56c8e3e7f950c37ef491b17b5c32fcd0e13d` is also retained.

Nine older divergent branches were independently checked using their complete changed-path mode/type/blob identities against equivalent commits already in main. They require no replay of older content. The initial upstream main `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` was already an ancestor. The original proof and inventories remain in `initial-reconciliation.json` and `remote-inventory.json`.

Subsequent inventories captured concurrently published branches and PR #218:

- Zotero history through `6626ad430a54122e4514cc2870fdcee18760682f`: paginated tag discovery, source citation occurrence navigation, the explicit rich-text style correction, tests, and incoming qualification records.
- VBA history through `435bc212401db13efa56483ac852e4bc25bcc5d2`: one-dimensional local dynamic arrays, ReDim/Preserve, Erase, Option Base, integration tests and smoke tooling, plus additional mail host regressions.
- PPTX history through `a5ae56c8e3e7f950c37ef491b17b5c32fcd0e13d`: slide backgrounds, crops, rich text, PDF/interlaced PNG work and tab positioning.

During the final pre-merge check, PR #218 had merged into remote main `88513f04cfbdec210340f2d70a674cf3f23e31c0`. That exact main commit and the latest Zotero tip were reconciled before merging #217. `premerge-main-reconciliation.json` records this later observation and verifies that product Dart source still matches the qualified checkpoint.

These histories are retained as merge parents/ancestors, not reconstructed patch-only replacements. `final-reconciliation.json` records the exact captured heads and their ancestry or previously recomputed equivalence proof.

The last observed VBA merge `435bc212401db13efa56483ac852e4bc25bcc5d2` also carried the compatible `updateMasterBackground` helper and additional dark-theme assertions. The helper/controller delegation and all assertions are retained. The same 15-case slide source cohort passed again against the updated model; prior source evidence remains in `slide-source-harness-before-vba435/`. `final-vba-reconciliation.json` records this final captured branch set. This adds no controller/widget execution claim.

### Compatibility decisions

Imported rich runs retain their source snapshot. Derived runs apply exposed font, color, alignment and direction edits, and a text replacement invalidates stale imported runs. The incoming native 16-point fallback, paragraph defaults, text-origin hit testing and explicit `b="0"` / `i="0"` behavior are retained.

Slide paper distinguishes inherited and explicitly authored colors. Assigning a nonempty color creates an explicit override; clearing it restores inheritance. An inherited resolved color retains its primary-master snapshot so a secondary imported master is preserved until the primary master changes. Copies retain that metadata. Repeated controller edits use the compatible `updateMasterBackground` helper; direct engine master edits follow the same contract, and PDF uses the resolver.

Inherited neutral white follows the display theme only when color adaptation is enabled. Explicit white remains white. Disabling adaptation retains resolved white paper as well as authored ink. Incoming and local regression groups are retained, including reset-to-inheritance and opt-out assertions. Those renderer/controller/PDF widget tests remain unexecuted here.

The only dependency-manifest addition comes from incoming PPTX work: `image: ^4.5.0` in the engine. The root lock already had image 4.13.1; its classification changed from transitive to direct main without version changes. No mail core/MIME/store/transport/UI or bundled vendor source changed, and previous reply-threading evidence is untouched.

## Evidence and execution boundaries

| Evidence directory/file | Contents |
| --- | --- |
| `mail-source-harness/` | AST-based whole-test omissions, original/adapted tests, exact diffs, final log, source hashes, 19 dependency-version differences and previous run records |
| `recipient-parser/` | Independent parser harness, result JSON and stderr log |
| `runtime/` | Runtime provenance, workspace setup failures, separate pubspec/lock and 54-case core log |
| `slide-source-harness/` | Import-only adaptations, 45-file graph hashes, 15-case log and reproduction script |
| `zotero-source-harness/` | Import-only adaptation, 27-case log, unchanged client/model/test hashes and excluded occurrence/widget dependencies |
| `final-mail-audit/` | Independent review of recipients, canonical MIME, provider envelopes, retries and protected-source preservation |
| `final-reconciliation-audit/` | Incoming multi-parent merge review, exact resolution deltas and adaptation opt-out rationale |
| `vba-offline-boundary/` | Real import graph and missing compatible dependencies preventing VBA execution |
| `final-static-checks/` | Formatter command, output, file list and source hashes |
| `source-binding.json` | Final product checkpoint and verification that qualified source hashes still match |
| `publication-checkpoints.json` | Remote checkpoint commits, parents and exact trees preceding the final evidence commit |

The full workspace `flutter pub get` stopped when the executor reported that network approval was cancelled before a decision was returned. A subsequent strict offline `--enforce-lockfile` resolution failed because `flutter_lints` was absent. The separate cached graph resolved normally; it differs from the repository lock in 19 packages, including crypto 3.0.7 versus 3.0.8 and analyzer 10.1.0 versus 13.3.0. No fabricated workspace package config or dependency stub was used. No network retry or alternate mirror bypassed the boundary.

Complete MIME serialization/round trips, native/EWS/Gmail/Graph host suites, Flutter composer/layout widgets, full PDF/interlaced-PNG suites, VBA dynamic arrays, Zotero occurrence/navigation widgets, the complete locked workspace and the full analyzer remain unexecuted by this continuation. VBA and Word occurrence graphs reach missing `characters`; PDF reaches missing `image`; enough_mail also needs uncached packages; cached archive does not satisfy the required legacy parser version. Live accounts were not used.

The [incoming Zotero integration report](../zotero-workflow-20261119/README.md) and its raw validation directory are preserved separately. Its author records broader runs, including 219 mail cases and six selected transport cases against an earlier captured mail tree. Those logs are useful provenance, but they are not presented as execution of this continuation's later draft extraction, host regressions and final reconciled renderer source.

## Pending full-environment commands

Run these with the repository's pinned Flutter runtime and a successfully resolved locked workspace. They are recorded for follow-up, not asserted to have run here.

```sh
flutter pub get --enforce-lockfile
cd packages/quds_office_editor/example
flutter test test/studio_mail_recipients_test.dart test/studio_mail_reply_test.dart test/studio_mail_threading_test.dart test/studio_mail_compose_test.dart test/studio_mail_session_test.dart test/studio_mail_test.dart test/studio_mail_ews_test.dart test/studio_mail_cloud_test.dart
```

From `packages/quds_office_editor`, run the dark-slide, slide-render-fidelity and Zotero tag/occurrence/navigation suites, plus the two layout/download suites still pending in the previous reply-threading receipt. From `packages/quds_office_engine`, run the slide import/text/render/explicit-style, PDF/interlaced-PNG, VBA dynamic-array and Zotero suites. Run the mail MIME and transport package suites, then required workspace analysis with the same locked dependency resolution. Live interoperability remains a distinct check.

## Publication

PR #217 publishes `work/mail-continuation-20261119` to `main`. Each remote checkpoint used the expected previous branch head, no force update, and a Git tree identical to its local candidate. Source and test work was published incrementally before this evidence commit. The final post-merge PR receipt records the published candidate, resulting main commit, merge parents, exact tree comparison and retained branch head.
