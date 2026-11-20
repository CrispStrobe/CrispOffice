# Mail attachment source review

Reviewed the published head `f80b46e2115d32b11b633cc47acec820aecf2db4` and the
captured Zotero head `e79c32e77f1990e303527e477e4909df993c1b9b` on 20 November 2026.
No product edits or remote mutations were made during this review.

No concrete product blocker was found in immutable ownership, quota admission,
atomic/cancellable reads, MIME structure, RFC 2231 filenames, Bcc envelope
separation or acknowledged uncertain retries. Tests in the published tree cover
these boundaries, including the narrow Arabic body/IME/resize regression.

The published mail guide referenced two absent evidence records:
`docs/validation/mail-attachments-20261120/README.md` and
`docs/validation/mail-attachments-20261120/attachment-core/README.md`. Its claimed
independent receiver and maximum-size probe had not yet been saved. The new
reproducible probe in this directory closes that evidence gap without claiming
to reproduce any unavailable historical run.

The captured Zotero branch had an older mail composer and test snapshot. The
later mail body reflow, Arabic direction and regression test must survive the
three-way reconciliation.

One inherited feedback limitation remains: a native pre-submission MIME
preparation exception reports `mailInvalidSender`. The valid bounded attachment
and body combinations fit the wire budget, so this is not considered a product
merge blocker. No live provider delivery or recipient-facing privacy testing was
performed.
