# Publication frontier and integration cutoff

The accepted product source is `be93371b680d8e39365a6b356fb727bda81dbed1`.
Publication checkpoint `71053bf61521e093903d55cba890ef4beee039e1` also contains
the latest observed remote main, `4a4ea1f0d8c990cc74ce8f7233545a8a9dc0887c`,
with the accepted product, test and acceptance-harness bytes unchanged.

Two inventories have deliberately different scopes:

| Inventory | Captured refs | Own refs excluded | External refs | Ancestors | Historical equivalents | Reviewed post-cutoff refs | Unaccounted |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Integration cutoff | 234 | 2 | 232 | 209 | 23 | 0 | 0 |
| Fresh publication observation | 236 | 2 | 234 | 206 | 23 | 5 | 0 |

The [cutoff reconciliation](reconciliation-final.json) covers 18 fork branches,
212 PR heads and four upstream branches. The original cutoff capture and its
earlier proof remain preserved separately. The
[publication inventory](publication-ref-inventory.json) covers 19 fork branches,
213 PR heads and four upstream branches. All 14 inherited equivalence proofs
were freshly recomputed for each inventory.

A final prepublication review at `906b8bc90ea352f03dfdab5f9bc50f3aafc359de` observed GUI head `cacae8569814e4cb81f58d358734d31431f102be`. The [GUI refresh proof](publication-gui-refresh.json) verifies complete tree identities down to the changed directories: only GUI validation documentation/evidence and the mail-store changelog changed from `fedabc7079db1c402cadcd9ef15296244979132e`. Runtime, test and dependency trees are identical. PR #211 remains an open draft; its authored 921-case receipt adds no accepted counts here. The prior observation is preserved separately.

The fresh inventory has fewer ancestor references because the GUI and VBA
branch/PR heads advanced after the cutoff. Their previously integrated heads
remain ancestors. Those four later references and the new bundled-NER branch
are explicitly reviewed post-cutoff work; they are not represented as merged
or as part of this milestone's accepted test counts.

## Latest main is incorporated without changing accepted product source

PR [#213](https://github.com/CrispStrobe/quds_office_suite/pull/213) is **closed
and merged**, with head `0e03878b028ec25ed3d84a790633433eafc3bede`. Its merge
commit is `4a4ea1f0d8c990cc74ce8f7233545a8a9dc0887c`; the reported merge time
is `2026-11-19T19:15:39Z`. That app-gaps implementation was already in the
accepted source before this main merge.

The complete 14,883-file remote-main tree was independently reconstructed from
the prior main and all 43 advertised changed path/blob entries, producing its
exact tree `58e10de36f44e4926467fb45c4dbf47a8128c02d`. Thirty-seven changed
paths were already byte-identical to the accepted source. The remaining source
differences retain our corrected NER status, the combined GUI documentation,
and pinned-formatter output for the explicit native gate.

The only incoming additions needed at publication were three validation
documents under `docs/validation/language-downloads-20261119/`:

- `README.md`
- `acceptance.json`
- `native-en-GB.json`

The actual publication checkpoint's complete Git diff contains those three
documents plus 37 local validation/evidence changes. There are no changes to
non-validation paths or the accepted harnesses. The
[main-integration proof](publication-main-proof.json) records the actual
parents, complete changed-path inventory, matching document blobs and unchanged
product/test/harness result. Incoming native qualification reports are retained
as their authors' evidence; their counts are not added to our fresh Linux
acceptance.

## Independently reviewed work after the cutoff

| Stream | Exact observed head | Observed status | Additional work outside this accepted source |
| --- | --- | --- | --- |
| GUI / PR [#211](https://github.com/CrispStrobe/quds_office_suite/pull/211) | `cacae8569814e4cb81f58d358734d31431f102be` | Open draft | Earlier dark-appearance assertions plus a documentation/evidence-only follow-up |
| VBA / PR [#210](https://github.com/CrispStrobe/quds_office_suite/pull/210) | `3abffb94dcf33a2766a4579d296d0ef09c9e35cd` | Open draft | Settings/downloads dark-dialog and document-preservation regression in `studio_layout_theme_test.dart`, with separate publication evidence |
| `fix/spacy-bundled-ner-20261119` | `dc93a176f8efc98feff9c25565fb036175793a54` | Independent branch at observation | A model-specific bundled inventory label, explanatory text and focused assertions |

Both newer GUI/VBA heads incorporate the main language-download behavior and
themed dialog routing already present in the accepted source. Their later
regressions exercise that existing behavior. The bundled-NER branch's shared
verification and model-only byte counts are also already implemented by our
`7e13a48c` correction and its five focused cases; the remaining label/test
changes are independent. No missing mail-resume prerequisite or correctness
gap was identified in these later changes.

[publication-frontier.json](publication-frontier.json) and
[publication-pr-metadata.json](publication-pr-metadata.json) retain exact draft
states, update times, reviewed unintegrated paths, API source URLs and decisions.
The reconciliation replay classifies post-cutoff work only when both its ref
name and SHA match that explicit review. It does not treat a later unknown head
as reviewed automatically.

## Independent reference-image and static checks

The two Linux reference images were independently inspected and compared to
their prior masters. Each differs at exactly 1,290 pixels, all within the top
or left 24-pixel ruler strips. Block placeholders are replaced by readable
numeric graduations; the selection, paragraph text, table and document body
are pixel-identical. The
[reference-image review](independent-review/ruler-reference-review.json)
records hashes and bounds. The `macOS`/`windows` labels name Flutter target
simulations running on Linux, not installed native-platform qualification.

The unchanged static runner passed three commands in final incoming window v3:
shell syntax, Python AST/in-memory compilation, and licence manifest/source-pin
verification. Twenty-five source inputs and 61 execution dependencies remained
unchanged; 13 notices and nine Studio mirrors matched their recorded hashes.
The raw licence source retained its originating Git blob and every byte.
Earlier static window v2 evidence is superseded and contributes no accepted
counts. These static checks contribute zero behavioral tests and do not build,
sign, load or execute a macOS app or model.

Remote advertisements and API metadata are separate observations, not an atomic
GitHub snapshot. Publication still checks the expected remote main. No Actions
status, workflow or job endpoint was queried or awaited.
