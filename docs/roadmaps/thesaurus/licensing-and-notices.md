# Thesaurus data licensing and notices

Updated: 18 November 2026. This record now describes the actual English/German
packs on the offline-thesaurus branch. The original scope commit contained
planned sources only; the implementation adds the pinned inputs, notices,
independent compiler and generated assets listed here.

## Distribution boundary

Independently written Quds code, including the compiler, provider and editor
integration, retains the repository's MIT license. Each lexical pack retains
its own data terms. The German derived pack uses the selected CC BY-SA 4.0
option; storing it separately does not remove ShareAlike from adapted data or
covered database rights. No noncommercial, research-only, school-vocabulary,
frequency-list, contextual-model or generated-candidate input is introduced.

The authoritative machine-readable inventory is
[`sources.json`](../../../packages/quds_office_engine/third_party/thesaurus/sources.json).
It pins source URL, release/export identity, retrieval timestamp, byte length,
SHA-256, original notices and the existing German morphology manifest. The
[redistribution record](../../../packages/quds_office_engine/third_party/thesaurus/README.md)
and [compiler documentation](../../../tools/thesaurus/README.md) describe the
transformations and exact regeneration commands.

| Distributed data | Exact selected source | Terms and attribution |
| --- | --- | --- |
| English lexical pack | Regular OEWN 2025 WN-LMF, `english-wordnet-2025.xml.gz` | OEWN CC BY 4.0 plus inherited Princeton WordNet terms; credit both projects |
| German lexical pack | OpenThesaurus SQL archive, export 2026-11-17 23:15:01 UTC | CC BY-SA 4.0 selected from the archive's offered options; credit OpenThesaurus, Daniel Naber and contributors |
| German noun lookup support | Existing qualified Unicode Inflection-derived resource in this fork | Existing Unicode-3.0 license, notice, manifest and finite noun coverage remain authoritative |

## English pack

The input is the regular lexical edition from
[OEWN's official download](https://en-word.net/static/english-wordnet-2025.xml.gz),
not the combined Grundwortschatz output. Its SHA-256 is
`9ca6d1dcb75f822fdd66617f7d9da48142ace38dd544d6ad5e2feca1674ad3fe`.
The 2025 source tag is pinned at `dc343f2683279ecbb13fab4e2fd778d7b162d287`.

The source archive and tag-specific `LICENSE.md` and `WNDB_License.txt` are
retained. The installed pack includes the original OEWN/Princeton notices,
the CC BY 4.0 legal text and a Quds attribution/change notice. It preserves
all 107,519 meaning groups and 185,129 source terms/senses, with lexical and
synset IDs, POS, definitions, examples, typed relations and source Form aliases.
The compiler does not relabel this data as MIT or solely Princeton-licensed.

English word-form fallback uses source aliases and an independent
implementation of the documented WordNet suffix rules. It only accepts
resulting lemmas present in the selected corpus with compatible POS. It does
not include an extra unqualified morphology database or claim every English
inflection is covered.

Princeton-only WordNet remains an alternative for a future explicit choice;
there is no second default English corpus in this distribution.

## German pack

The input is the
[official OpenThesaurus SQL archive](https://www.openthesaurus.de/export/openthesaurus_dump.tar.bz2).
Its SHA-256 is
`80873823310f2dec7618e9a171fd375d786bb3007d6de51b58cde54db55bfd38`.
The exact bytes are checked in because this download URL is mutable.

The archive's `COPYING` and `DATABASE-README.txt` are retained verbatim. The
installed pack also contains the CC BY-SA 4.0 legal text and a Quds change and
attribution notice. Quds selects CC BY-SA 4.0 for the adapted lexical pack;
it does not replace the original dual-license notice or infer a different
LGPL version from a website summary.

The independent parser reads the SQL dump as data and never executes it.
It exports visible German synonym groups and terms with original IDs,
category/usage/tag labels, available term notes and typed relations. Empty
visible groups and hidden/non-German source records are counted and excluded
as documented by the compiler. All 50,264 accepted groups and 203,767 terms
are retained without transitive synonym flattening or a spelling allowlist.
Parenthetical lookup aliases retain their reason and never replace literal
source display forms. The source's folded aliases and `word_mapping` table
are not imported; umlauts and ß are not globally stripped or folded to ss.

The existing finite German noun resource supplies qualified lookup lemmas.
Its [documentation](../../../packages/quds_office_engine/third_party/proofing/MORPHOLOGY.md),
[license](../../../packages/quds_office_engine/third_party/proofing/UNICODE_INFLECTION_LICENSE)
and [notice](../../../packages/quds_office_engine/third_party/proofing/UNICODE_INFLECTION_NOTICE)
continue to apply; copies of the latter two are included in the pack's
accessible notice view. This is noun lookup support, not general German
morphology, contextual disambiguation or automatic replacement inflection.

## Packaging and verification

Both packs live under the editor package's `assets/thesaurus/{en,de}/` tree.
Each manifest lists notice paths and the size/SHA-256 of every logical file,
plus compressed size/SHA-256 for raw-deflate shards. The manifest itself is
pinned in generated Dart constants. It also records source-manifest and
compiler digests and the zlib version used for the deterministic build.

`BundledOfficeThesaurus` loads package assets on demand. `Sources and licenses`
in the dialog loads and verifies the actual bundled notice files through the
same manifest-bound service. Release packaging must retain those asset paths;
the source archive notices alone are not a substitute for installed notices.
Native Flutter bundle verification and web compilation are recorded in the
[continuation evidence](../../validation/thesaurus-20261118/continuation/README.md).
Installed-desktop and actual offline-browser interaction remain release gates
where the present environment cannot execute them.

## Inputs outside this scope

The [HF pipeline review](hf-pipeline-review.md) remains a source/metadata audit;
it grants no reuse of the combined `cstr/grundwortschatz*` databases. Their
mixed provenance and output qualification questions remain separate. No Moby,
OdeNet, Wiktionary/Kaikki, external ranking data, optional model or MyThes
implementation code is copied into this feature.
