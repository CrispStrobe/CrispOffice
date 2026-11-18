# English and German thesaurus

Status: scoped; implementation and language-pack qualification are pending.
Scope recorded: 18 November 2026.

This is a documentation-only plan. This change adds no thesaurus corpus,
compiled language pack, executable provider, model, or user-visible feature.
The integration assessment uses the CrispStrobe fork at
[`f383c826205e321eda3ed3bdbcd584e9a2d4da14`](https://github.com/CrispStrobe/quds_office_suite/tree/f383c826205e321eda3ed3bdbcd584e9a2d4da14);
earlier findings about the much smaller public upstream are not the fork's
implementation baseline.

## Goal and license decision

Provide a useful offline thesaurus for English and German selected words and
phrases, with alternatives grouped by meaning, available usage labels, and an
explicit, source-safe replacement that can be undone.

Prefer MIT, Apache, BSD, CC0 and similarly permissive inputs. Noncommercial
restrictions are unacceptable. Evaluate implementation code, lexical data,
morphology, ranking inputs, model outputs and transitive inputs separately.

| Role | Planned source | License treatment and decision |
| --- | --- | --- |
| English default | Open English WordNet (OEWN), regular lexical edition | CC BY 4.0 for OEWN developments plus the underlying Princeton WordNet terms. Attribute both projects. The current target is the 2025 lexical edition; the exact artifact, revision and digest must be pinned in TH1. |
| English alternative | Princeton WordNet | Custom permissive WordNet license. Prefer this alternative if minimizing data-license conditions outweighs continuing lexical maintenance. Do not combine it with OEWN as a second default corpus. |
| German default | OpenThesaurus | Select its offered CC BY-SA 4.0 option. Preserve attribution and the applicable ShareAlike obligations for distributed adapted data. The exact export snapshot remains a TH1 decision. |
| Initial German noun lookup support | Existing qualified Unicode Inflection-derived resource in this fork | Reuse its Unicode-3.0 notices, manifest and finite coverage; do not relicense or imply complete German morphology. |

Independent implementation code follows the repository's existing MIT
licensing. Language packs retain their source-specific terms. The
[planned licensing and notices record](licensing-and-notices.md) is the
source of truth for the future packs; it is not a statement that those packs
are already distributed.

## Existing fork capabilities to reuse

Read [PROOFING.md](../../PROOFING.md) and the
[proofing adapter reuse map](../proofing-adapter-reuse.md) before implementation.

- `OfficeProofingRequest` and the current language utilities already provide
  source-oriented contracts and EN/DE locale normalization. Effective Word
  language inherits from run to paragraph to document; UI language is separate.
- `WordProofingSession` already captures immutable paragraph sources, checks
  document/block identity, revisions and configuration, handles protected
  content, and rejects stale results.
- `WordEditorController.applyProofingSuggestion` already uses a validated
  command with rich-inline, revision and caret/selection snapshots for
  correction and undo/redo. Factor or reuse the backend-independent replacement
  behavior; retain the existing proofing caller's validation.
- That API currently accepts an actual `WordProofingIssue` belonging to the
  proofing session. A thesaurus result must have its own validated target and
  candidate identity. Do not fabricate a spelling/grammar finding to bypass
  session membership.
- `GermanNounMorphology.shared` already supplies bounded noun readings and
  lemmas. Reuse its ambiguity and unresolved-reading behavior. See the
  [morphology documentation](../../../packages/quds_office_engine/third_party/proofing/MORPHOLOGY.md).
- Existing
  [proofing data manifests and notices](../../../packages/quds_office_engine/third_party/proofing/README.md)
  provide the pattern for immutable inputs, original license files and
  reproducible generation.
- Optional spaCy analysis can later contribute qualified lemma/POS information
  when the host has explicitly installed and enabled it. The
  [native spaCy work](../native-spacy/README.md) owns its runtime/model contract;
  basic thesaurus lookup must work independently.

A missing general thesaurus does not mean that language inheritance,
grapheme-safe source handling, morphology or reliable correction needs to be
rebuilt from scratch.

## Initial product scope

- Explicit lookup from a selected word/phrase or the word at the caret.
- English and German offline packs, loaded on demand.
- Alternatives grouped by source meaning; preserve available part of speech,
  definitions, examples, regional/register/archaic labels and source identity.
- A clear language override using the existing locale conventions.
- Explicit replacement, one undo unit, and the current source/protection/IME
  guards. Lookup itself does not change the document or add proofing errors.
- Distinct no-entry, unsupported-language, missing-pack and failed-pack states.
- An accessible source/attribution view.
- Common inflected-form lookup within the qualified English and German
  resources. State the coverage of each resource instead of claiming complete
  morphology.

The first editable target is a contiguous, modeled, single-paragraph text
range. Use the fork's story membership and source-capture machinery wherever
the current editor supports the target. A readable story does not imply that
its canvas can navigate to or edit every position. Mixed-language selections,
multi-paragraph selections, generated fields, locked content and unsupported
targets must produce a clear state.

## Proposed architecture

New names in this section are proposed contracts, not existing exported APIs.

| Component | Responsibility | Boundary |
| --- | --- | --- |
| Build-time importers | Read pinned OEWN/OpenThesaurus exports; validate records; compile an index and notices | No network lookup from document editing; never infer data rights from the importer license |
| Optional pure-Dart lookup module | Typed queries, sense-grouped results, pack loading, bounded caches and lemma candidates | No Flutter or `dart:ui`; no native/model dependency required for basic lookup |
| Editor target/replacement integration | Capture source identity and exact ranges; validate selected candidate; apply the shared guarded command | Preserve existing proofing guards, rich content, tracked changes and undo/redo |
| Host action and panel | Review/context-menu entry, language choice, meanings, labels, replace action and attribution | Keep the document surfaces custom RenderBox; follow existing host chrome conventions |

Use explicit typed query, sense, candidate, result and pack-manifest types.
Represent lookup outcomes independently from proofing issue severity. Keep
pack I/O injectable so document-only engine users do not acquire Flutter
assets or filesystem dependencies.

The data model should retain:

- Source namespace, source record/meaning ID and pack version.
- Original term/display form and lookup aliases with their reasons.
- Meaning membership, optional POS/gloss/examples and usage labels.
- Relation type, distinguishing synonyms from antonyms, broader/narrower terms
  and associations.
- Provenance and license references sufficient to trace the imported input.

Index terms to meaning IDs, and meaning IDs to records. Do not flatten
overlapping synonym groups into a transitive connected component. Do not
invent absent POS, glosses or interchangeability guarantees.

Choose the source export after comparing the fields it retains. A MyThes
importer is an optional compatibility path, not a reason to require C++ FFI.
The source format's reader license and each dictionary's data license remain
separate. Compile large JSON/XML/SQL inputs during the build, not inside widget
builds or on the typing path.

## Word forms, locales and source offsets

Use exact lookup first, then documented normalization and qualified lemma
candidates. Keep display spelling and the original document range intact.

English lookup may use the selected WordNet release's morphology rules and
exception data after their provenance is captured. German lookup should first
reuse the existing qualified noun resource. Its nouns-only, finite inventory
does not establish verb/adjective coverage or contextual disambiguation.

Keep valid thesaurus entries available even when the finite spelling vocabulary
lacks them; spelling checks can qualify generated forms rather than prune the
source's lexical coverage.

Preserve ambiguity, including multiple lemmas/readings. An unresolved reading
must not be turned into a confident correction. Lemmatization and replacement
inflection are separate capabilities. Initial replacement inserts the reviewed
candidate; no promise of automatic agreement, article changes, verb government
or grammar-preserving substitution is made.

Keep umlauts, capitalization and ß meaningful. Do not globally equate distinct
German words through accent stripping or ß/ss replacement. Regional pack
selection and aliasing must be explicit. A de-CH spelling transform does not
establish complete Swiss vocabulary coverage.

Normalize lookup copies only. Document ranges remain exact UTF-16 source
ranges with grapheme boundaries; pack byte offsets cannot be used as document
offsets. Reuse the existing source/projection handling for discretionary soft
hyphens and formatting runs.

## Delivery sequence and acceptance

| Stage | Deliverable | Completion evidence |
| --- | --- | --- |
| TH0 | Scope, roadmap links and planned-source notices | This documentation change; all implementation stages below remain pending |
| TH1 | Source selection and redistribution record | Exact input artifacts/revisions/digests, original notices, chosen license option, export-field review and a reproducible source manifest |
| TH2 | Pack schema and deterministic importers | Identical outputs from identical pinned inputs; sense/relation/label preservation; output digests, counts and notices; malformed/corrupt input handling |
| TH3 | Offline lookup and bounded morphology | Real EN/DE packs; exact and phrase lookup; qualified inflected forms; ambiguity, unsupported/missing/error outcomes; measured load/query/memory costs |
| TH4 | Word review and replacement | Current-language resolution, target/candidate validation, stale-result rejection, protection/IME handling, formatting/revision preservation and one-unit undo/redo |
| TH5 | Distribution and product acceptance | Pack notices in each shipped target, offline desktop and actual-browser evidence, representative linguistic review and accurately scoped documentation |

### TH1: source and notice acceptance

- Select OEWN or the Princeton-only alternative explicitly before importing.
- Pin German export bytes, not a moving download URL alone.
- Record source URL, upstream revision/release, retrieval timestamp, input
  SHA-256, selected license, original notice paths and converter revision.
- Resolve discrepancies between upstream pages and the actual archive before
  accepting an input. Unknown, NC, research-only or otherwise incompatible
  inputs do not enter distributed packs.
- Record rights for any extra morphology, frequency/ranking or generated
  content separately. Current proofing allowlists are not silently broadened.
- Complete the pack's actual redistribution notices before distribution;
  planning summaries are insufficient.

### TH2/TH3: lookup acceptance

- Preserve English and German polysemy, including separate meanings for
  English "bank" and German "Bank".
- Cover same-spelling/different-POS entries where supplied, multiword
  expressions, reflexive forms, labels, missing entries and language overrides.
- Test German capitalization, umlauts, ß, common noun forms such as "Häusern",
  and supported regional distinctions without conflating "Maße" and "Masse".
- Test exact-to-lemma fallback, ambiguous and unresolved morphology, and
  independently report words outside supported morphology.
- Show synonyms separately from related concepts; no claim that every
  same-sense alternative is grammatically interchangeable in every sentence.
- Measure compressed pack size, expanded/index size, cold-load time, warm
  p50/p95 query latency and peak memory on named desktop/browser targets.
  Use a provisional warm-query p95 target of 50 ms on the documented reference
  targets; record the corpus and hardware instead of reporting an unqualified
  speed claim. Expensive preparation stays outside the UI typing path.
- Prove lookup works with network access disabled after pack installation.
  Do not send selected text to an external service.

### TH4: editor acceptance

- Capture document, story/block, exact text, range, effective language,
  source snapshot, session/configuration revision and pack identity.
- Reject a result after text, language, story, selection target or pack changes;
  require the selected literal candidate to belong to that current result.
- Reuse the existing guarded rich-text replacement path through a neutral
  target contract; preserve the proofing API's existing checks.
- Exercise word-to-phrase and phrase-to-word replacement, formatted-run
  boundaries, links/bookmarks/comments, surrogate pairs,
  combining marks, bidi text, soft hyphens, protected/generated/data-bound
  ranges, IME composition and pending tracked revisions.
- Verify tracked replacement and exact before/after rich text, selection and
  revision restoration through undo/redo.
- Keep the existing proofing correction tests passing; add thesaurus-specific
  cases that exercise the new target/candidate boundary.

### TH5: release acceptance

Use a reviewed, bounded English/German query panel with expected senses,
negative controls and identified source records. Record coverage and failure
examples rather than extrapolating universal vocabulary quality from it.
Synthetic fixtures establish parser/UI/protocol behavior; actual pack queries
and human linguistic review establish the relevant lexical behavior.

Run the narrow engine/provider/editor checks needed for the implementation,
rebuild the packs exactly, inspect the packaged notices, and exercise an actual
desktop and browser runtime. A compiled-JavaScript test alone is not browser
loading/CSP/UI acceptance. Preserve source and artifact identities with results.

This planning commit requires Markdown content/link review only. It does not
claim Dart, Flutter, pack-generation or product acceptance tests have run.

## Deferred work and related dataset review

- Automatic contextual sense selection, sentence rewriting and generalized
  grammatical reinflection.
- Moby expansion, Wiktionary/Kaikki additions and OdeNet enrichment. Reassess
  each source's actual data terms and quality before adding it.
- A remote thesaurus API or automatic model installation.
- Broad morphology imports, including LanguageTool/Morphy-derived resources,
  until a separate artifact-specific provenance and coverage review justifies
  them. Prefer reusing the fork's already qualified resources.
- Cross-paragraph replacement and additional editor surfaces beyond the
  qualified Word targets.

The requested inspection of the Hugging Face `cstr/grundwortschatz*`
repositories follows this scope commit. Assess their pipeline definitions,
input licenses, generated-output provenance, validation and publishing behavior
before proposing any reuse for vocabulary coverage, ranking, morphology or
sense data. A vocabulary list alone does not establish synonym relationships,
and a pipeline's code license does not license every upstream input or output.
This paragraph records a follow-up task, not completed inspection evidence.

## References

- [Princeton WordNet license](https://wordnet.princeton.edu/license-and-commercial-use)
- [Princeton project status](https://wordnet.princeton.edu/)
- [OEWN data license and inherited terms](https://github.com/globalwordnet/english-wordnet/blob/main/LICENSE.md)
- [OEWN downloads](https://en-word.net/downloads)
- [OpenThesaurus exports and license choice](https://www.openthesaurus.de/about/download)
- [OpenThesaurus sense and editorial conventions](https://www.openthesaurus.de/about/faq)
- [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
- [MyThes format](https://github.com/hunspell/mythes/blob/master/data_layout.txt)
