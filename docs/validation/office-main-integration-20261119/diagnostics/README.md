# Preserved unsuccessful attempts

The initial Mail gate at `056414ba` failed because of incoming test defects.
The complete run and hashes are retained in `mail-first-attempt.tar.xz`; it is
not counted as accepted qualification.

The source-bound transport red archive proves the original malformed FETCH and
FormatException compatibility defects before repair: three of six raw-parser
cases failed, and the existing oversized-literal case failed. No input changed
during those reproductions.

`root-shape-only.jsonl` is a development diagnostic from the intermediate,
uncommitted root-shape repair. Its seventh case exposed a repeated empty list
that the generic iterator had normalized away. It is not a source-bound
qualification receipt. The final strict iterator rejects repeated attached
lists, including empty ones, while default legacy iteration stays unchanged.

`transport-analysis-initial.log` records one new-test style diagnostic, fixed
by using a method tearoff. Final qualification will rerun strict analysis.
