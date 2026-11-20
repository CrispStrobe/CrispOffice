# Subsequent main refresh: macOS pinned-library preservation

Main commit `3e5f44ae14926b8054b2e5c0558ce71477891a33` merged PR #228
while the mail evidence was being prepared. It is retained by local source
`f8f36eb87b051a0b26ee68747dfd24c4717eaec1`, tree
`26f0d546e9d6ef29a3ab90ea0081425cba13c1d4`.

Relative to the previous qualified checkpoint, only the macOS build script,
release documentation and four Dart documentation-comment lines changed. All
executable Dart bytes and package configuration remain unchanged. The weekly
workflow and its earlier portability correction were already included.

The build-script change preserves the downloaded pinned spaCy library bytes in
ad hoc mode after strict signature verification. Release signing retains the
code-identity gate and uses the stripped-byte cross-check when the local
`codesign` reproduces the recorded reference. Rebuilt libraries remain
unqualified for grammar suggestions.

The complete Studio pin test passed **one case**, with all original strict
selection, completion and input guards. That test reads the build script's six
pin assignments; all six retain the same values. The fresh run replaces the
same already-counted case and **does not increase the 2,049 application total**.

`bash -n` passed. Eight controlled Linux scenarios execute the exact changed
Bash blocks using explicit external signing/digest stubs. They cover pinned
byte preservation, release acceptance, code or normalized-strip drift refusal,
invalid signature refusal and unqualified rebuild behavior. These are scoped
script controls, not additional application cases and not a native macOS
build, signature or release qualification.

`receipt.json` summarizes the refresh. `pin-test/` retains the fresh event
stream, selection and complete input manifests. `script-checks/` exposes the
script, input and comment-only proof receipts; its indexed archive preserves
all extracted blocks, raw command output, synthetic fixture bytes and case
receipts. `restore_evidence.py` in the parent directory restores the original
`macos-portability-refresh/` layout for independent audit replay.
