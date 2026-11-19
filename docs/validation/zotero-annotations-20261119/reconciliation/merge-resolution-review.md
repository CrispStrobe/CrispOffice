# Independent merge-resolution review

Reviewed frozen integration commit `b818ca30001a13604b79eaf8a15f4bfaeb3956b7`.
Its first parent is Notes integration `36c35745cc487f07cd1af32f9e6295d509eba962`;
the final merge incorporates latest thesaurus `7e4adc08fce78fb95524f304962f9c1804e18691`.
The Notes merge incorporates `840362cd74a3d4b4365cf2bc9a2ae326225009c3`, which
already contains latest Mail `086e15b7c059edd09cc77dea721f489b5ef97fa9`.

## Resolution rationale

- `word_notes_pane.dart` retains incoming guarded document undo/redo rather than
  EditableText-only history. `_history` checks interaction permission, active
  composition, and ownership before invoking document history. The existing
  note-object controller/focus identity, composing range preservation, and
  source-bound focus-request handling survive unchanged.
- `office_editors.dart` combines the Notes `_documentPaneKey` GlobalKey with the
  thesaurus stable Flex wrapper. Keeping the same element hierarchy when Review
  opens or changes direction avoids unnecessary disposal; the key also preserves
  the document/Notes subtree across legitimate reparenting.
- `office_controller.dart` retains Zotero numbering snapshot capture/restore
  alongside incoming Notes text-options mapping, history behavior, and manual
  proofing coverage. The Zotero composition guard and header/footer variant
  identity remain present.
- Notes controller regressions retain the explicit `collapseSelection` helper
  and exercise both tracking=false and tracking=true after IME ends. The tracked
  branch asserts deletion/insertion spans; both variants undo the correction and
  pending typing without removing the pre-existing body revision.
- Notes pane regressions retain keyboard undo/redo, active composition, language
  controls, and actual field/controller identity across Review layout changes.
- The Zotero Notes selection helper retains `ensureVisible`, a subsequent pump,
  `hitTestable`, and the incoming focused-field assertion. This preserves the
  final RTL reachability fix without duplicating tap operations.

No code or repository metadata was modified by this review. This is a static
merge review and ancestry/equivalence audit; it does not substitute for the
parent agent's local runtime qualification of the integrated source.

## Multi-paragraph list-item scope assessment

The current research-note parser maps exactly one native paragraph per `li`:
the outer `li` becomes `p`, and its optional child `p` becomes `span`. List metadata
is keyed by paragraph index and increments numbering for every metadata entry.
Consequently, accepting a second child paragraph by merely relaxing validation
would either flatten an authored paragraph boundary or create another numbered
item. A safe extension needs explicit continuation-paragraph representation,
indented unnumbered rendering, citation placeholder paragraph mapping, and DOCX
save/reopen plus undo verification. This is not recommended as a small incidental
follow-up to the current work.
