# Initial integrated style-API test attempt

Source: `0afbb178076ea6b081fd82fabbb8cdf974cca802`.

This attempt completed with 96 passes and four test-fixture assertion failures.
All 409 inputs remained unchanged; there was no compilation failure. The four
owner/range cases assigned a formula while leaving its model type as `number`,
then captured their expected state before recalculation. The existing grid
command correctly recalculates that cell as a formula. The initial expected
state therefore disagreed with the fixture's normalized state before any history
assertion was reached. These four failures are not product-failure witnesses.

The correction adds `controller.recalculateWorkbook()` before capturing that
fixture's initial state. Production code is unchanged. The complete original
attempt, exact test bytes, input hashes and logs are retained here; correction
metadata and the one-line patch are in the parent directory. The corrected
100-test run will be captured separately.
