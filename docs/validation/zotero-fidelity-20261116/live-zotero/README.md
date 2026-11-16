# Native Zotero fidelity acceptance — 16 November 2026

The final run passed against Quds source commit
`ca4011de0e17783f12bcff07336e318adc1db99c`, using the official Zotero 10.0.8
desktop application, the actual `ZoteroClient`, `ZoteroCitingClient`,
`WordZoteroCitingSession`, and Studio HTTP transport. The profile contained only
three newly created synthetic books, one synthetic saved search, and test
styles. No account or API key was used.

This is integration-component acceptance against the running native processor.
It does not establish full Quds/CrispCloud native application packaging,
Microsoft Word/LibreOffice interoperability, or real operating-system keychain
behavior. The application style chooser was not automated again: valid saved
German style preferences were seeded in each document.

## Results

| Scenario | Observed result |
| --- | --- |
| Local catalog and saved search | Three local books with durable Zotero URIs and CSL JSON; the saved-search list returned the expected entry; its title condition selected Alpha; an additional query for Beta remained inside the saved-search condition and returned no items. |
| German Chicago bibliography | Native refresh produced four linked note citations and one protected bibliography spanning two real paragraphs, with mixed italic titles and ordinary text. |
| German small-caps bibliography | A minimal synthetic CSL style caused native Zotero to emit author small caps, italic titles, double line spacing, and bibliography paragraph formatting; all supported formatting was applied with zero simplification warnings. |
| Reopen and refresh | Each style was saved to DOCX, reopened, refreshed a second time, saved, and reopened again. Fields, rich runs, paragraph layout, and German document preferences survived. |
| Native layout callback lifecycle | The first refresh for each style received one `Document.setBibliographyStyle` callback. The refresh after DOCX reopen received none; the layout already stored in the document remained intact. |
| Staging | Every native transaction left its original document unchanged until the staged result was explicitly applied. |

There was one successful catalog/saved-search scenario and two native style
scenarios, each with two refresh transactions: **four native refresh
transactions in total**. These are separate from unit/widget-test counts.

For both styles the first three citations used Alpha at pages 12, 12, and 34.
Zotero returned a full first citation, then `Ebd.`, then `Ebd., 34.`. A fourth
citation referenced Beta. Exact strings and rich runs are retained in the four
`logs/*-result.json` files.

The native layout callback used a first-line indent of −720 twips, a left indent
of 720 twips, entry spacing of 240 twips, and line spacing of 240 or 480 twips.
The adapter stored these as a 36-point hanging indent and left indent,
12-point paragraph spacing after each entry, and automatic line spacing of
1 or 2. The independent DOCX XML check found those actual Word values, one
bibliography begin/end pair across two `w:p` elements, four citation fields in
the footnotes part, no inline line break separating bibliography entries, and
the expected `w:smallCaps` runs.

## Evidence and source identity

- [Final acceptance receipt](logs/acceptance-receipt.json): runtime identities,
  compile and execution commands, native readiness responses, elapsed bounds,
  source hashes, artifact hashes, and verification results.
- [Delivery source proof](delivery-source-proof.json): an additional check of
  every recorded source file and the retained executed kernel after completion,
  plus the observed synthetic GUI lifecycle.
- [Client output](logs/client-run.log) and [catalog result](logs/catalog-result.json).
- [Independent DOCX verification](logs/independent-docx-verification.json).
- [Source map before](logs/source-before.json) and
  [source map after](logs/source-after.json): 439 source/manifest/script/style
  inputs, unchanged across compilation and execution.
- [Actual Dart acceptance entry point](scripts/fidelity-live.dart) and
  [compile/run/XML-check wrapper](scripts/run-live-acceptance.py).
- `logs/*-protocol.jsonl`: the actual catalog requests and native citing
  callbacks, including complete native RTF field results.
- `inputs/`: the genuine Studio harness manifest, lockfile, and resolved package
  configuration used to compile the integration.

The executed kernel SHA-256 was
`03f53d286ee4d8f0c6353a0cba7426f9d10c013b693d73cbf40167fabe737e93`.
The wrapper captured inputs before compilation, checked them again before
execution, checked the kernel immediately before execution, then checked both
source and kernel afterward. The final run started at
`2026-11-16T07:27:31.605976+00:00` and completed at
`2026-11-16T07:27:38.074854+00:00`.

The SDK was official Flutter 3.47.8 / Dart 3.13.7. Production dependency
declarations were unchanged. Package restoration used genuine locked
dependencies. No GitHub Actions were queried, polled, waited for, or rerun.

## Actual DOCX files

| Stage | Before | Refreshed and reopened |
| --- | --- | --- |
| Chicago initial refresh | [Before](chicago-first-before.docx) | [Refreshed](chicago-first-refreshed.docx) |
| Chicago refresh after reopen | [Before](chicago-repeat-before.docx) | [Refreshed](chicago-repeat-refreshed.docx) |
| Small caps initial refresh | [Before](smallcaps-first-before.docx) | [Refreshed](smallcaps-first-refreshed.docx) |
| Small caps refresh after reopen | [Before](smallcaps-repeat-before.docx) | [Refreshed](smallcaps-repeat-refreshed.docx) |

These files contain only synthetic data. Their purpose is inspecting actual
fields and layout properties; no independent Word/LibreOffice visual rendering
was performed in this acceptance.

## Retained setup failures and retry

Earlier unsuccessful work is preserved and is not included in the successful
scenario count.

1. [Metadata preflight](logs/preflight-setup-attempt.json) failed before
   compilation or native launch because the wrapper looked for
   `application.ini` at the binary root. Correcting the wrapper path to
   `app/application.ini` resolved it without changing production source.
2. [Cold headless attempt](attempt-1-cold-profile/logs/acceptance-receipt.json)
   compiled successfully and could probe the local API, but the first catalog
   request requiring CSL export timed out. The captured source and kernel were
   unchanged. No native citation-refresh scenario completed.
3. [Headless readiness attempt](attempt-2-headless-readiness/logs/acceptance-receipt.json)
   compiled successfully, then failed before executing the production client.
   Its plain saved-search endpoint responded, but CSL readiness did not
   complete within its bounded wait. Concurrent small-caps source changes also
   invalidated this attempt. That earlier wrapper's final source guard replaced
   its previous exception message, so the receipt does not preserve the exact
   underlying exception. The later wrapper preserves both errors separately.
4. [Desktop preparation](desktop-preparation/receipt.json) opened the official
   GUI, visibly showing the three synthetic books and saved search. The plain
   search endpoint responded, but the direct CSL readiness request reached its
   45-second timeout. This setup-only probe did not run product code.
5. The final run used the same isolated native GUI/profile after CSL export
   became available. It passed with the final source checkpoint and no
   production-source or production-timeout changes to work around the setup
   failures. The exact reason for the delayed export readiness was not
   established; these results do not claim a successful cold-profile first-use
   catalog request.

The desktop preparation's launcher terminated while its Zotero GUI remained
running. The final wrapper's own launch command exited with status 0; the
actual API responses and citing callbacks came from the same isolated profile
already visible on the desktop. After observing the passing terminal result,
the synthetic GUI was explicitly quit through its native controls. This
lifecycle is recorded separately rather than treating the wrapper process exit
as evidence that the GUI had closed.

Original failed-run scripts, source maps, raw logs, and failure output are
included within their respective attempt directories. The final `logs/`
directory omits the stale `failure.txt` left by the first attempt; that file is
preserved in both earlier attempt archives. The successful final log and receipt
are the authoritative final result.

## Reproduction inputs and boundaries

The official Linux archive used here was:

`https://download.zotero.org/client/release/10.0.8/Zotero-10.0.8_linux-x86_64.tar.xz`

Its SHA-256 was
`a704cfd49f5de65507910e0cada4acf72097572201b3576583f0a92a32c1032b`.
The archive identifies Zotero 10.0.8, build `20261106171756`.

The Chicago style is retained as
[chicago-notes-bibliography-subsequent-ibid.csl](chicago-notes-bibliography-subsequent-ibid.csl).
It was downloaded from the CSL styles repository at commit
`d16ba6427ca3c5dada6578a6f7a0f98bd3ea03b3`; its SHA-256 was
`39c868e65da74bff51f5be6cbaefc39f809841ab81758a378b883ef767eb500a`.
Its upstream licensing information remains inside the file.
[quds-synthetic-smallcaps.csl](quds-synthetic-smallcaps.csl) is the minimal style
written for this acceptance.

The scripts expect a workspace containing `quds_office_suite`,
`zotero-toolchain`, and a working copy of this directory named
`zotero-native-fidelity-acceptance`. Copy the evidence directory to that last
location before reproducing; its committed location is an archive, not the
runtime location. Restore the SDK/harness using the preceding continuation's
`setup/bootstrap-local-tests.sh`, download and extract the verified official
archive into `binary/`, and create fresh disposable `profile/`, `data/`, and
`tmp/` directories. The profile must enable the local API and select only this
new data directory. Disable automatic sync for the isolated test and connect
no account.

[bootstrap-headless.py](scripts/bootstrap-headless.py) contains the exact
synthetic book fixture and real connector save operation. Run it only on a
fresh disposable profile; it expects exactly three books afterward. The saved
search was inserted offline while Zotero was stopped, with key `QUDSABCD`,
name `Synthetic Alpha saved search`, local library ID 1, and condition
`title contains Alpha`. Its setup receipt is
[saved-search-fixture-receipt.json](logs/saved-search-fixture-receipt.json).
Only fixture construction touched the SQLite database; all final saved-search
listing and execution used the native local API through the actual client.

Copy both retained styles into that disposable data directory's `styles/`
folder. Use an actual graphical desktop session for this environment. Once
native CSL export is ready, run:

```bash
python3 /path/to/workspace/zotero-native-fidelity-acceptance/scripts/run-live-acceptance.py --desktop
```

The wrapper enforces bounded waits and refuses qualification if its source or
kernel changes. It overwrites current run logs; preserve a completed attempt
before rerunning. No binary, compiled kernel, database, full profile, private
account data, or credentials are included in this evidence archive.
