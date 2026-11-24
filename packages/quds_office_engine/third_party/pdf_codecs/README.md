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
existing host raster/Office paths. Mixed-mode CCITT Group 3 now shares the
corrected T.4/T.6 decoder with Group 4. Unknown row counts require the
RTC/EOFB marker unless EndOfBlock is false; known image heights accept
complete rows without a trailing marker. Uncompressed extensions and
DamagedRowsBeforeError recovery are not supported.

## Preliminary license and provenance review (2026-11-24)

The pinned pub.dev package metadata and published project documentation identify:

| Package | Declared terms | Upstream | Direct dependencies |
| --- | --- | --- | --- |
| j2k 1.0.0 | MIT plus JJ2000 notice/license | [insinfo/jpeg2000](https://github.com/insinfo/jpeg2000), JJ2000 | meta, web |
| jbig2 1.0.0 | Apache-2.0 | [insinfo/jbig2](https://github.com/insinfo/jbig2), Apache PDFBox JBIG2 ImageIO | logging |

Sources: [j2k license](https://pub.dev/packages/j2k/license),
[j2k origin and limitations](https://pub.dev/packages/j2k),
[jbig2 license](https://pub.dev/packages/jbig2/license),
[jbig2 origin and fixture provenance](https://pub.dev/packages/jbig2).

Do not import the upstream JBIG2 non-commercial ITU fixtures into the suite
or commercial distributions; the synthetic libtiff and OpenJPEG fixtures
used here have independent provenance. Both package publishers are unverified.
The JJ2000 license contains standard-conformance restrictions and patent
cautions; review their applicability to the actual distribution before
release. The upstream repository's moving main branch is not proof of the
contents of the pinned hosted archive.

The independent PDF codec CI job archives the exact resolved license and
notice files from the workspace package configuration and uploads the
generated root lockfile separately. Missing required notice files fail
qualification. Review those artifacts against the pinned versions, commit
the generated lockfile, and include the relevant license texts in the actual
release/installer notices. Collecting CI evidence alone is not legal approval
or full supply-chain/security qualification.

## Validation

Run from the workspace root:

    flutter pub get
    cd packages/quds_office_engine
    dart analyze --fatal-infos
    dart test test/pdf_filter_expansion_test.dart test/pdf_file_test.dart test/deflate_test.dart
    dart test test/pdf_ccitt_test.dart
    dart test --platform node test/pdf_filter_expansion_test.dart test/pdf_ccitt_test.dart

The added tests include independent OpenJPEG-generated synthetic RGB, gray
and RGBA fixtures and JBIG2 generic/symbol round-trips including a shared
global dictionary via indirect PDF DecodeParms. Round-trips are integration
tests, not independent JBIG2 conformance evidence. Full PDF rendering,
independent JBIG2 Huffman/refinement/halftone vectors, and VM/browser/Wasm
coverage must qualify the change before release.

The CCITT tests use original synthetic bilevel images independently encoded
with Pillow 12.3.0 / libtiff 4.7.1, using WhiteIsZero TIFF single-strip
payloads. They cover T4Options 0/1/5 and T.6, transitions at column zero,
long makeup runs, both polarities, EOL/RTC/EOFB, byte alignment, and invalid
streams. The code words are defined by ITU-T T.4 and T.6.
