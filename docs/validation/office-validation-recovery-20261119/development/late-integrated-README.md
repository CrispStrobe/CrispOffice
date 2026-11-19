# Later integrated development and Arabic preparation

This archive preserves every file in the completed Arabic native development,
merged language preflight and offline dependency refresh directories, plus the
pinned Arabic build source/native outputs, build and preparation receipts,
model manifest/notices and current runtime binding/configuration.

The two language engine suites passed 36 cases after calibration reconciliation.
An initial adapter preflight failed because a four-candidate rejection fixture
implicitly used the old default topK3; the incoming calibrated default is5. The
fixture now explicitly requests topK3. The full corrected adapter run passed
26 cases. Both original reporters remain unchanged.

The Arabic baseline normal-dispose test failed with a retained database mapping.
The fixed complete local native suite passed17 cases, with zero failures/skips
and identical source hashes throughout. The live-download test was preserved
byte-for-byte in a separate explicitly optional suite.

All of these are development observations on working source, not an accepted
frozen aggregate. The exact command/source receipts remain authoritative.

The12,166,992-byte public database itself is omitted, as are the previously
omitted SDK/cache trees. Its immutable URL, exact size/hash and successful
download verification are recorded in the catalog and preparation receipt;
prepare_arabic_morph.py reproduces it. No authored source, raw log or receipt
inside the declared captured source directories is omitted.

Verify every indexed member and reconstruct the archive with
archive_development.py verify --index late-integrated-evidence.index.json.
The committed index and verification receipt give full counts and hashes.
