# Independent license and dependency continuity

The [receipt](receipt.json) compares previous proofing head
`62563c61f02ee44504776d9e7d26557f9bae490a` with qualified source
`3a2ada5a04395fd2fa01c7878f4df9f1b9215558`.

**All 107 protected existing inputs and all 14 dependency/toolchain manifests
are unchanged.** This includes the explicit Flutter pin, dictionaries,
hyphenation data, provenance and license files, generated German data,
optional German model resources, and the existing Harper dependency selections.
All 17 recorded German generated-file SHA-256 pins match.

The new `german_grammar.dart` source was independently inspected as a
first-party same-library part containing bounded rules and explicit ordinary
language paradigms. It introduces no imported grammar-rule corpus, model,
network service, or runtime dependency. Improvements to existing spelling,
hyphenation and language routing use the existing resources.

The Harper notice bundle was inspected rather than relying only on an unchanged
filename. Its **226 packages**, license selections, per-member hashes and
**three MPL source archives** passed verification. The MPL packages remain
`colored 3.1.1`, `cssparser 0.38.0` and `dtoa-short 0.3.5`. The policy's nine
selection/rejection controls passed, including rejection of GPL-, AGPL- and
LGPL-only expressions.

MPL-2.0 remains permitted under the existing non-GPL policy with its notice
and source-distribution obligations retained. It is not relabeled as a
permissive license. German dictionary/pattern inputs and GB patterns retain
their existing MIT terms; US patterns retain their reviewed permissive terms
and original notice. This is a scoped continuity review, not a new legal
certification of every inherited dependency.

To repeat the audit from a prepared repository checkout:

```sh
python3 docs/validation/proofing-grammar-expansion-20261117/license/audit_continuity.py \
  --repository . \
  --qualified 3a2ada5a04395fd2fa01c7878f4df9f1b9215558 \
  --output ../proofing-license-replay.json
```
