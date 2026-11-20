# macOS signing and release (CrispOffice)

How the Studio macOS app (`packages/quds_office_editor/example`, product
`quds_office_studio`, brand CrispOffice) is signed for the Mac App Store and
for direct download, and how the spaCy grammar qualification survives
re-signing. Private values (team, key and certificate identifiers, keychain
passwords, contact data) are deliberately not recorded here; they live in the
maintainer's private release notes and in repository secrets referenced by
name below.

## Build modes

`packages/quds_office_editor/example/tool/build_macos_app.sh [--sign MODE]
[--rebuild-spacy] [flutter build arguments]`

| Mode | Identity | Output | Bundle id |
|------|----------|--------|-----------|
| `adhoc` (default) | ad hoc (`-`) | `build/macos/Build/Products/Release/quds_office_studio.app` | unchanged (`com.quds.qudsOfficeStudio`) |
| `appstore` | Apple Distribution + Mac Installer Distribution | `build/macos/signed/CrispOffice.app` and `CrispOffice-<version>-<build>.pkg` | `com.crispstrobe.crispoffice` |
| `developer-id` | Developer ID Application | notarized, stapled `build/macos/signed/CrispOffice.app` and `CrispOffice-<version>-<build>-macos.zip` | `com.crispstrobe.crispoffice` |

Every mode builds the same native libraries and installs the same pinned
spaCy library. Signed modes copy the built app to `QUDS_SIGN_OUTPUT`
(default `build/macos/signed`), rename it `CrispOffice.app`, set the bundle id,
embed the provisioning profile and sign inside out: each dylib, each
framework, then the app with `Release.entitlements` plus
`com.apple.application-identifier` and `com.apple.developer.team-identifier`
taken from the profile. Hardened runtime and secure timestamps are on in both
signed modes; App Sandbox stays on in every mode.

Pass `--build-name X.Y.Z --build-number N` through to Flutter for releases. App
Store Connect rejects a repeated `CFBundleVersion` and a repeated
`CFBundleShortVersionString` after a version has been released.

### Environment

| Variable | Modes | Meaning |
|----------|-------|---------|
| `QUDS_PROVISIONING_PROFILE` | signed | Path to the Mac App Store profile (appstore) or Developer ID profile (developer-id) for the bundle id. Required: the data-protection keychain used for mail credentials needs the application identifier, which only a profile authorizes. The script checks that the profile names this bundle id and includes the signing certificate. |
| `QUDS_SIGN_IDENTITY` | signed | SHA-1 or full name of the code-signing identity. Default: the single valid `Apple Distribution: …` / `Developer ID Application: …` identity on the keychain search list (the script fails when there are several). |
| `QUDS_INSTALLER_IDENTITY` | appstore | SHA-1 or full name of the installer identity (`3rd Party Mac Developer Installer: …` / `Mac Installer Distribution: …`). Set it when several are listed; a stale one in the login keychain is a common cause of ambiguity. |
| `QUDS_SIGN_KEYCHAIN` | signed | Limit identity lookup to this keychain (it must also be on the user search list; `codesign` searches only there). |
| `QUDS_BUNDLE_ID` | signed | Default `com.crispstrobe.crispoffice`. |
| `QUDS_APP_NAME` | signed | Default `CrispOffice` (name of the signed `.app` and its archives). |
| `QUDS_SIGN_OUTPUT` | signed | Output directory. |
| `QUDS_NOTARY_KEY`, `QUDS_NOTARY_KEY_ID`, `QUDS_NOTARY_ISSUER` | developer-id | App Store Connect API key file (`.p8`), key id and issuer id for `notarytool`. |
| `QUDS_NOTARIZE=0` | developer-id | Sign only; skip notarization and stapling. |

## spaCy qualification across signatures

The manual German grammar provider is qualified for one exact build of
`libcrispembed-spacy.dylib` (macOS arm64, ad hoc signed, SHA-256
`ccc96620…1b40f`, Hub revision `2aa70083…`). A release signature rewrites the
end of the file, so the file digest necessarily changes. The scheme keeps the
qualification bound to the code that was qualified, not to a signature:

1. **Code identity.** `machOCodeSha256` (`quds_proofing_spacy`,
   `lib/src/macho_code_identity.dart`) is SHA-256 over the file prefix up to
   the code signature (`LC_CODE_SIGNATURE.dataoff`) with exactly three fields
   zeroed: the signature's `datasize` and the `__LINKEDIT` `vmsize` and
   `filesize`. Everything dyld maps, binds or executes is covered. A file is
   rejected (no code identity) unless it is a thin 64-bit Mach-O with one
   signature that ends the file and one `__LINKEDIT` that ends with it, so
   nothing can hide behind the mask. Measured: the ad hoc qualified file, an
   Apple Distribution copy and a Developer ID copy (with secure timestamp) all
   give `f2022b1c…07efeb`; changing one code byte changes it.
2. **Apple's tool agrees.** `codesign --remove-signature` of the qualified file
   and of every re-signed copy yields identical bytes (with Xcode 26: 2,300,136
   bytes, SHA-256 `f62d2a0c…886ed2`). The stripped form depends on the
   codesign version (Xcode 16 on the CI runner produces other bytes), so the
   build compares input and output under the same tool rather than against
   that constant.
3. **Build-time proof.** `build_macos_app.sh` checks the code digest of the
   pinned input before signing (after verifying its SHA-256 and length) and of
   the signed output, requires the signed output to strip to exactly the
   pinned input's stripped bytes, and refuses to record the library as
   qualified otherwise. It writes `sha256` and `code_sha256` into
   `Contents/Resources/spacy-native.json`, which the app signature seals.
4. **Runtime proof.** For a host-bundled library the native backend reads the
   file once, verifies its SHA-256 and computes `machOCodeSha256` from the same
   bytes; the result travels in `SpacyBackendIdentity.codeSha256`. The grammar
   planner accepts an exact qualified library digest
   (`spacyGrammarNativeSha256s`) or a measured code digest in
   `spacyGrammarCodeSha256s`; it never reads `spacy-native.json`. Studio uses
   the recorded `code_sha256` only to display the qualification
   (`spacyQualificationForHostBundled`). Downloaded packages stay bound to
   their exact bytes; unknown code, a missing code digest, or a different
   capability profile is still refused.

With the hardened runtime, library validation additionally requires every
loaded library to carry the app's team signature, so the re-signed library is
also the only one the signed app can load.

The other bundled libraries (Hunspell, Arabic morphology, CLD3 language ID,
Harper) are built from source, checked against their build receipts before
installation and loaded by path; no runtime digest is pinned to their signed
bytes. The CLD3 model and other assets are data inside the sealed bundle and
are not changed by signing.

## Data location after the bundle id change

A sandboxed app's data lives in `~/Library/Containers/<bundle id>`. Ad hoc
development builds keep `com.quds.qudsOfficeStudio`, so existing test data,
settings and the gate instructions for development builds are unchanged.
Release-signed builds use `com.crispstrobe.crispoffice` and start with an empty
container: spelling dictionaries, the Arabic morphology database and the spaCy
model files are verified downloads and can be installed again from the app;
saved mail account passwords are in the keychain under the old identity and
must be entered again. To carry existing data over to a signed build once,
quit both apps and copy the application-support directory (macOS may ask to
allow Terminal access to another app's data):

```bash
ditto "$HOME/Library/Containers/com.quds.qudsOfficeStudio/Data/Library/Application Support/quds_office_studio" \
      "$HOME/Library/Containers/com.crispstrobe.crispoffice/Data/Library/Application Support/quds_office_studio"
```

Point `QUDS_STUDIO_DATA` of the gate tests at the matching container (or a
scratch directory) for whichever build is tested.

## Mac App Store procedure

1. Prerequisites (one-time): the bundle id `com.crispstrobe.crispoffice` is
   registered and a Mac App Store provisioning profile exists for it, issued
   against the account's single shared Apple Distribution certificate (never
   create another one; the account caps certificates). The Apple Distribution
   and Mac Installer Distribution identities must be in a keychain on the
   search list.
2. Build: `QUDS_PROVISIONING_PROFILE=<profile> QUDS_INSTALLER_IDENTITY=<sha1>
   tool/build_macos_app.sh --sign appstore --build-name X.Y.Z --build-number N`.
3. Verify: the script runs `codesign --verify --deep --strict` and
   `pkgutil --check-signature`. Then, once the App Store Connect app record
   exists: `xcrun altool --validate-app -f <pkg> --type macos --apiKey <id>
   --apiIssuer <issuer>` (camelCase flags work on old and new Xcode; altool
   finds the `.p8` only as `AuthKey_<id>.p8` in `~/.appstoreconnect/private_keys`
   or `~/.private_keys`).
4. Upload (`altool --upload-package … --type macos --apple-id <numeric app
   id>`), TestFlight and review submission are deliberate human release
   decisions; nothing in this repository uploads automatically.

## Developer ID procedure

1. Prerequisites: the Developer ID Application identity (reuse the account's
   existing certificate and key; do not create a new certificate) in a
   keychain on the search list, a Developer ID (`MAC_APP_DIRECT`) provisioning
   profile for the bundle id, and an App Store Connect API key for notarytool.
2. Build: `QUDS_PROVISIONING_PROFILE=<profile> QUDS_NOTARY_KEY=<p8>
   QUDS_NOTARY_KEY_ID=<id> QUDS_NOTARY_ISSUER=<issuer>
   tool/build_macos_app.sh --sign developer-id --build-name X.Y.Z
   --build-number N`.
3. The script submits a zip with `notarytool submit --wait`, fails with the
   notary log on anything but `Accepted`, staples the ticket, runs
   `stapler validate` and `spctl --assess --type execute`, and zips the
   stapled app for distribution.

## Keychain notes

- A headless shell cannot answer keychain prompts. If `codesign` fails with
  `errSecInternalComponent`, the private key's access list needs a one-time
  human `security unlock-keychain` / `security set-key-partition-list` with the
  keychain password. Prefer a dedicated build keychain with a known password
  over the login keychain.
- An identity present in two keychains with the same name makes name-based
  `codesign -s` ambiguous; the script signs by SHA-1 and fails on ambiguous
  defaults instead of guessing.

## CI

`.github/workflows/macos-app-weekly.yml` builds the ad hoc app on a clean
macOS arm64 runner every Monday (and on manual dispatch), runs both bundle
gates against it with a scratch data directory, runs `dart analyze packages
apps` and uploads logs (not the app).

Manual dispatch with `sign=appstore` or `sign=developer-id` additionally runs
the `signed` job, which needs these repository secrets:

| Secret | Used for |
|--------|----------|
| `DIST_CERT_P12_BASE64`, `DIST_CERT_PASSWORD` | base64 `.p12` holding the Apple Distribution and Mac Installer Distribution identities (appstore) |
| `MAC_PROFILE_BASE64` | base64 Mac App Store provisioning profile (appstore) |
| `MACOS_DEVELOPER_ID_P12_BASE64`, `MACOS_DEVELOPER_ID_P12_PASSWORD` | base64 `.p12` with the Developer ID Application identity (developer-id) |
| `MACOS_DEVELOPER_ID_PROFILE_BASE64` | base64 Developer ID provisioning profile (developer-id) |
| `ASC_API_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID` | App Store Connect API key for notarization (developer-id) |

The job imports them into a temporary keychain, builds with `--build-number`
set to the run number, verifies, uploads the `.pkg` or notarized zip as a
seven-day workflow artifact and deletes the keychain. It never uploads to App
Store Connect.
