# Integration decisions

## Captured main — `388bd7451067794b58276d174fe05470aa9994ed`

Merged the captured main, including PR #115 table borders/row heights, PR #118
paragraph tabs, and the newer bounded German noun-agreement source, evaluator
tools and source-bound syntax evidence. The merge retained the recovered PAGE,
paragraph-color validation and structured-frame code automatically.

## Parallel Office qualification — `7a9702c3b74e0e905c76fcf467d608bbb852d004`

The paragraph-style conflict was resolved using the already integrated writer:
its strict six-digit color validation, PAGE fixes and newer tab/table support
remain. The incoming color-key implementation is weaker and is superseded by
the recovered normalized identity; it adds no distinct supported behavior.

Both original paragraph-decoration regression suites remain executable. The
20-case recovered suite keeps its path. The incoming two-case suite is retained
byte-for-byte as `test/odt_paragraph_decoration_resume_test.dart` within the
engine package to resolve an add/add path collision.

The section-test conflict differed only in explanatory wording; the recovered
wording and equivalent empty-body assertion remain. The `const` correction is
already present. The incoming qualification documentation, archives and
changelog entries remain, with their original source and runtime attribution.
Historical passes do not qualify this new combined source.
