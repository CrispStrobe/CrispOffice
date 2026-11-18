# Review of cstr/grundwortschatz pipelines

Reviewed: 18 November 2026.
Status: source and published-metadata inspection complete; binary artifact,
input-license and rebuild qualification remain pending.

## Decision for Quds

Keep the [thesaurus plan](README.md): direct Open English WordNet (OEWN) for
English, with Princeton WordNet as the permissive alternative, and direct
OpenThesaurus under its CC BY-SA 4.0 option for German.

The existing vocabulary pipelines already implement useful sense extraction,
pack compaction, repairs and integrity checks. Reuse qualified importer code
or concepts and add a dedicated thesaurus export. Do not treat the combined
school-vocabulary databases as already qualified Quds thesaurus packs.

The English combined dataset declares CC BY-SA 4.0 and the German combined
dataset declares GPL-3.0-or-later. Neither declaration is an NC license.
However, an aggregate label does not establish the rights of every input.
The findings below identify review gaps; they do not establish that a current
published binary contains an NC or infringing contribution.

## Repositories and evidence boundary

The HF cards link the older GitHub name `CrispStrobe/words-universe`, which
redirects to [CrispStrobe/WordUniverse](https://github.com/CrispStrobe/WordUniverse).
Code links in this review are pinned to
[`474e7eff24e7aaa0bd86fec7d1500e5f1c240e04`](https://github.com/CrispStrobe/WordUniverse/tree/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04).

| Published repository | Files relevant to this review | Observed main revision | Declared combined-data license |
| --- | --- | --- | --- |
| [cstr/grundwortschatz-voc-en](https://huggingface.co/datasets/cstr/grundwortschatz-voc-en) | `grundwortschatz_en.db.gz`, Parquet tables and card | `e52b555` (abbreviated HF tree revision) | CC BY-SA 4.0 |
| [cstr/grundwortschatz-voc-de](https://huggingface.co/datasets/cstr/grundwortschatz-voc-de) | `grundwortschatz.db.gz`, `grundwortschatz-app.db.gz`, Parquet tables and card | `4cc0f04` (abbreviated HF tree revision) | GPL-3.0-or-later |

The application registry separately pins the German runtime file to full HF
revision `4cc0f0465710393c02d7aa0cb27debfbc2d277e8`, with compressed and
expanded SHA-256/byte counts. English uses a bundled runtime asset with an
expanded digest. See the
[pack registry](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/lib/core/models/language_pack.dart).

This review read source files, cards, public previews and repository trees.
It did not download or query the binary databases, execute builds or
enrichment services, trigger workflows, or upload/change any HF or
WordUniverse files. Script presence does not prove that a script ran on the
current artifact. Card counts and previews are not a substitute for a
revision-pinned binary audit.

## Existing thesaurus extraction

### English

The [OEWN expansion stage](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/pipeline/voc-en/13_wordnet_expansion.py)
uses `oewn:2024` and emits separate `wordnetSenses` records containing POS,
definition, synonyms and typed semantic relations. It also emits flat
synonym/antonym fields across meanings and blends definitions with other
enrichment. The emitted sense records omit stable upstream synset/sense IDs.

The current [slimming stage](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/tools/pack/slim_pack.py) preserves reduced
English sense groups with POS, definition, synonyms and hypernyms. It does
not discard all sense structure. Some source relations, including
sense-specific antonyms and other relation types, are dropped from the
reduced groups.

The later [English filtering implementation](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/tools/pack/thesaurus_en.py)
uses Princeton WordNet 3.0 through NLTK, a different lexical version from
the initial OEWN import. The
[synonym review builder](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/tools/pack/build_synonym_senses.py) produces
review overlays for selected meanings and educational use. Those choices
should not silently become the coverage policy of a general office thesaurus.

For Quds, retain source IDs, distinct senses and typed relations from the
selected pinned source. The plan's OEWN 2025 target is a new input selection,
not an assertion that this inspected pipeline already uses it.

### German

The [OpenThesaurus SQL importer](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/pipeline/voc-de/13b_enrich_with_openthesaurus.py)
parses synsets, terms, categories, usage levels and links. It excludes hidden
synsets and filters `derb`/`vulgär` material. It writes separate meaning
groups and a flat union of synonyms, with hypernym/hyponym/association
information, for words already selected into the school vocabulary.

Its exported group records omit original synset IDs and most per-term
usage labels. Some relation collections are converted through sets without
explicit final ordering. The current
[slimming stage](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/tools/pack/slim_pack.py) retains reduced German
groups containing categories and synonyms.

For Quds, import broader source coverage independently of school-word
selection, keep source IDs and labels, sort deterministically and preserve
separate meanings. Make register filtering an explicit product choice.
Do not infer that the current runtime exposes a raw all-sense union: later
review and filtering stages alter its flat display lists.

## Build and publication paths

The manual [pack-build workflow](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/.github/workflows/pack-build.yml)
currently performs:

1. Download the canonical language database from HF `resolve/main`.
2. Run `slim_pack.py`, then `repair_pack.py`.
3. Apply checked-in review overlays with `apply_llm_overlay.py`.
4. Run `index_pack.sh`, compress, and calculate output digests/byte counts.
5. Retain a GitHub build artifact; optionally publish the German runtime
   archive and/or the canonical dataset export.

Both publishing inputs default to false. The runtime upload option writes
the German `grundwortschatz-app.db.gz` and prints the resulting revision
for a separately reviewed registry update. English runtime distribution uses
the repository asset; the workflow's runtime upload branch does not update it.

Canonical publication is a separate path:
[publish_dataset.py](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/tools/pack/publish_dataset.py) copies the canonical
input through repairs, exports its tables to Parquet and compresses the
repaired database. It does not run the review-overlay stage. Its upload
allowlist excludes the card, so a successful data upload does not refresh
README descriptions or counts. Consequently, canonical SQLite/Parquet,
runtime SQLite, cards and previews may represent different transformations.

The older [build_hf_datasets.py](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/pipeline/build_hf_datasets.py) is another
staging/export helper. It is not the complete description of the current
runtime build and should not be used as the sole basis for pipeline assessment.

### Useful controls to carry forward

- Output digests, sizes, an immutable German runtime revision and
  content-addressed installed filenames.
- Repair/review layers separate from the original source DB.
- Overlay source-list digests that reject stale edits.
- Dedicated consistency, repair, thesaurus and pack-contract checks in the
  [CI workflow](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/.github/workflows/ci.yml).
- Published source and data-license inventories, despite the discrepancies
  listed below.

These controls help integrity and review. Output hashes alone do not pin
every upstream input, establish linguistic quality, or resolve licenses.

### Concrete pipeline follow-ups

| Finding at the inspected source revision | Effect | Follow-up before adopting this path |
| --- | --- | --- |
| [index_pack.sh](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/tools/pack/index_pack.sh) pipes the Flutter index test through `grep ... || true` | A failing test pipeline can return success despite `set -o pipefail` | Propagate the original test exit status and verify index completeness on the exact candidate artifact |
| [apply_llm_overlay.py](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/tools/pack/apply_llm_overlay.py) parses `--report` but never branches on it; the normal path updates and commits the DB | The flag does not provide a read-only dry run | Implement/verify true report semantics or remove the flag; do not invoke it expecting no writes |
| Canonical publication omits the overlay stage used for runtime construction | Corrections and lexical lists can differ between public representations | Define one versioned transformation manifest, or explicitly document and test the intended differences |
| The source download uses mutable `resolve/main` | Output hash receipts do not make upstream selection reproducible | Accept an immutable input revision plus expected bytes/digest and record it in build receipts |
| The publish workflow itself does not depend on successful CI or run the full qualification suite against its candidate | Separate CI coverage is not enforced by this publication workflow | Require the relevant lexical, schema, provenance, index and digest checks before upload |
| Missing/stale overlay rows are skipped and counted, without a required zero-stale release threshold | A build can omit intended review fixes | Decide explicit acceptance thresholds and bind the overlay/source versions together |

These are source-review findings and proposed follow-ups. No failing runtime
execution is claimed; external administrative release controls and historical
run outcomes were not assessed. `publish_dataset.py --report` is a different flag:
that command repairs/exports a copy but skips its upload; do not confuse it
with the overlay script's ignored flag.

## Code and data licensing boundaries

The repository's [DATA_LICENSE.md](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/DATA_LICENSE.md) contains an explicit
MIT grant for the scripts in `pipeline/`. Preserve that grant and applicable
notices when copying covered importer code. It does not expressly extend the
same grant to `tools/pack/` or application code.

The root [LICENSE](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/LICENSE) is AGPLv3 with an additional marketplace
distribution permission. The README/DATA_LICENSE description of application
code as proprietary is inconsistent with that file. Confirm the applicable
file-level grant before copying code outside the explicit MIT scope; a
package or script license is not the license of its input data or generated
lexical output.

The [HF cards](https://huggingface.co/datasets/cstr/grundwortschatz-voc-de)
attribute the German combined database's GPL declaration to childLex-derived
content. This is broader than the OpenThesaurus-only data required by Quds.
Do not relabel the combined German database CC BY-SA merely because one
selected upstream component offers that license.

### Provenance discrepancies requiring resolution for combined-data reuse

| Item | Observed evidence | Required resolution |
| --- | --- | --- |
| wordfreq | [DATA_LICENSE.md](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/DATA_LICENSE.md) says MIT; [upstream](https://github.com/rspeer/wordfreq) distinguishes Apache-2.0 code and CC BY-SA 4.0 data | Record the exact component, version and actual data notices; this is not an NC finding |
| CEFR-J versus Octanove | English pipeline/card labels obscure the distinction between the [CEFR-J v1.5 grant and the separate Octanove C1/C2 list](https://github.com/openlanguageprofiles/olp-en-cefrj) | Preserve the v1.5 research/commercial-use grant and citation conditions; do not assign Octanove's CC BY-SA license to CEFR-J by association |
| Cambridge YLE tags | [DATA_LICENSE.md](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/DATA_LICENSE.md) asserts an NC restriction was lifted for tags; the inspected records do not supply that grant | Establish the exact permission or a documented, source-specific rights basis before reuse |
| OpenThesaurus | DATA_LICENSE says CC BY-SA 3.0, while the pipeline inventory/card and [official download page](https://www.openthesaurus.de/about/download) point to 4.0 | Match the selected dump and its notice; record the chosen offered license |
| LEO739 cleanup | [strip_leo_attribution.py](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/pipeline/voc-de/strip_leo_attribution.py) documents no formal source license and removes attribution tokens while retaining 38 LEO-only entries with empty source arrays | Check whether those records survive in the exact candidate and establish independent qualified provenance or rebuild without that input; deleting a token does not establish rights |
| Leeds frequency list | [pipeline/LICENSES.md](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/pipeline/LICENSES.md) describes rank-only use; [consolidation code](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/pipeline/voc-de/01_consolidate_wordlists_csv.py) retains rank and numeric frequency, also visible in the HF preview | Verify the exact internet-corpus list and grant against actual retained/derived fields; this is not evidence that the distinct NC Kelly list was used |
| Other German input clearances | [pipeline/LICENSES.md](https://github.com/CrispStrobe/WordUniverse/blob/474e7eff24e7aaa0bd86fec7d1500e5f1c240e04/pipeline/LICENSES.md) leaves `200Fehler.csv` origin/license and Goethe redistribution unresolved | Close the recorded issues with source evidence before calling a combined import qualified |

Other optional layers include Wiktionary/OdeNet/ConceptNet enrichments,
childLex/LiTKey, examples and generated content. They need their own input
and derivation records if selected. Script presence alone does not establish
which layers are present in a specific current HF file. Generic source tags
and a wrapper license are insufficient to qualify those layers.

## Scoped implementation follow-up

1. **TH1:** retain direct OEWN/OpenThesaurus source selection. Pin raw exports,
   their original notices and selected licenses. Use the inspected MIT
   importers as candidates, not as a reason to inherit every existing input.
2. **TH2:** add a source-selected thesaurus export preserving IDs, senses,
   POS where available, usage labels and relation types. Keep provenance
   through every transformation; record deterministic source/output digests.
3. **TH3:** reuse Quds's already qualified finite German noun morphology;
   evaluate extra vocabulary/ranking data independently if it later adds value.
4. **Before optional HF reuse:** bind the exact file/revision/digest, audit its
   retained and derived fields, resolve the listed source discrepancies, and
   compare the canonical and runtime records. Removing a column or source tag
   from a mixed output is not evidence of an independently rebuilt corpus.
5. **Before pipeline publication work:** fix and qualify the concrete release
   and report-mode issues above in a separately scoped WordUniverse change.

This source review informs the plan and
[planned notices](licensing-and-notices.md). It does not approve a data import,
complete TH1, or authorize a new HF upload.
