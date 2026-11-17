# Independent ODF consumers — final second-wave source

**Accepted source:** `48b6998bb47ffdf43e95025229dc5a5eab09ee9a`, tree `741494bdebf9afa7c2a341f745f85f07a799cad1`.

**Result:** all **31 fixtures pass**, including all **124 XML parts** checked against the official OASIS OpenDocument 1.3 RelaxNG schemas. LibreOfficeDev 26.8.0.0.alpha0 independently opens every generated ODT and exports PDF plus DOCX; Poppler supplies PDF page geometry and word coordinates. This is an actual independent-consumer run, not a second parse by the writer's own library.

## Preserved and added acceptance

The baseline manifest is byte-identical to the accepted `ec5ecbff` manifest. All 29 generated fixture specifications must equal that baseline after JSON parsing, including the original 26 subset. The original `check_fixture` AST is unchanged; `check_recovery_fixtures.py` and `check_current_fixtures.py` are byte-identical. The [independent extension review](wave2-runner/independent-review.json) verifies these invariants and the new expected geometry.

Two fixtures extend that scope:

| Fixture | Independently observed result |
| --- | --- |
| Two columns with an explicit column break | Authored 24 pt gap reopens as 480 twips. Left text renders at 36.1 pt; both right-column paragraphs render at 212.1 pt, within 0.4 pt of the authored 36/212 pt positions. The following plain paragraph remains below the right-column heading on the same page. |
| Keep-state isolation in both orders | Reopened DOCX resolves document defaults, style inheritance and direct paragraph properties. True/false/true and false/true/false states remain distinct. |

The kept paragraphs in these fixtures are one line. This establishes preservation of the DOCX keep-lines property, not multi-line pagination behavior. The actual final rasters were visually inspected and are included in `previews/`; [visual review](visual-review.json) records the scope.

The final run binds **399 source/harness inputs and 10,420 runtime inputs**, with unchanged before/after maps, source HEAD and fixture hashes. Exact tool versions, commands, results, page coordinates and resolved paragraph properties are in [final receipt](final-receipt.json).

## Reproduce and inspect evidence

The [archive index](consumer-evidence-index.json) lists every member's exact size and SHA-256. All archive members were fully read back and verified. `consumer-evidence.tar.xz` includes:

- Both source-distinct 31-fixture runs: earlier writer-fix `4a4101c1` and accepted formatted source `48b6998b`. Their counts are not added together.
- The exact generators, original and extended checkers, immutable expected manifests, official schema files and independent review.
- Generated ODTs, converted DOCX/PDF/text/bounding boxes, rasters, raw command logs and full before/after input maps.

After extracting while preserving paths, provide the frozen Git checkout and its resolved workspace from the canonical qualification harness:

```sh
python wave2-runner/verify_consumers.py \
  --output /absolute/new-consumer-run \
  --schemas /absolute/extracted/schemas \
  --dart /absolute/flutter-sdk/bin/cache/dart-sdk/bin/dart \
  --repo /absolute/resolved-workspace \
  --source-repo /absolute/frozen-git-checkout \
  --expected-head 48b6998bb47ffdf43e95025229dc5a5eab09ee9a
```

The output directory must not exist. Use the recorded locked dependencies and runtime versions; library symlinks must resolve to the frozen source. The runner checks both schema hashes before use and rejects altered original expectations. It does not use GitHub CI endpoints.
