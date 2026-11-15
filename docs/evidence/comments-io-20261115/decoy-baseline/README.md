# Relocated-comment deletion with a legacy decoy: failing baseline

Saved source: [`9d1f6755a21c5d9936fd89532a4ebdbb510e9a2d`](https://github.com/CrispStrobe/quds_office_suite/commit/9d1f6755a21c5d9936fd89532a4ebdbb510e9a2d).

Both targeted tests failed: clearing comments referenced by an authored relocated relationship removed that relationship, allowing an unrelated fixed-name comments part to become the legacy fallback. All three decoy notes appeared on the first serialized reopen. The same failure occurred when another worksheet still owned the relocated part. Source, package-resolution inputs, HEAD/tree and tool hashes remained unchanged.

The earlier 139-test result in `../accepted/` did not include this combined case. Its raw successful receipts remain intact; this additional failing baseline extends that evidence and does not replace it.

The tests retain decoy bytes and exercise three save/reopen cycles, including the other owner's text, author and target in the shared case. The correction retains an explicit, namespace-correct empty comments part only when unlinking would activate the unrelated legacy fallback. Existing copy-on-write handling prevents changes to the shared owner's content.

The archive includes the exact raw command, machine events, snapshots, tool hashes, runner and suite manifest. The independent schema proof validates `<comments xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><authors/><commentList/></comments>` against the official ECMA-376 Part 4 fifth-edition Transitional SpreadsheetML XSD. Both containers are required in order, but their children are optional; no placeholder author is needed. That proof covers this XML shape, not the whole workbook.

Every archive member and the complete inventory were verified against the saved manifest. No GitHub Actions result was awaited.
