# Native Zotero field recovery — 22 November 2026

## Goal and baseline

Continue the Word/LibreOffice parity roadmap from main `a5b4eb7d329b0700768b1fc72bb63cf58a9f5cd6` (PR #361). All 24 captured fork tips and four upstream tips are already included; the fork has no open pull requests. [The intake record](intake.json) preserves the exact refs and recent PR inventory.

## Implementation contract

A damaged citation payload must not prevent Zotero from presenting its own recovery workflow when the native field has complete, unambiguous structural ownership. Separate payload validity from safe result ownership. Send the original recognized payload to Zotero; never infer bibliographic data from cached display text. Permit Zotero's temporary empty repair code only inside the detached transaction, and require valid final metadata or an explicit unlink/delete before publication.

Retain the original document until the complete operation succeeds. Explicit conversion to ordinary text preserves the cached runs. Repair, removal and conversion remain one undoable operation with source/selection/lifecycle guards and DOCX save/reopen coverage. Locked, nested, opaque, incomplete, overlapping, aliased and cross-owner structures remain guarded; recovery never invents missing field boundaries.

## Work and verification

Implementation and local qualification are in progress. The engine, editor and regression evidence will be saved as separate remote checkpoints on `codex/zotero-field-recovery-20261122`. GitHub Actions are not a wait path for this work. Before merge, refresh incoming refs and reconcile any concurrent work.

This milestone will qualify bounded metadata recovery. Installed Zotero, Word and LibreOffice acceptance and legacy Apache OpenOffice compatibility remain separate from controlled protocol and local document tests.
