# Word VBA AllCaps continuation — 21 November 2026

## Intake and scope

Work starts at `01517de8886ef7bd24947894be5dc823d0328869`, the remote
`main` merge of PR #310. The [initial intake](initial-intake.json) records all
27 pre-existing fork branches, the 100 recent PR heads (#211–#310), and four
upstream branches as ancestors of that baseline. There were no open PRs.
The new remote checkpoint branch is `codex/word-vba-formatting-20261121`.

The implementation adds the bounded Boolean `Font.AllCaps` setter through
the source adapter, native run formatting, DOCX import/export, layout and
editor model consumers. Capitalization is a display property; authored text
and source offsets stay intact. Setting AllCaps true clears SmallCaps, and
setting SmallCaps true clears AllCaps. False changes only the named flag.

The existing document-independent compiler, explicit paragraph/story
selectors, detached transaction, resource limits and opaque VBA-project
preservation remain the integration boundary. General Word automation,
property reads, numeric toggles and embedded VBA execution are outside this
increment.

## Checkpoint status

Initial intake and implementation checkpoints are saved. Source compilation,
native formatting, model import/export, Unicode display mapping, editor
regressions and CLI/MCP integration are implemented. Independent review found
and corrected an existing CSL small-capital interaction with inherited
AllCaps; plain spans keep host formatting and explicit small capitals clear
AllCaps sparsely. Targeted development checks pass. The complete source-bound
local gate is in progress; its commands, results and limits will follow here.

GitHub Actions, workflow runs and CI status queues are not queried or awaited.

## Primary contracts

- [Word Font.AllCaps](https://learn.microsoft.com/en-us/office/vba/api/word.font.allcaps)
- [Word Font.SmallCaps](https://learn.microsoft.com/en-us/office/vba/api/word.font.smallcaps)
- [WordprocessingML caps](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.caps)

The source dialect accepts actual Booleans, as for its existing font setters;
Microsoft's broader Long/toggle/read behavior is not claimed.
