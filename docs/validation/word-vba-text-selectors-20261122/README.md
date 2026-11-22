# Word source text and named selectors

## Intake and preservation

Work began from remote main `4621326a5a452da475f219353c298d0f9b12470e`.
The [intake audit](intake.json) checked 40 fork branches, the 100 most recent
pull requests and all four upstream branches. All captured PR heads, upstream
heads and previous Word branches were already ancestors of main. Two active
Mail/Zotero branches formed one combined history. The work branch first
fast-forwarded to `5d79e934c5400594410bb6dfcb347d279fe0c335`, preserving both
heads and their original parents before macro implementation.

That incoming source still has an independently recorded DOCX direction/indent
interoperability issue in its in-progress Zotero qualification. This Word
continuation will record its own executed scope and reconcile subsequent fixes;
it does not treat inherited or in-progress validation as a fresh passing result.

Remote work is checkpointed on `codex/word-vba-text-selectors-20261122` using
expected-head, non-forced updates. The initial integrated source is also
retained on `codex/word-vba-array-data-20261122`. GitHub Actions are not a gate;
no workflow queue is queried or awaited.

## Scope

- Ordinary `Left`, `Right` and expression `Mid` functions across all three VBA
  adapters, with Variant String/Empty/Null behavior and the existing exact-index,
  UTF-16, work and native publication boundaries. String-returning `$` variants
  and standalone Mid assignment retain their established contracts.
- Required case-insensitive named `Index` arguments on supported Word
  `Paragraphs`, `Sections`, `Headers` and `Footers` selectors and their `Item`
  methods. Existing body, independent story and cell-paragraph selectors keep
  their native admission rules and retained aliases.

The implementation, examples, independent conformance cases and local test
receipts are added in subsequent checkpoints. No installed Microsoft Office
differential qualification or full VBA compatibility is claimed.

## Primary contracts

- [Left](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/left-function)
- [Right](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/right-function)
- [Mid](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/mid-function)
- [Variant and String function results](https://learn.microsoft.com/en-us/office/vba/language/concepts/getting-started/returning-strings-from-functions)
- [Paragraphs.Item](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphs.item)
- [Sections.Item](https://learn.microsoft.com/en-us/office/vba/api/word.sections.item)
- [HeadersFooters.Item](https://learn.microsoft.com/en-us/office/vba/api/word.headersfooters.item)
