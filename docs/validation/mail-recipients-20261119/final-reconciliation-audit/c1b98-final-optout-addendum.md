# Final c1b98 resolution: adaptation opt-out

The completed local merge `cfbb5d78c3a5adf72f5b459ede496a8044995614` has parents `4731ffbd4636d4e7eafe4db9de42c7ef11a8cdf3` and `c1b98f12f802863fb602e9919ead524891bfbcc6`. Its complete tracked content delta from the first parent is exactly the slide renderer and dark-slide test. Model, controller, PDF exporter, changelogs, and all mail files remain unchanged.

## Opt-out rationale

`OfficeTheme.adaptDocumentColors` documents low-contrast ink adaptation with an opt-out for exact on-screen colour reproduction. `resolveDocumentColor` returns authored ink immediately when the flag is false, and the slide renderer also disables its ink-adaptation background lookup. Both dark and high-contrast presets normally enable the flag.

The final paper rule requires **both** adaptation enabled **and** inherited background ownership before mapping resolved white to theme paper. This retains c1b98's opt-out without importing its regression that also recolored explicit white. When adaptation is disabled, resolved inherited white stays white and authored black ink remains legible. Explicit white remains white for either flag value. Missing/unparseable background RGB retains the existing theme-paper fallback. This is an implementation inference consistent with the reproduction contract; the flag's documentation directly describes ink, not a separate paper algorithm.

## Preserved regressions

The existing master-paper test now includes the four-line reset from an explicit fill to inherited background and the next master-color update. The inherited-white test checks opt-out white paper for both dark and high-contrast themes. The earlier stronger explicit-white test remains in place.

This addendum supersedes only the initial audit's renderer recommendation by retaining the incoming opt-out as well as the current ownership distinction. No model, controller, PDF, engine slide source, mail source, dependency, or archive-schema change was introduced by this merge resolution. The widget assertions have not been executed in this reviewer session; no new runtime acceptance is claimed.
