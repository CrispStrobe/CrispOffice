# Incoming Office reconciliation and focused acceptance

This directory records fresh local qualification of the combined Office source
used to complete mail attachment PR #221. The overall result and captured-head
scope are in the [parent report](../README.md).

## What the integration review repaired

PPTX background resolution now chooses the slide, its layout or its owning
master in that order and draws a single selected background image behind
decorations. `showMasterSp` controls inherited shapes, not the background.
Explicit solid/gradient/no-fill choices suppress an inherited image. A slide's
own background image works without a layout, and secondary-master references
retain their correct owning part.

The original authored `p:bg` XML and namespace bindings are retained through
import, save, repeated save and slide copy. New slide parts receive the required
image relationships. An explicit background-color edit clears the retained
source fill/image, while clearing the override permits inheritance again after
reopening. **Gradient display still approximates the first stop as a solid
color**; all authored gradient stops survive serialization. This is preservation
of source fidelity, not a claim of full gradient rendering.

PDF pictures retain their visible border after restoring crop and image
transforms. The final tests parse numeric tokens instead of assuming that `2.5`
is spelled differently from `2.500`, permit PDF whitespace between operators,
and require both crop-state restores before the border stroke. Earlier
numeric multiline fitting, hidden layout decorations, connector/flip state and
animation identity fixes remain in the combined source.

## Final executed checks

| Scope | Result | Receipt |
| --- | --- | --- |
| Twelve complete engine slide/PDF suites | 224 passed; zero failures/skips | [Engine rendering](engine-rendering/receipt.json) |
| Eleven complete spaCy package suites | 113 passed; one optional real macOS-library test not run | [Controlled acceptance](spacy-package/controlled-suite-receipt.json) |
| Three complete macro CLI/language/runtime suites | 41 passed; zero failures/skips | [Macros](macros/receipt.json) |
| Sixteen selected analyzer file/directory targets | Strict analysis passed, zero diagnostics | [Analysis](analysis/receipt.json) |

All executed tests used source `58c6962ec3ea82811bfcafec42981385f216f892`,
tree `d38c7b44d4ec3f6f576f182f773096bd3534e6c5`, with unchanged source,
workspace, dependency, runtime and applicable font inputs before/after. The
final comment-language test change is separately checked and does not alter
these selected tests or their production inputs.

The original spaCy receipt remains strict and reports `failed` only because its
blanket no-skips guard rejects the optional native case. Its separate controlled
receipt verifies the precise test name, file and missing-library reason. It
does not count that case as passed or establish native-model/macOS execution.

## Preserved development evidence

[slide-background](slide-background/README.md) retains the initial 30-pass /
8-failure result, the partial repair, and the final 42-pass background run. The
42 cases are already included in the final 224 engine cases. These intermediate
runs are not counted again.

The [development archive](../diagnostics/development.tar.xz) retains the first
full engine run (222 passed and two failed new PDF assertions), the raw PDF
operator probe that established correct product output, the corrected complete
rerun's source distinction, and initial whole-package analyzer diagnostics.
Nine old style findings in `tool/consume_distribution.dart` remain outside the
final selected strict scope. The one new evaluator missing-braces finding was
fixed before acceptance.

Inherited native grammar/macOS and earlier VBA conformance reports remain at
their original repository paths and source identities. They are not recounted
as tests executed during this continuation. In particular, an incoming native
grammar README reported an editor run whose raw log was absent; that absence is
now explicit rather than presented as independently recountable evidence.
