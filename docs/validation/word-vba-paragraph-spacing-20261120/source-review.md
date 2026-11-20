# Independent Word spacing source review

**Accepted** on committed source `0201b549d0dc3f601c50e36255d557034cb01699` (tree `86531c002a6b1d6e748849f7370a87072a5fa768`). There are no outstanding findings within the documented contract.

## Reviewed inputs and contract

The review binds all eight changed Dart files, the exact BAS example, and `docs/VBA_WORD_MACROS.md`: ten inputs total. Their current bytes, sizes, Git blob identities and modes match the reviewed commit. The final supplemental replay verifies these inputs before and after execution, alongside 38 explicitly recorded runtime and probe inputs; all remain unchanged. The JSON report contains every hash and the raw-record manifest.

The compiler holds at most one pending rule. Rules 3/4/5 must be followed by a same-paragraph amount before another native mutation or macro completion. The pair can cross typed ByVal helpers, alias rebinding and scalar control flow while retaining explicit target identity. Every native emission checks the pending boundary, and completing a pair emits one indivisible rule/amount operation. The existing statement/work/native-step bounds remain in force.

Conversion inputs retain actual numeric typing. Exact native-grid inputs receive canonical unit arithmetic; other inputs use the ordinary numeric representation. There is no epsilon widening of raw LineSpacing values. An adjacent source line value can naturally multiply to a native-grid point value under ordinary floating arithmetic; the contract and regression distinguish that existing behavior from explicit grid snapping.

## Findings corrected

1. **Method call forms (P2):** property-only validation rejected bare and parenthesized Space methods. Method arity now permits exactly zero arguments in all supported statement/Call forms.
2. **Common decimal conversions (P2):** common multiples such as 1.15 lines were rejected through last-bit multiplication residue. Exact-grid canonical arithmetic now yields 13.8 points while preserving ordinary off-grid arithmetic and raw point refusal boundaries.
3. **Preset source guard bypass (P1):** duplicate spacing could silently change back after reopening, and MC spacing branches could disappear. Custom and preset line writes now share the same pre-mutation source guard.
4. **Unrelated property alternative loss (P2):** non-spacing MC choices inside paragraph properties were lost during accepted edits. The guard now refuses alternatives within or wrapping native pPr. The contract states the remaining ordinary-serializer boundary for unrelated body drawing alternatives.

## Final independent probes

The final replay exited zero with empty stderr and **56 passing supplemental expectations**: 14 method/helper/With checks, 18 unit conversions, six original native-refusal fixtures, 16 numeric/type/alias/evaluation-order boundaries, and two unrelated-property-alternative refusals. Raw JSON and the source/runtime receipt are retained. These expectations are separate from, and add zero cases to, the parent regression total.

The probes verify that retained aliases complete the original target, rebinding a ByVal parameter cannot redirect the caller, changing the actual target refuses, and a native mutation from an amount target-selector helper cannot bypass the pending guard. A complete paired helper executed before an outer rule retains its correct native operation order.

All initial failure demonstrations and the intermediate 54-record fixed stream remain separately indexed. They are diagnostic evidence and do not substitute for the source-bound final replay.

## Qualification limits

This review does not replace the parent complete regression, analyzer/formatter or compiled-JavaScript gates. It does not claim installed Microsoft Word pagination, live providers, embedded VBA execution or universal whole-package byte preservation. No GitHub Actions, workflow or status endpoints were queried or awaited.
