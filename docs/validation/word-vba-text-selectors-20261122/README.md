# Word VBA text functions and named selectors

## Completed result

This continuation adds ordinary Variant-returning `Left`, `Right` and expression
`Mid`, named Word document/story selectors, and typed `Sections` / `Paragraphs`
collection aliases. The qualified source checkpoint is
`5949a298444cec06632a28858c75670541a914a9`. Production and configuration bytes
have not changed since the combined implementation checkpoint `0cf0127`; later
changes add verification, clarify documentation, and correct an obsolete test
expectation about discarded XML metadata.

**9,482 substantive cases across 193 suites are accepted, with no remaining
failures, skips or unresolved cases.** Reruns replace their original suite
results; loaders and lifecycle hooks are excluded. This is a local qualification
of the documented subset, not a VBA compatibility percentage or installed
Microsoft Word differential result. See [qualification.json](qualification.json)
for the machine-readable totals and source hash.

## Intake and incremental preservation

Work began from remote main `4621326a5a452da475f219353c298d0f9b12470e`.
The [initial intake](intake.json) checked 40 fork branches, the 100 most recent
pull requests and all four upstream branches. The work branch first advanced
to `5d79e934c5400594410bb6dfcb347d279fe0c335`, preserving the then-active Mail
and Zotero histories before the macro changes.

Later intake incorporated the native Word RTL correction `d68df6d6`, published
Mail and Zotero work, and the new Mail navigation planning head. The
[final intake](final-intake.json) records **43 actual fork branch heads, four
upstream heads and 100 recent PR heads**, all ancestors of the integrated work.
There were no open PRs in that capture. Git's symbolic `origin/HEAD` is not
counted as another branch. Original parents were retained; no history was
squashed or force-pushed.

Remote work is saved on `codex/word-vba-text-selectors-20261122`. Checkpoints
include `091be781` (intake), `9d4f48e9` (implementation), `f275fd7d` (example and
documentation), `bc15ae55` (cyclic cell-alias regression), `0cf0127` (latest native
changes), `fb6fb6c1` (publication/planning histories), and `5949a298` (RTL
interaction and metadata-preservation verification). The initial combined
source also remains on `codex/word-vba-array-data-20261122`.

Branch updates use expected-head checks and non-forced writes. Final main
publication preserves the qualified branch and the observed main as merge
parents. **No GitHub Actions queue, workflow or status was queried or awaited.**

## Behavior added

- Ordinary `Left`, `Right` and expression `Mid` work across the Word, Excel and
  PowerPoint source adapters. String text uses the existing bounded UTF-16
  slicing rules; Empty text becomes an empty string and Null text propagates.
  Supplied index/count arguments remain exact bounded integers and are checked
  before Null propagation. Numeric/Boolean text coercion stays explicit.
- Required, case-insensitive named `Index:=` arguments work on supported Word
  `Paragraphs`, `Sections`, `Headers` and `Footers` selectors, including explicit
  `.Item` calls. Receiver and argument expressions execute once in source order.
- `Dim ... As Sections` and `Dim ... As Paragraphs`, `Set` aliases, and required
  `ByVal` helper parameters retain document, story and cell-paragraph identity.
  Local helper rebinding does not retarget the caller's alias.
- Static cell ownership follows the whole alias graph, including rooted cycles
  and collection aliases. An inactive cell-only `ListFormat` operation is
  refused consistently; generic and mixed selectors keep their runtime guards.

String-returning `$` forms and standalone `Mid` assignment keep their existing
contracts. The change does not add live text/property reads, collection
`Count`/enumeration, object arrays, optional object parameters, `ByRef` object
parameters, arbitrary COM calls or execution of embedded VBA projects.

The committed [BAS example](../../../packages/quds_office_engine/example/macros/word_text_selectors.bas)
extracts an invoice label, prefixes selected body/header/footer paragraphs,
bolds one header, and handles a Null reference explicitly. Its five native
operations are checked against independently written expectations.

## Accepted local gates

| Gate | Suites | Accepted cases |
|---|---:|---:|
| VBA and native macro regression selection | 157 | 8,317 |
| New named-selector / RTL interaction | 1 | 2 |
| Incoming Mail core, store, transport and UI | 18 | 559 |
| Studio integration | 3 | 276 |
| Office editor, Zotero and ruler | 6 | 42 |
| Native Word, Zotero, directional IO and styles | 8 | 286 |
| **Total** | **193** | **9,482** |

The final broad macro execution passed 8,314 cases and found three failures in
one old measurement helper. That helper required a foreign indentation attribute
to be discarded. The incoming serializer intentionally preserves it while still
replacing the owned indentation geometry. Model values and exact native numeric
properties already passed. The helper now positively requires preservation; its
**entire 11-case integration suite** passed again, including CLI and MCP paths.
Those 11 results replace the same 11 cases from the broad run. No production
code was changed to resolve these assertions.

The earlier broad attempt also exposed an older cyclic-alias test that allowed
an inactive cell list operation. Its expectation was corrected to the stronger
static guard, and it passed in the subsequent broad execution. Both original
runs and their failures remain in the evidence; they are not described as
passing runs.

The two new RTL interaction cases start from authored OOXML with asymmetric
physical indents, noncentered alignment, inherited styles and foreign metadata.
They exercise body and header selections, named arguments and `ByVal` rebinding,
then check independent native XML and three saved generations.

Strict analysis and formatting passed for the 15 changed macro Dart files and
the nine incoming Dart files; the native serial directory was also analyzed.
The runtime is pinned Flutter **3.47.8**, Dart **3.13.7**, Node **24.22.3**, with the
repository lockfile unchanged. The official SDK archive and 204 dependency
archives were verified during setup; runtime and native SQLite identities are
recorded separately.

## Portable execution

The versioned `word_text_selectors_v1.json` corpus contains **64 independently
authored cases: 34 complete native plans and 30 positioned diagnostics**. The
canonical JSON is consumed by the existing portable runner. Dart VM and
optimized JavaScript/Node receipts are byte-identical:

`b5f4a9b74b19022f1ce065469f905a28f26984cc9be46f598eb0665e2b8e7de1`

The actual new BAS also passes both targets. Parsed receipts match exactly;
their raw JSON differs only in 72 integral spacing values rendered as `0.0`/`8.0`
on the VM and `0`/`8` on JavaScript. No normalization was introduced to manufacture
byte equality. Its DOCM fixture verifies selected edits, 35 untouched body/story
paragraphs, detached validation, repeated save/reopen, native recording/replay,
rollback, MCP, CLI and policy boundaries. Dedicated substring tests also cover
DOCX and DOCM transactions.

The corrected existing measurement BAS passes both targets with byte-identical
706-byte output:

`579f31da832e2f32d78e8b7bd54a27dc4060abc73bb5584855c552892a040154`

Portable executions and the separately run 65-case corpus/schema suite overlap
the regression coverage and are **not added again** to the 9,482-case count.

## Evidence and reproduction

- [Word local checks](evidence/word-local-checks.tar.xz): raw logs, exact commands,
  accepted case identities, source manifests, portable outputs, review records,
  verification scripts and retained earlier attempts.
- [Incoming local checks](evidence/incoming-local-checks.tar.xz): per-package
  gates, static checks, source snapshots and previous attempts.
- [Artifact index](evidence/artifacts.json): archive hashes and every retained
  member's size/hash.
- [Runtime provenance](evidence/runtime-provenance.json): SDK, dependency,
  lockfile, native SQLite and explicit test-runner identities.

Commands retain the actual workspace paths used during execution. For another
checkout, adjust the root/runtime paths in the included scripts and use the
pinned SDK with the same lockfile. The explicit compiled `package:test` runner
was used because the ordinary test launcher stalled in this environment.
Reproducible compiled JS/dill products are omitted from the archives; their
commands and hashes are retained.

`word/final-source-continuity.json` verifies that later test-helper corrections
do not change any retained suite's local Dart import/export/part dependencies.
It explicitly records the two changed verification files in broader snapshots;
it does not assert that every overcaptured test file remained byte-identical.
All production and configuration bytes remain unchanged. The corrected suite
and the new RTL test have their own final-source receipts.

Embedded VBA and signature payloads are preserved as opaque package parts;
this is neither VBA execution nor validation of a document's signature. Installed
Word execution, general COM interoperability and complete typography/pagination
parity are outside this qualification. Incoming Zotero converter evidence keeps
its separately documented native-editability and ODT limitations.

## Primary contracts

- [Left](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/left-function)
- [Right](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/right-function)
- [Mid](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/mid-function)
- [Variant and String function results](https://learn.microsoft.com/en-us/office/vba/language/concepts/getting-started/returning-strings-from-functions)
- [Paragraphs.Item](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphs.item)
- [Sections.Item](https://learn.microsoft.com/en-us/office/vba/api/word.sections.item)
- [HeadersFooters.Item](https://learn.microsoft.com/en-us/office/vba/api/word.headersfooters.item)
