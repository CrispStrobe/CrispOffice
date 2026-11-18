# Incoming Office review — 18 November 2026

Use current main `482e0817` as the source base. PR #152 already lands the corrected Office union, and PR #151 adds calendar-relative conditions. Later main commits retain German grammar completion, complete-phrase formatting, and spreadsheet icon spacing. The older recovery trees would discard those changes if used wholesale.

The current snapshot has **190 live branch heads and 152 PR heads**. It began with 188 branches; the two new branches point to already captured commits. The only open PR is separately owned native spaCy #139. The live main tip and all original branch tips stayed fixed during this review. Three remote-tracking names left by the initial upstream clone are not branches in CrispStrobe's live inventory.

## Isolated Office repair from the spaCy branch

Commit `2bfac9b2` contains a relevant two-constructor fix in `sml_conditional_format.dart` and eight pure Dart calendar controls. The main resolver blob exactly equals that commit's parent resolver. Its UTC cell dates were compared to local midnight boundaries, producing offset-dependent endpoints and DST arithmetic errors. Creating UTC civil dates from the injected clock's own year, month, and day preserves the intended calendar date.

Bring in the resolver and calendar test, and retain the original calendar evidence with its historical source attribution. Run the controls under UTC, Europe/Berlin and America/Los_Angeles on the new frozen source. The current review is static; it does not claim a fresh runtime pass.

## Historical evidence that the squash did not retain

- `6d97fedc`: seven missing union evidence files, plus corrected handoff documents. The rejected `3d487008` fixture attempted to place a body-only frame in a header/footer visual list. The corrected source was `5c66e629`; both valid frame controls remain. The saved retained33 archive belongs to the rejected source and remains historical.
- `8ad80eb2`: the 19-file `docs/validation/office-resume-20261118/` directory, including retained33/current7/boundary5 consumer archives. Their source is `c08fdc70`, which uses an alternate frame implementation and old spaCy integration. Preserve the directory without adopting its product tree.

See [remote-review.json](remote-review.json) for exact SHAs, source identities, paths, reasoning and remaining gates. No GitHub Actions, workflow, check or status endpoint was queried or awaited.

