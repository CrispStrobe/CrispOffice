# Late incoming integration plan

Read-only audit after root confirmed the final origin fetch completed. Observed cutoff: **2026-11-16T15:23:50.196577+00:00**. Current text work at audit: `03a28d585869eec70b5d06eae4005a68151e9c34`. Preserve any later validation-receipt checkpoint and use its descendant as the integration base.

The full pinned inventory is `late-incoming-refs-audit.json`. It contains **138 refs**: 62 origin branch heads, 68 origin PR heads, four upstream branch heads, and four upstream PR heads. The text work branch and symbolic HEAD are excluded. 129 refs already descend into the text work; nine refs, representing seven distinct commits, remain incoming. Six maximal commits cover all seven; vendor metadata includes vendor writer. No CI Actions were queried or awaited.

## Pinned merge inputs

| Input | Commit | Treatment |
|---|---|---|
| Proofing continuation | `6b5c114df362b88851d7bf4642faf496c098b0ca` | Normal merge; retain input ownership and navigation fixes plus validation evidence |
| Current main | `a042466eaf8cc83db2b7b6a5123d67a1b58f9304` | Normal merge; adds current underline/input/unit work and ODS writer/metadata |
| Latest dialog continuation | `537600886555c3b7156aabd932e1f241a47c23a5` | Normal merge; four commits beyond shared main ancestor `ea88b25`, including direction chord and final underline clearance |
| ODS writer feature / PR 67 | `0ee0a8320875248adac9718cae2e67875b6b932c` | Equivalent writer delta already included through main; record ancestry after verifying retained files |
| ODS metadata feature / PR 68 | `82215309dc64ef8c473fec3c4892cf0c9884bc91` | Entire tree identical to current main; record ancestry |
| ODS metadata vendor | `1808f38493d1cf2fddc1761d146432ceaaea70aa` | Equivalent writer + metadata deltas; also includes vendor writer `e14a55b50af4b6870ed1044284f74c36b5f194d9` |

## Evidence for duplicate ODS histories

The writer delta is identical by `git patch-id --stable` in `ea88b25..0ee0a832`, `e14a55b5^..e14a55b5`, and `3398d53^..3398d53`: **`4e965791f0a14c8c5a83ba392076bd76cb01ad7a`**.

The metadata delta is identical in `82215309^..82215309`, `1808f384^..1808f384`, and `a042466^..a042466`: **`6deecbe7b48412dfe90a611e962efd3cb0eabaa6`**.

The complete tree of `a042466` and `82215309` is **`0e238f72cbff29f30eb842c7dafb809bb4be6342`**. The final writer blob is identical at main, feature metadata, and vendor metadata: **`630c391f4c6ca6cbd61503595ef7b662a7f414ff`**.

These checks justify retaining main's implementation while recording the three duplicate heads as merge parents. A naive normal merge of the first feature writer can produce add/add conflicts because its 513-line writer and main's later 705-line writer were introduced on separately squashed histories. Do not downgrade the writer to the earlier version.

## Recommended sequence, executed by root in its isolated integration worktree

Start from the latest saved text-work checkpoint descending from the audited base. Apply each substantive merge separately, inspect and resolve it, and save a checkpoint before the next one:

```sh
git merge --no-ff --no-commit 6b5c114df362b88851d7bf4642faf496c098b0ca
# Resolve the adaptations below and commit the reviewed merge.
git merge --no-ff --no-commit a042466eaf8cc83db2b7b6a5123d67a1b58f9304
# Resolve the adaptations below and commit the reviewed merge.
git merge --no-ff --no-commit 537600886555c3b7156aabd932e1f241a47c23a5
# Resolve the adaptations below and commit the reviewed merge.
```

After the main implementation and duplicate evidence are verified, the explicit ancestry-only merges are:

```sh
git merge --no-ff -s ours -m 'Record equivalent ODS writer feature history [skip ci]' 0ee0a8320875248adac9718cae2e67875b6b932c
git merge --no-ff -s ours -m 'Record equivalent ODS metadata feature history [skip ci]' 82215309dc64ef8c473fec3c4892cf0c9884bc91
git merge --no-ff -s ours -m 'Record equivalent ODS writer vendor histories [skip ci]' 1808f38493d1cf2fddc1761d146432ceaaea70aa
```

This is a proposed sequence only; this audit did not mutate Git, create a worktree, merge, commit, or push.

## Required adaptations

1. **Keep the text work's shaping and Unicode source changes.** Main/dialog touch `paint_run_text.dart`, `render_word_canvas.dart`, and `line_breaker.dart`. Preserve run/actual-line measurements, scalar fallback restoration, semantic control-span extraction, full bidi-level grouping, source-grapheme guards, and disposal.
2. **Carry ordinary-space ownership into the new repair path.** Incoming `_canBreakAfter` disallows a break before U+0020; incoming `_constrainBreaks` excludes those boundary starts. The new `_isClusterBoundary`/`_refineBreaks` emergency candidates must obey the same policy. Preserve the distinction for tabs, NBSP, and explicit hard-break leading spaces.
3. **Combine underline paint with disposal.** Add incoming `foreground` support and `paintUnderlined`; dispatch within the current decorated painter's `try/finally`, so it still disposes exactly once. Retain latest dialog clearance **0.04 × font size**, superseding main's 0.10. Keep the native font underline metrics and the new normal/Retina tests.
4. **Combine all input ownership changes in `office_editors.dart`.** Preserve proofing's `_inputRouteWasCurrent`, stable named `_allowsWordInput` guard, and post-frame `_onFocus` reattachment. Retain current proofing `onSpellCheckRequested` binding/unbinding and controller-transfer `_onFocus`, alongside incoming controller/modal guards, guarded autofocus, and `OfficeDirectionKeyChord` state/reset/release handling.
5. **Keep proofing navigation state cleanup.** Revealing a body issue now clears equation, picture/crop, frame, and table editing state before selecting document text. The companion navigation tests are substantive.
6. **Keep the stronger input focus tests.** Proofing independently fixes the same viewing/selecting-mode mismatch already corrected here, and additionally proves the platform IME reconnects after an unfocused covering dialog closes without an explicit attach. Retain both aspects.
7. **Treat formatting-only deltas as such.** Proofing changes to German rules, theme strings, hyphenation caret tests, and several renderer hunks are formatting-only; do not replace working text-rendering logic wholesale to resolve them.

The incoming ODS writer uses the existing pure-Dart ZIP/XML/model code. No dependency-manifest change was found in main's delta.

## Qualification and final receipt

Verify the merged source with the focused engine line-break, measured-run, contained-wrap, and new ODS writer tests. Re-run editor run metrics/source-span/shaped-wrap tests plus incoming underline, physical-unit, input ownership/focus, direction-chord, proofing navigation, and hyphen caret tests. Prior source-bound receipts remain historical evidence; do not describe them as validating the merged head.

After the final integration commit, check **every pinned inventory SHA** with `git merge-base --is-ancestor SHA FINAL_HEAD`. The expected result is 138/138. Record the final integration head, cutoff, counts, equivalent-history decisions, local test receipts, and any remaining limitations. Do not wait for GitHub Actions.
