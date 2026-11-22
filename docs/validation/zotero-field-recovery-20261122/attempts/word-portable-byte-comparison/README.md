# Retained portable comparison attempt

The original workflow at source `6ba219a03a9933eded77980f9d7cdbd118183ee1`
compared the BAS smoke results byte for byte. Both the Dart VM and JavaScript
execution succeeded, but `cmp` failed because five paragraph spacing values
serialized as floating-point spellings on VM and integral spellings on JS.
`comparison-diagnosis.json` records those five paths and verifies parsed JSON
equality. No semantic value differs. The raw 956-byte VM and 946-byte JS outputs
are retained alongside the original failed receipt and logs.

Concurrent Word commit `45a1c0846f3fb78a203f2967e5b80a79fdca2ca9` changed the
workflow smoke assertion to parsed JSON equality without changing production
or test source. The later accepted portable gate uses that exact correction.
The canonical conformance route retains its bytewise comparison.
