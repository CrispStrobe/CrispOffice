# German core validation after recovery

The existing local verifier completed successfully against the resumed source:

```sh
python3 packages/quds_office_engine/tool/proofing/verify_german.py \
  --download-wordlist \
  --output docs/validation/proofing-20261116/german-resume
```

| Check | Observed result |
| --- | --- |
| Focused Dart static analysis | Passed with `--fatal-infos`, no issues |
| Shared proofing, German spelling, writing rules and terminology tests | 38 passed |
| Pinned dictionary regeneration | All 18 generated files matched byte for byte |
| Compiled Dart JavaScript executed with Node | 10 checks passed |
| Source stability | All 36 recorded source/configuration/data files unchanged during validation |

The wordlist was freshly downloaded from its immutable upstream revision and
verified against SHA-256
`55b457fac8e322146853f45bbda59046a55496a3e3deb32d3a88feb908eca243`.
No fallback to an earlier receipt was needed.

The JavaScript checks use the actual generated German dictionary and rules.
They cover source UTF-16 offsets after an emoji, decomposed umlauts, Swiss
variants, all-capitals sharp-s, rejection of obsolete orthography, soft-hyphen
lookup without source changes, a limited grammar rule, personal vocabulary,
and disposed-provider availability. This is Node execution of compiled Dart;
browser hosting and editor geometry are covered separately.

`receipt.json` records exact commands, log hashes, source hashes, the compiled
JavaScript hash, and successful source-stability verification. The existing
experimental German model evaluation was not rerun or enabled by this check.
