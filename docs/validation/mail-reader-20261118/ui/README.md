# Shared saved-message reader validation

The final native run passed **30 functional tests** across four files and **two visual fixtures** in a separate tool file. There were no failed or skipped tests. The release web application and independent browser network-guard helper compile successfully. **Browser runtime remains unqualified.** These results do not depend on GitHub Actions.

## Evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Functional reader and MIME example tests | 30 passed | `native-final-summary.json`, `native-final.jsonl` |
| Desktop and narrow enlarged RTL fixtures | 2 passed, captured and inspected | `screenshots/` |
| UI static analysis | No issues | `analyze-final.txt` |
| Browser guard helper compilation | Exit 0; no runtime execution | `browser-guard-compile-final.txt` |
| Release web compilation | Exit 0 | `web-build-final.txt`, `web-artifacts.json` |
| Final source identity and commands | Recorded | `source-hashes.json`, `receipt.json` |

The final native run includes the human-facing diagnostic banner and singular `1 match` text fixes. Earlier `native-attempt-1` evidence records the previous 30-test run; it is retained for traceability and is **not added** to the final test count. Framework-internal loading events in the JSON reporter are also excluded.

The functional cohort exercises hostile script/CSS/font/form/SVG/srcset/resource inputs, text/header/body/attachment/node/depth/pixel limits, raw and decoded source identity, read-only attachment identity, search and grapheme selection, link policy approval and stale-decision invalidation, rejection diagnostics, narrow RTL layout, and the real MIME example. Native network denial uses an `HttpOverrides` guard with an independent positive control, in addition to the injected host policy checks.

## Visual inspection

The desktop capture is 1100 × 850 at text scale 1. The preview capture is 390 × 844 with RTL direction and text scale 1.5. Both use the same original multipart MIME bytes, parsed by `QudsMimeCodec`. The PNGs come directly from a Flutter `RepaintBoundary` with local Latin/Arabic fonts and MaterialIcons; there is no image modification.

Desktop text, the selected search hit, diagnostics, source actions and read-only attachment cards are readable. Narrow RTL controls and message content wrap without a Flutter overflow or exception. The harness title ellipsizes at the narrow width, and the remaining body and attachment actions continue below the viewport in the scroll view. These are native widget captures, not browser screenshots or installed-device certification.

## Browser and offline boundaries

The example builds with `--no-web-resources-cdn`. The generated build configuration has `useLocalCanvasKit: true`, and the artifact inventory includes local CanvasKit JavaScript/Wasm and a Roboto fallback font. Its standard custom bootstrap explicitly sets same-origin `canvasKitBaseUrl` and `fontFallbackBaseUrl`, avoiding the engine's default third-party font fallback URL.

The flag does not package every Unicode font. A completed host must bundle/cache the fonts needed by its content and verify offline behavior. The native capture's local fonts do not prove that the example's browser font assets are complete. The build still reports a Cupertino font-family warning from Flutter icon tree shaking; the harness itself uses Material icons. No browser appearance or font-runtime pass is claimed.

The initial browser test attempt stopped at compilation errors in the test harness before browser execution. The example package import and JS interop signatures were corrected; the browser guard now compiles independently, and the final production web target compiles. A successful browser test execution remains outstanding because the environment cannot launch Chromium or reach the executor from the available cloud browser. See `../browser-limitations.md`. No launch was repeated after that boundary was established.

## Reproduction

With the repository's resolved workspace and recorded compatible Flutter SDK:

```sh
# Repository root:
dart analyze packages/quds_mail_ui

# packages/quds_mail_ui:
flutter --no-version-check --suppress-analytics test --no-pub --reporter json test tool/reader_visual_test.dart
dart compile js tool/web_guard_compile.dart -o /tmp/mail-runtime-guard.js

# packages/quds_mail_ui/example:
flutter --no-version-check --suppress-analytics build web --release --no-pub --no-web-resources-cdn
```

This environment invoked the installed Flutter tool snapshot using its bundled Dart executable and writable `TMPDIR`/`PUB_CACHE`; `receipt.json` records the actual command scope. Set `FLUTTER_ROOT` when running the visual fixture, which loads the SDK's local MaterialIcons file. Set `MAIL_READER_EVIDENCE` to an absolute output directory to capture the PNGs elsewhere.

CrispCloud route parity, installed native host behavior, mobile performance, complete multilingual offline browser behavior and App Store packaging remain separate integration and release checks.
