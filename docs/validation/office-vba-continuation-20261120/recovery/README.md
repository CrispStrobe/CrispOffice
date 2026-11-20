> Historical snapshot, superseded by the [completed local qualification](../README.md).
> The blocked status and completion checklist below describe that earlier checkpoint.

# Word and PowerPoint VBA continuation — recovery checkpoint

## Status

The incoming work is integrated and preserved, and the new source implementation is saved as work in progress. This checkpoint is **not accepted final validation** and has **not been merged into main**.

The local filesystem exhausted available space. The sandbox launcher then failed before every command with `bwrap: Can't create file /workspace/scratch/86ea302351d7/.git: No space left on device`. The configured environment disallows escalated commands, so the attempted task-cache cleanup outside the sandbox was rejected. The computer recovery interface was also unavailable. No GitHub Actions were queried or awaited.

## Preserved incoming work

Starting main: `d040c15a07f652d01e75363031d0efdee6357bda`.

| Incoming branch head | Retained remote integration commit |
| --- | --- |
| Typing/proofing `afa9272a6e31e2cbd6b9896c450a7bccfd62c579` | `6b9ca183d5d7370c6fa14d453f00ac28508e20d3` |
| Mail/presentation `1d26181b0161d88abe5977f9848ffd4cd99e6259` | `4f311d42df1748128f0e4e76b32f427287ec281f` |
| Zotero evidence `40a8f8eb76bd9bf51205fa0cb9f576ba497ad76b` | `9aa177ba9abeae7179edd517da8924f16c4c78f4` |

The complete intake evidence was saved at `dd415bfef2381c57c0a5b0e157056804b4d674da`. All 239 fetched PR heads are covered by 225 ancestors and 14 independently verified historical equivalents. The 23 branch refs (including this continuation) are covered by 14 ancestors and 9 equivalents. The 4 known upstream heads were already ancestors of the starting main. Counts describe the captured snapshot, not a continuously refreshed remote.

## Implemented source work

Word: explicit ActiveDocument/Application.ActiveDocument aliases, Paragraphs.Item, Font.SmallCaps, Font.Superscript/Subscript, and Range.HighlightColorIndex with the 17 fixed palette/removal values. Source remains a bounded write-only plan, using existing detached transactions.

PowerPoint: typed TextFrame/Font/ParagraphFormat/SlideShowTransition bindings, vertical anchors top/middle/bottom, slide visibility, advance-on-click, exact millisecond duration, and 11 supported transition effect enum values. Transition import provenance and per-property writing preserve unrelated sound/effect/extension data. Broad fill/line editing was deferred because the current model cannot preserve the required native paint provenance.

## Development evidence and its limits

The Word typography compiler suite passed 48 cases with exit 0; its native integration suite passed 25 cases with exit 0. These are development runs against the then-current source, not final frozen-source qualification. The legacy Word suite reported 156 passing cases but exited 255 while writing its test-kernel cache; that run is explicitly rejected as acceptance evidence. The earlier combined 229-case run failed similarly during cleanup and is also excluded.

No completed PowerPoint native gate, strict final analysis, final CLI run, or final VM/JavaScript comparison is claimed. No Flutter/native application or Microsoft Office host was run.

## Required completion work

1. Restore a working filesystem with sufficient room for Dart compiler/test caches. Use the repository's pinned/previously qualified Dart 3.13.7 environment or its normal Flutter workspace. The official Linux x64 SDK archive used here had SHA-256 `eb99aed266efbcb615c6ae21c12f52cfe935b9f208bccc5fea7f64c21e867229`; all 56 shared resolved dependency versions matched the repository lock.
2. Apply namespace-qualified XML attribute changes and collision regressions. `XmlElement.setAttribute` without a namespace can match unrelated extension attributes by local name. Preserve extension attributes while writing native Word/PPT attributes.
3. Make source-null authored Word runs serialize explicit baseline vertical alignment and explicit no-highlight, so inherited styles do not reappear on save.
4. Finish and run PowerPoint compiler/native fixtures, docs, and a runnable example. Check no-effect durations, unknown effects/sound/extensions, empty text frames, same-value writes, target guards, permissions, and late rollback.
5. Format and analyze the exact combined source. Run the changed/new suites, affected native XML suites and existing shared compiler regressions, then actual CLI and VM/compiled-JavaScript checks. Record exit codes and source hashes. Avoid parallel test compiler caches in a constrained workspace; retain failed attempts separately.
6. Refresh main and all live relevant refs, reconcile new work, run affected local checks, and merge the qualified branch into remote main with an expected-head update. Verify the final main tree equals the tested branch tree and retain this checkpoint branch.

The accompanying recovery files distinguish exact recreated blobs from pre-formatter source reconstructed through exact successful patch inputs. Pending changes are explicitly identified; no reconstruction is presented as a passed test.
