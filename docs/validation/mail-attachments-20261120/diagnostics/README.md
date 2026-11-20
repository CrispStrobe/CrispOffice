# Preserved diagnostics, excluded from acceptance totals

The final acceptance report identifies replacement runs explicitly. Earlier
records remain available and are never added to the passing-case total.

| Record | What happened | Accepted replacement |
| --- | --- | --- |
| `preliminary-mail-packages.tar.xz` | All selected cases passed, but the receipt rejected an incoming PPTX merge's concurrent lockfile classification change. `concurrency-cause.json` identifies that commit. | Stable locked mail rerun in `../mail-packages` |
| `../incoming-office/slide-background` | Incoming background tests exposed eight ownership/serialization regressions; repair development is retained through the final 42-pass stage. | Complete 224-case engine rendering cohort |
| `development.tar.xz`: engine preliminary assertions | Two new PDF tests assumed literal number/operator formatting; the saved independent PDF stream had the correct border. Assertions were corrected and the cropped case strengthened to check both restores. | Complete 224-case engine rendering rerun |
| `development.tar.xz`: whole-package analyzer | Nine old lints in the unrelated distribution-consumer tool plus one new evaluator brace lint. | New lint fixed; explicit changed-target/selected-scope strict analysis passed. Old findings remain disclosed. |
| `development.tar.xz`: Arabic capture attempts | An animation prevented `pumpAndSettle`; another capture used Ahem chrome. | Finite-pump, real-font capture in `../arabic-composer` |

Every archive has an adjacent index with each file's byte length and SHA-256,
plus the archive's own digest. The original spaCy strict receipt is retained in
`../incoming-office/spacy-package`; its separately accepted controlled receipt
allows only the precisely named optional macOS-library case to remain not run.
