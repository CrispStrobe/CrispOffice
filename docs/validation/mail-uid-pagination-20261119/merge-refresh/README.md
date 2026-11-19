# Bounded final ref refresh and product reconciliation

The final origin refresh was captured at **09:05:31 UTC / 10:05:31 CET on
19 November 2026**. It contains **424 actual origin refs**: 222 branches,
185 pull-request heads and 17 tags. Four peeled-tag advertisements are listed
separately in the raw output. This is a new origin snapshot; the four upstream
refs in the earlier 421-ref capture retain their earlier timestamp.

The 13 changed/new advertisements include two unique frontier heads not already
in the remote checkpoint `79998b32`:

- `293f45449b496e3024ff100968d78f37983faadd`, the parallel Office integration
  branch, with complete Arabic/Hunspell evidence and additional regressions.
- `c0c71a26e014cadda7a1f42244e710509dea5f6c`, the parallel Office synchronization
  branch, with complete prior evidence, missing-dictionary admission, shared
  provider disposal and delayed Mail file-read controls.

Both are parents of remote checkpoint `39444f0d`. Their evidence retains its
original source and runtime identities. Historical passing totals are not
added to the current continuation's acceptance totals.

## Reviewed reconciliation choices

The existing v3 Mail cursor, bounded discovery and transactional reconciliation
implementation remains unchanged. The incoming Mail UI analyzer exclusion for
generated `build/**` output is preserved. Because that changes an input in the
previous exact Mail closure, the final gate uses **fresh Mail replay**, without
relaxing the earlier 399-input carryforward rule.

Arabic production rules retain the stronger existing Unicode token boundaries
and semantic combining-mark handling. All incoming Arabic regression cases are
added. Newer main's Studio host wiring, branding, English default and hidden
comments default take precedence over older interface expectations; tests open
the required UI explicitly and retain the delayed picker/file-read cases.

Hunspell keeps the statically rooted finalizer, explicit ownership clearing and
two-second bounded shutdown. The incoming ownership review adds termination at
the next worker event boundary, preserving attachment after a synchronous
native open. Missing affix/dictionary admission and shared provider disposal
are retained. All three independently authored fixture families are preserved
under distinct test filenames and environment variables. The six ownership
controls use a 3.5-second native delay and disposal bounds below that delay to
exercise the existing two-second fallback rather than the incoming branch's
one-second variant.

AyaSpell retains safe output-directory reuse, exact verified-file publication
and all 17 offline controls. Its card now describes Studio's implemented
optional dictionary download workflow. No live publication was performed.

The incoming multi-platform artifact workflow is retained and repaired to build
from the Studio app directory and package receipt-verified Hunspell engines and
source/notice bundles. The Linux native build and installer are exercised
separately. Workflow review is static: no Actions endpoint, dispatch or wait is
used, and no new desktop/mobile platform execution is claimed. Android's job
targets arm64; the macOS artifact uses an ad-hoc local signature, without a
release identity or notarization.

The frozen-source gate and independent final audit are recorded in the parent
report when complete. Review and author-only checks remain separate from that
gate.

## Later main guard

At 09:21 UTC, main had advanced to `00014577265d1f95d4c016159029510d3a10804b`.
Its eight-file About/German-label and macOS menu delta is retained separately
from the 09:05 snapshot. Both source conflicts concerned formatting around
translated labels; incoming translations are retained. Eighteen German values
had unambiguous UTF-8/Latin-1 mojibake and were repaired with unchanged keys;
the exact mapping and hashes are retained in the adjacent encoding receipt.
The two added Dart files expand strict checking to 150 paths. Native libraries,
Mail behavior, Word routing repairs and all prior fixture families are retained.

`local-review.bundle` preserves the exact local reconciliation and reviewed
source history through `21d97959`; `local-about-review.bundle` adds the later
main merge, exact encoding correction and formatting commit. Their verified
prerequisites and hashes are recorded in the adjacent JSON files. Import the
first bundle before the second when restoring these local commit identities.
