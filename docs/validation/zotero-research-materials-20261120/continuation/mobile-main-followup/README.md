# Final mobile-main preservation

Source **`65ea4c3095ff5d821c57d4dced0ba50bdd9387e7`**, tree
`f1500a15749ec6cbb8556d852f22bcedf70afd83`, preserves main
`88905c56547fa91206acbc306616c3ad10f9d77b` (PR #232) and the completed
Arabic/evidence checkpoint `2e4516e4924e0e13de0736f67aa8beb010a9023b`.
The ordinary two-parent merge is conflict-free. All 88 incoming paths,
including 18 Dart paths, match main exactly; the [source review](incoming-review.json)
records their Git identities and SHA-256 hashes.

Final formatter source **`2b74f1091c8fb968f1cb53c803bdd2a0b395159d`**, tree
`b8d5a8eb9b5bf9a3a93f8756b4708e5fea16b9f4`, changes only the formatting of
`studio_native_paths_test.dart`: one `expect` call wraps and gains a trailing
comma. Its assertions and application implementation remain unchanged. This
single test-file exception follows the exact-main postimage comparison above.

The incoming work adds iOS/Android packaging and build helpers, Studio private
data/startup/native-host paths, native proofing loaders, a mobile spaCy analysis
catalog and an integration-test harness. Zotero engine/editor, Word, slides,
Mail and browser host/transport implementations remain unchanged. All twelve
Arabic follow-up test files remain byte-identical, but twenty of that phase's
recorded source inputs change, so its 633-case result retains source `f69e774f`.
The earlier 2,386-case, 356-case and 3,201-case populations likewise retain their
original source and input attribution and are not presented as final-source
reruns. Counts from these overlapping selections must not be added together.

## Focused host acceptance

The fixed-configuration [host runs](host-tests.json) pass **51 cases in five
files** at `65ea4c30`: 36 Studio cases across native paths, authenticated spaCy
development fixtures, Zotero shortcuts and Zotero citing transport, plus 15
spaCy distribution cases. Both commands finish with zero failures, skips,
errors, duplicate case identities or unfinished test events, and their
recorded configuration and tracked product/lock inputs remain unchanged.
This bounded supplement does not claim a new complete runtime/dependency
payload inventory. The earlier preliminary runs are not added to its count.
An independent [raw-event recount](event-recount.json) confirms the 51 distinct
cases, exact stream hashes, completed event identities and unchanged recorded
configuration.

The original [static check](static.json) passes strict analysis of all 18
changed Dart paths, but formatting flags `studio_native_paths_test.dart`.
That failed receipt is preserved. The formatter-only source above addresses
this exact diagnostic. The [formatter comparison](formatter-equivalence.json)
preserves quoted literals and comments, and accounts explicitly for the one
added trailing argument comma. Its [two-case rerun](formatter-followup/events.jsonl)
passes at `2b74f109`, and [strict analysis and formatting](formatter-followup/static.json)
pass all **18 changed Dart targets**. The two repeated cases remain included
once in the 51-case total; no test name, assertion or acceptance guard is
changed to obtain that result.

## Native evidence boundary

The incoming [author report](../../../native-proofing-mobile-20261120/README.md)
contains sanitized iOS Simulator and Android emulator gate JSON and native
build receipts. These are preserved as upstream evidence, not fresh native
execution in this Linux environment. They do not contain complete raw
application-event streams or a fingerprint of the final combined source.

The [Arabic receipt limitation](native-receipt-limitation.json) is material:
the author receipt pins CrispEmbed `0ed76631` / PR #255 and the old adapter,
whereas the final builder pins `3bab3248` and the loader requires ABI 3 /
adapter 2. The sanitized gate lines identify Arabic word-analysis output but
not the loaded Arabic library or ABI. They therefore do not qualify the
current Arabic native source. Older ABI 2 Arabic libraries must be rebuilt for
the current ABI. No iOS/Android, native Arabic model, Wasm or physical-device
acceptance is inferred from the fresh host tests.

The earlier blocked Chrome launch still records zero application cases at
`a45ee3bf`; it is not a new attempt at this source. The incoming Arabic web
model-removal buffer concern, native Word's 20/24-page threshold result and
existing shape limitation are unchanged by this mobile delta.

## Dependency boundary

Studio adds the SDK `integration_test` development dependency. The lock adds
three SDK packages and `sync_http 0.3.1` / `webdriver 3.2.0`; every existing
lock entry remains unchanged. The first direct spaCy test command implicitly
resolved/downloaded the previously unavailable exact `webdriver 3.2.0` and
refreshed local metadata. This unintended [resolver transition](implicit-resolution.json)
is recorded; its raw streams and earlier intended no-refresh scope remain
under `preliminary/` and are not final acceptance evidence.

The subsequent authorized [offline enforced-lockfile verification](dependency-scope.json)
passes with the original lock unchanged: 157 resolved packages and 128 hosted
versions/cached archive-hash markers match. Unpacked payload files for the
five added packages are independently hashed; retained archive bytes are not
claimed to have been independently rehashed. The resulting configuration is
frozen before the final explicit no-resolution host runs and static checks.
Earlier qualification keeps its own older configuration and source bindings.
Resolving the integration dependencies does not execute the mobile harness
or confer native acceptance. No GitHub Actions, workflow-run, check or
commit-status endpoint is queried or awaited.
