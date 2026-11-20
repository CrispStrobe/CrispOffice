# Mail reply and forwarding continuation — 2026-11-20

## Scope

Complete the existing reply/forward workflow without changing account catalogs or connection ownership: inert text quotes for HTML-only mail, plus an explicit forward-with-attachments action with all-or-none attachment admission. Preserve plain-text preference, Bcc privacy, reply threading, draft recovery, uncertain-submission guards and composer limits.

## Intake

`intake.json` records all 19 observed remote branch heads. Work starts at `f7bf155337b0ba77dc20c6be548ef38ac06c5c65`, the published integration of current main, latest Downloads refinements and the published account identity/ownership guards. Older ODS/Office heads have equivalent incorporated commits recorded in the existing account intake; they must not be reapplied over current files. The concurrent account and credential lanes retain ownership of their changes.

## Validation status

At intake, the local clone ran out of disk space and the executor could no longer start its sandbox. A scoped cleanup request was rejected by the environment's approval policy. GitHub read/write operations remain usable. No new implementation test results are claimed. This record will be updated with the exact verification performed before merge. GitHub Actions will not be awaited.
