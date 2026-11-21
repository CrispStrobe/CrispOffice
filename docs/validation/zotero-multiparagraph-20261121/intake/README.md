# Initial intake and reconciliation

Baseline main: `bf761552d22dcd1eb8cbb0ab00ddab6507e1d572`. Incoming continuation: `bbccae1bdead10951e2d7a23b33cf14c55382e02` (`codex/word-vba-unit-conversions-20261120`). The merge preserves both histories.

The frozen Git advertisements cover **329 refs**: 41 fork branches, 280 fork PR heads, four upstream branches and four upstream PR heads. The initial audit independently proves **304 ancestors and 24 exact equivalents**, leaving only the unit-conversion continuation to integrate. `snapshot.json` and the original TSV advertisements preserve the complete inventory; `audit.json` records the 15 replayed historical proof definitions and every disposition.

## Resolution

The continuation overlaps newer main Mail work. All 28 conflicts were reviewed and resolved in favor of the current implementation and source-specific documentation. Main retains durable flag journaling, reader identity/cancellation, cumulative image budgets, the existing runner/coordinator APIs and all Word picture identity regressions. No Zotero/Word product source, workflow, dependency or golden fixture changes in this merge.

One missing compatibility feature is restored: `MailReaderPresentation.remoteImageUris` aliases `remoteImageUrls`. Both expose the same immutable list; providing contradictory URI order, length or values throws before a usable presentation is returned. The incoming regression is retained. Existing image projection and admission algorithms remain intact.

All **30 new historical evidence files** are byte-identical to the incoming branch. The two incoming Zotero narratives retain distinct `incoming-pr277-*` names, so current qualification claims are not replaced by older claims. No previous test result is relabeled as acceptance for this merge.

## Regression identity

| Incoming suite | Retained main suite | Verification |
| --- | --- | --- |
| `quds_mail_core/test/bulk_flag_runner_test.dart` | `quds_mail_core/test/bulk_flags_test.dart` | Exact same Git blob |
| `quds_mail_core/test/bulk_flags_test.dart` | `quds_mail_core/test/bulk_flags_coordinator_test.dart` | Exact same Git blob |
| `example/test/studio_mail_remote_image_loader_test.dart` | `example/test/studio_mail_remote_images_incoming_test.dart` | Existing API adaptation; main retains stronger blocked-resource/remaining-URI assertions |

Identical or already-adapted suites are not registered twice. The original incoming source remains available through the retained parent and unchanged historical evidence. The current explicit `loadInto(reader)` API avoids colliding with `load(urls)`, which has a different argument and return type. `resolution.json` records exact blobs, every conflict decision and evidence retention.

## Reproduce

From the repository root, with the fetched immutable objects available:

```sh
python3 docs/validation/zotero-multiparagraph-20261121/intake/audit_intake.py \
  --head HEAD \
  --snapshot docs/validation/zotero-multiparagraph-20261121/intake/snapshot.json \
  --output /path/to/replayed-intake.json
```

After the merge, all 329 captured refs must be ancestors or verified equivalents. GitHub Actions, check/status endpoints and workflows were neither queried nor awaited. Local regression results are recorded separately after execution.
