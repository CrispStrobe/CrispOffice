# Captured incoming integration reconciliation

This integration preserves the ancestry of the four captured follow-up heads:
`708f2821f5563912642d8062ea4db126462a67a1` (Zotero),
`b8f4a7be7cc5ac1a6d9c1d89d999c5e6f3e13fb6` (window-focus),
`740f3e247102734ab1e689dc9473efcb3543ed15` (Mail), and
`1eddb91495bd405a1dfb3b1e8734e93e85b04b1d` (presentation UI).
The heads were captured before integration; this pass does not chase subsequent
remote branch movement or wait for hosted CI.

## Native macros and text

The Word/PowerPoint compiler adapters, native operations, strict top-level shape
selectors, nullable rich-text overrides, empty-shape text bodies, replacement
templates, and their tests are retained. An additional regression fixes native
text replacement on authored models that have display runs but no imported XML
source: live rendering now uses the same scalar text and style as PPTX export,
without mutating the old display-run snapshot.

## Paragraph layout and autofit

The shared measurement and painting path and the `!forceLayout` line-count guard
remain authoritative. Numeric authored-LTR text goes through the existing
`_layoutLines` path rather than a second `plainWidth`/`drawPlainLtr` shortcut.
Zotero's finite, nonnegative fixed line advances, zero-scale paint suppression,
zero percentage leading, bounded autofit values, and editor handling of
collapsed line advances are retained. Fixed point leading is not reduced again
by percentage autofit.

## Picture opacity

Mail's finite-alpha validation and canonical `GS0` through `GS1000` resource
validation are combined with Zotero's `endText()` before changing opacity.
Validation occurs before the canvas changes state. The page sink registers its
alpha resources once. Picture transparency, crop, shadow, and border operations
retain the caller's graphics state and preserve independent source image alpha.

## Radial fills

The newer centered-circle convention is applied consistently in the editor and
PDF export: the outer radius is half the shape diagonal and color stops run from
the central focus to the circumscribed bounds. Existing shape clipping and the
depth/namespace-bounded shape and background parsers remain intact.

Only an explicit centered `a:path path="circle"` with all four `a:fillToRect`
values equal to 50% and an absent or default tile rectangle is modeled as radial.
Other paths, absent/offset focus rectangles, and custom tiles retain their solid
first-stop fallback instead of being approximated. The earlier valid-circle
fixture now states its center explicitly; the incoming missing-focus refusal
test remains as coverage of the narrower supported representation.

The incoming engine ring-color/geometry tests and editor pixel tests are retained.
Test execution results are recorded separately in the final local validation
receipt; this note does not claim that an unavailable Flutter runtime was used.
