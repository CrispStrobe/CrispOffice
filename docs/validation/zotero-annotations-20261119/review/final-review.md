# Add Annotation final review

Reviewed `f3b7dc3bf4a994781e40fa89e076ebe485ce3d0d..ff06e5544673ce7f70be983299241bcdcef780d3`, tree `ee23dc2179d4b3e26eabf3b35e7aa13f95a7963d`, without modifying tracked files. `git diff --check` passed.

**No blocking product-code finding. One documentation precision correction was accepted by root for the documentation-only publication commit.**

## Annotation export boundary

At the reviewed checkpoint, the Zotero guide (lines 77–82) and new validation README (lines 66–70) imply refusal according to the selected annotation type. Quds receives exported HTML, not the selected Zotero annotation objects.

The inspected upstream source is `chrome/content/zotero/xpcom/editorInstance.js`, blob `3c769e6ca8e20d4aad449024e406f5d749cffca8`. Its `serializeAnnotations` implementation:

- Skips an annotation whose attachment cannot be resolved at lines **1704–1708**.
- Skips a non-image annotation with no text, comment or image at lines **1710–1715**.
- Emits image markup when image content is present, but substitutes a localized missing-image notice at lines **1797–1807**.
- Embeds that content into a paragraph template at lines **1821–1830**.

[Exact upstream blob](https://api.github.com/repos/zotero/zotero/git/blobs/3c769e6ca8e20d4aad449024e406f5d749cffca8)

The implemented guarantee is atomic rejection of **unsupported returned markup**, including image elements. It cannot validate an annotation type that Zotero no longer represents in its returned HTML. Root agreed to state that only text annotations are supported and that returned images/unsupported structures are refused atomically. The UI scope statement asking users to choose text annotations remains accurate.

## Concrete review conclusions

Cancellation routes through `insertsNoteText` and the no-content check before any apply. Older-command error alerts are acknowledged and drained without marking the staged model complete; the annotation-specific STOP/YES_NO regression checks refusal of staged preferences and a single initial request. The unavailable-command UI test correctly covers HTTP failure rather than claiming an installed old-version replay.

The new ribbon command uses the existing direct dialog and focus-return wrapper. That wrapper checks document identity, current route and composition before requesting editing focus. The persistent workspace retains its normal browsing behavior. Neither route adds credential handling, a remote endpoint, logging, or a fallback transport.

Returned image tags are rejected by the bounded note parser before its staged note assignment. The controller retains its snapshot/restore application boundary. The new command has both native ribbon and Document workspace entry points; existing editability, composition and busy guards apply.

No further test process was started during frozen qualification. Root's fresh 98-file run owns the published qualification totals. This review adds no live Zotero or installed-application acceptance.

## Review scope disclosure

This agent implemented the enum/controller preflight and their tests. The final read-only review of root's dialog, ribbon, guide and UI regression changes is separate from those implementations. The detailed machine-readable receipt is in `final-review.json`.
