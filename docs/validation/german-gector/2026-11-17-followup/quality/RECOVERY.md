# Quality replay recovery record

The baseline observations in `recovered-baseline-observations.json` were reconstructed from retained conversation and tool output after the execution workspace was lost. **The original raw baseline archive was not remotely saved before the loss and is unavailable.** This record preserves observed counts and identities; it is not a replacement raw report and does not claim a fresh successful audit.

## What was observed before the loss

All six baseline panels completed on integrated commit `db453d88d82700e9b8c96b0d9c00c1061e6ac18d`, with two native threads and one check per case. There were 377 case rows and no recorded operational failures. The baseline auditor reconstructed the results after the optional-null metadata fix described below.

| Panel | Errors | Combined exact corrections | Declared-clean changes / flags |
|---|---:|---:|---:|
| Original | 18 | 18 | 0 / 0 |
| Development | 32 | 23 | 0 / 0 |
| Syntax | 20 | 15 | 0 / 0 |
| Context | 23 | 21 | 0 / 0 |
| Completion | 8 | 8 | 3 / 3 |
| Holdout | 46 | 45 | 0 / 0 |

These are reused synthetic regression panels, not a representative German accuracy estimate. Durations were diagnostic only because other functional document work was running concurrently.

The three declared-clean changes were `Ihr hat viel Zeit geholfen.` → `Ihr habt viel Zeit geholfen.`, `Ihr hat Geld gefehlt.` → `Ihr habt Geld gefehlt.`, and `Das Buch, dass ich heute lese, ist gut.` → `Das Buch, das ich heute lese, ist gut.`. The last is a pre-existing label inconsistency: the frozen corpus marks a sentence with the wrong relative-clause spelling as clean. All gold and labels were left unchanged.

## Exact comparator correction

The prior auditor included optional `pair_id: null` in declared metadata. The runner's existing `QualityCase.toJson` contract omits null metadata, causing the independent audit to reject 12 development rows. The recovered comparator changes only the metadata comprehension:

```python
# Before
**{k:raw[k]for k in ('category','pair_id')if k in raw}
# After
**{k:raw[k]for k in ('category','pair_id')if k in raw and raw[k]is not None}
```

Before workspace loss, all six panels passed reconstruction with this correction, and a deliberate changed nonnull pair ID was still rejected. The corpus, provider findings and projections were not modified. The original failure/control files were in the lost raw archive; these observations are recovered from the retained tool transcript.

## Missing evidence and unfinished work

The lost archive was reported as `baseline-replay-evidence.tar.xz`, 70,428 bytes, SHA-256 `f219d533d4a6777afb260a61f106ec25f234425a10ccb716cfa43725a334dc9b`, with 26 members. Those values are historical observations. No archive with that identity is supplied by this recovery.

The final replay never started. Root paused it when document consumers identified header-ordering and frame-anchor defects. The intermediate final AOT remains an observed historical build, and its conservative dependency seal became obsolete after the Office source fixes. A replacement `build-final-2`, baseline-versus-final comparison and native performance sweep were not completed.

Use the recorded exact model and native-library identities to recover and rerun if possible. Do not substitute binaries, infer final quality from baseline results, or describe the missing raw evidence as available. No GitHub CI was started or awaited.
