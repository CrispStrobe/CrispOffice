# Roadmap

This is the current direction, not a release promise. Completed wave history
and detailed acceptance notes are preserved in
[the 2026-11 roadmap archive](roadmap-details-2026-11.md).

## Now

| Workstream | Current focus |
| --- | --- |
| **Mail** | Live-provider qualification for native IMAP, EWS, Gmail and Microsoft 365; encrypted/local store parity; unified cached search and conversation indexing |
| **Proofing** | Installed-desktop and browser acceptance for thesaurus, Arabic providers and optional native models; broader German/English quality review |
| **Office fidelity** | Close documented ODF and legacy gaps; preserve unknown structures only where the model supports them; keep vendor comparisons reproducible |
| **Typing performance** | Keep layout, selection, proofing and paint work bounded during active typing; validate release/AOT builds on real documents |
| **Zotero** | Installed Zotero/Word interop, ODT edge cases and bibliography layout regressions |
| **Verification** | Turn local feature tests into exact-head hosted, installed and live-provider evidence where the claim requires it |

## Next

- Complete durable Mail body retention and account-wide indexed search.
- Finish browser persistence, quota and Web Locks acceptance for the Mail store.
- Expand Office preservation tests for real-world DOCX/XLSX/PPTX packages.
- Add mobile and accessibility acceptance for the shared editor surfaces.
- Reduce the remaining VBA parity gaps without claiming the full object model.
- Publish reproducible desktop builds for Report Studio and CrispOffice Studio.

## Later

- Calendar and People as shared modules beside Mail.
- Deeper ODF authoring profiles and explicitly bounded round-tripping.
- More offline language packs, with separate data licences and verification.
- Report/export parity across PDF, XLSX and DOCX for charts and shapes.
- Broader desktop automation while keeping macro execution inert by default.

## Product boundaries

- The engine remains pure Dart with no Flutter or `dart:ui` dependency.
- Editor document surfaces remain custom `RenderBox` canvases, not text-widget
  stacks.
- Macro and ActiveX payloads are never executed implicitly.
- ODF, legacy and unknown OOXML constructs are not silently rewritten into a
  false fidelity claim.
- Host chrome, storage, networking and platform integration stay outside the
  engine packages.

## Waves already delivered

| Wave | Result |
| --- | --- |
| 1 | PDF correctness and print fidelity |
| 2 | Word depth: styles, sections, notes, review, fields |
| 3 | Excel and PowerPoint print paths |
| 4 | Platform foundations, isolates and packaging |
| 5+ | PDF file program, reports, Mail, proofing and editor depth |

## Tracking

- [Standards coverage](STANDARDS.md)
- [Mission](MISSION.md)
- [Office remaining gaps](office-remaining-gaps.md)
- [Proofing](PROOFING.md)
- [Mail status](roadmaps/mail/status.md)
- [VBA parity](VBA_PARITY_ROADMAP.md)
- [Typing/autocorrect performance](roadmaps/typing-autocorrect-performance.md)

Dates and completion markers in archived plans are historical. Verify the
implementation and tests before treating an item as shipped.
