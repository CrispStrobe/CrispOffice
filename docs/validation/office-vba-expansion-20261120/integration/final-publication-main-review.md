# Later main review before publication

Remote main was observed at
`13be50464d1b43e9f2100fb9ccc12f8fe22eb55e`, which merges PR 250's durable Mail
Outbox work and qualification records. This is a later observation than the
[frozen branch/PR cutoff](final-cutoff-inventory.json). The
[source D inclusion receipt](final-cutoff-inclusion.json) and
[cutoff reconciliation](final-cutoff-reconciliation.md) remain unchanged.

The [new machine-readable review](final-publication-main-review.json) compares
that main head with frozen D, `192ea2aedbf0b1494627953c79a7042037a63301`.
The standard Git prospective merge is conflict-free and produces tree
`8638adaa51d9fba055fd41245626fe50c040207e`. **All 1,164 recorded D input paths
retain their exact mode, object type, Git blob, and independently recomputed
SHA-256. There are zero input differences.** This is source preservation;
runtime results remain tied to their actual execution source.

## Changes outside the Office engine inputs

Relative to D, the prospective merge changes exactly 22 paths, all outside the
recorded input union:

| Scope | Paths |
| --- | ---: |
| Outbox qualification documents, raw evidence, intake records, and screenshots | 11 |
| Mail test fixtures, fake stores, and widget database support | 6 |
| Mail JSONL audit tool and its regression fixture | 2 |
| Native/EWS Outbox status notices and localized strings | 3 |

The three application changes add an instruction to open Outbox after a saved
item remains unsubmitted and clarify the existing save-failure guidance in
English, German, and Arabic. They do not change submission, retry, persistence,
account, or credential control flow. The audit tool now splits JSONL records at
LF boundaries while retaining Unicode separators inside JSON string values.

Twenty-one resulting entries exactly match the new main snapshot. The native
Mail host combines the incoming one-line notice change with D's credential
selection and external-store protections; its complete D-to-prospective patch
is preserved in the JSON review.

## Captured Outbox work and later qualification

D already contains the earlier Outbox checkpoint
`bda00b32911bcab4e748851d89af0dbdfc886d39`. The new main brings that work's later
qualification records and supporting corrections. Those records retain their
own source identities and execution claims. This review does not reexecute
Outbox or Flutter tests, and the Office engine gate does not qualify those
application workflows.

The histories have two merge bases: captured main `b42eca1d` and captured Outbox
`bda00b32`. The four engine paths appearing in the new main's delta from
`b42eca1d` are therefore already represented in D's history. The prospective
merge preserves D's newer engine contents exactly.

## Publication proposal

After D's evidence collection completes, perform a normal merge of this exact
main head, retain the frozen D and cutoff receipts, and verify the actual merged
input entries again. Later evidence-file commits may change the complete tree
without changing these inputs. A further main advance requires its own review.

This document records a **prospective merge**, not an actual final merge to
remote main. The review performed no tests, compilers, analyzers, fetches,
GitHub Actions queries, or changes to HEAD, the index, or product source.
