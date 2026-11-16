# Bounded noProof cascade control

The primary proofing source
`f4d52e5b0f04aa0a57cef2074f0b5ee3d2868f48` still retained a lower layer's
explicit `w:noProof w:val="0"` when a higher-priority run supplied
`<w:noProof/>`. The omitted on/off value must enable noProof.

The exact four-test fixture from alternate tip
`ca294cf8668706b45f40031ed9a2db52e5737cd2` was copied into the genuine engine
harness. The existing primary cascade compiled successfully and produced
**3 behavioral failures and 1 pass**: the last run was `noProof=false` instead
of `true` on initial import, after DOCX save/reload, and after document-language
refresh. The style-refresh control passed already.

Only the incoming **12-line normalization guard** was applied to
`packages/quds_office_engine/lib/src/word/serial/word_style_cascade.dart`.
The follow-up run passed **all 4 new tests plus 15 existing style/layout tests**,
for **19 passing tests**. This bounded control is separate from final
combined-source qualification; its counts must not be added again.

The measured before cascade exactly matches primary blob
`caf96b49dc2ad56ca8eab57cc7fb33f5378a6739`. The after cascade exactly matches
the incoming file, and the fixture bytes remain identical to incoming test
blob `41fe56ccc9e6afbea44814a29539d235d5c32374`. `receipt.json` records those
identities, SHA-256 values, exact commands, exits and log hashes. Genuine
harness manifests, lockfile and package configuration remain unchanged.

`word_style_cascade.before.dart`, `word_style_cascade.after.dart`,
`word_comment_proofing_styles_test.dart` and `no-proof.patch` preserve the
measured inputs and narrow change. No alternate session architecture or
unrelated style changes were imported. These controls ran during the pending
integration merge, so the receipt describes the bounded engine inputs rather
than asserting a final combined-source commit.

The runtime is the existing genuine Flutter 3.47.8 / Dart 3.13.7 engine harness.
No production dependencies were changed, no commits were created, and no
GitHub Actions or CI status checks were used.
