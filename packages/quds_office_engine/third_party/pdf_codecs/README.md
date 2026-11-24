# PDF codec dependency qualification

This branch pins two pure-Dart dependencies (no native library or browser plugin):

- [jbig2 1.0.0](https://pub.dev/packages/jbig2/versions/1.0.0), Apache-2.0,
  derived in part from Apache PDFBox JBIG2 ImageIO. Preserve its LICENSE and NOTICE
  in binary distributions.
- [j2k 1.0.0](https://pub.dev/packages/j2k/versions/1.0.0), MIT plus the
  upstream JJ2000 license/notice. Preserve both notices; review the JJ2000
  conformance and patent language before shipping.

Both packages are new and have unverified pub.dev publishers. Review pinned
package source, dependency hashes, allocation and CPU limits, and the complete
license/NOTICE payload before accepting them for a production release. Run
workspace resolution and commit the generated root pubspec.lock; do not
fabricate hosted archive hashes.

The adapter limits each compressed codec input (including JBIG2 globals) to
16 MiB and sets decoder limits of 8192 pixels per dimension and 16 Mi pixels
per image. These are not a guarantee against every decompression bomb;
independent malformed-input and aggregate resource-budget testing remain
release gates.

JPX supports common Part 1 JP2 and raw J2K device-color XObjects. Non-device
PDF color spaces, JPX image stencils, complex Part 2 extensions and HTJ2K are
not claimed. Color management and CMYK accuracy remain bounded by the existing
device-color approximation. JPEG is still deliberately passed through to
existing host raster/Office paths; mixed-mode CCITT is not addressed here.

## Validation

Run from the workspace root:

    flutter pub get
    cd packages/quds_office_engine
    dart analyze --fatal-infos
    dart test test/pdf_filter_expansion_test.dart test/pdf_file_test.dart test/deflate_test.dart
    dart test --platform node test/pdf_filter_expansion_test.dart

The added tests include independent OpenJPEG-generated synthetic RGB, gray
and RGBA fixtures and JBIG2 generic/symbol round-trips including a shared
global dictionary via indirect PDF DecodeParms. Round-trips are integration
tests, not independent JBIG2 conformance evidence. Full PDF rendering,
independent JBIG2 Huffman/refinement/halftone vectors, and VM/browser/Wasm
coverage must qualify the change before release.
