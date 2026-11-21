# Late native Word style reconciliation

The incoming checkpoint `cf12544d` supplied an independent native implementation
and `word_paragraph_style_assignment_test.dart`. The unified implementation keeps
the reviewed detached paragraph-style operation and incorporates the incoming
behavioral checks and missing preservation guards.

## Unchanged intake run

The incoming test file was first executed unchanged, with the cyclic-block case excluded by the runner until the pre-traversal
ownership guard existed. The single-line name filter also omitted the invalid
selector case whose display name contains a newline; the final run includes
both omitted cases without a name filter.
The run completed in 3.1 seconds: **45 passed and 13 failed**. Every engine-library
source hash stayed unchanged during that run. An earlier unsupported runner flag
exited before executing any tests; its original diagnostics remain in
`invocation-error/`.

The meaningful missing behavior identified by this run was:

- Retaining the selected live inline/run identity after a successful style edit.
- Rejecting style-level `pStyle` references and invalid native scalar,
  measurement and font-size values before publication.
- Rejecting duplicate original paragraph-property packets.
- Counting generated TOC paragraphs as ownership references, so a run shared
  between ordinary content and generated content is refused.

The source review also required a cyclic/duplicate block guard before field
traversal, explicit generated-TOC target refusal, original `pStyle` metadata
ownership, and the incoming `rStyle` depth/namespace reader guard. Those changes
belong to the unified native implementation; they are qualified by the final
reconciled run.

## Explicit contract reconciliations

All incoming fixture XML is retained. Six test registrations change their
expectation to the documented, narrower operation contract:

| Incoming case | Accepted unified expectation |
| --- | --- |
| Foreign/nested style references, native prefix `w` | Import retains the true `Base`/`Emphasis` identities; assignment refuses atomically; three save/reopen cycles preserve the original identities and opaque metadata. |
| Same fixture, native prefix `word` | Same boundary. The ordinary reader's existing effective color is preserved; the sparse native color declaration is independently checked as exactly `AABBCC` through every reopen. This does not claim the unrelated alias-color projection is repaired. |
| Shared properties on distinct runs | Assignment refuses without replacing either shared reference or changing either run's original values. |
| Active direct numbering with unchanged modeled IDs | Assignment refuses and preserves the original style reference, numbering ID/level, label and sparse source. Active numbering remains unsupported, because style-linked numbering can change beyond those modeled IDs. |
| A live run shared by two ordinary paragraphs | Atomic refusal remains required; its documented exception class is `UnsupportedError`. |
| A live run shared by body content and a generated TOC | Atomic refusal remains required; its exception class is `UnsupportedError`. |

Repeated/cyclic block ownership still requires `StateError`. Generated-TOC
targets still require `UnsupportedError`. The incoming successful identity,
table-context, stale-spacing, outline-level, built-in-name and invalid-source
fixtures retain their behavioral expectations.

The `rStyle` import assertions are retained and backed by the incoming narrow
reader correction. Unsupported restyling is not used to conceal an incorrect
character-style identity at import.

## Evidence scope

`word-final/` remains the preserved **3,654-test** qualification before this late
reconciliation. The final `word-final-reconciled/` cohort includes the independent
incoming native suite and reruns the complete selected Word cohort because the
shared reader changed. Its receipt, exact per-file counts and source hashes
supersede the earlier accepted count for publication.

## Final reconciled result

The complete coherent-source run passed **3,716 test registrations across 73
files**, with zero failures or skips and exit code 0. All 509 captured input
hashes were identical before and after execution. The independent incoming
native suite contributed 60 passing cases, including the previously excluded
cyclic ownership case. No test was excluded in this final run.
