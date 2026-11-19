# Final bounded capture and retained intentions

The final capture ran from **12:23:58 to 12:24:05 UTC on 19 November 2026**.
Its original fork/upstream advertisements, open-PR metadata, and capture hashes
are preserved in `remote-refs-final-cutoff.tsv`,
`upstream-refs-final-cutoff.tsv`, `open-prs-final-cutoff.json`, and
`final-cutoff-capture.json`. Only PR #191 was open. Captured main was
`666e9a2ea46f7aeaaa1d01b60aabea0c2fe6f0fd`; the captured continuation was
`fee5e98481d1f21528756668a9072b8cb3d5efcb`.

The [final cutoff audit](final-cutoff-audit.json) binds published integration
`1c415fef97a9552191e83a6e5f8a071a6fe06710`, tree
`6ccb9d6ca611a5fe6ef7a4e75d86edc1ed5c6fee`. All **468 actual references** are
accounted for: **440 ancestors, 28 historical equivalents, zero unaccounted
references**. All 14 historical equivalence proofs were freshly recomputed.
The counts are 233 fork branches, 194 fork PR heads, 17 fork tags, four upstream
branches, four upstream PR heads, and 16 upstream tags. Generated PR merge
advertisements remain explicit exclusions; actual PR heads remain required.

## Newly captured tips

| Captured source | Exact head | Retention |
| --- | --- | --- |
| `codex/office-final-union-20261119` | `0f16754c278aa83cc79d5777e5b45d3f739e5469` | Ancestor of published integration |
| `codex/office-finish-20261119`, PR #194 head | `e77d0dab229bc0ea4c195a164771d3c44809f0f0` | Ancestor of published integration |
| `codex/office-resume-main-20261119` | `0601d2790c7636bc02d53430f6e99f471e8ac83e` | Ancestor of published integration |
| `integrate/codex-drafts-20261119` | `5a910773995be2244d27d5d2ad8341481bb6eed1` | Ancestor of published integration |
| PR #192 head | `22ffa8bdcc11e5e10eb37f2326f832066f609a08` | Retained through the later resume-main ancestry |

No further remote advertisement was used for this cutoff. Subsequent checks of
main's expected head belong to merge consistency, not an expanded capture.

## Source and regression review

The comparison baseline was canonical continuation
`f76b30ae8128369a86beccdda07c67dc91578d45`. Incoming histories and their original
evidence remain retained as ancestors. Overlapping implementations and tests
were reviewed by intention before choosing the combined source.

- **Word language controls:** the resume-main engine implementation and its two
  language/inheritance test files already match the canonical implementation.
  Its controller chiefly changes the default of `activeLanguageOnly` to false.
  The canonical API keeps active-slot preservation as its default and exposes
  explicit both-slot editing with false. Its mixed-fragment, selected-fragment,
  inactive-metadata, history and DOCX-save regressions preserve both behaviors.
  Older controller/cascade variants would remove that synthesis and were not
  substituted for it.
- **Mail ownership and message actions:** existing canonical tests retain late
  discovery/send/read completion handling, captured connection credentials,
  reader disposal, stale composers, exact-byte loading and UID-bound mark-read
  behavior. The additional selectable-folder regression covers a nonselectable
  INBOX falling back to Archive. Saved-message picker/read success, failure and
  dismissal intentions are already represented in the canonical saved suite.
  The app continues to send with `appendToSent: false`; its body-only reply helper
  explicitly declines HTML-only quotation. Incoming alternative UI policies do
  not silently change those documented boundaries.
- **Compact review status:** the canonical thirteen existing cases retain their
  multilingual, scaling, hit-testing and review-action assertions. The unique
  incoming checking-state regression is added at a compact viewport while a
  provider remains pending; the Arabic partial-status tooltip additionally
  retains its provider detail.
- **New nonconflicting product behavior:** the combined source keeps SMTP abort
  rejection of the pending command, the bounded body-only presentation field,
  and consistent numeric morphology feature text on VM and JavaScript targets.
  Their distinct regression intentions remain in the affected ordinary suites.

These are source-reconciliation decisions. The reference audit proves captured
history inclusion, and focused development runs remain development evidence.
Only the later frozen aggregate and independent acceptance audit establish
qualification of their exact recorded source. No GitHub Actions were queried or
awaited in this capture or review.

## Replay

```sh
python audit_refs.py --repo /path/to/quds_office_suite \
  --head 1c415fef97a9552191e83a6e5f8a071a6fe06710 \
  --refs remote-refs-final-cutoff.tsv \
  --upstream-refs upstream-refs-final-cutoff.tsv \
  --expected-total 468 --output /tmp/office-final-cutoff-audit.json
```
