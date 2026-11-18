# Document review continuation checkpoint — 18 November 2026

## Saved work

This branch starts at main `690e6ac8a1f7d8f5c8d4bea69d989a6728f3b27e` and first reconciles these captured incoming heads:

- Mail reader and durable-store continuation: `a39f786d5707af308b1f9899c3461a72e62b4b68`.
- Zotero note insertion/navigation: `5a68c2fdec18f723dd97e3435cd5e33a315a5006`.
- Thesaurus qualification and compact review fixes: `7530f83a5503987dbee5b9678af56116ca98621f`.

Integration checkpoints were saved as `8b53b55d61711975475ba05a52e468aadc390fe1`, `35b3052f988c232f461df4168b3e619b1c129210`, and `840809bbe23f95815a5ddcd2a7ee76c250b9fb8c`. GitHub tree identities matched the corresponding local merge trees before publication. The only final incoming conflict kept the precise oversized-reply assertion. PR #165 was closed after verifying its head is already included in main; #172 remains open.

The bounded incoming audit observed 211 fork branches, 172 PR heads and four upstream branches: 387 references / 252 distinct heads. It found 359 references through ancestry and 28 references corresponding to 14 reverified historical equivalents, with no unaccounted captured head. The audit rerun against remote `840809bb` passed. See [the recovered audit summary](recovery/audit-summary.json) for exact scope and limitations.

## Feature implementation in this checkpoint

- Notes uses source-bound red, blue and amber wavy underlines for spelling, grammar and style findings.
- Notes shows checking/coverage state, the live-checking toggle, explicit checking, correction buttons, ignore/dictionary controls and previous/next finding navigation.
- F7 checks and Alt+F7 / Alt+Shift+F7 move through the active note's findings.
- Notes' Review changes button opens the persistent Changes pane.
- Footnote/endnote review navigation maps native source offsets to the real Notes field, including the hidden reference separator and multi-paragraph text.
- Notes proofing actions retain exact source ownership and reject stale/protected/composing contexts. A narrowly scoped alias preserves current suggestion identity across committing already-applied Notes typing into undo history.
- Header/footer navigation and editing distinguish default, first-page and even-page stories. Caret, selection, IME, language/proofing controls and painting use the actual rendered source.
- Header editing background is painted below text; selection highlighting does not leak into a different variant.
- A stored alternate story not present on a laid-out page remains pane-only. Navigation does not change the document's page settings.

## Validation status — NOT ACCEPTED YET

The official Flutter 3.47.8 / Dart 3.13.7 archive and executables were verified. The 176 downloaded hosted package archives passed hash checks, 130 workspace packages resolved, and offline lock enforcement passed with the incoming Mail lock. An existing runtime smoke suite passed two actual cases. This proves runtime readiness, not feature acceptance.

The new 17-case header suite reached 16 passing cases, with no product assertion failure, before the final rendering fixture stalled on a proofing future inside Flutter fake time. The saved test contains the intended `tester.runAsync` fix, but the complete suite has not been rerun. Notes-pane analysis passed at an intermediate source state. The new Notes controller/widget behavior and final combined source still need complete targeted regression and strict-analysis checks. Incoming Mail-store and newer Zotero behavior also need validation on this integrated source.

Do not describe this checkpoint as a passing full suite, a validated release, or qualification of native/web application builds, physical IME/keyboard behavior, optional provider services, or live Mail/Zotero accounts.

## Why publication used recovery

The host filesystem became full. All filesystem-backed execution and patch tools then failed during sandbox initialization (`bwrap: Can't create file .../.git: No space left on device`). The desktop runtime was unavailable. A request to clear only generated Flutter test caches outside the failed sandbox was rejected by the configured policy because sandbox escalation is disabled.

The connected GitHub API remained available. Source was reconstructed from the exact saved `840809bb` files plus the successful editing operations already recorded in the task. Header and Notes controller edits were applied with unique literal-match assertions; their independent reconstructed results were compared with the collaborators' recovery blobs before combination. This preserves the intended source, but is **not** a byte-for-byte readback of the inaccessible local checkout and does not establish formatting or a fresh passing test result.

Recovery edit data and the actual source are both saved in this branch. Local raw test logs and full generated audit/runtime manifests could not all be read after the failure. Recovered summaries explicitly distinguish observed outcomes from inaccessible raw artifacts.

## Resume without GitHub Actions

1. Use a workspace with enough free disk for the SDK, dependencies and Flutter test artifacts.
2. Fetch this branch and read its current head before adding work; other project branches may have advanced beyond the recorded cutoff.
3. Restore the recorded SDK/dependency pins. The portable recovery installer is a reconstruction and must be verified before treating it as accepted tooling; a complete official SDK is also suitable.
4. Format and strictly analyze the changed Dart files, then run the complete header suite and Notes mapping, typing/correction/Undo, stale-action, composition, protection, keyboard, narrow/RTL and Changes-pane tests.
5. Run affected existing review/Zotero/Notes/Studio regressions and incoming Mail-store tests. Inspect the actual rendered header and Notes screenshots.
6. Preserve exact source/runtime hashes, actual completed test counts and raw logs. Save further checkpoints with non-forced expected-head updates.

No GitHub Actions status was queried or awaited. Commits use `[skip ci]`.
