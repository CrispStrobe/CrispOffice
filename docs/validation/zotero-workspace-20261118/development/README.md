# Focused development checks — excluded from final totals

The [archive](focused-checks.tar.xz) preserves all original development events,
commands, stderr and available source bindings. Its
[index](focused-checks.index.json) records every file hash.

The [widget development summary](library-details-development-summary.json)
records the initial 18-pass/one-error run, the genuine 8-pixel large-text layout
failure, its targeted one-case retest, the subsequent 21-case pass, and the
additional one-case details/copy check. The first failed run had no captured
source hashes; that limitation is explicit. Later runs have unchanged source
bindings. The one-case selected-layout retest overlaps the 21-case run.

The archive also contains `narrow-wrap-fix/`: all five exact cases that failed
in the initial complete editor run passed after increasing the narrow tab
allowances. These checks overlap the final complete 257-case editor cohort.

None of these development results, or the 31-test runtime setup smoke, is added
to the final 720-test total.
