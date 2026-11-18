# Rejected editor attempt at frozen product f57fde45

The complete machine stream contains 215 substantive tests: 214 successes and one error. The final event reports `success: false`. The failing existing pagination case could not activate the offscreen Next page control and therefore could not find the second source. All source, dependency, runtime and workspace guards remained unchanged. This run is rejected and excluded from accepted final counts.

The runner also failed during summarization because Flutter emits JSON arrays for machine infrastructure events as well as individual Dart test event objects. The exact failed runner is retained. A separate replay handles arrays and blank lines and reconstructs test counts and guards from the complete retained data. The Python process exited 1; the Flutter child exit was not written before the parser error and is deliberately left unknown. No successful process-exit claim is reconstructed.

The correction is confined to evidence handling: retain the child exit immediately, preserve machine array envelopes separately, and ignore empty lines. A fresh accepted product run follows only after the pagination regression is resolved and the source is frozen again.
