# Planned thesaurus data licensing and notices

Recorded: 18 November 2026.
Status: planned-source record; no thesaurus data is added or shipped by this
documentation change.

The [English/German thesaurus scope](README.md) selects the intended source
families. Exact artifact review, immutable pins, attribution text and packaged
license files must be completed in TH1 before incorporating a pack. This file
is not a substitute for the notices accompanying the actual downloaded data.

## Policy and distribution boundary

Prefer MIT, Apache, BSD, CC0 and similarly permissive grants. Noncommercial
restrictions are unacceptable. Check code, data, morphology, ranking material,
models and transitive sources independently.

The existing Quds implementation remains under its existing license. An
independently written importer or lookup module does not relicense the data
it reads. Keep each pack's notices and source manifest with that pack and
make attribution accessible in the application and distributed documentation.

OpenThesaurus's CC BY-SA option is an explicit scoped data choice for this
feature. It does not change the license of independently written Quds code.
Separate packaging clarifies obligations; it is not a way to remove
ShareAlike from covered data or an adapted/combined database.

## Intended English default: Open English WordNet

- Project: [Open English WordNet](https://en-word.net/).
- Target family: regular lexical edition; current planning target is 2025.
- [Downloads](https://en-word.net/downloads).
- [License record](https://github.com/globalwordnet/english-wordnet/blob/main/LICENSE.md).
- Treatment: CC BY 4.0 for OEWN development, with the original Princeton
  WordNet license applying to underlying data.

Before distribution, retain the exact release's applicable license files,
including its Princeton notice, attribute both the OEWN team and Princeton
WordNet, identify our changes and preserve supplied attribution information.
Record the original archive digest and the generated pack digest. Do not
describe OEWN as solely MIT/BSD or solely the Princeton license.

No OEWN archive, compiled index or final attribution notice is included by
this planning change.

## English alternative: Princeton WordNet

- Project: [Princeton WordNet](https://wordnet.princeton.edu/).
- [License and commercial use](https://wordnet.princeton.edu/license-and-commercial-use).
- Treatment: the custom permissive WordNet license, not literally MIT or
  BSD-3-Clause.

Use this as an explicitly selected alternative to OEWN if the permissive
license preference takes priority over ongoing lexical maintenance. Retain
the actual release's copyright, permission statements and disclaimer, and
observe the restriction on using Princeton's name in distribution publicity.
Do not bundle both corpora merely to duplicate the same inherited entries.

No Princeton release or derived pack is imported by this change.

## Intended German source: OpenThesaurus

- Project: [OpenThesaurus](https://www.openthesaurus.de/).
- [Official download and license choice](https://www.openthesaurus.de/about/download).
- Selected option for this plan: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

The official site offers CC BY-SA 4.0 or LGPL at the recipient's choice.
This plan selects CC BY-SA 4.0; it does not infer an exact LGPL version from
the generic page.

For an incorporated pack, credit OpenThesaurus with a normal source link,
include the license information and supplied notices, and identify our
transformations. Preserve the applicable ShareAlike terms for distributed
adaptations and database rights; do not impose additional restrictions on
covered material. Conversion to an index does not turn the source data into
MIT data.

Pin the actual export and inspect its embedded notice before acceptance.
No German thesaurus export or compiled pack is included by this change.

## Morphology and optional inputs

The initial reuse candidate is the fork's existing Unicode Inflection-derived
German noun resource. Its
[documentation](../../../packages/quds_office_engine/third_party/proofing/MORPHOLOGY.md),
[original license](../../../packages/quds_office_engine/third_party/proofing/UNICODE_INFLECTION_LICENSE),
[notice](../../../packages/quds_office_engine/third_party/proofing/UNICODE_INFLECTION_NOTICE)
and manifest remain authoritative. Reuse does not imply complete German
morphology or license additional sources.

English morphology rules/exceptions must be tracked with the selected
WordNet release. Any added German verb/adjective forms, external frequency
lists, contextual models or generated candidates need their own source
record and qualification.

Original Moby data, OdeNet, Wiktionary/Kaikki and the user's Hugging Face
`cstr/grundwortschatz*` outputs remain candidates for later review. Their
presence in a permissively licensed code repository is not evidence that
every input or output has the same license. Do not infer commercial
redistribution rights from a model card badge or wrapper license alone.

If MyThes implementation code is copied or linked, retain its actual
[COPYING](https://github.com/hunspell/mythes/blob/master/COPYING) terms, including
its modification-marking condition. Do not label that text as standard
BSD-3-Clause without verifying the exact grant. An independent format
reader and its input dictionaries have separate licensing records.

## Required manifest and packaging record

For each accepted input, record:

1. Project, original source/download URL and immutable revision or release.
2. Retrieval timestamp, exact input filename and SHA-256.
3. Actual data license, selected option where applicable, copyright holders,
   attribution parties and original license/notice file paths.
4. Any inherited or separately licensed input and its own provenance.
5. Converter revision, documented transformations, schema version and output
   filename/SHA-256.
6. Applicable locale/coverage, source and output counts, and validation receipt.
7. The final notice location in each desktop/web/download distribution.

Preserve original notices verbatim when the artifact is accepted. Keep the
source manifest and regeneration procedure reviewable. Reject unresolved or
NC/research-only inputs from distribution. A pack must not silently lose its
notice when copied from a development build into a release bundle.

## Current inventory

| Item | State in this change |
| --- | --- |
| Implementation scope and licensing decision | Documented |
| Exact EN/DE thesaurus artifacts and SHA-256 pins | Pending TH1; none imported |
| Original thesaurus archive notices | Pending artifact review; none represented as bundled |
| Generated language packs and final redistribution notices | Not produced |
| HF `cstr/grundwortschatz*` pipeline/output audit | Follow-up inspection; no reuse approved by this record |
