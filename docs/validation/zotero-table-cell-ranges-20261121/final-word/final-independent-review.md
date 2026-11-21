# Independent acceptance of the final Word delta

**Accepted for `4034c7e7d384ed1f947d1702b4c2cf5231b7d3d1`**, tree
`1e21f3c97cc7e37ff55f8302f668e05276fe9d6d`. This bounded review extends the
previous combined-source acceptance; it makes no claim about a later remote
head. The [machine-readable review](final-independent-review.json) records
the exact source, impact and runtime identities.

## Source and dependency delta

Both `5289b90a` and incoming main `9f23cbd2` are actual ancestors. Exactly two
recorded source paths differ from the previously accepted combination:
`word_header_footer_guard.dart` and its unselected header/footer macro test.
Both files exactly preserve incoming main's bytes. The Mail native Close fix
and the added saved-Mail regression preserve their previously qualified bytes.

The reviewer read the guard diff and the incremental replay program. Its
replay reproduces the recorded impact JSON exactly, using the unchanged,
previously reviewed dependency helper. All 119 selected test files remain
unchanged; 117 selected dependency closures are unchanged. Only table-grid
addressing and bookmark fidelity reach the changed guard. The guard's imports
are unchanged, selected closures have no unresolved or unsupported local
directives, and the changed production source adds no dynamic loader. The
previously reviewed loader sources and both Node suite closures are unchanged.
No new full-tree AST analysis was required for this two-path delta.

## Raw execution and source binding

Independent reconstruction of the raw JSON stream confirms **39 successful
cases in two suites**: 22 table-grid cases and 17 bookmark cases. The exact
normal-runner command selects those original files without name filters.
The process exits 0, supplies one successful terminal event, and completes
every started case once. There are no failures, skips, runtime error events,
captured runtime exception messages or stderr bytes. Only two successful
loading events are excluded.

All 39 suite/name identities exactly match both the original qualification
and the 151-case intermediate execution. They add **zero new distinct cases**.
No Studio, Mail or Node rerun is asserted by this final cohort.

All **2,994 recorded inputs** match the frozen commit, current bytes, Git blob
identities and modes. All before/after maps agree, with canonical SHA-256
`9ce3a43c7b6708a6f2be62843fc4eb037208a01ec8e2e5d24075eaf1bfb19c42`.
Of those inputs, 2,992 remain identical to the preceding checkpoint; only the
two named paths change, with no additions or removals. The 33 recorded runtime
files remain unchanged from the preceding execution and throughout this one.

The original qualification archive remains unchanged. The earlier accepted
source captures, explicit metadata exclusion, dependency-scope limits and
runtime-environment limits remain applicable. This review launches no tests
and changes no product file or Git ref. It does not claim installed
Word/LibreOffice/Zotero plugin acceptance, live Mail account acceptance or a
fresh full 119-suite execution.
