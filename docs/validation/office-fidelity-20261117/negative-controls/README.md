# Historical negative controls

These separately attributed probes use their retained historical test versions
against source before each repair. They are not part of the final passing-test
total and do not claim to execute every later test on old source.

| Probe | Executed cases | Assertion failures | Passing controls |
| --- | ---: | ---: | ---: |
| PDF text-string decoding | 59 | 41 | 18 |
| Conditional expression/PDF rendering | 4 | 4 | 0 |
| ODF text/structure | 22 | 21 | 1 |
| Native conditional DXF edits | 15 | 15 | 0 |

Exact test versions, logs and available source/runtime records are retained in
the archives, bound by `manifest.json`. The ODF archive also contains two earlier
test-construction compilation attempts; those are excluded from the 22-case run.
The conditional rendering archive contains the original four tests and JSON event
stream from integrated source `b9dd6bab`; later API/raster/formula cases are not
part of that old-source probe. The PDF and ODF source snapshots identify the
unchanged production files. The DXF probe predates the separate rename-save undo
integration repair. No potentially hanging extreme numeric negative probe was
executed against the old looping implementation.

The first combined 108-file run is preserved separately under
`../attempts/pre-numeric-and-save-undo-repair/`, including its three real editor
errors. Final qualification uses the repaired source and fresh full cohorts.

`rename-save-undo.tar.gz` retains the focused five-case integration probe: three
runtime errors before repair and two positive stale-edit controls. The numeric
archive contains source review and 200 passing scoped repaired-source tests,
including 31 numeric guard regressions. It is deliberately not an old-source
negative execution; potentially unbounded expressions were not run on the old
implementation. Neither archive contributes additional tests to final totals.
