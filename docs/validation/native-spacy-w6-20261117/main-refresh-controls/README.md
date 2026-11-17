# Latest Office main integration controls

The incoming main `23f3b4204fce45d38a103e3159bdc7f1e8d37c4e` contains calendar-relative
sheet conditions (#151) and Office reconciliation/frame-bookmark coverage
(#152). All **17** incoming Office source/test/changelog paths match that main
in both the merged index and working tree. The ODT writer already matches the
feature branch exactly: automatic frame styles reference the common
`QudsTextFrame` graphic parent. No conflicting frame-style resolution was needed.

The focused merged-source run passes **265 engine tests** across calendar
serialization, conditional rendering, frame common styles, inline/complex
fields and section fidelity, plus **2 Studio widget tests**. All 17 paths and
the lock remain unchanged during this run.

A separate bounded calendar-boundary probe exposes a defect in the newly
incoming calendar-relative rule implementation. Its twelve unchanged cases
pass in UTC, but one fails in Europe/Berlin and seven fail in
America/Los_Angeles. The implementation compares UTC spreadsheet dates with
local-time day/week boundaries. Consequently, `last7Days` can omit a valid
endpoint, and week rules can shift a Sunday endpoint in negative-offset zones.

The complete initial [receipt](first.json), probe source and three outputs are
retained. That receipt remains **failed** because of these confirmed calendar
results; the successful ordinary suites do not hide the defect. The subsequent
minimal repair and successful same-probe replays are recorded separately in
[calendar-repair](../calendar-repair/README.md). No grammar qualification panel
or native acceptance input was read, and no GitHub Actions endpoint was queried.
