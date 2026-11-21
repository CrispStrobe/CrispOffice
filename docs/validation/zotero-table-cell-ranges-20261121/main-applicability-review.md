# Independent review of later-main applicability

**Accepted for the precisely recorded delta.** The combined worktree preserves
the qualified Zotero implementation while incorporating main
`eb286fb7254d6850c9f33b46e8aa65e2ea32f7f0` (PR #290). This review does not replace
the original runtime qualification or assert the identity of a later remote
head.

The reviewer read `verify_main_applicability.py`, `main-applicability.json`, the
README's later-main section and the complete incoming screenshot-gate diff.
One independent verifier replay exited 0 with no stderr and reproduced the
recorded JSON exactly. The reviewed verifier SHA-256 is
`ccdb7dbde9c0007a8dcd826db9d21c83e8bb15baa664746f20f38611a2420dcc`;
the receipt SHA-256 is
`ab71b522f99b2f80c547fd3859864f40d419119e5efdca93cf0423b212dda577`.

The checks establish:

- Exactly seven files differ between the previous and incoming main: six
  documentation PNGs and the standalone `app_store_screenshots_gate.dart`.
  The combined worktree preserves all seven incoming blobs and executable
  modes exactly.
- Of the 2,978 frozen recorded inputs, 2,977 remain unchanged. The only
  exception is the named screenshot gate. This is explicitly a changed source
  map, not an assertion that all recorded inputs remain identical.
- All 119 selected suite files belong to the frozen source map and retain
  their exact source identities. The reviewer additionally checked each of
  these identities directly against the archived manifest. None of the eight
  archived execution commands includes the screenshot gate.
- All 356 recorded Node inputs remain unchanged and equal their corresponding
  frozen input hashes; the portable before/after maps agree.
- The gate's import/export/part declarations are unchanged, and no other
  recorded Dart/YAML source refers to it. The reviewed changes affect its
  screenshot fixtures, local native-host settling and capture helpers.
- The external qualification and selection JSON files exactly match their
  archived copies. The frozen 159-member archive remains unchanged at SHA-256
  `7605bf4f72509aa52d5544fcca515e0b15997679ecab0ddf717db2068ab83229`.

The original 2,551-case/119-suite qualification and overlapping 121-case Node
execution therefore remain applicable to the unchanged Zotero implementation.
They remain bound to the original qualified commit
`a6095c304ad2d6935f2ae6f8b74412038d19f142`. This acceptance claims neither a new
execution of the macOS screenshot gate nor a fresh full-population test run.
No product files or Git refs were changed by this review.
