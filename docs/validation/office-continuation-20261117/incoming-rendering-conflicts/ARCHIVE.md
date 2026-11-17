# Historical rendering evidence variants

These files preserve the ten conflicting evidence variants from incoming commit
`aff69c221f24d2bf9bcab7001f976ac085b4e841` byte for byte. Canonical records under
`docs/validation/text-rendering-continuation-20261116` retain the final qualification
from `51cc65f1`. No production source conflicted.

Incoming `source-binding.json`, `verify_binding.py` and `poppler-final` records
remain attributed to their original pinned source. Their hashes and path bindings
must be evaluated in that source checkout, not treated as a new qualification
of the merged tree. The complete original tree is retained by merge ancestry.

`conflict-resolution.json` identifies every retained and archived hash.
