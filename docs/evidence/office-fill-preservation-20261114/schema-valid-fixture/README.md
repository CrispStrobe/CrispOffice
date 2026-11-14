# Schema-valid native fill fixture

Canonical source `3543b29a2daa82279777802df8728d72dc96e9c5` corrects the authored
font-child order in `sheet-fill-native.xml`: size precedes color. All font values,
fill definitions and production code remain unchanged. The independent app
OpenXML check discovered this input-fixture error; all three initial saved
workbooks were already schema-valid. The app retains both the original failure
and the schema-valid diagnostic separately from actual host acceptance.

On the corrected source, all **five engine fill tests and six editor fill/history
tests passed**. All 402 captured inputs stayed unchanged. Compared with the
previous combined gate, the fixture is the only changed shared input; all 385
production Dart files are byte-identical. The earlier 60-test result keeps its
original measured source and scope. These repeated fill tests are not additional
unique cases to add to that count.

`completion.json` records the source comparison and hashes nine companion
artifacts. Commands, complete logs, exact input hashes and resolved dependency
snapshots are retained here. The collector records its original workspace layout;
place this directory beside `quds_office_suite` and `toolchain` to reuse that layout.
