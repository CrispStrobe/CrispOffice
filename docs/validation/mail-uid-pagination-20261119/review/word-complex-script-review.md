# Independent Word language and download-cancellation review

## Result and source boundary

The Word language changes reviewed at `9b123dde85dd5679aa4ab11d44a77a76dbf43042`, with the `rtl`/`cs` inheritance repair at `d420c1474d859e51abf22ebf88c55f9d255633b1`, have no remaining blocking review findings. The exact final file hashes appear below and in [the machine-readable receipt](word-complex-script-review.json). This is a bounded independent review and focused author verification; the combined repository qualification is recorded separately.

The independent review checked that the Unicode detector requires an Arabic or Hebrew **letter**, including presentation and supplementary forms. Digits, punctuation, marks, and the byte-order mark do not independently choose the complex-script language. Selecting a language updates both run-language attributes, and resetting it restores style/document inheritance. The lower-level clear API retains its previous Latin-only default unless the caller explicitly requests complex-script clearing. Sparse XML updates own `val` and `bidi` separately and retain East Asian language and unrelated native formatting. Document defaults remain live for routing, and captured editor targets bind both defaults plus relevant run state.

## Reproduced defect and repair

The review found that the style cascade retained a lower `w:val="0"` when a higher direct property used an empty, default-on `<w:rtl/>` or `<w:cs/>`. An independent import probe using Latin text, `w:lang/@w:val="en-US"`, and `w:bidi="ar-SA"` observed `complex=false` and `en-US` for both cases, although the direct marker required complex-script routing.

The repair extends the cascade's existing explicit default-on handling for `noProof` to `rtl` and `cs`. Eight controls cover each marker, both inherited states, direct default-on and explicit-off states, and save/reopen. The author's pre-repair regression run recorded **two failures and six passes** before the repair. Its final engine run recorded **41 passes, zero failures, zero skips**. The reviewer inspected those raw JSON results and independently reran the same two-case observation after repair; both returned `complex=true` and `ar-SA`.

The [indexed evidence archive](word-complex-script-evidence-index.json) retains the author's failing and passing reports, source bindings, and the independent probe/green observation. The author executed the full engine suite; the reviewer executed only the two-case probe. No browser execution is established by this evidence.

## Cancellation review and retained first attempt

Download cancellation is implemented in `99cd4598409bdc20779f44adaf53284de56cabd3`. The [author receipt](hunspell-cancellation-author.json) binds all six changed source/test files. The [independent cancellation receipt](hunspell-cancellation-independent-review.json), authored by the other reviewer, confirms those hashes and records no blocking finding.

Native cancellation closes the active `HttpClient` forcefully. The web host supplies an `AbortableRequest` trigger so cancellation reaches a streamed body after headers have completed. Both paths check cancellation at admission and before publication and remove registered listeners after completion. The final focused results are **four native cases and four Flutter-VM web-host cases**, each with zero failures/skips; strict analysis, formatting, and whitespace checks also passed.

The first native attempt recorded three passes and one timeout: the loopback fixture buffered its partial response body, so it never reached the intended cancellation point. The fixture now disables response buffering and cancels pending work during teardown. The [cancellation archive index](hunspell-cancellation-author-index.json) retains that failed run separately from the final passing run, alongside raw logs, the receipt, and analysis/format output.

These tests establish Linux loopback cancellation and the web host's abortable HTTP contract on Flutter VM. They do not establish browser/Worker/Wasm execution. Cancellation is checked before native atomic publication and web verified-byte publication; filesystem commit semantics were not expanded.

## Scope retained

The shared agreeing-finding merge policy is unchanged; transitive suggestion coalescing was not treated as an independently established defect. The document complex-script default remains the explicitly documented imported routing metadata; this repair does not add a new default-language persistence API. No GitHub Actions workflow, job, status, or queue was queried or awaited.

## Exact final Word hashes

| File | SHA-256 |
| --- | --- |
| `packages/quds_office_engine/lib/src/word/model/word_proofing_language.dart` | `a3a5727dd3db23baf186c4d83963982d47261532eb5512eb2539774ab00d10a0` |
| `packages/quds_office_engine/lib/src/word/properties/wml_properties.dart` | `2b43064fa36abfbf7a32ef737fcdc6f99b821d36eeafb1b3f59c2d69146ecb43` |
| `packages/quds_office_engine/lib/src/word/serial/word_deserializer.dart` | `8a4046231f9ae23167936d2c375a7bac1b3f1e00dec8e42afd031c2c62ff909d` |
| `packages/quds_office_engine/lib/src/word/serial/word_property_io.dart` | `e2f4698b0e837ce455c3935d10be87a6a02276278efad9bf1bc01760ef634f7b` |
| `packages/quds_office_engine/lib/src/word/serial/word_serializer.dart` | `fc6be4341183f9e7a9d27708f293ba4ab7f67d330aff25863fbbafe7408c0db8` |
| `packages/quds_office_engine/lib/src/word/serial/word_style_cascade.dart` | `f51f466e6247aeb184a65e75642a1ee87a25ebd012ac325f408ab904c9636b70` |
| `packages/quds_office_editor/lib/src/embed/office_controller.dart` | `e2cbe6411ea7b3c06480f9eace9af8ccbf2896d8f569b9d5d6394283fb63ddca` |
| `packages/quds_office_engine/test/proofing/word_proofing_language_test.dart` | `26c078780cc05e565e13728857dedce774a4863e02893b0de524da2cb0300863` |
| `packages/quds_office_editor/test/word_text_proofing_controls_test.dart` | `75192a259587a6304fad4540a70bab5b3cbb8defef66df45e84bde18720622c8` |
