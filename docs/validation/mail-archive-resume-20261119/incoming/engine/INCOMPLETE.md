# Incomplete plain Dart CLI startup

The initial plain `dart test` invocation emitted no test events while resolving implicit dependency/build hooks in the full Flutter workspace. It was interrupted with exit 130. No test counts from this attempt are accepted. Independent analysis/format/JavaScript logs remain preserved, but final qualification is rerun with the explicit installed test entrypoint.
