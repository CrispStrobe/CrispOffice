# Incoming Quds Office reference audit

Status: **PASS** at `0201b549d0dc3f601c50e36255d557034cb01699`.

The captured fork main is `5ad4461a93c835479bf67acab63623944b3900a3`. The audit covers 25 fork branch heads, 263 fork PR heads, 4 upstream branch heads and 4 upstream PR heads. There are 0 uncovered references.

Every historical substitute was recalculated from immutable Git objects: 13 complete-tree identities and one exact 37-path ODT continuation. Modes, types and object IDs agree for each changed path, and each accepted substitute is an ancestor of the reviewed target. Historical branches need no replay.

## Recent work

The baseline `0201b549d0dc3f601c50e36255d557034cb01699` contains completed cached-Mail checkpoint `c7e721b7703766491fd4459b69de30bf68d9010d` and Word paragraph-spacing PR #263, including its latest source-preservation correction. The captured main already contained the earlier spacing implementation checkpoint `5ad4461a93c835479bf67acab63623944b3900a3`. PR #262 is merged; its body retained stale draft qualification text, while its committed final acceptance seal reports PASS. PR #263 was open and draft at intake and explicitly withheld final acceptance. The new continuation must qualify that incoming Word code as well as its own changes.

## Reproduce

From the repository root, replay the committed captures without network:

```sh
python docs/validation/word-vba-paragraph-controls-20261120/verify_intake.py --repo . --target 0201b549d0dc3f601c50e36255d557034cb01699
```

To collect a new inventory, add `--capture` and choose the intended immutable target. The script reads remote refs only; it does not fetch, push, merge, or query CI. Unknown or unincorporated references are recorded and cause exit 1. This is a source-inclusion audit; incoming test evidence is not a new test run.
