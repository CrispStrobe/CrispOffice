# Mail restore-resume publication continuation — 2026-11-19

Work resumed from remote checkpoint
`b2c05a0afa0ae606b061b13d5e50937c2a8eb1df`. PR #212 was still an open draft.
Its saved complete acceptance had already passed 2,243 test executions across
121 files, with zero failures/skips, 42 successful commands and six JavaScript
programs. Those historical results retain their original source and runtime
bindings; they are not new executions in this continuation.

## New main integration

Main advanced to `9ceb994d8edce3989228f1244cda90ecc9884931` through PR #214.
The exact main delta contains four paths. The merge preserves both parent
histories and resolves the overlapping work as follows:

| Path in `packages/quds_office_editor/example/` | Resolution |
| --- | --- |
| `lib/studio_spacy_host_native.dart` | Retain the accepted mail blob exactly. Its `_nerStatus()` implementation already verifies optional NER installation for bundled and downloaded runtimes, with behavior equivalent to main's `_nerState()`. |
| `lib/studio_downloads_manager.dart` | Use main's model-specific German title and bundled-library explanation, retaining the already accepted model-only download size. |
| `test/studio_downloads_manager_test.dart` | Retain all accepted cases, adapt the size-test title finder for bundled models, and add main's label/detail regression using the existing richer fixture. |
| `test/studio_spacy_setup_test.dart` | Retain main's two explicit missing-NER assertions. |

Exactly three files differ from the previously accepted product/test tree.
The native host, mail implementation, mail tests, root package manifest and
lockfile remain byte-identical. Focused local qualification of the three
changed files and unchanged native host is required before merging PR #212.

## Recovered evidence

The original `verify-publication.py` was rerun before changing source. It passed
against `b2c05a0afa0ae606b061b13d5e50937c2a8eb1df`, whose complete tree is
`93fdf5a60b0db71a77c58dbff5b23f5cb3f8dfef`. All 4,493 original source inputs
were rehashed against the accepted inventory and candidate Git blobs. See
[the fresh baseline verification](baseline-publication-verification.json).

The current fork branches and all PR heads were fetched. The unchanged late
draft heads for PR #210 (`3abffb94dcf33a2766a4579d296d0ef09c9e35cd`) and
PR #211 (`cacae8569814e4cb81f58d358734d31431f102be`) retain their explicit
post-cutoff review in the original publication-frontier record. Their
additional work is outside this milestone. The newly merged PR #214 is now
included through actual main ancestry. The raw remote advertisement is saved
in [remote-refs-before.txt](remote-refs-before.txt).

## Validation status at this source checkpoint

The source merge is saved before its focused local test gate. The original
acceptance evidence is preserved without edits. No new acceptance count is
claimed until the focused commands and independent replay finish. GitHub
Actions are not awaited or used as a gate.

Native macOS/Windows/mobile packaging, native model loading and real-account
interoperability remain outside the Linux and fixture qualification described
in the original report.
