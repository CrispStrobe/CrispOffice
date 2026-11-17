# Editor integration replay

The initial 13-file editor cohort passed 188 tests and failed one because an
incoming fixture expected `de.grammar.verb-case` for the sentence
`Sie hat ein roten Mantel.`. The retained stricter direct-object rule correctly
emits `de.grammar.verb-object-case`; the fixture now selects that rule while
preserving all correction, clean recheck, undo and redo assertions. The focused
German integration file passes after this expectation repair.

The Studio smoke test still required the AOT action removed by PR #129. It now
verifies the Spelling action remains available and the retired action is absent.
Both Studio smoke tests pass. Production UI is unchanged by these fixture fixes.

Original failures and follow-up logs are retained. The final full editor replay
is recorded separately after the last Office source repair. No GitHub Actions
were awaited.
